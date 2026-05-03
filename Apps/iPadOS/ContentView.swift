import SwiftUI
import RebornZuneCore
import UniformTypeIdentifiers

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
    @State private var library = LibraryHostState()
    @State private var showPicker = false

    var body: some View {
        // M5.8 debug hook still honored — disables lighting for grayscale verification.
        let lighting: LightingAnimator? =
            ProcessInfo.processInfo.environment["REBORN_ZUNE_DEBUG_NO_LIGHTING"] == "1"
            ? nil
            : LightingAnimator()

        ZStack(alignment: .bottom) {
            switch library.phase {
            case .needsFolder:
                FolderPrompt(showPicker: $showPicker)
            case .loading:
                LoadingView()
            case .ready:
                TileWallView(
                    tiles: library.tiles.isEmpty ? SyntheticTiles.sample(count: 250) : library.tiles,
                    lightingAnimator: lighting
                )
            }

            // Liquid-glass player chrome: bottom-strip with now-playing
            // info, transport + progress, and a toggleable queue panel.
            PlayerChrome(engine: engine)
        }
        .fileImporter(
            isPresented: $showPicker,
            allowedContentTypes: [.folder]
        ) { result in
            if case .success(let url) = result {
                Task { await library.load(folder: url, into: engine) }
            }
        }
        .task {
            // Debug override (testing / sim launch convenience). If
            // `REBORN_ZUNE_DEBUG_LIBRARY_FOLDER` is set in the env, use
            // that as the library folder instead of restoring a saved
            // bookmark or waiting for the user to pick.
            if let override = ProcessInfo.processInfo.environment["REBORN_ZUNE_DEBUG_LIBRARY_FOLDER"] {
                await library.load(folder: URL(fileURLWithPath: override), into: engine)
                return
            }
            // Restore last folder if persisted.
            if let saved = LibraryFolderStore.read() {
                await library.load(folder: saved, into: engine)
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

    func load(folder: URL, into engine: PlaybackEngine) async {
        phase = .loading
        let source = FolderLibrarySource(folder: folder)
        do {
            let loaded = try await source.load()
            tracks = loaded
            tiles = MusicTileBuilder.tiles(from: loaded)
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

private struct FolderPrompt: View {
    @Binding var showPicker: Bool
    var body: some View {
        VStack(spacing: 16) {
            Text("Reborn Zune")
                .font(.largeTitle)
            Text("Pick a folder of music to begin.")
                .foregroundStyle(.secondary)
            Button("Choose Folder…") {
                showPicker = true
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

private struct LoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Reading library…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
