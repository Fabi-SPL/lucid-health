import SwiftUI

/// Confidence-tier insight card — used in InsightsView.
struct InsightCard: View {
    let pattern: FoodPattern

    private var tierColor: Color {
        switch pattern.confidenceTier {
        case .high:   return DS.Colors.teal
        case .medium: return DS.Colors.amber
        case .low:    return DS.Colors.textFaint
        }
    }

    private var tierLabel: String {
        switch pattern.confidenceTier {
        case .high:   return "High confidence"
        case .medium: return "Emerging"
        case .low:    return "Early data"
        }
    }

    @State private var appeared = false

    private var isLucid: Bool { pattern.source == .lucid }
    private var provenanceColor: Color { isLucid ? DS.Colors.teal : DS.Colors.violet }

    private var provenanceBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: isLucid ? "diamond.fill" : "sparkles")
                .font(.system(size: 8, weight: .bold))
            Text(isLucid ? "LUCID · computed" : "GEMINI · AI guess")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(0.5)
        }
        .foregroundStyle(provenanceColor)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(provenanceColor.opacity(0.12)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            provenanceBadge
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(pattern.title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.Colors.textPrimary)
                    Text(pattern.subtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(DS.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                GlassStatusPill(icon: "chart.bar.fill", text: tierLabel, color: tierColor)
            }

            if let effect = pattern.effectDescription {
                HStack(spacing: 6) {
                    Image(systemName: pattern.effectPositive ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(pattern.effectPositive ? DS.Colors.teal : DS.Colors.pink)
                    Text(effect)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DS.Colors.textSecondary)
                }
            }

            // Confidence bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(DS.Colors.surfaceElevated)
                        .frame(height: 3)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(tierColor)
                        .frame(width: appeared ? geo.size.width * CGFloat(pattern.confidenceValue) : 0, height: 3)
                        .animation(DS.Anim.cardAppear.delay(0.2), value: appeared)
                }
            }
            .frame(height: 3)

            if let note = pattern.dataQualityNote {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DS.Colors.amber)
                    Text(note)
                        .font(.system(size: 10.5, weight: .regular))
                        .foregroundStyle(DS.Colors.textFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(DS.Spacing.lg)
        .glassDefault()
        .onAppear { appeared = true }
    }
}

// MARK: - Models

/// One day of health_metrics, dated so food (by day) can be joined to it.
struct DailyMetric {
    let date: String          // "yyyy-MM-dd" (UTC metric_date)
    let recovery: Double?
    let sleepScore: Double?
    let sleepHours: Double?
    let hrv: Double?
    let restingHr: Double?
    let alcoholImpact: Double?
}

struct FoodPattern: Identifiable {
    let id: UUID
    let title: String
    let subtitle: String
    let confidenceTier: ConfidenceTier
    let confidenceValue: Double    // 0.0–1.0
    let effectDescription: String?
    let effectPositive: Bool
    let source: Source             // who made this connection
    let dataQualityNote: String?   // e.g. "logging inconsistent — read loosely"

    enum ConfidenceTier { case high, medium, low }
    // Provenance: .lucid = deterministic correlation we computed. .gemini = AI-generated, speculative.
    enum Source { case lucid, gemini }

    init(
        id: UUID = UUID(),
        title: String,
        subtitle: String,
        confidenceTier: ConfidenceTier,
        confidenceValue: Double,
        effectDescription: String? = nil,
        effectPositive: Bool = true,
        source: Source = .lucid,
        dataQualityNote: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.confidenceTier = confidenceTier
        self.confidenceValue = confidenceValue
        self.effectDescription = effectDescription
        self.effectPositive = effectPositive
        self.source = source
        self.dataQualityNote = dataQualityNote
    }
}
