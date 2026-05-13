import SwiftUI

/// Horizontal scrolling row of QuickLogPills.
struct QuickLogRow: View {
    let onLog: (QuickLogItem) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.sm) {
                ForEach(QuickLogItem.defaults) { item in
                    QuickLogPill(item: item) { onLog(item) }
                }
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.xs)
        }
    }
}
