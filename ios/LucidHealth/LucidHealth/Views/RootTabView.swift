import SwiftUI

// MARK: - RootTabView
// Principle #8: floating pill tab bar, content-first design.
// Mesh gradient lives here once — never reflows on tab change.
// Settings is NOT a tab — gear icon → sheet on Today + Health.

struct RootTabView: View {
    @EnvironmentObject var bleManager: BLEManager
    @State private var selectedTab: AppTab = .today

    var body: some View {
        ZStack(alignment: .bottom) {
            // Single mesh background — shared across all tabs (no reflow)
            MeshGradientBackground()
                .ignoresSafeArea()

            // Tab content — opacity/zIndex swap, no NavigationStack rerender
            ZStack {
                ForEach(AppTab.allCases, id: \.rawValue) { tab in
                    NavigationStack {
                        tabContent(tab)
                    }
                    .opacity(selectedTab == tab ? 1 : 0)
                    .allowsHitTesting(selectedTab == tab)
                }
            }
            .ignoresSafeArea()

            // Floating pill tab bar at bottom
            PillTabBar(selectedTab: $selectedTab)
        }
        .ignoresSafeArea(.keyboard)
    }

    @ViewBuilder
    private func tabContent(_ tab: AppTab) -> some View {
        switch tab {
        case .today:
            TodayView()
                .environmentObject(bleManager)
        case .health:
            HealthView()
                .environmentObject(bleManager)
        case .food:
            FoodView()
                .environmentObject(bleManager)
        case .insights:
            InsightsView()
                .environmentObject(bleManager)
        }
    }
}
