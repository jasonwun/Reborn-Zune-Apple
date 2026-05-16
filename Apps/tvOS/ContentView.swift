import SwiftUI
import RebornZuneCore

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
    @State private var tiles: [TileWallEntry] = []
    @State private var library: ResonantLibrary = ResonantLibrary(albums: [], artists: [])

    var body: some View {
        let lighting: LightingAnimator? =
            ProcessInfo.processInfo.environment["REBORN_ZUNE_DEBUG_NO_LIGHTING"] == "1"
            ? nil
            : LightingAnimator()

        let tilesToShow = tiles.isEmpty ? SyntheticTiles.sample(count: 250) : tiles

        TvResonantApp(
            engine: engine,
            library: library,
            tiles: tilesToShow,
            lightingAnimator: lighting
        )
        .task {
            if ProcessInfo.processInfo.environment["REBORN_ZUNE_DEBUG_DEMO_LIBRARY"] == "1" {
                loadDemo(into: engine)
                return
            }
            let userMusic = BundleLibrarySource(subdirectory: "UserMusic")
            do {
                var tracks = try await userMusic.load()
                if tracks.isEmpty {
                    let fallback = BundleLibrarySource()
                    tracks = (try? await fallback.load()) ?? []
                }
                if !tracks.isEmpty {
                    tiles = MusicTileBuilder.tiles(from: tracks)
                    library = ResonantLibrary.from(tracks: tracks)
                    engine.setQueue(tracks)
                    engine.play()
                    return
                }
            } catch {
                // Bundle load failed; fall through to demo library.
            }
            // No bundled tracks → load the demo library so Home is not
            // an empty grid on first run.
            loadDemo(into: engine)
        }
    }

    private func loadDemo(into engine: PlaybackEngine) {
        let tracks = ResonantDemoLibrary.makeMusic()
        tiles = MusicTileBuilder.tiles(from: tracks)
        library = ResonantLibrary.from(tracks: tracks)
        engine.setQueue(tracks)
        engine.play()
    }
}
