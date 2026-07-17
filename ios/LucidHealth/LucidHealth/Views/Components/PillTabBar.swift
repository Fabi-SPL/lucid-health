import SwiftUI

/// Floating Aurora tab bar — 60pt, radius-26, icon-only, square accent
/// indicator behind the active icon (per AURORA-DESIGN-SPEC §2).
/// 4 tabs: Today / Health / Food / Insights.
/// Settings is NOT a tab — accessed via SettingsGearButton sheet.
enum AppTab: Int, CaseIterable {
    case today, health, food, insights

    var icon: String {
        switch self {
        case .today:    return "sun.max.fill"
        case .health:   return "heart.fill"
        case .food:     return "fork.knife"
        case .insights: return "chart.bar.fill"
        }
    }

    var label: String {
        switch self {
        case .today:    return "Today"
        case .health:   return "Health"
        case .food:     return "Food"
        case .insights: return "Insights"
        }
    }
}

struct PillTabBar: View {
    @Binding var selectedTab: AppTab
    @Namespace private var indicator

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases, id: \.rawValue) { tab in
                Button {
                    withAnimation(DS.Anim.standard) { selectedTab = tab }
                } label: {
                    tabItem(tab)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.label)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 60)
        // ONE selection haptic per switch — was inside the ForEach (fired 4× per tap).
        .sensoryFeedback(.selection, trigger: selectedTab)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(DS.Colors.cardFillElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(DS.Colors.border, lineWidth: 0.5)
        )
        .padding(.horizontal, 32)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func tabItem(_ tab: AppTab) -> some View {
        let isActive = selectedTab == tab

        ZStack {
            if isActive {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(DS.Colors.violet.opacity(0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(DS.Colors.borderViolet, lineWidth: 0.5)
                    )
                    .frame(width: 44, height: 44)
                    .matchedGeometryEffect(id: "tabIndicator", in: indicator)
            }

            Image(systemName: tab.icon)
                .font(.system(size: 17, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isActive ? DS.Colors.violet : DS.Colors.textMuted)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
    }
}

#Preview {
    ZStack(alignment: .bottom) {
        AuroraBackground()
        PillTabBar(selectedTab: .constant(.today))
    }
}
