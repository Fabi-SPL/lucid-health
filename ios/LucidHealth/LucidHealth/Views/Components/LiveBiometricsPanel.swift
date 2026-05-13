import SwiftUI

/// Always-visible live BLE stats strip — HR, RMSSD, RR, skin temp, battery.
/// Pulses when new data arrives.
struct LiveBiometricsPanel: View {
    @EnvironmentObject private var bleManager: BLEManager
    @State private var pulse = false

    private var engine: HealthEngine { bleManager.healthEngine }
    private var connected: Bool { bleManager.connectionState == .connected }

    var body: some View {
        HStack(spacing: 0) {
            liveCell(
                icon: "heart.fill",
                value: bleManager.heartRate > 0 ? "\(bleManager.heartRate)" : "—",
                unit: "bpm",
                color: DS.Colors.pink
            )
            divider
            liveCell(
                icon: "waveform.path.ecg",
                value: engine.currentRMSSD > 0 ? "\(Int(engine.currentRMSSD))" : "—",
                unit: "ms",
                color: DS.Colors.teal
            )
            divider
            liveCell(
                icon: "lungs",
                value: engine.respiratoryRate > 0 ? String(format: "%.1f", engine.respiratoryRate) : "—",
                unit: "/min",
                color: DS.Colors.violet
            )
            divider
            liveCell(
                icon: "thermometer.medium",
                value: bleManager.skinTemperature > 0 ? String(format: "%.1f", bleManager.skinTemperature) : "—",
                unit: "°C",
                color: DS.Colors.amber
            )
            divider
            liveCell(
                icon: batteryIcon,
                value: bleManager.battery > 0 ? "\(Int(bleManager.battery))" : "—",
                unit: "%",
                color: bleManager.battery < 20 ? DS.Colors.pink : DS.Colors.success
            )
        }
        .padding(.vertical, DS.Spacing.sm)
        .glassCard()
        .scaleEffect(pulse ? 1.0 : 0.998)
        .onChange(of: bleManager.heartRate) {
            guard connected else { return }
            withAnimation(.easeOut(duration: 0.15)) { pulse = true }
            withAnimation(.easeOut(duration: 0.15).delay(0.15)) { pulse = false }
        }
    }

    private func liveCell(icon: String, value: String, unit: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(color.opacity(0.8))
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(DS.Colors.textPrimary)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.2), value: value)
            Text(unit)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(DS.Colors.textFaint)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(DS.Colors.border.opacity(0.4))
            .frame(width: 0.5, height: 28)
    }

    private var batteryIcon: String {
        let b = Int(bleManager.battery)
        if bleManager.isCharging { return "battery.100.bolt" }
        switch b {
        case 75...: return "battery.100"
        case 50...: return "battery.75"
        case 25...: return "battery.50"
        default:    return "battery.25"
        }
    }
}
