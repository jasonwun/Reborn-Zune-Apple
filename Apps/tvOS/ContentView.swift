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

    var body: some View {
        // M5.8: setting `REBORN_ZUNE_DEBUG_NO_LIGHTING=1` at launch
        // disables the lighting shader entirely. Used to verify the
        // pre-shader `.saturation(0)` overlay actually renders the tiles
        // as grayscale — the lit captures should match this baseline
        // tinted by warm/cool light pools, not introduce new color.
        let lighting: LightingAnimator? =
            ProcessInfo.processInfo.environment["REBORN_ZUNE_DEBUG_NO_LIGHTING"] == "1"
            ? nil
            : LightingAnimator()
        ZStack(alignment: .bottom) {
            TileWallView(
                tiles: SyntheticTiles.sample(count: 250),
                lightingAnimator: lighting
            )
            PlaybackStatusPanel(engine: engine)
                .padding()
        }
        .task {
            // Showcase mode: load bundled music + auto-play.
            let source = BundleLibrarySource()
            do {
                let tracks = try await source.load()
                if !tracks.isEmpty {
                    engine.setQueue(tracks)
                    engine.play()
                }
            } catch {
                // BundleLibrarySource is documented not to throw on empty
                // bundles; if it does, we just leave the engine empty.
            }
        }
    }
}
