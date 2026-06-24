import SwiftUI

/// 8px colored category dot + uppercase label — principle #5.
/// Body=violet, Mind=teal, Care=amber, Sleep=lavender, Food=green.
struct CategoryDot: View {
    let category: DS.Category

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(category.color)
                .frame(width: 8, height: 8)
            Text(category.label)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(DS.Colors.textMuted)
                .tracking(0.8)
                .textCase(.uppercase)
        }
    }
}

#Preview {
    ZStack {
        AuroraBackground()
        VStack(alignment: .leading, spacing: 12) {
            CategoryDot(category: .body)
            CategoryDot(category: .mind)
            CategoryDot(category: .care)
            CategoryDot(category: .sleep)
            CategoryDot(category: .food)
        }
        .padding()
    }
}
