import SwiftUI

struct ContentView: View {
    @EnvironmentObject var bleManager: BLEManager

    var body: some View {
        RootTabView()
            .environmentObject(bleManager)
    }
}
