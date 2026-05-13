import SwiftUI

/// Wraps any view with iOS-style trailing swipe actions (delete + edit).
/// Works in ScrollView/LazyVStack contexts where `.swipeActions` (List-only)
/// can't be used.
///
/// Direction-locked: at gesture start, decides horizontal vs vertical and only
/// commits to horizontal swipes. Lets the parent ScrollView win all vertical
/// drags so scrolling stays smooth.
struct SwipeActionsCard<Content: View>: View {
    var onDelete: () -> Void
    var onEdit: (() -> Void)?
    @ViewBuilder var content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var baseOffset: CGFloat = 0
    @State private var direction: SwipeDirection = .undecided

    private enum SwipeDirection { case undecided, horizontal, vertical }

    private let actionWidth: CGFloat = 76
    private let snapPoint: CGFloat = 60

    private var totalWidth: CGFloat {
        onEdit == nil ? actionWidth : (actionWidth * 2)
    }
    private var isOpen: Bool { offset < -snapPoint }

    var body: some View {
        ZStack(alignment: .trailing) {
            // Background action layer
            HStack(spacing: 0) {
                if let onEdit {
                    actionButton(icon: "square.and.pencil", label: "Edit", color: DS.Colors.violet) {
                        onEdit()
                        close()
                    }
                }
                actionButton(icon: "trash.fill", label: "Delete", color: DS.Colors.danger) {
                    onDelete()
                    close()
                }
            }
            .frame(width: totalWidth)
            .opacity(offset < -2 ? 1 : 0)

            // Foreground content
            content()
                .offset(x: offset)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { value in
                            // Lock direction at first significant move
                            if direction == .undecided {
                                let dx = abs(value.translation.width)
                                let dy = abs(value.translation.height)
                                if max(dx, dy) >= 8 {
                                    direction = (dx > dy) ? .horizontal : .vertical
                                    baseOffset = offset
                                }
                            }

                            if direction == .horizontal {
                                offset = max(-totalWidth, min(0, baseOffset + value.translation.width))
                            }
                        }
                        .onEnded { value in
                            let dir = direction
                            direction = .undecided
                            guard dir == .horizontal else { return }

                            let predicted = baseOffset + value.predictedEndTranslation.width
                            let final = baseOffset + value.translation.width
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.85)) {
                                if predicted < -snapPoint || final < -snapPoint {
                                    offset = -totalWidth
                                } else {
                                    offset = 0
                                }
                            }
                        }
                )
                // Tap on open card → close it (separate from action button taps)
                .onTapGesture {
                    if isOpen {
                        close()
                    }
                }
        }
    }

    private func close() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
            offset = 0
        }
    }

    private func actionButton(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button {
            let h = UIImpactFeedbackGenerator(style: .medium)
            h.impactOccurred()
            action()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                Text(label)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white)
            .frame(width: actionWidth, height: 76)
            .background(color)
        }
        .buttonStyle(.plain)
    }
}
