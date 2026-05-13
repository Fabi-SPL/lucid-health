import SwiftUI

/// Featured card for the most recent meal — larger, richer layout.
struct LastMealCard: View {
    let entry: FoodEntry

    private var mindColor: Color {
        DS.Colors.mindColor(Double(entry.mindScore ?? 0))
    }

    private var timeAgo: String {
        let diff = Date().timeIntervalSince(entry.capturedAt)
        if diff < 3600 {
            return "\(Int(diff / 60)) min ago"
        } else {
            let h = Int(diff / 3600)
            return "\(h) h ago"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack {
                SectionHeader(title: "Last meal")
                Spacer()
                Text(timeAgo)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.Colors.textFaint)
            }

            Text(entry.caption ?? entry.items.map(\.name).joined(separator: " · "))
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.Colors.textPrimary)
                .lineLimit(2)

            HStack(spacing: DS.Spacing.md) {
                if let kcal = entry.totalKcal, kcal > 0 {
                    MetricChip(
                        label: "\(kcal)",
                        unit: "kcal",
                        color: DS.Colors.amber
                    )
                }
                if let mind = entry.mindScore, mind > 0 {
                    MetricChip(
                        label: "\(mind)",
                        unit: "/ 15 brain",
                        color: mindColor
                    )
                }
                if let nova = entry.novaAvg, nova > 0 {
                    MetricChip(
                        label: String(format: "%.1f", nova),
                        unit: "NOVA",
                        color: DS.Colors.novaColor(nova)
                    )
                }
            }

            if !entry.items.isEmpty {
                FlowItemRow(items: entry.items.map { $0.name })
            }
        }
        .padding(DS.Spacing.lg)
        .glassCard()
    }
}

private struct MetricChip: View {
    let label: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
            Text(unit)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DS.Colors.textFaint)
        }
    }
}

private struct FlowItemRow: View {
    let items: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.xs) {
                ForEach(items, id: \.self) { name in
                    Text(name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DS.Colors.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(DS.Colors.surfaceElevated)
                                .overlay(Capsule().stroke(DS.Colors.border, lineWidth: 0.5))
                        )
                }
            }
        }
    }
}
