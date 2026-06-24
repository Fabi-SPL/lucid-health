import SwiftUI

/// Pulsing ambient dot for live-data BLE-connected sections.
/// 2.4s breath cycle. Variants: connected / scanning / disconnected.
enum LiveDotState {
    case connected, scanning, disconnected

    var color: Color {
        switch self {
        case .connected:    return DS.Colors.teal
        case .scanning:     return DS.Colors.amber
        case .disconnected: return DS.Colors.textFaint
        }
    }

    var isPulsing: Bool {
        switch self {
        case .connected, .scanning: return true
        case .disconnected:         return false
        }
    }
}

struct AmbientLiveDot: View {
    let state: LiveDotState
    var size: CGFloat = 8

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    var body: some View {
        ZStack {
            if state.isPulsing && !reduceMotion {
                Circle()
                    .fill(state.color.opacity(0.30))
                    .frame(width: size * 2.0, height: size * 2.0)
                    .scaleEffect(breathing ? 1.0 : 0.6)
                    .opacity(breathing ? 0 : 0.6)
                    .animation(
                        .easeOut(duration: 2.4).repeatForever(autoreverses: false),
                        value: breathing
                    )
            }
            Circle()
                .fill(state.color)
                .frame(width: size, height: size)
                .scaleEffect(breathing && state.isPulsing && !reduceMotion ? 1.05 : 1.0)
                .animation(DS.Anim.breath, value: breathing)
        }
        .onAppear { breathing = state.isPulsing }
        .onChange(of: state.isPulsing) { _, pulsing in breathing = pulsing }
    }
}

#Preview {
    ZStack {
        AuroraBackground()
        VStack(spacing: 20) {
            HStack(spacing: 10) {
                AmbientLiveDot(state: .connected)
                Text("Connected").font(DS.Font.body).foregroundStyle(DS.Colors.textPrimary)
            }
            HStack(spacing: 10) {
                AmbientLiveDot(state: .scanning)
                Text("Scanning…").font(DS.Font.body).foregroundStyle(DS.Colors.textPrimary)
            }
            HStack(spacing: 10) {
                AmbientLiveDot(state: .disconnected)
                Text("Disconnected").font(DS.Font.body).foregroundStyle(DS.Colors.textMuted)
            }
        }
        .padding()
    }
}
