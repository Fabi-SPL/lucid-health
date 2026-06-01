import SwiftUI

struct ReviewView: View {
    let image: UIImage
    var onSaved: ((FoodEntry) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var caption: String = ""
    @State private var items: [DetectedItem] = []
    @State private var isAnalyzing = false
    @State private var isSaving = false
    @State private var hasAnalyzed = false
    @State private var error: String?
    @State private var geminiResult: GeminiFoodResult?

    private let gemini = GeminiClient.shared
    private let supabase = SupabaseClient.shared

    var body: some View {
        ZStack {
            MeshGradientBackground()

            ScrollView {
                VStack(spacing: DS.Spacing.lg) {
                    // Photo
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 260)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
                        .overlay(Group { if isAnalyzing { ShimmerOverlay() } })
                        .padding(.horizontal, DS.Spacing.md)

                    // Caption ALWAYS visible — user can add context BEFORE analysis
                    captionCard

                    if isAnalyzing {
                        analyzingCard
                    } else if hasAnalyzed {
                        VStack(spacing: DS.Spacing.sm) {
                            ForEach($items) { $item in
                                DetectedItemRow(item: $item)
                            }
                        }
                        .padding(.horizontal, DS.Spacing.md)
                    }

                    if let error {
                        AlertBanner(icon: "exclamationmark.triangle", message: error, color: DS.Colors.danger)
                            .padding(.horizontal, DS.Spacing.md)
                    }

                    actionButton

                    Color.clear.frame(height: DS.Spacing.xl)
                }
                .padding(.top, DS.Spacing.lg)
            }

            // Close button
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
    }

    // MARK: - Subviews

    private var captionCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text(hasAnalyzed ? "ADD DETAIL" : "ADD CONTEXT (OPTIONAL)")
                .font(DS.Font.label)
                .foregroundStyle(DS.Colors.textMuted)
                .tracking(0.8)
            TextField(
                hasAnalyzed
                    ? "Description (improves accuracy on re-analyze)"
                    : "e.g. Homemade lasagna, big plate — improves Gemini accuracy",
                text: $caption,
                axis: .vertical
            )
            .font(DS.Font.body)
            .foregroundStyle(DS.Colors.textPrimary)
            .lineLimit(2...5)
            .disabled(isAnalyzing)
        }
        .glassCard()
        .padding(.horizontal, DS.Spacing.md)
    }

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

    @ViewBuilder
    private var actionButton: some View {
        // Save is ALWAYS available — never gate logging behind Gemini.
        // (Was: Save only appeared after hasAnalyzed==true, so a Gemini 429
        // permanently trapped the user with no way to log the meal.)
        // Gemini analysis is now an OPTIONAL enrichment, not a prerequisite.
        VStack(spacing: DS.Spacing.sm) {
            Button { saveEntry() } label: {
                HStack {
                    if isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "checkmark")
                        Text(hasAnalyzed ? "Save meal" : "Save meal")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(GlassActionButtonStyle(tint: DS.Colors.violet, filled: true))
            .disabled(isSaving)

            // Optional enrichment — analyze (or re-analyze) with Gemini.
            Button {
                if hasAnalyzed { hasAnalyzed = false; items = []; geminiResult = nil }
                Task { await analyze() }
            } label: {
                HStack {
                    if isAnalyzing {
                        ProgressView().tint(DS.Colors.violet)
                    } else {
                        Image(systemName: hasAnalyzed ? "arrow.clockwise" : "sparkles")
                        Text(hasAnalyzed ? "Re-analyze with new context" : "Analyze with Gemini (optional)")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(GlassActionButtonStyle(tint: DS.Colors.textSecondary, filled: false))
            .disabled(isSaving || isAnalyzing)
        }
        .padding(.horizontal, DS.Spacing.md)
    }

    private func analyze() async {
        isAnalyzing = true
        error = nil
        do {
            let result = try await gemini.analyzeFood(image: image, caption: caption.isEmpty ? nil : caption)
            geminiResult = result
            items = result.items
            hasAnalyzed = true
        } catch {
            self.error = "Analysis failed: \(error.localizedDescription)"
            items = []
        }
        isAnalyzing = false
    }

    private func saveEntry() {
        isSaving = true
        error = nil
        Task {
            // Track which step failed so the error message can be precise.
            // Previously a generic "403" with no context made debugging painful.
            var step = "preparing image"
            do {
                let filename = "\(UUID().uuidString).jpg"
                let jpeg = image.jpegData(compressionQuality: 0.85) ?? Data()

                // Photo is OPTIONAL — never let a Storage 403 nuke the whole log.
                // try? swallows upload failure; the food row still inserts with
                // photoUrl = nil. (Was: try await → threw → meal never saved.)
                step = "uploading photo (optional)"
                let photoUrl = try? await supabase.uploadFoodPhoto(jpeg, filename: filename)

                let result = geminiResult
                let entry = FoodEntry(
                    id: nil,
                    userId: SupabaseClient.shared.userId,
                    capturedAt: Date(),
                    photoUrl: photoUrl,
                    geminiRawJson: result?.notes,
                    items: items,
                    caption: caption.isEmpty ? nil : caption,
                    totalKcal: result?.totalKcal,
                    novaAvg: result?.novaAvg,
                    mindScore: result?.mindScore,
                    confidence: result?.confidence,
                    source: "photo",
                    createdAt: nil
                )

                step = "inserting food_entries row"
                let saved = try await supabase.saveFoodEntry(entry)
                onSaved?(saved)
                dismiss()
            } catch {
                self.error = "Failed \(step): \(error.localizedDescription)"
            }
            isSaving = false
        }
    }
}

// MARK: - Detected Item Row

struct DetectedItemRow: View {
    @Binding var item: DetectedItem

    private var novaColor: Color {
        switch item.novaClass {
        case 1: return DS.Colors.success
        case 2: return DS.Colors.teal
        case 3: return DS.Colors.warning
        default: return DS.Colors.danger
        }
    }

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Food", text: $item.name)
                    .font(DS.Font.bodyMed)
                    .foregroundStyle(DS.Colors.textPrimary)
                HStack(spacing: DS.Spacing.xs) {
                    TextField("0", value: $item.grams, format: .number)
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Colors.textMuted)
                        .frame(width: 40)
                        .keyboardType(.numberPad)
                    Text("g")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Colors.textFaint)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("NOVA \(item.novaClass)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(novaColor)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(novaColor.opacity(0.12))
                    .clipShape(Capsule())
                Text("\(item.kcal) kcal")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Colors.textMuted)
            }
        }
        .glassCard()
    }
}

// MARK: - Shimmer Overlay

struct ShimmerOverlay: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            LinearGradient(
                stops: [
                    .init(color: .clear,                      location: 0.0),
                    .init(color: Color.white.opacity(0.18),   location: 0.48),
                    .init(color: Color.white.opacity(0.32),   location: 0.50),
                    .init(color: Color.white.opacity(0.18),   location: 0.52),
                    .init(color: .clear,                      location: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(width: geo.size.width * 0.5)
            .offset(x: phase * geo.size.width * 2.2)
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }
}
