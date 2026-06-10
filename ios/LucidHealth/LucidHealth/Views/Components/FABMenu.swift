import SwiftUI

/// FAB action sheet — floats above content when FAB is open.
struct FABMenu: View {
    @Binding var isOpen: Bool
    let onCamera: () -> Void
    let onBarcode: () -> Void
    let onManual: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: DS.Spacing.sm) {
            FABMenuItem(icon: "camera.fill",   label: "Photo",    color: DS.Colors.violet) {
                withAnimation(DS.Anim.quick) { isOpen = false }
                onCamera()
            }
            FABMenuItem(icon: "barcode.viewfinder", label: "Barcode", color: DS.Colors.teal) {
                withAnimation(DS.Anim.quick) { isOpen = false }
                onBarcode()
            }
            FABMenuItem(icon: "pencil",        label: "Manual", color: DS.Colors.amber) {
                withAnimation(DS.Anim.quick) { isOpen = false }
                onManual()
            }
        }
        .transition(.asymmetric(
            insertion: .scale(scale: 0.8, anchor: .bottomTrailing).combined(with: .opacity),
            removal:   .scale(scale: 0.8, anchor: .bottomTrailing).combined(with: .opacity)
        ))
    }
}

struct FABMenuItem: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: {
            DS.Haptic.tap()
            action()
        }) {
            HStack(spacing: DS.Spacing.sm) {
                Text(label)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.Colors.textPrimary)
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.sm)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(Capsule().stroke(DS.Colors.border, lineWidth: 0.5))
                    )

                ZStack {
                    Circle()
                        .fill(color.opacity(0.2))
                        .overlay(Circle().stroke(color.opacity(0.35), lineWidth: 0.5))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(color)
                }
            }
            .scaleEffect(isPressed ? 0.96 : 1.0)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in withAnimation(DS.Anim.quick) { isPressed = true } }
                .onEnded   { _ in withAnimation(DS.Anim.quick) { isPressed = false } }
        )
    }
}
