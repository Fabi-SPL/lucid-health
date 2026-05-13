import SwiftUI

/// Thin banner shown at the top of mode home views when a recovery overlay
/// is active. Renders the tone, not the numbers — numbers live in the cards below.
struct RecoveryOverlayBanner: View {
    let overlay: RecoveryOverlay

    var body: some View {
        if overlay.shouldShow {
            HStack(spacing: 12) {
                Image(systemName: overlay.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(overlay.accent)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(overlay.accent.opacity(0.14))
                            .overlay(Circle().stroke(overlay.accent.opacity(0.30), lineWidth: 0.5))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(overlay.title)
                        .font(DS.Font.bodyMed)
                        .foregroundStyle(DS.Colors.textPrimary)
                    Text(overlay.subtitle)
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .fill(overlay.accent.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .stroke(overlay.accent.opacity(0.22), lineWidth: 0.5)
                    )
            )
            .padding(.horizontal, DS.Spacing.md)
            .padding(.top, 10)
        }
    }
}
