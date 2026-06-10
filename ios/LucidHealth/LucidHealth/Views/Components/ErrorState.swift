import SwiftUI

/// Reusable error placeholder with retry action.
struct ErrorState: View {
    let message: String
    var onRetry: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: DS.Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundStyle(DS.Colors.amber)
            Text(message)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(DS.Colors.textSecondary)
                .multilineTextAlignment(.center)
            if let retry = onRetry {
                Button("Try again", action: retry)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Colors.violet)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.xl)
    }
}
