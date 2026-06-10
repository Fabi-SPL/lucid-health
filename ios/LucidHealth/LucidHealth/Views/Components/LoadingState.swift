import SwiftUI

/// Reusable loading placeholder — spinning ring + label.
struct LoadingState: View {
    var label: String = "Loading…"

    var body: some View {
        VStack(spacing: DS.Spacing.md) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(DS.Colors.violet)
                .scaleEffect(1.2)
            Text(label)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(DS.Colors.textFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.xl)
    }
}
