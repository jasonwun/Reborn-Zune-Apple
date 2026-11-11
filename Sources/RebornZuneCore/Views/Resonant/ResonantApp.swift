import SwiftUI
import SwiftData

public enum ResonantPlatform: Sendable {
    case mac
    case ipad
    case tv
}

@MainActor
public struct ResonantApp: View {
    let engine: PlaybackEngine
    let library: ResonantLibrary
    let tiles: [TileWallEntry]
    let lightingAnimator: LightingAnimator?
    let density: ResonantDensity
    let platform: ResonantPlatform
    let needsLibraryFolder: Bool
    let onPickFolder: () -> Void
    let libraryStatus: LibraryStatus?
    let scanBanner: String?
    let onRetry: () -> Void

    @State private var router = ResonantRouter(initial: ResonantRouter.envInitialRoute())
    @State private var showCreatePlaylist = false
    @Environment(\.modelContext) private var modelContext

    public init(engine: PlaybackEngine,
                library: ResonantLibrary,
                tiles: [TileWallEntry],
                lightingAnimator: LightingAnimator?,
                density: ResonantDensity = .cozy,
                platform: ResonantPlatform = .mac,
                needsLibraryFolder: Bool = false,
                onPickFolder: @escaping () -> Void = {},
                libraryStatus: LibraryStatus? = nil,
                scanBanner: String? = nil,
                onRetry: @escaping () -> Void = {}) {
        self.engine = engine
        self.library = library
        self.tiles = tiles
        self.lightingAnimator = lightingAnimator
        self.density = density
        self.platform = platform
        self.needsLibraryFolder = needsLibraryFolder
        self.onPickFolder = onPickFolder
        self.libraryStatus = libraryStatus
        self.scanBanner = scanBanner
        self.onRetry = onRetry
    }

    private var spacing: ResonantSpacing { ResonantSpacing.for(density) }

    private var upNext: [Music] { engine.upNext }

    public var body: some View {
        innerBody
            .preferredColorScheme(.dark)
            .task { await runAutoNav() }
    }

    /// DEBUG perf hook: `REBORN_ZUNE_DEBUG_AUTO_NAV=<route>:<delaySeconds>`
    /// navigates to the route after the delay — used with
    /// `REBORN_ZUNE_DEBUG_PERF=1` to measure main→tile-wall cold-entry cost
    /// without Accessibility permissions.
    private func runAutoNav() async {
        guard let raw = ProcessInfo.processInfo.environment["REBORN_ZUNE_DEBUG_AUTO_NAV"] else { return }
        let parts = raw.split(separator: ":", maxSplits: 1).map(String.init)
        let delay = parts.count > 1 ? Double(parts[1]) ?? 3 : 3
        try? await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000))
        guard !Task.isCancelled, let route = ResonantRouter.parse(parts[0]) else { return }
        router.go(route)
    }

    @ViewBuilder
    private var innerBody: some View {
        ZStack {
            ResonantColors.paper.ignoresSafeArea()

            if platform == .mac {
                // macOS: the MiniPlayer is pinned to the window's bottom
                // edge via safeAreaInset so shrinking the window HEIGHT can
                // never push it off-screen (a VStack sibling gets pushed out
                // whenever the content's fixed-height chain exceeds the
                // window — the content scales with window WIDTH, so a
                // wide-but-short window overflows). Overflow now compresses
                // the content's safe area instead.
                VStack(spacing: 0) {
                    if router.route != .nowPlaying {
                        PivotNav(router: router, spacing: spacing)
                    }
                    if let scanBanner {
                        ScanBanner(message: scanBanner, onRetry: onRetry)
                    }
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if router.route != .nowPlaying {
                        miniPlayer
                    }
                }
            } else {
                VStack(spacing: 0) {
                    if router.route != .nowPlaying {
                        PivotNav(router: router, spacing: spacing)
                    }
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if router.route != .nowPlaying {
                        miniPlayer
                    }
                }
            }

            if showCreatePlaylist {
                CreatePlaylistSheet(
                    onCancel: { showCreatePlaylist = false },
                    onCreate: { name, _ in
                        let newPlaylist = StoredPlaylist(name: name)
                        modelContext.insert(newPlaylist)
                        try? modelContext.save()
                        showCreatePlaylist = false
                        router.go(.playlist(newPlaylist.id.uuidString))
                    }
                )
                .transition(.opacity)
            }
        }
    }

    private var miniPlayer: some View {
        MiniPlayer(engine: engine,
                   spacing: spacing,
                   upNext: upNext.first,
                   isTouch: platform == .ipad,
                   onOpenNowPlaying: { router.go(.nowPlaying) })
    }

    @ViewBuilder
    private var content: some View {
        if let libraryStatus {
            LibraryStatusView(status: libraryStatus, onRetry: onRetry, onPickFolder: onPickFolder)
        } else if needsLibraryFolder {
            FolderEmptyState(onPickFolder: onPickFolder)
        } else {
            switch router.route {
            case .home:
                HomeScreen(library: library,
                           spacing: spacing,
                           engine: engine,
                           showArrows: platform == .mac,
                           onOpen: { router.go(.album($0.id)) },
                           onArtist: { router.go(.artist($0.name)) })
            case .albums:
                AlbumsScreen(library: library, spacing: spacing,
                             onOpen: { router.go(.album($0.id)) })
            case .album(let id):
                // Resolve by exact id, fall back to title prefix match (for
                // env-driven test routes), then to the first album so the
                // screen always renders when the library has content.
                let resolved = library.albums.first(where: { $0.id == id })
                    ?? library.albums.first(where: { $0.title.lowercased().contains(id.lowercased()) })
                    ?? library.albums.first
                if let album = resolved {
                    AlbumScreen(album: album, spacing: spacing, engine: engine,
                                onArtist: { router.go(.artist($0)) })
                } else {
                    Text("Album not found.").foregroundColor(ResonantColors.ink2)
                }
            case .playlists:
                PlaylistsScreen(library: library, spacing: spacing,
                                onOpen: { router.go(.playlist($0.id.uuidString)) },
                                onCreateTapped: { showCreatePlaylist = true })
            case .playlist(let id):
                PlaylistByIDScreen(idString: id,
                                   library: library,
                                   spacing: spacing,
                                   engine: engine)
            case .artists:
                #if os(macOS)
                MacArtistsScreen(library: library, spacing: spacing,
                                 onOpen: { router.go(.artist($0.name)) })
                #else
                ArtistsScreen(library: library, spacing: spacing,
                              onOpen: { router.go(.artist($0.name)) })
                #endif
            case .artist(let name):
                let resolved = library.artists.first(where: { $0.name == name })
                    ?? library.artists.first(where: { $0.name.lowercased().contains(name.lowercased()) })
                    ?? library.artists.first
                if let artist = resolved {
                    #if os(macOS)
                    MacArtistScreen(artist: artist, library: library, spacing: spacing, engine: engine,
                                    onAlbum: { router.go(.album($0.id)) },
                                    onArtist: { router.go(.artist($0.name)) })
                    #else
                    ArtistScreen(artist: artist, library: library, spacing: spacing,
                                 onAlbum: { router.go(.album($0.id)) },
                                 onArtist: { router.go(.artist($0.name)) })
                    #endif
                } else {
                    Text("Artist not found.").foregroundColor(ResonantColors.ink2)
                }
            case .search:
                SearchScreen(library: library, spacing: spacing,
                             onOpen: { router.go(.album($0.id)) })
            case .nowPlaying:
                NowPlayingScreen(tiles: tiles,
                                 lightingAnimator: lightingAnimator,
                                 engine: engine,
                                 upNext: upNext,
                                 spacing: spacing,
                                 onBack: {
                                     if router.canGoBack { router.back() }
                                     else { router.go(.home) }
                                 })
            }
        }
    }
}

private struct PlaylistByIDScreen: View {
    let idString: String
    let library: ResonantLibrary
    let spacing: ResonantSpacing
    let engine: PlaybackEngine
    @Query var playlists: [StoredPlaylist]

    var body: some View {
        if let playlist = playlists.first(where: { $0.id.uuidString == idString }) {
            PlaylistScreen(playlist: playlist, library: library, spacing: spacing, engine: engine)
        } else {
            VStack {
                Text("Playlist not found.")
                    .foregroundColor(ResonantColors.ink2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// What the Library coordinator can honestly report when there is nothing
/// to browse. Never substitutes Demo Library content.
public enum LibraryStatus: Equatable, Sendable {
    case loading
    case empty(path: String)
    case failed(message: String)
}

/// Shown when a refresh failed but a previously committed Library is still
/// browsable and playing.
private struct ScanBanner: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(ResonantColors.ink2)
                .lineLimit(2)
            Spacer(minLength: 12)
            Button("Retry", action: onRetry)
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(2.2)
                .textCase(.uppercase)
                .foregroundColor(ResonantColors.magenta)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }
}

private struct LibraryStatusView: View {
    let status: LibraryStatus
    let onRetry: () -> Void
    let onPickFolder: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ResonantStack().frame(width: 88, height: 88)
            switch status {
            case .loading:
                Text("RESONANT · SCANNING")
                    .resonantTag(size: 10, tracking: 2.2, color: ResonantColors.magenta)
                Text("Scanning your library…")
                    .font(ResonantFont.display(72, weight: .ultraLight))
                    .tracking(-1.4)
                ProgressView().controlSize(.small)
            case .empty(let path):
                Text("RESONANT · YOUR LIBRARY IS EMPTY")
                    .resonantTag(size: 10, tracking: 2.2, color: ResonantColors.magenta)
                Text("No music found")
                    .font(ResonantFont.display(96, weight: .ultraLight))
                    .tracking(-2.0)
                Text("There are no supported audio files (MP3, M4A, MP4, AAC, FLAC, WAV, AIFF) in \(path). Add some and relaunch, or scan again.")
                    .font(.system(size: 14))
                    .foregroundColor(ResonantColors.ink2)
                    .frame(maxWidth: 540, alignment: .leading)
                HStack(spacing: 18) {
                    retryButton("Scan again")
                    Button("Manage Sources", action: onPickFolder)
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .tracking(2.2)
                        .textCase(.uppercase)
                        .foregroundColor(ResonantColors.magenta)
                        .padding(.top, 8)
                }
            case .failed(let message):
                Text("RESONANT · SCAN FAILED")
                    .resonantTag(size: 10, tracking: 2.2, color: ResonantColors.magenta)
                Text("Couldn’t read your library")
                    .font(ResonantFont.display(72, weight: .ultraLight))
                    .tracking(-1.4)
                Text(message)
                    .font(.system(size: 14))
                    .foregroundColor(ResonantColors.ink2)
                    .frame(maxWidth: 540, alignment: .leading)
                retryButton("Retry")
            }
        }
        .padding(80)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func retryButton(_ title: String) -> some View {
        Button(action: onRetry) {
            Text(title)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(2.2)
                .textCase(.uppercase)
                .foregroundColor(ResonantColors.paper)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
        }
        .background(ResonantColors.magenta)
        .buttonStyle(.plain)
        .padding(.top, 8)
    }
}

private struct FolderEmptyState: View {
    let onPickFolder: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ResonantStack().frame(width: 88, height: 88)
            Text("RESONANT · YOUR LIBRARY IS EMPTY")
                .resonantTag(size: 10, tracking: 2.2, color: ResonantColors.magenta)
            Text("Pick a folder")
                .font(ResonantFont.display(120, weight: .ultraLight))
                .tracking(-2.4)
            Text("Resonant scans the folder you choose for audio files and turns them into the panorama. Drag-and-drop is coming later.")
                .font(.system(size: 14))
                .foregroundColor(ResonantColors.ink2)
                .frame(maxWidth: 540, alignment: .leading)
            HStack(spacing: 12) {
                Button(action: onPickFolder) {
                    Text("Choose folder…")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .tracking(2.2)
                        .textCase(.uppercase)
                        .foregroundColor(ResonantColors.paper)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                }
                .background(ResonantColors.magenta)
                .buttonStyle(.plain)
            }
            .padding(.top, 8)
        }
        .padding(80)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
