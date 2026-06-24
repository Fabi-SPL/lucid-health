import SwiftUI

/// Real per-entry edit sheet — fixes the case where Gemini misclassified
/// or you put grams in the wrong field. Edit caption + each item's name,
/// grams, NOVA class, mind tags. Save → PATCH the entry server-side and
/// recompute totals locally.
struct EditFoodEntrySheet: View {
    let original: FoodEntry
    var onSaved: (FoodEntry) -> Void
    var onCancel: () -> Void

    @State private var caption: String
    @State private var items: [DetectedItem]
    @State private var isSaving = false
    @State private var saved = false
    @State private var error: String?

    init(entry: FoodEntry, onSaved: @escaping (FoodEntry) -> Void, onCancel: @escaping () -> Void) {
        self.original = entry
        self.onSaved = onSaved
        self.onCancel = onCancel
        _caption = State(initialValue: entry.caption ?? "")
        _items = State(initialValue: entry.items)
    }

    private var totalKcal: Int {
        items.reduce(0) { $0 + $1.kcal }
    }
    private var novaAvg: Double {
        guard !items.isEmpty else { return 1.0 }
        let sum = items.map { Double($0.novaClass) }.reduce(0, +)
        return sum / Double(items.count)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: DS.Spacing.lg) {
                    Color.clear.frame(height: DS.Spacing.xs)

                    // Caption
                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        SectionHeader(icon: "text.cursor", title: "MEAL NAME", iconColor: DS.Colors.violet)
                        TextField("e.g. Chicken with rice", text: $caption)
                            .font(.system(size: 14, weight: .medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(DS.Colors.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                            .foregroundStyle(DS.Colors.textPrimary)
                            .textInputAutocapitalization(.sentences)
                    }
                    .padding(DS.Spacing.md)
                    .glassDefault()
                    .padding(.horizontal, DS.Spacing.md)

                    // Totals — read-only, recompute live
                    HStack(spacing: DS.Spacing.md) {
                        totalCard(label: "TOTAL", value: "\(totalKcal)", unit: "kcal", color: DS.Colors.amber)
                        totalCard(label: "NOVA Ø", value: String(format: "%.1f", novaAvg), unit: "/ 4", color: DS.Colors.novaColor(novaAvg))
                        totalCard(label: "ITEMS", value: "\(items.count)", unit: "", color: DS.Colors.violet)
                    }
                    .padding(.horizontal, DS.Spacing.md)

                    // Items — each editable, swipe to delete
                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        HStack {
                            SectionHeader(icon: "list.bullet", title: "ITEMS", iconColor: DS.Colors.teal)
                            Spacer()
                            Button {
                                addItem()
                            } label: {
                                Label("Add", systemImage: "plus.circle.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(DS.Colors.teal)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, DS.Spacing.md)

                        VStack(spacing: DS.Spacing.sm) {
                            ForEach($items) { $item in
                                EditableItemRow(item: $item) {
                                    items.removeAll { $0.id == item.id }
                                }
                            }
                        }
                        .padding(.horizontal, DS.Spacing.md)
                    }

                    // Save button
                    Button {
                        Task { await save() }
                    } label: {
                        HStack(spacing: 8) {
                            if isSaving {
                                ProgressView().tint(.white)
                            } else if saved {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Saved")
                            } else {
                                Image(systemName: "checkmark")
                                Text("Save changes")
                            }
                        }
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Spacing.md)
                        .background(Capsule().fill(saved ? DS.Colors.success : DS.Colors.violet))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving || saved)
                    .padding(.horizontal, DS.Spacing.md)

                    if let err = error {
                        Text(err)
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Colors.danger)
                            .padding(.horizontal, DS.Spacing.lg)
                    }

                    Color.clear.frame(height: DS.Spacing.lg)
                }
            }
            .background(AuroraBackground().ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    TwoToneHeadline(
                        primary: "Edit",
                        secondary: " · meal",
                        font: .system(size: 17, weight: .heavy, design: .rounded)
                    )
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { onCancel() }
                        .foregroundStyle(DS.Colors.textSecondary)
                }
            }
        }
    }

    private func totalCard(label: String, value: String, unit: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(DS.Colors.textFaint)
                .tracking(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(color)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(DS.Colors.textFaint)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.md)
        .glassDefault()
    }

    private func addItem() {
        let h = UIImpactFeedbackGenerator(style: .light)
        h.impactOccurred()
        items.append(DetectedItem(
            name: "",
            grams: 0,
            kcal: 0,
            novaClass: 1,
            mindTags: []
        ))
    }

    private func save() async {
        guard let id = original.id?.uuidString else {
            await MainActor.run { error = "Missing entry ID" }
            return
        }
        await MainActor.run { isSaving = true; error = nil }

        let trimmedCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let mindScore = recomputeMindScore(items: items)

        let ok = await SupabaseClient.shared.updateFoodEntry(
            id: id,
            caption: trimmedCaption.isEmpty ? nil : trimmedCaption,
            items: items,
            totalKcal: totalKcal,
            novaAvg: novaAvg,
            mindScore: mindScore
        )

        await MainActor.run {
            isSaving = false
            if ok {
                let h = UINotificationFeedbackGenerator()
                h.notificationOccurred(.success)
                saved = true
                let updated = FoodEntry(
                    id: original.id,
                    userId: original.userId,
                    capturedAt: original.capturedAt,
                    photoUrl: original.photoUrl,
                    geminiRawJson: original.geminiRawJson,
                    items: items,
                    caption: trimmedCaption.isEmpty ? nil : trimmedCaption,
                    totalKcal: totalKcal,
                    novaAvg: novaAvg,
                    mindScore: mindScore,
                    confidence: original.confidence,
                    source: original.source,
                    createdAt: original.createdAt,
                    logQuality: original.logQuality
                )
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    onSaved(updated)
                }
            } else {
                error = "Save failed — check connection"
            }
        }
    }

    private func recomputeMindScore(items: [DetectedItem]) -> Int {
        let pos: Set<String> = ["leafy_green", "fish", "berries", "olive_oil", "nuts", "legumes", "whole_grain", "protein"]
        let neg: Set<String> = ["fried", "fried_food", "processed_meat", "pastries", "ultra_processed", "alcohol"]
        var p = 0, n = 0
        for item in items {
            for tag in item.mindTags {
                if pos.contains(tag) { p += 1 }
                if neg.contains(tag) { n += 1 }
            }
        }
        return max(0, min(15, p - min(n, 2)))
    }
}

// MARK: - Editable Item Row

private struct EditableItemRow: View {
    @Binding var item: DetectedItem
    var onDelete: () -> Void

    private let novaOptions = [1, 2, 3, 4]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            // Row 1 — name + delete
            HStack(spacing: DS.Spacing.sm) {
                TextField("Food name", text: $item.name)
                    .font(.system(size: 14, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(DS.Colors.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                    .foregroundStyle(DS.Colors.textPrimary)

                Button {
                    let h = UIImpactFeedbackGenerator(style: .medium)
                    h.impactOccurred()
                    onDelete()
                } label: {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(DS.Colors.danger)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle().fill(DS.Colors.danger.opacity(0.10))
                        )
                }
                .buttonStyle(.plain)
            }

            // Row 2 — grams + kcal
            HStack(spacing: DS.Spacing.sm) {
                gramsField
                kcalField
            }

            // Row 3 — NOVA picker
            HStack(spacing: 6) {
                Text("NOVA")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DS.Colors.textFaint)
                    .tracking(0.6)
                ForEach(novaOptions, id: \.self) { n in
                    Button {
                        item.novaClass = n
                    } label: {
                        Text("\(n)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(item.novaClass == n ? .white : DS.Colors.textSecondary)
                            .frame(width: 28, height: 24)
                            .background(
                                Capsule()
                                    .fill(item.novaClass == n ? DS.Colors.novaColor(Double(n)) : DS.Colors.surface)
                                    .overlay(Capsule().stroke(DS.Colors.border, lineWidth: 0.5))
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                if let conf = item.novaConfidence {
                    Text(conf)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(DS.Colors.textFaint)
                        .tracking(0.5)
                }
            }
        }
        .padding(DS.Spacing.md)
        .glassDefault()
    }

    private var gramsField: some View {
        HStack(spacing: 4) {
            Text("g")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DS.Colors.textFaint)
            TextField("0", value: $item.grams, format: .number)
                .keyboardType(.numberPad)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.Colors.textPrimary)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(DS.Colors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
    }

    private var kcalField: some View {
        HStack(spacing: 4) {
            Text("kcal")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DS.Colors.textFaint)
            TextField("0", value: $item.kcal, format: .number)
                .keyboardType(.numberPad)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.Colors.amber)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(DS.Colors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
    }
}
