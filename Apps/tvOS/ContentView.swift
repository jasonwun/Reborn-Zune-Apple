import SwiftUI
import RebornZuneCore

struct ContentView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Reborn Zune")
                .font(.largeTitle)
            Text("tvOS — core v\(RebornZuneCore.version)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
