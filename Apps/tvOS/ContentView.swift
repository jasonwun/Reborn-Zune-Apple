import SwiftUI
import RebornZuneCore

struct ContentView: View {
    var body: some View {
        #if DEBUG
        if let path = SnapshotHarness.requestedOutputPath {
            SnapshotView(outputPath: path)
        } else {
            DefaultContent()
        }
        #else
        DefaultContent()
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

private struct DefaultContent: View {
    @State private var engine = PlaybackEngine()
    @State private var tiles: [TileWallEntry] = []

    var body: some View {
        let lighting: LightingAnimator? =
            ProcessInfo.processInfo.environment["REBORN_ZUNE_DEBUG_NO_LIGHTING"] == "1"
            ? nil
            : LightingAnimator()

        ZStack(alignment: .bottom) {
            TileWallView(
                tiles: tiles.isEmpty ? SyntheticTiles.sample(count: 250) : tiles,
                lightingAnimator: lighting
            )
            PlayerChrome(engine: engine)
        }
        .task {
            // Load music bundled at Resources/UserMusic/. If no music is
            // bundled, fall back to the silence.m4a sample.
            let userMusic = BundleLibrarySource(subdirectory: "UserMusic")
            do {
                var tracks = try await userMusic.load()
                if tracks.isEmpty {
                    let fallback = BundleLibrarySource()
                    tracks = (try? await fallback.load()) ?? []
                }
                if !tracks.isEmpty {
                    tiles = MusicTileBuilder.tiles(from: tracks)
                    engine.setQueue(tracks)
                    engine.play()
                }
            } catch {
                // Leave tiles empty → falls back to synthetic wall.
            }
        }
    }
}
