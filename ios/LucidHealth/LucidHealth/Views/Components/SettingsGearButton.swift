import SwiftUI

/// Gear icon button (top-trailing) — presents SettingsView as a sheet.
/// 44pt minimum tap target per HIG.
struct SettingsGearButton: View {
    @State private var showSettings = false

    var body: some View {
        Button {
            showSettings = true
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 16, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(DS.Colors.textMuted)
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}

#Preview {
    ZStack {
        MeshGradientBackground()
        HStack {
            Spacer()
            SettingsGearButton()
        }
        .padding()
    }
}
