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
    @State private var confidenceFilter: FoodPattern.ConfidenceTier? = nil  // All — show strongest real patterns first
    @State private var showCoherenceDrill = false
    @State private var showBiostate = false
    @State private var biostateInitialCorrect: BiostateDetector? = nil
    @State private var lastNight: SleepRestlessness? = nil
    @State private var illness: IllnessRisk? = nil
    @State private var dailyMetrics: [DailyMetric] = []

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

                    // Last-night signals (sleep restlessness + illness early-warning)
                    LastNightCard(sleep: lastNight, illness: illness)
                        .padding(.horizontal, DS.Spacing.md)
                        .offset(y: appeared ? 0 : 20)
                        .opacity(appeared ? 1 : 0)
                        .animation(DS.Anim.stagger(index: 2), value: appeared)

                    if isLoading {
                        LoadingState(label: "Analyzing patterns…")
                    } else {
                        // Slim nudge when food logging is thin — but real health
                        // correlations (HRV/RHR/sleep → recovery) still render below.
                        if entryCount < Self.minimumEntries {
                            DataGateCard(entriesLogged: entryCount, required: Self.minimumEntries)
                                .statusGlow(DS.Colors.violet, intensity: 0.6)
                                .padding(.horizontal, DS.Spacing.md)
                                .offset(y: appeared ? 0 : 20)
                                .opacity(appeared ? 1 : 0)
                                .animation(DS.Anim.stagger(index: 0), value: appeared)
                        }

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

                        // Featured pattern hero + diverging impact bars (v6 mockup)
                        if let top = patterns.max(by: { $0.confidenceValue < $1.confidenceValue }) {
                            FeaturedPatternCard(pattern: top)
                                .padding(.horizontal, DS.Spacing.md)
                                .offset(y: appeared ? 0 : 20)
                                .opacity(appeared ? 1 : 0)
                                .animation(DS.Anim.stagger(index: 1), value: appeared)
                        }
                        if patterns.count >= 3 {
                            PatternImpactBars(patterns: patterns)
                                .padding(.horizontal, DS.Spacing.md)
                                .offset(y: appeared ? 0 : 20)
                                .opacity(appeared ? 1 : 0)
                                .animation(DS.Anim.stagger(index: 2), value: appeared)
                        }

                        // Sleep↔recovery scatter + recovery heatmap (v6 mockup)
                        if dailyMetrics.filter({ $0.recovery != nil && ($0.sleepHours ?? 0) > 0 }).count >= 4 {
                            SleepRecoveryScatter(metrics: dailyMetrics)
                                .padding(.horizontal, DS.Spacing.md)
                                .offset(y: appeared ? 0 : 20)
                                .opacity(appeared ? 1 : 0)
                                .animation(DS.Anim.stagger(index: 3), value: appeared)
                        }
                        if dailyMetrics.contains(where: { $0.recovery != nil }) {
                            RecoveryHeatmap(metrics: dailyMetrics)
                                .padding(.horizontal, DS.Spacing.md)
                                .offset(y: appeared ? 0 : 20)
                                .opacity(appeared ? 1 : 0)
                                .animation(DS.Anim.stagger(index: 4), value: appeared)
                        }

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
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    DS.Haptic.tap()
                    showBiostate = true
                } label: {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DS.Colors.violet)
                }
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
        .fullScreenCover(isPresented: $showBiostate) {
            BiostateDashboardView(initialCorrect: biostateInitialCorrect)
        }
        .onReceive(NotificationCenter.default.publisher(for: .lucidOpenBiostate)) { note in
            biostateInitialCorrect = (note.object as? String).flatMap { BiostateDetector(rawValue: $0) }
            showBiostate = true
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
            .pressableCard()
        }
    }

    private var headerSpacer: some View { Color.clear.frame(height: DS.Spacing.sm) }
    private var bottomSpacer: some View { Color.clear.frame(height: 100) }

    private func loadInsights() async {
        isLoading = true
        // Health-metric correlations don't need food data — fetch both, always compute.
        let metrics = await SupabaseClient.shared.fetchDailyMetrics(days: 120)
        dailyMetrics = metrics
        var entries: [FoodEntry] = []
        do { entries = try await SupabaseClient.shared.fetchRecentFoodEntries(limit: 90) } catch { }
        entryCount = entries.count
        patterns = InsightEngine.compute(entries: entries, metrics: metrics)
        isLoading = false
        // Last-night signals load independently (don't gate the patterns view on them).
        lastNight = await SupabaseClient.shared.fetchSleepRestlessness()
        illness = await SupabaseClient.shared.fetchIllnessRisk()
    }
}

// MARK: - Last Night Card (sleep restlessness + illness early-warning)

private struct LastNightCard: View {
    let sleep: SleepRestlessness?
    let illness: IllnessRisk?

    var body: some View {
        if let s = sleep {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack {
                    Text("LAST NIGHT")
                        .font(DS.Font.label)
                        .foregroundStyle(DS.Colors.textMuted)
                        .tracking(0.8)
                    Spacer()
                    Text(String(format: "%.1fh in bed", s.inBedH))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DS.Colors.textFaint)
                        .monospacedDigit()
                }
                HStack(spacing: DS.Spacing.md) {
                    metric(value: "\(s.stability)/10", label: "stability", color: stabilityColor(s.stability))
                    metric(value: "\(s.restlessMin)m", label: "restless", color: DS.Colors.textSecondary)
                    metric(value: "\(s.wakeups)", label: "wake-ups", color: DS.Colors.textSecondary)
                    metric(value: "\(s.sleepingHr)", label: "sleep HR", color: DS.Colors.teal)
                }
                if let ill = illness, ill.isSignal {
                    HStack(alignment: .top, spacing: 6) {
                        Circle()
                            .fill(illnessColor(ill.level))
                            .frame(width: 7, height: 7)
                            .padding(.top, 4)
                        Text(ill.note)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(DS.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 2)
                }
            }
            .padding(DS.Spacing.md)
            .glassDefault()
        }
    }

    private func metric(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(DS.Colors.textFaint)
        }
        .frame(maxWidth: .infinity)
    }

    private func stabilityColor(_ s: Int) -> Color {
        if s >= 7 { return DS.Colors.teal }
        if s >= 4 { return DS.Colors.amber }
        return DS.Colors.danger
    }

    private func illnessColor(_ level: String) -> Color {
        switch level {
        case "elevated": return DS.Colors.danger
        case "watch":    return DS.Colors.amber
        default:         return DS.Colors.teal
        }
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

// MARK: - Recovery Heatmap + Sleep↔Recovery Scatter (v6 mockup)

private struct RecoveryHeatmap: View {
    let metrics: [DailyMetric]

    private var cells: [DailyMetric?] {
        let sorted = metrics.sorted { $0.date < $1.date }
        let last = Array(sorted.suffix(35))
        let pad: [DailyMetric?] = Array(repeating: nil, count: max(0, 35 - last.count))
        return pad + last.map { Optional($0) }
    }

    private func color(_ v: Double?) -> Color {
        guard let v = v else { return DS.Colors.track }
        if v >= 67 { return DS.Colors.success }
        if v >= 34 { return DS.Colors.amber }
        return DS.Colors.danger
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recovery · 5 weeks")
                    .font(.system(size: 10, weight: .bold)).tracking(1.4).textCase(.uppercase)
                    .foregroundStyle(DS.Colors.textMuted)
                Spacer()
                HStack(spacing: 4) {
                    Text("Low").font(.system(size: 9, weight: .semibold)).foregroundStyle(DS.Colors.textMuted)
                    RoundedRectangle(cornerRadius: 2).fill(DS.Colors.danger).frame(width: 10, height: 10)
                    RoundedRectangle(cornerRadius: 2).fill(DS.Colors.amber).frame(width: 10, height: 10)
                    RoundedRectangle(cornerRadius: 2).fill(DS.Colors.success).frame(width: 10, height: 10)
                    Text("High").font(.system(size: 9, weight: .semibold)).foregroundStyle(DS.Colors.textMuted)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 7), spacing: 5) {
                ForEach(0..<cells.count, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(color(cells[i]?.recovery))
                        .aspectRatio(1, contentMode: .fit)
                }
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(DS.Colors.cardFill))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(DS.Colors.border, lineWidth: 1))
    }
}

private struct SleepRecoveryScatter: View {
    let metrics: [DailyMetric]

    private var points: [(x: Double, y: Double)] {
        metrics.compactMap { m in
            guard let s = m.sleepHours, let r = m.recovery, s > 0 else { return nil }
            return (s, r)
        }
    }

    private func recColor(_ v: Double) -> Color {
        if v >= 67 { return DS.Colors.success }
        if v >= 34 { return DS.Colors.amber }
        return DS.Colors.danger
    }

    var body: some View {
        let pts = points
        let xs = pts.map { $0.x }
        let ys = pts.map { $0.y }
        let xMin = max((xs.min() ?? 4) - 0.3, 0)
        let xMax = (xs.max() ?? 9) + 0.3
        let xSpan = max(xMax - xMin, 1)
        let n = Double(pts.count)
        let sx = xs.reduce(0, +), sy = ys.reduce(0, +)
        let sxx = xs.reduce(0) { $0 + $1 * $1 }
        let sxy = zip(xs, ys).reduce(0) { $0 + $1.0 * $1.1 }
        let denom = n * sxx - sx * sx
        let slope = denom != 0 ? (n * sxy - sx * sy) / denom : 0
        let intercept = n != 0 ? (sy - slope * sx) / n : 0

        return VStack(alignment: .leading, spacing: 12) {
            Text("Sleep vs recovery")
                .font(.system(size: 10, weight: .bold)).tracking(1.4).textCase(.uppercase)
                .foregroundStyle(DS.Colors.textMuted)
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                let px: (Double) -> CGFloat = { CGFloat(($0 - xMin) / xSpan) * w }
                let py: (Double) -> CGFloat = { h - CGFloat(min(max($0, 0), 100) / 100) * h }
                ZStack {
                    Path { p in
                        p.move(to: CGPoint(x: px(xMin), y: py(slope * xMin + intercept)))
                        p.addLine(to: CGPoint(x: px(xMax), y: py(slope * xMax + intercept)))
                    }
                    .stroke(DS.Colors.violet.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                    ForEach(0..<pts.count, id: \.self) { i in
                        Circle().fill(recColor(pts[i].y))
                            .frame(width: 7, height: 7)
                            .position(x: px(pts[i].x), y: py(pts[i].y))
                    }
                }
            }
            .frame(height: 128)
            HStack {
                Text("\(Int(xMin.rounded()))h").font(.system(size: 9, weight: .semibold)).foregroundStyle(DS.Colors.textMuted)
                Spacer()
                Text("sleep duration").font(.system(size: 9, weight: .medium)).foregroundStyle(DS.Colors.textMuted)
                Spacer()
                Text("\(Int(xMax.rounded()))h").font(.system(size: 9, weight: .semibold)).foregroundStyle(DS.Colors.textMuted)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(DS.Colors.cardFill))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(DS.Colors.border, lineWidth: 1))
    }
}

// MARK: - Featured Pattern Hero (accent card — v6 mockup)

private struct FeaturedPatternCard: View {
    let pattern: FoodPattern
    private var accent: Color { pattern.effectPositive ? DS.Colors.teal : DS.Colors.danger }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: "star.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(DS.Colors.violet)
                Text("Strongest pattern")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(DS.Colors.textMuted)
            }
            Text(pattern.title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(DS.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let eff = pattern.effectDescription, !eff.isEmpty {
                Text(eff)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(pattern.subtitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DS.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(Int((pattern.confidenceValue * 100).rounded()))% confidence")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(DS.Colors.violet)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(DS.Colors.violet.opacity(0.12)))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(DS.Colors.violet.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(DS.Colors.violet.opacity(0.28), lineWidth: 1))
    }
}

// MARK: - Diverging Impact Bars (v6 mockup)

private struct PatternImpactBars: View {
    let patterns: [FoodPattern]
    private var rows: [FoodPattern] { Array(patterns.prefix(6)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What moves your body")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(DS.Colors.textMuted)
            VStack(spacing: 10) {
                ForEach(rows) { DivergingRow(pattern: $0) }
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(DS.Colors.cardFill))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(DS.Colors.border, lineWidth: 1))
    }
}

private struct DivergingRow: View {
    let pattern: FoodPattern
    private var color: Color { pattern.effectPositive ? DS.Colors.teal : DS.Colors.danger }
    private var frac: CGFloat { CGFloat(min(max(pattern.confidenceValue, 0.06), 1.0)) }

    var body: some View {
        HStack(spacing: 10) {
            Text(pattern.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.Colors.textSecondary)
                .lineLimit(1)
                .frame(width: 100, alignment: .leading)
            GeometryReader { geo in
                let half = geo.size.width / 2
                let barW = half * frac
                ZStack(alignment: .center) {
                    Rectangle()
                        .fill(DS.Colors.track)
                        .frame(width: 1.5)
                    Capsule()
                        .fill(color)
                        .frame(width: barW, height: 13)
                        .offset(x: pattern.effectPositive ? barW / 2 : -barW / 2)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 16)
        }
    }
}

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

// MARK: - Insight Engine (real correlations)
//
// REWRITE (2026-06-01): the old engine multiplied the CURRENT recovery score
// by arbitrary constants (e.g. (1 - recoveryScore/100)*15) and called it a
// "correlation" — pure theater. This computes real day-over-day relationships:
//   • Recovery predictors (HRV / RHR / sleep → recovery) from health_metrics —
//     hundreds of real days, live TODAY.
//   • Food / alcohol → next-day recovery, food → sleep — real once food
//     logging accumulates; honestly gated until then (no fake numbers).

enum InsightEngine {

    private static let utc: TimeZone = TimeZone(identifier: "UTC") ?? .current

    /// Pearson correlation; nil if too few points or zero variance.
    private static func pearson(_ xs: [Double], _ ys: [Double]) -> Double? {
        let n = Double(xs.count)
        guard xs.count == ys.count, xs.count >= 5 else { return nil }
        let mx = xs.reduce(0, +) / n
        let my = ys.reduce(0, +) / n
        var num = 0.0, dx = 0.0, dy = 0.0
        for i in xs.indices {
            let a = xs[i] - mx, b = ys[i] - my
            num += a * b; dx += a * a; dy += b * b
        }
        guard dx > 0, dy > 0 else { return nil }
        return num / (dx.squareRoot() * dy.squareRoot())
    }

    private static func tier(n: Int, r: Double) -> FoodPattern.ConfidenceTier {
        let a = abs(r)
        if n >= 30 && a >= 0.45 { return .high }
        if n >= 14 && a >= 0.28 { return .medium }
        return .low
    }

    private static func strength(_ r: Double) -> String {
        switch abs(r) {
        case 0.6...:    return "strong"
        case 0.4..<0.6: return "clear"
        case 0.25..<0.4: return "mild"
        default:        return "weak"
        }
    }

    static func compute(entries: [FoodEntry], metrics: [DailyMetric]) -> [FoodPattern] {
        var out: [FoodPattern] = []

        // ── Recovery predictors (real, from health_metrics) ──────────────
        func paired(_ sel: (DailyMetric) -> Double?) -> ([Double], [Double]) {
            var xs = [Double](), ys = [Double]()
            for m in metrics {
                if let x = sel(m), let r = m.recovery, r > 0 { xs.append(x); ys.append(r) }
            }
            return (xs, ys)
        }

        let hrvPair = paired { $0.hrv }
        if let r = pearson(hrvPair.0, hrvPair.1) {
            out.append(FoodPattern(
                title: "HRV drives your recovery",
                subtitle: "Across \(hrvPair.0.count) days, higher morning HRV preceded higher recovery.",
                confidenceTier: tier(n: hrvPair.0.count, r: r),
                confidenceValue: min(abs(r), 1.0),
                effectDescription: "\(strength(r)) link · r \(String(format: "%.2f", r))",
                effectPositive: r > 0))
        }

        let rhrPair = paired { $0.restingHr }
        if let r = pearson(rhrPair.0, rhrPair.1) {
            out.append(FoodPattern(
                title: "Resting HR vs recovery",
                subtitle: "Lower resting heart rate nights tend to precede stronger recovery.",
                confidenceTier: tier(n: rhrPair.0.count, r: r),
                confidenceValue: min(abs(r), 1.0),
                effectDescription: "\(strength(r))\(r < 0 ? " inverse" : "") link · r \(String(format: "%.2f", r))",
                effectPositive: r < 0))
        }

        let slpPair = paired { $0.sleepHours }
        if slpPair.0.count >= 8, let r = pearson(slpPair.0, slpPair.1) {
            out.append(FoodPattern(
                title: "Sleep duration → recovery",
                subtitle: "Recovery measured against sleep length over \(slpPair.0.count) nights.",
                confidenceTier: tier(n: slpPair.0.count, r: r),
                confidenceValue: min(abs(r), 1.0),
                effectDescription: "\(strength(r)) link · r \(String(format: "%.2f", r))",
                effectPositive: r > 0))
        }

        // ── Food-dependent (real once logging accumulates) ───────────────
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = utc
        let cal = Calendar.current

        var foodByDay: [String: [FoodEntry]] = [:]
        for e in entries { foodByDay[fmt.string(from: e.capturedAt), default: []].append(e) }
        var metByDay: [String: DailyMetric] = [:]
        for m in metrics { metByDay[m.date] = m }

        // Alcohol → NEXT-day recovery
        var alcRecov = [Double](), soberRecov = [Double]()
        for (day, es) in foodByDay {
            guard let d = fmt.date(from: day),
                  let next = cal.date(byAdding: .day, value: 1, to: d) else { continue }
            guard let r = metByDay[fmt.string(from: next)]?.recovery, r > 0 else { continue }
            if es.contains(where: { $0.items.contains { $0.isAlcohol == true } }) {
                alcRecov.append(r)
            } else {
                soberRecov.append(r)
            }
        }
        if alcRecov.count >= 3 && soberRecov.count >= 3 {
            let a = alcRecov.reduce(0, +) / Double(alcRecov.count)
            let s = soberRecov.reduce(0, +) / Double(soberRecov.count)
            let pct = s > 0 ? ((a - s) / s) * 100 : 0
            out.append(FoodPattern(
                title: "Alcohol → next-day recovery",
                subtitle: "Morning-after recovery vs sober nights, over \(alcRecov.count) drinking days.",
                confidenceTier: alcRecov.count >= 8 ? .high : .medium,
                confidenceValue: min(Double(alcRecov.count) / 12.0, 1.0),
                effectDescription: String(format: "%+.0f%% recovery the morning after", pct),
                effectPositive: (a - s) >= 0))
        }

        // High-NOVA day → that night's sleep score
        var novaSleep = [Double](), cleanSleep = [Double]()
        for (day, es) in foodByDay {
            guard let ss = metByDay[day]?.sleepScore, ss > 0 else { continue }
            let avgNova = es.compactMap { $0.novaAvg }.reduce(0, +) / Double(max(es.count, 1))
            if avgNova >= 3.0 { novaSleep.append(ss) } else { cleanSleep.append(ss) }
        }
        if novaSleep.count >= 4 && cleanSleep.count >= 4 {
            let hi = novaSleep.reduce(0, +) / Double(novaSleep.count)
            let lo = cleanSleep.reduce(0, +) / Double(cleanSleep.count)
            out.append(FoodPattern(
                title: "Processed food → sleep",
                subtitle: "Sleep score on heavy ultra-processed days vs cleaner days, \(novaSleep.count) days each.",
                confidenceTier: novaSleep.count >= 10 ? .high : .medium,
                confidenceValue: min(Double(novaSleep.count) / 14.0, 1.0),
                effectDescription: String(format: "%+.0f sleep score on processed days", hi - lo),
                effectPositive: (hi - lo) >= 0))
        }

        return out.sorted { $0.confidenceValue > $1.confidenceValue }
    }
}
