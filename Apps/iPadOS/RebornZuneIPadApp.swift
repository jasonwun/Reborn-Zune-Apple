import SwiftUI
import RebornZuneCore
import SwiftData

@main
struct RebornZuneIPadApp: App {
    private let modelContainer: ModelContainer = {
        do {
            return try RebornZunePersistence.makePersistentContainer()
        } catch {
            return (try? RebornZunePersistence.makeInMemoryContainer())
                ?? (try! ModelContainer(for: RebornZunePersistence.schema,
                                        configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}
