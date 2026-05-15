import SwiftUI
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

    var body: some View {
        let lighting: LightingAnimator? =
            ProcessInfo.processInfo.environment["REBORN_ZUNE_DEBUG_NO_LIGHTING"] == "1"
            ? nil
            : LightingAnimator()

        let tilesToShow = state.tiles.isEmpty
            ? SyntheticTiles.sample(count: 250)
            : state.tiles
        let library = state.library

        IPadShell(route: .home) {
            ResonantApp(
                engine: engine,
                library: library,
                tiles: tilesToShow,
                lightingAnimator: lighting,
                density: .cozy,
                platform: .ipad,
                needsLibraryFolder: state.phase == .needsFolder,
                onPickFolder: { showPicker = true }
            )
            .padding(.top, 32)   // status bar
            .padding(.bottom, 28) // home indicator
        }
        .ignoresSafeArea()
        .fileImporter(
            isPresented: $showPicker,
            allowedContentTypes: [.folder]
        ) { result in
            if case .success(let url) = result {
                Task { await state.load(folder: url, into: engine) }
            }
        }
        .task {
            if ProcessInfo.processInfo.environment["REBORN_ZUNE_DEBUG_DEMO_LIBRARY"] == "1" {
                let tracks = ResonantDemoLibrary.makeMusic()
                state.tracks = tracks
                state.tiles = MusicTileBuilder.tiles(from: tracks)
                state.library = ResonantLibrary.from(tracks: tracks)
                state.phase = .ready
                engine.setQueue(tracks)
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
            phase = .ready
            if !loaded.isEmpty {
                engine.setQueue(loaded)
            }
        } catch {
            phase = .needsFolder
        }
    }
}
