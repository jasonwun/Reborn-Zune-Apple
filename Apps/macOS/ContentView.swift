import SwiftUI
import AppKit
import RebornZuneCore
import UniformTypeIdentifiers

struct ContentView: View {
    var body: some View {
        #if DEBUG
        if let path = SnapshotHarness.requestedOutputPath {
            SnapshotView(outputPath: path)
        } else {
            ResonantHost()
        }
        #else
        ResonantHost()
        #endif
    }
}

#if DEBUG
private struct SnapshotView: View {
    let outputPath: String
    private let panelSize = CGSize(width: 1280, height: 720)

    var body: some View {
        TileWallView.staticSnapshot(
            tiles: SyntheticTiles.sample(),
            unitSize: 70,
            frozenTime: SnapshotHarness.requestedSnapshotTime,
            panelSize: panelSize
        )
        .frame(width: panelSize.width, height: panelSize.height)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let view = TileWallView.staticSnapshot(
                    tiles: SyntheticTiles.sample(),
                    unitSize: 70,
                    frozenTime: SnapshotHarness.requestedSnapshotTime,
                    panelSize: panelSize
                )
                _ = SnapshotHarness.render(
                    view,
                    size: panelSize,
                    outputPath: outputPath
                )
                exit(0)
            }
        }
    }
}
#endif

@MainActor
private struct ResonantHost: View {
    @State private var engine = PlaybackEngine()
    @State private var state = LibraryHostState()
    @State private var showPicker = false
    /// Hardware screen size backing the M15.1 screen-fixed scale tokens.
    /// Re-derived only when the window moves to another screen — never
    /// on window resize. M16.3: initialized synchronously (was a
    /// 1440×900 placeholder until `.task` ran) so the tile wall's
    /// first-layout freeze never sees a stale screen size.
    @State private var screenSize = NSScreen.main?.frame.size ?? CGSize(width: 1440, height: 900)
    /// M16.3: the window's top-left corner in screen-local points,
    /// published live so the tile wall can anchor itself to the hardware
    /// screen instead of the window.
    @State private var windowOriginTL: CGPoint = .zero

    var body: some View {
        let _ = PerfProbe.once("app.body")
        let lighting: LightingAnimator? =
            ProcessInfo.processInfo.environment["REBORN_ZUNE_DEBUG_NO_LIGHTING"] == "1"
            ? nil
            : LightingAnimator()

        let tilesToShow = state.tiles.isEmpty
            ? SyntheticTiles.sample(count: 250)
            : state.tiles
        let library = state.library

        // M15.1: size tokens are fixed per screen (`.mac(screen:)`);
        // the live window size goes to `resonantWindowSize`, which views
        // use for discrete reflow decisions only (never as a multiplier).
        GeometryReader { proxy in
            ResonantApp(
                engine: engine,
                library: library,
                tiles: tilesToShow,
                lightingAnimator: lighting,
                density: .cozy,
                needsLibraryFolder: state.phase == .needsFolder,
                onPickFolder: { showPicker = true }
            )
            .environment(\.resonantLayout, .mac(screen: screenSize))
            .environment(\.resonantWindowSize, proxy.size)
            .environment(\.resonantScreenSize, screenSize)
            .environment(\.resonantWindowOrigin, windowOriginTL)
        }
        .background(WindowSizeAccessor(targetSize: Self.initialWindowTarget))
        .background(WindowChromeConfigurator())
        .background(WindowOriginReporter(topLeft: $windowOriginTL))
        .onReceive(NotificationCenter.default.publisher(
            for: NSWindow.didChangeScreenNotification)) { _ in
            updateScreenSize()
        }
        .fileImporter(
            isPresented: $showPicker,
            allowedContentTypes: [.folder]
        ) { result in
            if case .success(let url) = result {
                Task { await state.load(folder: url, into: engine) }
            }
        }
        .task {
            updateScreenSize()
            // Debug: synthetic demo library to bypass TCC / sandbox file access.
            if ProcessInfo.processInfo.environment["REBORN_ZUNE_DEBUG_DEMO_LIBRARY"] == "1" {
                let tracks = ResonantDemoLibrary.makeMusic()
                state.tracks = tracks
                state.tiles = MusicTileBuilder.tiles(from: tracks)
                state.library = ResonantLibrary.from(tracks: tracks)
                state.phase = .ready
                engine.setQueue(tracks)
                PerfProbe.mark("library.demo.ready")
                return
            }
            if let override = ProcessInfo.processInfo.environment["REBORN_ZUNE_DEBUG_LIBRARY_FOLDER"] {
                await state.load(folder: URL(fileURLWithPath: override), into: engine)
                return
            }
            if let saved = LibraryFolderStore.read() {
                await state.load(folder: saved, into: engine)
            }
        }
    }

    private func updateScreenSize() {
        if let screen = NSApp.windows.first?.screen ?? NSScreen.main {
            screenSize = screen.frame.size
        }
    }

    /// DEBUG-only harness hook: `REBORN_ZUNE_DEBUG_WINDOW_SIZE=WxH`
    /// forces the window's content size so the resize sweep can run
    /// without Accessibility permissions — even over a restored frame
    /// (a user's saved window always wins in production, where this
    /// returns nil and `WindowSizeAccessor` does nothing). The forced
    /// size still respects the 900 × 600 content minimum, so the hook
    /// doubles as a window-floor probe.
    private static var initialWindowTarget: CGSize? {
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
        return nil
    }
}

/// M16.3: publishes the window's top-left corner in screen-local points
/// (origin = the current screen's top-left, y DOWN — SwiftUI-friendly).
/// The tile wall counter-offsets by this value so tiles and the light
/// field stay put on the hardware screen while the window moves.
private struct WindowOriginReporter: NSViewRepresentable {
    @Binding var topLeft: CGPoint

    func makeCoordinator() -> Coordinator { Coordinator(topLeft: $topLeft) }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.start(view: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.report(nsView)
    }

    @MainActor
    final class Coordinator: NSObject {
        private let topLeft: Binding<CGPoint>
        private var observers: [NSObjectProtocol] = []
        private var observedWindow: NSWindow?

        init(topLeft: Binding<CGPoint>) { self.topLeft = topLeft }

        func start(view: NSView) {
            // The view is not in a window yet at makeNSView time.
            Task { @MainActor [weak self] in
                self?.attach(to: view.window)
            }
        }

        func report(_ view: NSView) {
            if view.window != observedWindow { attach(to: view.window) }
            if let window = view.window { update(window) }
        }

        private func attach(to window: NSWindow?) {
            guard let window, window !== observedWindow else { return }
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            observers = []
            observedWindow = window
            update(window)
            let center = NotificationCenter.default
            for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
                observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] note in
                    guard let w = note.object as? NSWindow else { return }
                    Task { @MainActor [weak self] in self?.update(w) }
                })
            }
        }

        private func update(_ window: NSWindow) {
            guard let screen = window.screen ?? NSScreen.main else { return }
            let tl = CGPoint(
                x: window.frame.minX - screen.frame.minX,
                y: screen.frame.maxY - window.frame.maxY
            )
            if tl != topLeft.wrappedValue { topLeft.wrappedValue = tl }
        }
        // No deinit cleanup: the block observers hold only a weak self,
        // so after teardown they fire into nil. Single-window app — the
        // token leak is one pair of observers at most.
    }
}

/// M16.1: macOS 26+ can still paint a bright titlebar strip even with
/// `.windowStyle(.hiddenTitleBar)` — force full immersion: hidden title,
/// transparent titlebar, content extending through the titlebar region,
/// and drag-anywhere-to-move since there is no visible chrome to grab.
private struct WindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { Self.apply(to: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        Self.apply(to: nsView)
    }

    private static func apply(to view: NSView) {
        guard let window = view.window else { return }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
    }
}

/// Bridges to the NSWindow once the view is installed, then applies the
/// DEBUG target content size. The second, delayed pass corrects any
/// later SwiftUI sizing that would otherwise override the first.
private struct WindowSizeAccessor: NSViewRepresentable {
    let targetSize: CGSize?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        apply(to: view, delays: [0, 0.4])
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private func apply(to view: NSView, delays: [TimeInterval]) {
        guard let targetSize else { return }
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard let window = view.window else { return }
                // Respect the content minimum (window floor 900 × 600).
                let clamped = NSSize(width: max(targetSize.width, window.contentMinSize.width),
                                     height: max(targetSize.height, window.contentMinSize.height))
                window.setContentSize(clamped)
            }
        }
    }
}

private enum LibraryPhase: Equatable {
    case needsFolder
    case loading
    case ready
}

@MainActor
@Observable
private final class LibraryHostState {
    var phase: LibraryPhase = .needsFolder
    var tiles: [TileWallEntry] = []
    var tracks: [Music] = []
    var library: ResonantLibrary = ResonantLibrary(albums: [], artists: [])

    func load(folder: URL, into engine: PlaybackEngine) async {
        phase = .loading
        let source = FolderLibrarySource(folder: folder)
        do {
            let loaded = try await source.load()
            tracks = loaded
            tiles = MusicTileBuilder.tiles(from: loaded)
            library = ResonantLibrary.from(tracks: loaded)
            LibraryFolderStore.write(folder)
            // A folder with no usable audio is functionally the same as
            // no folder picked — fall back to the empty state.
            phase = loaded.isEmpty ? .needsFolder : .ready
            if !loaded.isEmpty {
                engine.setQueue(loaded)
            }
        } catch {
            phase = .needsFolder
        }
    }
}
