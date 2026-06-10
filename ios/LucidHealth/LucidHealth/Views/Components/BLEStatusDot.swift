import SwiftUI

/// Compact BLE connection indicator — pulsing dot with label.
struct BLEStatusDot: View {
    @EnvironmentObject private var bleManager: BLEManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var color: Color {
        switch bleManager.connectionState {
        case .connected, .streaming: return DS.Colors.teal
        case .syncing:               return DS.Colors.violet
        case .scanning, .connecting: return DS.Colors.amber
        case .disconnected:          return DS.Colors.textFaint
        }
    }

    private var label: String {
        switch bleManager.connectionState {
        case .connected:    return "Connected"
        case .streaming:    return "Live"
        case .syncing:      return "Syncing…"
        case .scanning:     return "Searching…"
        case .connecting:   return "Connecting…"
        case .disconnected: return "Disconnected"
        }
    }

    private var isPulsing: Bool {
        switch bleManager.connectionState {
        case .scanning, .connecting, .syncing, .streaming: return true
        default: return false
        }
    }

    @State private var pulse = false

    var body: some View {
        HStack(spacing: 5) {
            ZStack {
                if isPulsing && !reduceMotion {
                    Circle()
                        .fill(color.opacity(0.3))
                        .frame(width: 12, height: 12)
                        .scaleEffect(pulse ? 1.8 : 1.0)
                        .opacity(pulse ? 0 : 1)
                        .animation(
                            .easeOut(duration: 1.0).repeatForever(autoreverses: false),
                            value: pulse
                        )
                }
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
            }
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(DS.Colors.textFaint)
        }
        .onAppear { if isPulsing { pulse = true } }
        .onChange(of: bleManager.connectionState) { _, _ in pulse = isPulsing }
    }
}
