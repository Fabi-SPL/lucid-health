import SwiftUI

/// Single meal entry row — used in Today and Food list views.
struct MealCard: View {
    let entry: FoodEntry

    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: entry.capturedAt)
    }

    private var mindColor: Color {
        DS.Colors.mindColor(Double(entry.mindScore ?? 0))
    }

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            // Left: colored mind-score bar
            RoundedRectangle(cornerRadius: 2)
                .fill(mindColor)
                .frame(width: 3, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.caption ?? entry.items.map(\.name).joined(separator: ", "))
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(DS.Colors.textPrimary)
                    .lineLimit(1)

                HStack(spacing: DS.Spacing.sm) {
                    if let kcal = entry.totalKcal, kcal > 0 {
                        Label("\(kcal) kcal", systemImage: "flame.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(DS.Colors.amber)
                    }
                    if let nova = entry.novaAvg, nova > 0 {
                        Label("NOVA \(String(format: "%.1f", nova))", systemImage: "leaf.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(DS.Colors.novaColor(nova))
                    }
                }
            }

            Spacer()

            Text(timeString)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(DS.Colors.textFaint)
        }
        .padding(DS.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(DS.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .stroke(DS.Colors.border, lineWidth: 0.5)
                )
        )
    }
}
