import SwiftUI

/// Compact 60pt HRV companion ring — today vs personal baseline.
/// Used in Health tab. Color-coded by deviation from baseline.
struct HRVRingMini: View {
    let today: Double      // today's HRV (RMSSD ms)
    let baseline: Double   // personal baseline HRV
    var size: CGFloat = 60
    var lineWidth: CGFloat = 6

    @State private var appeared = false

    private var ratio: Double { baseline > 0 ? today / baseline : 0 }
    private var trimEnd: CGFloat { appeared ? min(CGFloat(ratio), 1.0) : 0 }

    private var ringColor: Color {
        if ratio >= 0.95 { return DS.Colors.teal }
        if ratio >= 0.75 { return DS.Colors.warning }
        return DS.Colors.danger
    }

    private var deltaText: String {
        let diff = today - baseline
        return diff >= 0 ? "+\(Int(diff))" : "\(Int(diff))"
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(ringColor.opacity(0.12), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: trimEnd)
                .stroke(
                    ringColor,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(DS.Anim.ringFill.delay(0.1), value: appeared)

            VStack(spacing: 1) {
                Text("\(Int(today))")
                    .font(.system(size: size * 0.28, weight: .heavy, design: .rounded))
                    .foregroundStyle(ringColor)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("ms")
                    .font(.system(size: size * 0.14, weight: .bold))
                    .foregroundStyle(DS.Colors.textMuted)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(DS.Anim.ringFill.delay(0.1)) { appeared = true }
        }
    }
}

#Preview {
    ZStack {
        MeshGradientBackground()
        HStack(spacing: 30) {
            VStack(spacing: 6) {
                HRVRingMini(today: 52, baseline: 48)
                Text("Above baseline").font(DS.Font.caption).foregroundStyle(DS.Colors.textMuted)
            }
            VStack(spacing: 6) {
                HRVRingMini(today: 35, baseline: 48)
                Text("Below baseline").font(DS.Font.caption).foregroundStyle(DS.Colors.textMuted)
            }
        }
        .padding()
    }
}
