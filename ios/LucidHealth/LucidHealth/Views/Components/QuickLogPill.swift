import SwiftUI

/// Press-scale feedback that does NOT block a parent ScrollView's pan gesture.
/// (The old pills used `.simultaneousGesture(DragGesture(minimumDistance: 0))`,
/// which grabbed every touch — so the bar couldn't scroll and a scroll-start
/// accidentally logged. ButtonStyle press detection cooperates with scrolling.)
struct PressableScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(DS.Anim.quick, value: configuration.isPressed)
    }
}

/// Tap-to-open pill for a QuickLogItem. Tap no longer logs instantly — it opens
/// the quick editor so an accidental touch never writes a junk entry.
struct QuickLogPill: View {
    let item: QuickLogItem
    let onTap: () -> Void

    var body: some View {
        Button {
            DS.Haptic.tap()
            onTap()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: item.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(DS.Colors.violet)
                Text(item.name)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(DS.Colors.textPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .background(
                Capsule()
                    .fill(DS.Colors.surface.opacity(0.8))
                    .overlay(
                        Capsule().stroke(DS.Colors.border, lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(PressableScale())
    }
}
