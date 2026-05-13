import SwiftUI

/// Manual food entry — user types what they ate (e.g. "lasagna I made yesterday")
/// and picks when. Gemini estimates nutrition from text only. No photo required.
struct ManualFoodEntrySheet: View {
    var onSaved: ((FoodEntry) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var description: String = ""
    @State private var eatenAt: Date = Date()
    @State private var items: [DetectedItem] = []
    @State private var caption: String = ""
    @State private var isAnalyzing = false
    @State private var isSaving = false
    @State private var hasAnalyzed = false
    @State private var error: String?
    @State private var geminiResult: GeminiFoodResult?

    @FocusState private var descriptionFocused: Bool

    private let gemini = GeminiClient.shared
    private let supabase = SupabaseClient.shared

    private var canAnalyze: Bool {
        !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isAnalyzing
    }

    var body: some View {
        ZStack {
            MeshGradientBackground()

            ScrollView {
                VStack(spacing: DS.Spacing.lg) {
                    header

                    descriptionCard

                    timeCard

                    if isAnalyzing {
                        analyzingCard
                    }

                    if hasAnalyzed && !items.isEmpty {
                        VStack(spacing: DS.Spacing.sm) {
                            sectionLabel("Detected items")
                            ForEach($items) { $item in
                                DetectedItemRow(item: $item)
                            }
                        }
                        .padding(.horizontal, DS.Spacing.md)

                        if let totals = geminiResult?.mealTotals {
                            mealTotalsCard(totals)
                        }
                    }

                    if let error {
                        AlertBanner(icon: "exclamationmark.triangle", message: error, color: DS.Colors.danger)
                            .padding(.horizontal, DS.Spacing.md)
                    }

                    actionButton

                    Color.clear.frame(height: DS.Spacing.xl * 2)
                }
                .padding(.top, DS.Spacing.lg)
            }

            closeButton
        }
        .onAppear { descriptionFocused = true }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Type a meal")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(DS.Colors.textPrimary)
            Text("No photo? Just describe what you ate.")
                .font(DS.Font.caption)
                .foregroundStyle(DS.Colors.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Spacing.md)
    }

    // MARK: - Description card

    private var descriptionCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            sectionLabel("What did you eat?")
            TextField(
                "e.g. Homemade lasagna, big plate, with side salad",
                text: $description,
                axis: .vertical
            )
            .font(DS.Font.body)
            .foregroundStyle(DS.Colors.textPrimary)
            .lineLimit(3...8)
            .focused($descriptionFocused)
            .submitLabel(.done)
        }
        .glassCard()
        .padding(.horizontal, DS.Spacing.md)
    }

    // MARK: - Time card

    private var timeCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            sectionLabel("When did you eat it?")
            DatePicker(
                "",
                selection: $eatenAt,
                in: ...Date(),
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.compact)
            .labelsHidden()
            .tint(DS.Colors.violet)

            HStack(spacing: DS.Spacing.xs) {
                quickTimeChip("Now") { eatenAt = Date() }
                quickTimeChip("1h ago") { eatenAt = Date().addingTimeInterval(-3600) }
                quickTimeChip("Yesterday 7pm") {
                    eatenAt = Calendar.current.date(
                        bySettingHour: 19, minute: 0, second: 0,
                        of: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
                    ) ?? Date()
                }
            }
            .padding(.top, 4)
        }
        .glassCard()
        .padding(.horizontal, DS.Spacing.md)
    }

    private func quickTimeChip(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: {
            let h = UIImpactFeedbackGenerator(style: .light)
            h.impactOccurred()
            action()
        }) {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.Colors.violet)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(DS.Colors.violet.opacity(0.12))
                        .overlay(Capsule().stroke(DS.Colors.violet.opacity(0.25), lineWidth: 0.5))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Analyzing

    private var analyzingCard: some View {
        HStack(spacing: DS.Spacing.sm) {
            ProgressView().tint(DS.Colors.violet)
            Text("Analyzing with Gemini…")
                .font(DS.Font.body)
                .foregroundStyle(DS.Colors.textMuted)
        }
        .frame(maxWidth: .infinity)
        .glassCard()
        .padding(.horizontal, DS.Spacing.md)
    }

    private func mealTotalsCard(_ totals: MealTotals) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            sectionLabel("Estimated totals")
            HStack(spacing: DS.Spacing.md) {
                if let mid = totals.caloriesMidpoint {
                    totalsCell(value: "\(mid)", unit: "kcal", color: DS.Colors.violet)
                }
                if let p = totals.proteinG {
                    totalsCell(value: String(format: "%.0f", p), unit: "g protein", color: DS.Colors.teal)
                }
                if let c = totals.carbsG {
                    totalsCell(value: String(format: "%.0f", c), unit: "g carbs", color: DS.Colors.amber)
                }
                if let f = totals.fatG {
                    totalsCell(value: String(format: "%.0f", f), unit: "g fat", color: DS.Colors.danger)
                }
            }
            if let conf = totals.confidenceLevel {
                Text("Confidence: \(conf)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DS.Colors.textFaint)
                    .padding(.top, 4)
            }
        }
        .glassCard()
        .padding(.horizontal, DS.Spacing.md)
    }

    private func totalsCell(value: String, unit: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
            Text(unit)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(DS.Colors.textFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Action button

    @ViewBuilder
    private var actionButton: some View {
        if !hasAnalyzed {
            Button { analyze() } label: {
                HStack {
                    if isAnalyzing {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "sparkles")
                        Text("Analyze with Gemini")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(GlassActionButtonStyle(tint: DS.Colors.violet, filled: true))
            .disabled(!canAnalyze)
            .opacity(canAnalyze ? 1.0 : 0.5)
            .padding(.horizontal, DS.Spacing.md)
        } else {
            VStack(spacing: DS.Spacing.sm) {
                Button { saveEntry() } label: {
                    HStack {
                        if isSaving {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "checkmark")
                            Text("Save meal")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(GlassActionButtonStyle(tint: DS.Colors.violet, filled: true))
                .disabled(isSaving)

                Button { reanalyze() } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Re-analyze")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(GlassActionButtonStyle(tint: DS.Colors.textSecondary, filled: false))
            }
            .padding(.horizontal, DS.Spacing.md)
        }
    }

    // MARK: - Close

    private var closeButton: some View {
        VStack {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DS.Colors.textSecondary)
                        .padding(10)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                .padding(.leading, DS.Spacing.md)
                Spacer()
            }
            .padding(.top, DS.Spacing.md)
            Spacer()
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(DS.Font.label)
            .foregroundStyle(DS.Colors.textMuted)
            .tracking(0.8)
    }

    // MARK: - Actions

    private func analyze() {
        descriptionFocused = false
        isAnalyzing = true
        error = nil
        Task {
            do {
                let result = try await gemini.analyzeFood(description: description)
                geminiResult = result
                items = result.items
                hasAnalyzed = true
            } catch {
                self.error = "Analysis failed: \(error.localizedDescription)"
                items = []
            }
            isAnalyzing = false
        }
    }

    private func reanalyze() {
        hasAnalyzed = false
        items = []
        geminiResult = nil
        analyze()
    }

    private func saveEntry() {
        isSaving = true
        error = nil
        Task {
            do {
                let result = geminiResult
                let entry = FoodEntry(
                    id: nil,
                    userId: SupabaseClient.shared.userId,
                    capturedAt: eatenAt,
                    photoUrl: nil,
                    geminiRawJson: result?.notes,
                    items: items,
                    caption: description,
                    totalKcal: result?.totalKcal,
                    novaAvg: result?.novaAvg,
                    mindScore: result?.mindScore,
                    confidence: result?.confidence,
                    source: "manual",
                    createdAt: nil
                )

                let saved = try await supabase.saveFoodEntry(entry)
                onSaved?(saved)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            isSaving = false
        }
    }
}
