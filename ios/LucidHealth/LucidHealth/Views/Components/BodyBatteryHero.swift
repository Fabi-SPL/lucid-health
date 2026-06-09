import SwiftUI

/// Body Battery hero — the MAIN metric on Today. A horizontal battery that fills
/// with the carry-over tank level (green/amber/red), a big number, a plain-language
/// status, and a demoted secondary row (recovery / sleep / stress).
///
/// Body Battery answers "how much can I actually push today" — it carries over
/// day-to-day and refills slowly, unlike recovery which is a memoryless
/// single-night charge. (Why "92% recovery but I feel like shit" happens.)
struct BodyBatteryHero: View {
    let level: Double          // 0..100 — the tank
    let recovery: Double       // demoted to secondary
    let sleepHours: Double
    let strain: Double         // 0..21

    private var lvl: Int { Int(level.rounded()) }
    private var color: Color { DS.Colors.bodyBatteryColor(level) }

    private var statusLine: String {
        switch level {
        case 75...:    return "Full tank. Green light to push hard today."
        case 55..<75:  return "Good charge. Train, work, go — just don't redline."
        case 35..<55:  return "Half tank. A normal day's fine; skip the big efforts."
        case 20..<35:  return "Low. Protect it — easy day, real recovery."
        default:       return "Running on fumes. Rest is the only smart move."
        }
    }
    private var stressLabel: String {
        if strain >= 14 { return "high" }
        if strain >= 7  { return "med" }
        return "low"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(color)
                Text("BODY BATTERY")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(DS.Colors.textFaint)
                Spacer()
                Text("in the tank")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DS.Colors.textFaint)
            }

            // Big number
            Text("\(lvl)")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundStyle(DS.Colors.textPrimary)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.4), value: lvl)

            // Battery gauge
            BatteryBar(level: level, color: color)
                .frame(height: 30)

            // Plain-language status
            Text(statusLine)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DS.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider().background(DS.Colors.border)

            // Secondary row — recovery DEMOTED here (still visible, not the headline)
            HStack(spacing: 0) {
                secondaryStat("recovery", "\(Int(recovery))", DS.Colors.recoveryColor(recovery))
                statDivider
                secondaryStat("sleep", String(format: "%.1fh", sleepHours), DS.Colors.textSecondary)
                statDivider
                secondaryStat("stress", stressLabel, DS.Colors.textSecondary)
            }
        }
        .padding(DS.Spacing.lg)
        .heroCard()
    }

    @ViewBuilder
    private func secondaryStat(_ label: String, _ value: String, _ valueColor: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(valueColor)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .tracking(0.5)
                .foregroundStyle(DS.Colors.textFaint)
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(DS.Colors.border)
            .frame(width: 0.5, height: 24)
    }
}

/// Horizontal battery: rounded body + terminal nub, fill width = level, animated.
private struct BatteryBar: View {
    let level: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let termW: CGFloat = 6
            let gap: CGFloat = 4
            let inset: CGFloat = 3
            let bodyW = w - termW - gap
            let fillMax = bodyW - inset * 2
            let pct = CGFloat(max(0.03, min(1, level / 100)))

            HStack(spacing: gap) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(DS.Colors.surfaceElevated)
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(DS.Colors.border, lineWidth: 1)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(LinearGradient(colors: [color.opacity(0.82), color],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(10, fillMax * pct), height: h - inset * 2)
                        .padding(.leading, inset)
                        .animation(.easeInOut(duration: 0.5), value: level)
                }
                .frame(width: bodyW, height: h)

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(DS.Colors.border)
                    .frame(width: termW, height: h * 0.42)
            }
        }
    }
}
