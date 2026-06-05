import SwiftUI

/// Wind-Down takeover — a calm full-screen page that comes up once per night
/// when wind-down mode opens (22:00). A slow breathing circle sets the pace;
/// tonight's plan (including alcohol-recovery note) is shown below. Dismissed
/// with the single button. Part of Smart Alarm Module 7.
struct WindDownView: View {
    @ObservedObject var bleManager: BLEManager
    let onDismiss: () -> Void

    @State private var breathe = false
    @State private var appeared = false

    private var isAlcohol: Bool { bleManager.tonightPlanMode == "alcohol" }

    private var planNote: String {
        if !bleManager.tonightPlanNote.isEmpty { return bleManager.tonightPlanNote }
        return "Lights low, screens away. Let your heart rate settle."
    }

    private func fmt(_ mins: Int) -> String {
        "\(String(format: "%02d", mins / 60)):\(String(format: "%02d", mins % 60))"
    }

    var body: some View {
        ZStack {
            MeshGradientBackground().ignoresSafeArea()

            VStack(spacing: DS.Spacing.lg) {
                Spacer()

                // Breathing hero — the pace-setter.
                ZStack {
                    Circle()
                        .fill(DS.Colors.violet.opacity(0.10))
                        .frame(width: 240, height: 240)
                        .scaleEffect(breathe ? 1.12 : 0.82)
                    Circle()
                        .stroke(DS.Colors.violet.opacity(0.35), lineWidth: 1)
                        .frame(width: 200, height: 200)
                        .scaleEffect(breathe ? 1.12 : 0.82)
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 52, weight: .light))
                        .foregroundStyle(DS.Colors.violet)
                        .symbolRenderingMode(.hierarchical)
                        .scaleEffect(breathe ? 1.06 : 0.94)
                }
                .animation(.easeInOut(duration: 4).repeatForever(autoreverses: true), value: breathe)

                VStack(spacing: 6) {
                    Text(isAlcohol ? "Wind down · recovery night" : "Wind down")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.Colors.textPrimary)
                    Text(breathe ? "Breathe out" : "Breathe in")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(DS.Colors.textSecondary)
                        .animation(.easeInOut(duration: 4).repeatForever(autoreverses: true), value: breathe)
                }

                // Tonight's plan note.
                VStack(alignment: .leading, spacing: 10) {
                    if isAlcohol {
                        HStack(spacing: 6) {
                            Text("\u{1F377}").font(.system(size: 14))
                            Text("ALCOHOL MODE")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(DS.Colors.amber)
                                .tracking(1.2)
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
                                 ? "No early alarm. Watch starts \(fmt(bleManager.tonightWindowStart)), backstop \(fmt(bleManager.tonightWindowEnd))."
                                 : "Wake window \(fmt(bleManager.tonightWindowStart))–\(fmt(bleManager.tonightWindowEnd)).")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(DS.Colors.textMuted)
                        }
                    }
                }
                .padding(DS.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(DS.Colors.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke((isAlcohol ? DS.Colors.amber : DS.Colors.violet).opacity(0.22), lineWidth: 0.5)
                        )
                )
                .padding(.horizontal, DS.Spacing.lg)

                Spacer()

                Button {
                    let h = UIImpactFeedbackGenerator(style: .medium)
                    h.impactOccurred()
                    onDismiss()
                } label: {
                    Text(isAlcohol ? "Got it — goodnight" : "I'm winding down")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            Capsule().fill(DS.Colors.violet)
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.xl)
            }
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            breathe = true
            withAnimation(.easeOut(duration: 0.5)) { appeared = true }
        }
    }
}
