import SwiftUI

/// Small pattern callout — alcohol impact explanation, sleep debt note, etc.
/// Single-string API to match `PatternNote(text:)` call sites.
struct PatternNote: View {
    let text: String
    var icon: String = "lightbulb.fill"
    var color: Color = DS.Colors.amber

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 24)

            Text(text)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(DS.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DS.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(color.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .stroke(color.opacity(0.2), lineWidth: 0.5)
                )
        )
    }
}
