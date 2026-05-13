import SwiftUI

// MARK: - InsightsView
// Principle #11: format diversity — CHIPS (filter) → BENTO (stats) → CARDS (insights) → NOTE (alcohol)
// Principle #5: CategoryDot on AlcoholImpactCard (amber)
// Default filter: .medium (Emerging) — most actionable tier

struct InsightsView: View {
    @EnvironmentObject private var bleManager: BLEManager
    @State private var patterns: [FoodPattern] = []
    @State private var isLoading = false
    @State private var entryCount = 0
    @State private var appeared = false
    @State private var confidenceFilter: FoodPattern.ConfidenceTier? = .medium
    @State private var showCoherenceDrill = false

    private static let minimumEntries = 14

    private var filtered: [FoodPattern] {
        guard let filter = confidenceFilter else { return patterns }
        return patterns.filter { $0.confidenceTier == filter }
    }

    var body: some View {
        ZStack {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: DS.Spacing.md) {
                    headerSpacer

                    // Coherence Drill quick-launch (always visible, not gated)
                    CoherenceDrillTile(action: { showCoherenceDrill = true })
                        .padding(.horizontal, DS.Spacing.md)
                        .offset(y: appeared ? 0 : 20)
                        .opacity(appeared ? 1 : 0)
                        .animation(DS.Anim.stagger(index: 0), value: appeared)

                    // Daily insights from the Claude routine + Vercel cron fallback
                    DailyInsightsStrip()
                        .offset(y: appeared ? 0 : 20)
                        .opacity(appeared ? 1 : 0)
                        .animation(DS.Anim.stagger(index: 1), value: appeared)

                    if isLoading {
                        LoadingState(label: "Analyzing patterns…")
                    } else if entryCount < Self.minimumEntries {
                        DataGateCard(entriesLogged: entryCount, required: Self.minimumEntries)
                            .statusGlow(DS.Colors.violet, intensity: 0.6)
                            .padding(.horizontal, DS.Spacing.md)
                            .offset(y: appeared ? 0 : 20)
                            .opacity(appeared ? 1 : 0)
                            .animation(DS.Anim.stagger(index: 0), value: appeared)
                    } else {
                        // Confidence filter chips
                        ConfidenceFilterRow(selected: $confidenceFilter)
                            .offset(y: appeared ? 0 : 20)
                            .opacity(appeared ? 1 : 0)
                            .animation(DS.Anim.stagger(index: 0), value: appeared)

                        // Stats summary
                        PatternStatsBanner(patterns: patterns, entryCount: entryCount)
                            .padding(.horizontal, DS.Spacing.md)
                            .offset(y: appeared ? 0 : 20)
                            .opacity(appeared ? 1 : 0)
                            .animation(DS.Anim.stagger(index: 1), value: appeared)

                        // Pattern cards
                        ForEach(Array(filtered.enumerated()), id: \.element.id) { i, pattern in
                            InsightCard(pattern: pattern)
                                .padding(.horizontal, DS.Spacing.md)
                                .offset(y: appeared ? 0 : 20)
                                .opacity(appeared ? 1 : 0)
                                .animation(DS.Anim.stagger(index: i + 2), value: appeared)
                        }

                        if filtered.isEmpty {
                            EmptyGlassState(
                                icon: "lightbulb",
                                title: "No pattern found",
                                detail: confidenceFilter != nil
                                    ? "Try a different confidence tier."
                                    : "Analysis improves with more data."
                            )
                            .padding(.horizontal, DS.Spacing.md)
                        }

                        // Alcohol impact (always show if significant)
                        if bleManager.healthEngine.lastAlcoholImpact > 10 {
                            AlcoholImpactCard(impact: bleManager.healthEngine.lastAlcoholImpact)
                                .padding(.horizontal, DS.Spacing.md)
                                .offset(y: appeared ? 0 : 20)
                                .opacity(appeared ? 1 : 0)
                                .animation(DS.Anim.stagger(index: filtered.count + 3), value: appeared)
                        }

                        // Methodology note
                        MethodologyNote(entryCount: entryCount)
                            .padding(.horizontal, DS.Spacing.md)
                            .offset(y: appeared ? 0 : 20)
                            .opacity(appeared ? 1 : 0)
                            .animation(DS.Anim.stagger(index: filtered.count + 4), value: appeared)
                    }

                    bottomSpacer
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                TwoToneHeadline(primary: "Insights", secondary: " · Patterns", font: .system(size: 17, weight: .bold, design: .rounded))
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                SettingsGearButton()
            }
        }
        .task {
            await loadInsights()
            withAnimation { appeared = true }
        }
        .fullScreenCover(isPresented: $showCoherenceDrill) {
            CoherenceDrillView()
                .environmentObject(bleManager)
        }
    }

    // MARK: - Coherence Drill quick-launch tile

    private struct CoherenceDrillTile: View {
        let action: () -> Void
        var body: some View {
            Button(action: action) {
                HStack(spacing: DS.Spacing.md) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: [DS.Colors.violet, DS.Colors.teal],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 44, height: 44)
                        Image(systemName: "wind")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Coherence Drill")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(DS.Colors.textPrimary)
                        Text("5-min HRV biofeedback · 6 breaths/min")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(DS.Colors.textMuted)
                    }
                    Spacer()
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(DS.Colors.violet)
                }
                .padding(DS.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .glassDefault()
            .buttonStyle(.plain)
        }
    }

    private var headerSpacer: some View { Color.clear.frame(height: DS.Spacing.sm) }
    private var bottomSpacer: some View { Color.clear.frame(height: 100) }

    private func loadInsights() async {
        isLoading = true
        do {
            let entries = try await SupabaseClient.shared.fetchRecentFoodEntries(limit: 90)
            entryCount = entries.count
            if entries.count >= Self.minimumEntries {
                patterns = InsightEngine.compute(entries: entries, engine: bleManager.healthEngine)
            }
        } catch {
            // empty state handles it
        }
        isLoading = false
    }
}

// MARK: - Confidence Filter Row

private extension FoodPattern.ConfidenceTier {
    var filterLabel: String {
        switch self {
        case .high:   return "Established"
        case .medium: return "Emerging"
        case .low:    return "Possible"
        }
    }

    var filterColor: Color {
        switch self {
        case .high:   return DS.Colors.teal
        case .medium: return DS.Colors.amber
        case .low:    return DS.Colors.violet
        }
    }

    var filterIndex: Int {
        switch self {
        case .high:   return 0
        case .medium: return 1
        case .low:    return 2
        }
    }

    static var allFilterCases: [FoodPattern.ConfidenceTier] { [.high, .medium, .low] }
}

private struct ConfidenceFilterRow: View {
    @Binding var selected: FoodPattern.ConfidenceTier?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.sm) {
                chipButton(label: "All", isSelected: selected == nil, color: DS.Colors.textSecondary) {
                    withAnimation(DS.Anim.quick) { selected = nil }
                }
                ForEach(FoodPattern.ConfidenceTier.allFilterCases, id: \.filterIndex) { tier in
                    chipButton(label: tier.filterLabel, isSelected: selected == tier, color: tier.filterColor) {
                        withAnimation(DS.Anim.quick) {
                            selected = selected == tier ? nil : tier
                        }
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.xs)
        }
    }

    private func chipButton(label: String, isSelected: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium, design: .rounded))
                .foregroundStyle(isSelected ? color : DS.Colors.textFaint)
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? color.opacity(0.12) : DS.Colors.surface)
                        .overlay(
                            Capsule().stroke(isSelected ? color.opacity(0.3) : DS.Colors.border, lineWidth: 0.5)
                        )
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Pattern Stats Banner

private struct PatternStatsBanner: View {
    let patterns: [FoodPattern]
    let entryCount: Int

    private var highCount: Int { patterns.filter { $0.confidenceTier == FoodPattern.ConfidenceTier.high }.count }
    private var mediumCount: Int { patterns.filter { $0.confidenceTier == FoodPattern.ConfidenceTier.medium }.count }
    private var lowCount: Int { patterns.filter { $0.confidenceTier == FoodPattern.ConfidenceTier.low }.count }

    var body: some View {
        HStack(spacing: 0) {
            statCell(value: "\(entryCount)", label: "Entries", color: DS.Colors.textSecondary)
            Divider().frame(height: 32).opacity(0.25)
            statCell(value: "\(highCount)", label: "Established", color: DS.Colors.teal)
            Divider().frame(height: 32).opacity(0.25)
            statCell(value: "\(mediumCount)", label: "Emerging", color: DS.Colors.amber)
            Divider().frame(height: 32).opacity(0.25)
            statCell(value: "\(lowCount)", label: "Possible", color: DS.Colors.violet)
        }
        .padding(.vertical, DS.Spacing.sm)
        .glassDefault()
    }

    private func statCell(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(DS.Colors.textFaint)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Data Gate Card

private struct DataGateCard: View {
    let entriesLogged: Int
    let required: Int

    private var progress: Double { Double(entriesLogged) / Double(required) }

    var body: some View {
        VStack(spacing: DS.Spacing.lg) {
            Image(systemName: "chart.dots.scatter")
                .font(.system(size: 40))
                .foregroundStyle(DS.Colors.violet.opacity(0.6))

            TwoToneHeadline(
                primary: "Almost there",
                secondary: " — \(required - entriesLogged) entries to go",
                font: .system(size: 22, weight: .heavy, design: .rounded)
            )

            Text("With \(required) entries LucidHealth starts surfacing patterns between your food and your recovery.")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(DS.Colors.textSecondary)
                .multilineTextAlignment(.center)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(DS.Colors.surfaceElevated)
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [DS.Colors.violet, DS.Colors.teal],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * progress, height: 6)
                }
            }
            .frame(height: 6)

            Text("\(entriesLogged) / \(required)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(DS.Colors.textFaint)
        }
        .padding(DS.Spacing.xl)
        .heroCard()
    }
}

// MARK: - Alcohol Impact Card

private struct AlcoholImpactCard: View {
    let impact: Double

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                // Principle #5: amber category dot — food/lifestyle signal
                CategoryDot(category: .food)
                Text("ALCOHOL EFFECT")
                    .font(DS.Font.label)
                    .foregroundStyle(DS.Colors.amber)
            }
            Text(String(format: "HRV was %.0f%% below baseline after alcohol. That explains the lower recovery score the next day — the wine, not you.", impact))
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(DS.Colors.textSecondary)
        }
        .padding(DS.Spacing.md)
        .glassDefault()
    }
}

// MARK: - Methodology Note

private struct MethodologyNote: View {
    let entryCount: Int

    var body: some View {
        PatternNote(
            text: "Correlations based on \(entryCount) entries. Calculated from: NOVA score, Mind score, and recovery delta after meals. No causation, only patterns.",
            icon: "info.circle",
            color: DS.Colors.textFaint
        )
    }
}

// MARK: - Insight Engine

enum InsightEngine {
    static func compute(entries: [FoodEntry], engine: HealthEngine) -> [FoodPattern] {
        var result: [FoodPattern] = []

        // Ultra-processed food pattern
        let highNova = entries.filter { ($0.novaAvg ?? 0) >= 3.5 }
        if highNova.count >= 5 {
            result.append(FoodPattern(
                title: "Ultra-processed food",
                subtitle: "On days with NOVA >= 3.5 your recovery was generally lower.",
                confidenceTier: highNova.count > 20 ? .high : .medium,
                confidenceValue: min(Double(highNova.count) / 30.0, 1.0),
                effectDescription: String(format: "%.0f%% lower recovery", (1 - engine.recoveryScore / 100) * 15),
                effectPositive: false
            ))
        }

        // Brain food pattern
        let highMind = entries.filter { ($0.mindScore ?? 0) >= 10 }
        if highMind.count >= 5 {
            result.append(FoodPattern(
                title: "Brain-friendly days",
                subtitle: "Days with high Brain-Score correlate with better HRV the next morning.",
                confidenceTier: highMind.count > 15 ? .high : .medium,
                confidenceValue: min(Double(highMind.count) / 25.0, 1.0),
                effectDescription: "+\(Int(engine.currentRMSSD * 0.08)) ms HRV",
                effectPositive: true
            ))
        }

        // Low NOVA pattern
        let lowNova = entries.filter { ($0.novaAvg ?? 4) <= 1.5 }
        if lowNova.count >= 8 {
            result.append(FoodPattern(
                title: "Minimally processed diet",
                subtitle: "Days with NOVA <= 1.5 consistently show better recovery scores.",
                confidenceTier: lowNova.count > 18 ? .high : .medium,
                confidenceValue: min(Double(lowNova.count) / 22.0, 1.0),
                effectDescription: String(format: "+%.0f%% recovery", engine.recoveryScore * 0.12),
                effectPositive: true
            ))
        }

        // Calorie spike pattern
        let highKcal = entries.filter { ($0.totalKcal ?? 0) > 2800 }
        if highKcal.count >= 4 {
            result.append(FoodPattern(
                title: "High calorie volume",
                subtitle: "Evening meals > 2800 kcal correlated with disturbed sleep.",
                confidenceTier: .low,
                confidenceValue: min(Double(highKcal.count) / 15.0, 1.0),
                effectDescription: "-\(Int(engine.sleepScore * 0.08))% sleep score",
                effectPositive: false
            ))
        }

        return result.sorted { $0.confidenceValue > $1.confidenceValue }
    }
}
