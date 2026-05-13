import SwiftUI

/// Tap-to-log pill for a QuickLogItem.
struct QuickLogPill: View {
    let item: QuickLogItem
    let onTap: () -> Void

    @State private var isPressed = false
    @State private var didLog = false

    var body: some View {
        Button {
            let haptic = UIImpactFeedbackGenerator(style: .medium)
            haptic.impactOccurred()
            withAnimation(DS.Anim.quick) { didLog = true }
            onTap()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(DS.Anim.quick) { didLog = false }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: item.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(didLog ? DS.Colors.teal : DS.Colors.violet)
                Text(item.name)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(didLog ? DS.Colors.teal : DS.Colors.textPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .background(
                Capsule()
                    .fill(didLog
                          ? DS.Colors.teal.opacity(0.15)
                          : DS.Colors.surface.opacity(0.8))
                    .overlay(
                        Capsule()
                            .stroke(
                                didLog ? DS.Colors.teal.opacity(0.4) : DS.Colors.border,
                                lineWidth: 0.5
                            )
                    )
            )
            .scaleEffect(isPressed ? 0.95 : (didLog ? 1.03 : 1.0))
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in withAnimation(DS.Anim.quick) { isPressed = true } }
                .onEnded   { _ in withAnimation(DS.Anim.quick) { isPressed = false } }
        )
        .animation(DS.Anim.quick, value: didLog)
    }
}
