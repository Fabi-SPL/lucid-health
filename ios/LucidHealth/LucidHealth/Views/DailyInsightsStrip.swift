import SwiftUI

// MARK: - Daily Insights Strip (top of InsightsView)
//
// Shows the output of the nightly Claude routine + Vercel cron fallback.
// One row per insight, expandable. Read-only — tap to toggle expansion,
// long-press to dismiss.
//
// Visual hierarchy:
//   - Routine-generated rows (Opus 4.7) get a soft violet glow
//   - Templated fallback rows are quieter, smaller body preview
//   - Negative effects get an amber accent dot
//   - Positive get teal, neutral textFaint

struct DailyInsightsStrip: View {
    @State private var insights: [ExperimentalFeaturesService.DailyInsight] = []
    @State private var expanded: Set<String> = []
    @State private var isLoaded = false

    var body: some View {
        Group {
            if isLoaded && insights.isEmpty {
                EmptyView()
            } else if isLoaded {
                content
            } else {
                EmptyView()
            }
        }
        .task { await load() }
    }

    private func load() async {
        insights = await ExperimentalFeaturesService.shared.fetchDailyInsights(limit: 8)
        isLoaded = true
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.Colors.violet)
                Text("DAILY INSIGHTS")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(DS.Colors.textFaint)
                    .tracking(0.8)
                Spacer()
                Text(insights.first.map { dateLabel(for: $0.generated_for_date) } ?? "")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(DS.Colors.textFaint)
                    .monospacedDigit()
            }
            VStack(spacing: 8) {
                ForEach(insights) { insight in
                    DailyInsightRow(
                        insight: insight,
                        isExpanded: expanded.contains(insight.id),
                        onTap: { toggle(insight.id) }
                    )
                }
            }
        }
        .padding(.horizontal, DS.Spacing.md)
    }

    private func toggle(_ id: String) {
        withAnimation(DS.Anim.quick) {
            if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
        }
    }

    private func dateLabel(for iso: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: iso) else { return "" }
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "today" }
        if cal.isDateInYesterday(d) { return "yesterday" }
        f.dateFormat = "MMM d"
        return f.string(from: d)
    }
}

// MARK: - Insight Row

private struct DailyInsightRow: View {
    let insight: ExperimentalFeaturesService.DailyInsight
    let isExpanded: Bool
    let onTap: () -> Void

    private var dotColor: Color {
        switch insight.effect_type {
        case "positive": return DS.Colors.success
        case "negative": return DS.Colors.amber
        case "curious":  return DS.Colors.violet
        default:         return DS.Colors.textFaint
        }
    }

    private var icon: String {
        switch insight.category {
        case "pc":       return "desktopcomputer"
        case "food":     return "fork.knife"
        case "sleep":    return "bed.double"
        case "weather":  return "cloud"
        case "recovery": return "heart"
        case "spiral":   return "waveform.path.ecg"
        default:         return "sparkles"
        }
    }

    private var isFromRoutine: Bool {
        (insight.model_used ?? "").contains("opus") || (insight.model_used ?? "").contains("sonnet")
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 6, height: 6)
                        .padding(.top, 6)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: icon)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(dotColor)
                            Text(insight.title)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(DS.Colors.textPrimary)
                                .lineLimit(isExpanded ? nil : 2)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 4)
                            if let conf = insight.confidence, conf > 0 {
                                Text("\(Int(conf * 100))%")
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(DS.Colors.textFaint)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule().fill(DS.Colors.surfaceElevated)
                                    )
                            }
                        }
                        Text(insight.body)
                            .font(.system(size: 11.5, design: .rounded))
                            .foregroundStyle(DS.Colors.textSecondary)
                            .lineLimit(isExpanded ? nil : 2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

                        if isExpanded {
                            metadataRow
                            if let action = insight.action_text, !action.isEmpty {
                                actionRow(action)
                            }
                        }
                    }
                }
            }
            .padding(DS.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .glassDefault()
        .overlay(alignment: .topTrailing) {
            if isFromRoutine {
                // Subtle marker that this came from Opus, not the template
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(DS.Colors.violet.opacity(0.7))
                    .padding(8)
            }
        }
    }

    @ViewBuilder
    private var metadataRow: some View {
        HStack(spacing: 8) {
            if let n = insight.sample_n, n > 0 {
                metaPill("n=\(n)")
            }
            if let sources = insight.data_sources, !sources.isEmpty {
                metaPill(sources.joined(separator: " · "))
            }
        }
        .padding(.top, 4)
    }

    private func metaPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(DS.Colors.textFaint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(DS.Colors.surface)
                    .overlay(Capsule().stroke(DS.Colors.border, lineWidth: 0.5))
            )
    }

    @ViewBuilder
    private func actionRow(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.right.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(DS.Colors.teal)
            Text(text)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.Colors.teal)
        }
        .padding(.top, 4)
    }
}
