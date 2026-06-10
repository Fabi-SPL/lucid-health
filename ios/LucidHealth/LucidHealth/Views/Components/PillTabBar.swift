import SwiftUI

/// Floating glass-pill tab bar — principle #8.
/// 4 tabs: Today / Health / Food / Insights.
/// Settings is NOT a tab — accessed via SettingsGearButton sheet.
enum AppTab: Int, CaseIterable {
    case today, health, food, insights

    var icon: String {
        switch self {
        case .today:    return "sun.max.fill"
        case .health:   return "heart.fill"
        case .food:     return "fork.knife"
        case .insights: return "sparkles"
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
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(height: 56)                      // hard-cap height — iOS 26 .glassEffect won't blow up
        // ONE selection haptic per switch — was inside the ForEach (fired 4× per tap).
        .sensoryFeedback(.selection, trigger: selectedTab)
        .glassEffect(.regular, in: .capsule)    // capsule-shaped glass directly (was .glassDefault rect)
        .overlay(
            Capsule()
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
                Capsule()
                    .fill(DS.Colors.violet.opacity(0.18))
                    .matchedGeometryEffect(id: "tabIndicator", in: indicator)
            }

            HStack(spacing: isActive ? 5 : 0) {
                Image(systemName: tab.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isActive ? DS.Colors.violet : DS.Colors.textMuted)

                if isActive {
                    Text(tab.label)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.Colors.violet)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                }
            }
            .padding(.horizontal, isActive ? 12 : 10)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
    }
}

#Preview {
    ZStack(alignment: .bottom) {
        MeshGradientBackground()
        PillTabBar(selectedTab: .constant(.today))
    }
}
