import SwiftUI
import RebornZuneCore
import SwiftData

@main
struct RebornZuneMacApp: App {
    /// Persistent SwiftData container holding playlists + app settings.
    /// Failure to open falls back to an in-memory container so the app
    /// can still launch (the user just loses persistence).
    private let modelContainer = RebornZuneMacApp.sharedContainer
    @State private var engine: PlaybackEngine
    @State private var library: LibraryCoordinator

    init() {
        let root: URL
        if let override = ProcessInfo.processInfo.environment["REBORN_ZUNE_DEBUG_LIBRARY_FOLDER"] {
            root = URL(fileURLWithPath: override)
        } else {
            root = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Music")
        }
        let library = LibraryCoordinator(
            container: RebornZuneMacApp.sharedContainer,
            sources: [FolderFileSource(root: root)])
        _library = State(initialValue: library)
        _engine = State(initialValue: PlaybackEngine(fileAccess: { [weak library] url in
            guard let library else { throw LibraryBookmarkError.accessDenied(url.path) }
            return try library.startPlaybackAccess(for: url)
        }))
    }

    /// One container shared by SwiftUI (`.modelContainer`) and the Library
    /// coordinator, so both see the same store. DEBUG builds honor
    /// `REBORN_ZUNE_DEBUG_STORE=<path>` to isolate verification runs.
    static let sharedContainer: ModelContainer = {
        do {
            #if DEBUG
            if let path = ProcessInfo.processInfo.environment["REBORN_ZUNE_DEBUG_STORE"] {
                return try RebornZunePersistence.makePersistentContainer(at: URL(fileURLWithPath: path))
            }
            #endif
            return try RebornZunePersistence.makePersistentContainer()
        } catch {
            return (try? RebornZunePersistence.makeInMemoryContainer())
                ?? (try! ModelContainer(for: RebornZunePersistence.schema,
                                        configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        }
    }()

    /// Initial window content size. 1440 × 900 (the Resonant design
    /// canvas, scale 1.0) by default. DEBUG builds honor
    /// `REBORN_ZUNE_DEBUG_WINDOW_SIZE=WxH` so the screenshot harness
    /// can drive the resize sweep without Accessibility permissions.
    private static var initialWindowSize: CGSize {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["REBORN_ZUNE_DEBUG_WINDOW_SIZE"] {
            let parts = raw.lowercased().split(separator: "x")
            if parts.count == 2,
               let w = Double(parts[0]), let h = Double(parts[1]),
               w > 0, h > 0 {
                return CGSize(width: w, height: h)
            }
        }
        #endif
        return CGSize(width: 1440, height: 900)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(library: library, engine: engine)
                // Window floor 900 × 600: below ~900pt the panorama's
                // three-column bottom strip has no honest layout, so
                // the window refuses to shrink further
                // (`.windowResizability(.contentMinSize)` turns this
                // frame's min into the window's minimum size).
                .frame(minWidth: 900, maxWidth: .infinity,
                       minHeight: 600, maxHeight: .infinity)
        }
        .windowResizability(.contentMinSize)
        // First-launch window size (later launches restore the user's
        // frame). `idealWidth/idealHeight` on the content frame is NOT
        // honored by WindowGroup initial sizing — the window falls back
        // to the content minimum — so the default must be set here.
        .defaultSize(width: Self.initialWindowSize.width,
                     height: Self.initialWindowSize.height)
        .modelContainer(modelContainer)
        // Resonant v2 sketch: chrome="off". Hide the system titlebar so
        // the canvas extends to the top of the window; native traffic
        // lights stay (functional necessity) and float over content.
        .windowStyle(.hiddenTitleBar)

        Settings {
            LibrarySourcesSettingsView(library: library)
        }
    }
}
