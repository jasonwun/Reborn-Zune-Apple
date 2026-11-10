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
    @State private var library: LibraryCoordinator
    @Environment(\.modelContext) private var modelContext
    /// Hardware screen size backing the M15.1 screen-fixed scale tokens.
    /// Re-derived only when the window moves to another screen — never
    /// on window resize. M16.3: initialized synchronously (was a
    /// 1440×900 placeholder until `.task` ran) so the tile wall's
    /// first-layout freeze never sees a stale screen size.
    @State private var screenSize = NSScreen.main?.frame.size ?? CGSize(width: 1440, height: 900)
    @State private var demo: DemoLibrary?

    init() {
        // DEBUG override lets verification point the default Library Source
        // at a prepared folder instead of ~/Music.
        let root: URL
        if let override = ProcessInfo.processInfo.environment["REBORN_ZUNE_DEBUG_LIBRARY_FOLDER"] {
            root = URL(fileURLWithPath: override)
        } else {
            root = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Music")
        }
        _library = State(initialValue: LibraryCoordinator(
            container: RebornZuneMacApp.sharedContainer,
            source: FolderFileSource(root: root)))
    }

    private struct DemoLibrary {
        let tracks: [Music]
        let tiles: [TileWallEntry]
        let library: ResonantLibrary
    }

    private var shownTracks: [Music] { demo?.tracks ?? library.tracks }

    var body: some View {
        let _ = PerfProbe.once("app.body")
        let lighting: LightingAnimator? =
            ProcessInfo.processInfo.environment["REBORN_ZUNE_DEBUG_NO_LIGHTING"] == "1"
            ? nil
            : LightingAnimator()

        let tilesToShow = shownTracks.isEmpty
            ? SyntheticTiles.sample(count: 250)
            : (demo?.tiles ?? MusicTileBuilder.tiles(from: library.tracks))
        let resonantLibrary = demo?.library ?? ResonantLibrary.from(tracks: library.tracks)

        let status: LibraryStatus? = {
            guard demo == nil else { return nil }
            switch library.phase {
            case .ready: return nil
            case .loading: return .loading
            case .empty: return .empty(path: library.sourcePath)
            case .failed: return .failed(message: library.scanError ?? "The scan did not finish.")
            }
        }()
        let banner: String? = (status == nil && demo == nil) ? library.scanError : nil

        // M15.1: size tokens are fixed per screen (`.mac(screen:)`);
        // the live window size goes to `resonantWindowSize`, which views
        // use for discrete reflow decisions only (never as a multiplier).
        GeometryReader { proxy in
            ResonantApp(
                engine: engine,
                library: resonantLibrary,
                tiles: tilesToShow,
                lightingAnimator: lighting,
                density: .cozy,
                libraryStatus: status,
                scanBanner: banner,
                onRetry: { Task { await library.retry() } }
            )
            .environment(\.resonantLayout, .mac(screen: screenSize))
            .environment(\.resonantWindowSize, proxy.size)
            .environment(\.resonantScreenSize, screenSize)
        }
        .background(WindowSizeAccessor(targetSize: Self.initialWindowTarget))
        .background(WindowChromeConfigurator())
        .onReceive(NotificationCenter.default.publisher(
            for: NSWindow.didChangeScreenNotification)) { _ in
            updateScreenSize()
        }
        .onChange(of: library.tracks) { _, tracks in
            // Adopt the Library as the playback queue only when nothing is
            // queued; a refresh must never disturb current playback.
            if engine.queue.isEmpty, !tracks.isEmpty { engine.setQueue(tracks) }
        }
        .task {
            updateScreenSize()
            // Debug: synthetic demo library to bypass TCC / sandbox file access.
            if ProcessInfo.processInfo.environment["REBORN_ZUNE_DEBUG_DEMO_LIBRARY"] == "1" {
                let tracks = ResonantDemoLibrary.makeMusic()
                demo = DemoLibrary(tracks: tracks,
                                   tiles: MusicTileBuilder.tiles(from: tracks),
                                   library: ResonantLibrary.from(tracks: tracks))
                engine.setQueue(tracks)
                PerfProbe.mark("library.demo.ready")
                return
            }
            await library.start()
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

/// M16.1: macOS 26+ can still paint a bright titlebar strip even with
/// `.windowStyle(.hiddenTitleBar)` — force full immersion: hidden title,
// M16.8 note: the M16.3 `WindowOriginReporter` (window-position @State →
// tile-wall counter-offset) was removed — `ScreenAnchorContainer` now
// repositions the wall at the AppKit/Core Animation level instead, so
// window drags no longer touch the SwiftUI update loop at all.
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
        // M17.2: no background dragging — it forced the legacy AppKit
        // drag path (main thread per mouse event, ~20 effective fps)
        // and drag-anywhere was the wrong UX anyway. The invisible
        // titlebar strip still drags (WindowServer session); the tile
        // wall drags via AnchorNSView's performDrag (M17.2).
        window.isMovableByWindowBackground = false
        // M17.2: the UI paints every pixel (no materials/vibrancy
        // anywhere), so the window may be opaque. This is a ~2x window-
        // move throughput win (measured 27% → 64% of 60 Hz slots with
        // visible motion): a non-opaque window forces WindowServer to
        // re-blend it against the desktop on EVERY frame of a drag,
        // while an opaque one can be blitted. The background color only
        // shows through if content fails to paint a sliver — match the
        // tile wall's backdrop grey (M5.26).
        window.isOpaque = true
        window.backgroundColor = NSColor(calibratedWhite: 0.10, alpha: 1)
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
