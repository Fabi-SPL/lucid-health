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
        case .high:   return "Hohes Vertrauen"
        case .medium: return "Mittleres Vertrauen"
        case .low:    return "Frühe Daten"
        }
    }

    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
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

    enum ConfidenceTier { case high, medium, low }

    init(
        id: UUID = UUID(),
        title: String,
        subtitle: String,
        confidenceTier: ConfidenceTier,
        confidenceValue: Double,
        effectDescription: String? = nil,
        effectPositive: Bool = true
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.confidenceTier = confidenceTier
        self.confidenceValue = confidenceValue
        self.effectDescription = effectDescription
        self.effectPositive = effectPositive
    }
}
