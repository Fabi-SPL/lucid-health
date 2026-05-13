import SwiftUI

/// HR zone breakdown: stacked bar + zone labels + minutes.
struct StrainZonesBar: View {
    let zoneMinutes: [Int]  // [zone0, zone1, zone2, zone3, zone4]

    private struct Zone: Identifiable {
        let id: Int
        let name: String
        let minutes: Int
        let color: Color
    }

    private var zones: [Zone] {
        let names = ["Rest", "Light", "Aerobic", "Anaerobic", "Peak"]
        let colors: [Color] = [
            DS.Colors.textFaint.opacity(0.5),
            DS.Colors.success,
            DS.Colors.teal,
            DS.Colors.amber,
            DS.Colors.pink
        ]
        return zip(zoneMinutes.indices, zoneMinutes).map { i, mins in
            Zone(id: i, name: names[i], minutes: mins, color: colors[i])
        }.filter { $0.minutes > 0 }
    }

    private var totalMinutes: Double {
        Double(zoneMinutes.reduce(0, +))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            if zones.isEmpty || totalMinutes == 0 {
                Text("No activity data")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Colors.textFaint)
            } else {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(zones) { zone in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(zone.color)
                                .frame(width: max(2, geo.size.width * CGFloat(Double(zone.minutes) / totalMinutes)))
                        }
                    }
                }
                .frame(height: 10)
                .clipShape(RoundedRectangle(cornerRadius: 5))

                // Two-column legend
                let gridCols = [GridItem(.flexible()), GridItem(.flexible())]
                LazyVGrid(columns: gridCols, spacing: 3) {
                    ForEach(zones) { zone in
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(zone.color)
                                .frame(width: 8, height: 5)
                            Text(zone.name)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(DS.Colors.textFaint)
                            Spacer()
                            Text("\(zone.minutes)m")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(DS.Colors.textSecondary)
                        }
                    }
                }
            }
        }
    }
}
