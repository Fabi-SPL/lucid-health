import SwiftUI

/// Triple-stat row — heart rate / HRV / respiratory rate.
struct BiometricStatRow: View {
    @EnvironmentObject private var bleManager: BLEManager

    private var engine: HealthEngine { bleManager.healthEngine }

    var body: some View {
        HStack(spacing: 0) {
            StatCell(
                icon: "waveform.path.ecg",
                value: bleManager.heartRate > 0 ? "\(bleManager.heartRate)" : "—",
                unit: "bpm",
                color: DS.Colors.pink
            )
            Divider()
                .frame(height: 28)
                .opacity(0.25)
            StatCell(
                icon: "heart.text.square",
                value: engine.currentRMSSD > 0 ? "\(Int(engine.currentRMSSD))" : "—",
                unit: "ms HRV",
                color: DS.Colors.teal
            )
            Divider()
                .frame(height: 28)
                .opacity(0.25)
            StatCell(
                icon: "lungs",
                value: engine.poincaréSD1 > 0 ? String(format: "%.1f", engine.poincaréSD1) : "—",
                unit: "SD1",
                color: DS.Colors.violet.opacity(0.85)
            )
        }
        .padding(.vertical, DS.Spacing.xs)
    }
}

private struct StatCell: View {
    let icon: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.Colors.textPrimary)
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(unit)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(DS.Colors.textFaint)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
    }
}
