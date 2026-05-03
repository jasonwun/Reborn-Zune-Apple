import SwiftUI
import RebornZuneCore
import SwiftData

@main
struct RebornZuneMacApp: App {
    /// Persistent SwiftData container holding playlists + app settings.
    /// Failure to open falls back to an in-memory container so the app
    /// can still launch (the user just loses persistence).
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
