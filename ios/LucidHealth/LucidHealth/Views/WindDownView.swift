import SwiftUI

/// Wind-Down takeover — a calm full-screen page that comes up once per night
/// when wind-down mode opens (22:00). A soft breathing glow sets the pace (4s in,
/// 4s out, time-driven); tonight's plan (including alcohol-recovery note) sits
/// below in a glass card. Dismissed with the single button. Smart Alarm Module 7.
struct WindDownView: View {
    @ObservedObject var bleManager: BLEManager
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var isAlcohol: Bool { bleManager.tonightPlanMode == "alcohol" }
    private var accent: Color { isAlcohol ? DS.Colors.amber : DS.Colors.violet }
    private var planNote: String {
        bleManager.tonightPlanNote.isEmpty
            ? "Lights low, screens away. Let your heart rate settle."
            : bleManager.tonightPlanNote
    }
    private func fmt(_ mins: Int) -> String {
        "\(String(format: "%02d", mins / 60)):\(String(format: "%02d", mins % 60))"
    }

    var body: some View {
        ZStack {
            AuroraBackground().ignoresSafeArea()
            // Vignette — dims the edges so the breathing glow + content hold the
            // centre. Depth, instead of competing violet-on-violet.
            RadialGradient(
                colors: [Color.black.opacity(0.0), Color.black.opacity(0.30)],
                center: .center, startRadius: 180, endRadius: 560
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 28) {
                Spacer()
                breathingSection
                planCard.padding(.horizontal, DS.Spacing.lg)
                Spacer()
                dismissButton
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.bottom, DS.Spacing.xl)
            }
            .opacity(appeared ? 1 : 0)
        }
        .onAppear { withAnimation(.easeOut(duration: 0.6)) { appeared = true } }
    }

    // Time-driven breath: an 8s cycle (4s in, 4s out). The glow is a radial
    // gradient that fades fully to clear — no hard disc edge (that was the
    // "broken gradient"). Glow + hairline ring + moon scale together; the
    // instruction text follows the same clock.
    private var breathingSection: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 86400 : 1.0 / 30.0)) { context in
            let t = reduceMotion ? 0.0 : context.date.timeIntervalSinceReferenceDate
            let cycle = (sin(t * .pi / 4) + 1) / 2          // 0…1 over 8s
            let inhaling = cos(t * .pi / 4) >= 0

            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [accent.opacity(0.42), accent.opacity(0.0)],
                                center: .center, startRadius: 2, endRadius: 150
                            )
                        )
                        .frame(width: 300, height: 300)
                        .blur(radius: 8)
                        .scaleEffect(0.70 + 0.30 * cycle)
                    Circle()
                        .stroke(accent.opacity(0.28), lineWidth: 1)
                        .frame(width: 188, height: 188)
                        .scaleEffect(0.80 + 0.20 * cycle)
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(accent)
                        .symbolRenderingMode(.hierarchical)
                        .scaleEffect(0.92 + 0.08 * cycle)
                }
                .frame(height: 300)

                VStack(spacing: 6) {
                    Text(isAlcohol ? "Wind down · recovery night" : "Wind down")
                        .font(.system(size: 27, weight: .semibold, design: .rounded))
                        .tracking(-0.4)
                        .foregroundStyle(DS.Colors.textPrimary)
                    Text(reduceMotion ? "Slow your breathing" : (inhaling ? "Breathe in" : "Breathe out"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DS.Colors.textSecondary)
                        .contentTransition(.opacity)
                }
            }
        }
    }

    private var planCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isAlcohol {
                HStack(spacing: 6) {
                    Text("\u{1F377}").font(.system(size: 13))
                    Text("ALCOHOL MODE")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(DS.Colors.amber)
                }
            }
            Text(planNote)
                .font(.system(size: 13))
                .foregroundStyle(DS.Colors.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            if bleManager.tonightWindowStart > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "alarm")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.Colors.textMuted)
                    Text(isAlcohol
                         ? "No early alarm. Watching from \(fmt(bleManager.tonightWindowStart)), backstop \(fmt(bleManager.tonightWindowEnd))."
                         : "Wake window \(fmt(bleManager.tonightWindowStart)) to \(fmt(bleManager.tonightWindowEnd)).")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DS.Colors.textMuted)
                }
            }
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)             // real glass — the mesh refracts through
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(accent.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                )
        )
    }

    private var dismissButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onDismiss()
        } label: {
            Text(isAlcohol ? "Got it, goodnight" : "I'm winding down")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Capsule().fill(DS.Colors.violet))
        }
        .buttonStyle(WindDownPressStyle())
    }
}

/// Tactile press — every interactive element should respond to touch.
private struct WindDownPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}
