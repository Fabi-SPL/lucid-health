import SwiftUI

/// Large animated recovery ring — primary hero element on TodayView.
/// Backwards-compatible signature. Upgraded internals: ringEntrance spring,
/// violet→teal gradient when recovered, breathing animation.
struct RecoveryRingHero: View {
    let score: Double        // 0–100
    let label: String        // "Good", "Okay", "Low"
    var size: CGFloat = 160
    var lineWidth: CGFloat = 14

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var breathing = false

    private var trimEnd: CGFloat { appeared ? CGFloat(score / 100.0) : 0 }

    private var strokeColors: [Color] {
        if score >= 67 { return [DS.Colors.violet.opacity(0.7), DS.Colors.teal] }
        if score >= 34 { return [DS.Colors.amber.opacity(0.7), DS.Colors.warning] }
        return [DS.Colors.danger.opacity(0.7), DS.Colors.danger]
    }

    private var glowColor: Color { DS.Colors.recoveryColor(score) }

    var body: some View {
        ZStack {
            // Track ring
            Circle()
                .stroke(glowColor.opacity(0.12), lineWidth: lineWidth)
                .frame(width: size, height: size)

            // Progress arc — angular gradient, ringEntrance spring
            Circle()
                .trim(from: 0, to: trimEnd)
                .stroke(
                    AngularGradient(
                        colors: strokeColors,
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
                .animation(DS.Anim.ringEntrance.delay(0.1), value: appeared)

            // Center content
            VStack(spacing: 2) {
                Text("\(Int(score))")
                    .font(.system(size: size * 0.28, weight: .heavy, design: .rounded))
                    .foregroundStyle(DS.Colors.textPrimary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .scaleEffect(breathing ? 1.012 : 1.0)
                    .animation(
                        reduceMotion ? .default : DS.Anim.breath,
                        value: breathing
                    )

                Text(label.uppercased())
                    .font(.system(size: size * 0.085, weight: .bold, design: .rounded))
                    .foregroundStyle(glowColor)
                    .tracking(1.5)
            }
        }
        .onAppear {
            withAnimation(DS.Anim.ringEntrance.delay(0.1)) { appeared = true }
            if !reduceMotion {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    breathing = true
                }
            }
        }
    }
}

#Preview {
    ZStack {
        AuroraBackground()
        VStack(spacing: 32) {
            RecoveryRingHero(score: 82, label: "Good")
            RecoveryRingHero(score: 47, label: "Okay", size: 120, lineWidth: 11)
            RecoveryRingHero(score: 21, label: "Low", size: 100, lineWidth: 10)
        }
    }
}
