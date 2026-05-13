import SwiftUI

/// Semicircle gauge for illness risk (0-4).
struct IllnessRiskGauge: View {
    let risk: Int   // 0-4
    let alert: String?

    @State private var appeared = false

    private var color: Color {
        switch risk {
        case 0:    return DS.Colors.success
        case 1:    return DS.Colors.teal
        case 2:    return DS.Colors.amber
        case 3, 4: return DS.Colors.pink
        default:   return DS.Colors.textFaint
        }
    }

    private var label: String {
        switch risk {
        case 0:    return "No risk"
        case 1:    return "Low"
        case 2:    return "Monitor"
        case 3:    return "Elevated"
        case 4:    return "High"
        default:   return "—"
        }
    }

    private var trimEnd: CGFloat {
        appeared ? CGFloat(risk) / 4.0 : 0
    }

    var body: some View {
        VStack(spacing: DS.Spacing.sm) {
            ZStack {
                // Track
                Circle()
                    .trim(from: 0.25, to: 0.75)
                    .stroke(DS.Colors.surfaceElevated, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(90))

                // Fill
                Circle()
                    .trim(from: 0.25, to: 0.25 + trimEnd * 0.5)
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(90))
                    .animation(DS.Anim.cardAppear, value: trimEnd)

                VStack(spacing: 1) {
                    Text("\(risk)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(color)
                        .monospacedDigit()
                    Text("/ 4")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(DS.Colors.textFaint)
                }
                .offset(y: 6)
            }

            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(color)

            if let alert {
                Text(alert)
                    .font(.system(size: 10))
                    .foregroundStyle(DS.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .onAppear {
            withAnimation(DS.Anim.cardAppear.delay(0.2)) { appeared = true }
        }
    }
}
