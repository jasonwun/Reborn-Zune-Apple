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
    let onGrantAccess: (() -> Void)?
    let usesStoreBrowsing: Bool
    let loadedTrackCount: Int
    let totalTrackCount: Int?
    let hasMoreTracks: Bool
    let onLoadMore: () -> Void
    let onBrowse: (LibraryTrackQuery) async -> Void
    let resolveAlbum: (Album) async -> Album?
    let resolveArtist: (Artist) async -> Artist?
    let resolveTracks: (([String]) async -> [Music])?
    let resolvePlaylistPickerTracks: ((String) async -> [Music])?

    @State private var router: ResonantRouter
    @State private var showCreatePlaylist = false
    @State private var playlistInteraction = PlaylistInteractionState()
    @State private var resolvedAlbums: [String: Album] = [:]
    @State private var resolvedArtists: [String: Artist] = [:]
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StoredPlaylist.createdAt, order: .reverse) private var playlists: [StoredPlaylist]

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
                onRetry: @escaping () -> Void = {},
                onGrantAccess: (() -> Void)? = nil,
                router: ResonantRouter? = nil,
                usesStoreBrowsing: Bool = false,
                loadedTrackCount: Int = 0,
                totalTrackCount: Int? = nil,
                hasMoreTracks: Bool = false,
                onLoadMore: @escaping () -> Void = {},
                onBrowse: @escaping (LibraryTrackQuery) async -> Void = { _ in },
                resolveAlbum: @escaping (Album) async -> Album? = { $0 },
                resolveArtist: @escaping (Artist) async -> Artist? = { $0 },
                resolveTracks: (([String]) async -> [Music])? = nil,
                resolvePlaylistPickerTracks: ((String) async -> [Music])? = nil) {
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
        self.onGrantAccess = onGrantAccess
        _router = State(initialValue: router ?? ResonantRouter(initial: ResonantRouter.envInitialRoute()))
        self.usesStoreBrowsing = usesStoreBrowsing
        self.loadedTrackCount = loadedTrackCount
        self.totalTrackCount = totalTrackCount
        self.hasMoreTracks = hasMoreTracks
        self.onLoadMore = onLoadMore
        self.onBrowse = onBrowse
        self.resolveAlbum = resolveAlbum
        self.resolveArtist = resolveArtist
        self.resolveTracks = resolveTracks
        self.resolvePlaylistPickerTracks = resolvePlaylistPickerTracks
    }

    private func openAlbum(_ album: Album) {
        Task {
            let resolved = await resolveAlbum(album) ?? album
            resolvedAlbums[resolved.id] = resolved
            router.go(.album(resolved.id))
        }
    }

    private func openArtist(_ artist: Artist) {
        Task {
            let resolved = await resolveArtist(artist) ?? artist
            resolvedArtists[resolved.name] = resolved
            router.go(.artist(resolved.name))
        }
    }

    private func openArtist(named name: String) {
        openArtist(resolvedArtists[name]
            ?? library.artists.first { $0.name == name }
            ?? Artist(id: Artist.makeID(name: name), name: name, albums: []))
    }

    private func playAlbum(_ album: Album) {
        Task {
            let resolved = await resolveAlbum(album) ?? album
            engine.setQueue(resolved.tracks)
            engine.play()
        }
    }

    private var spacing: ResonantSpacing { ResonantSpacing.for(density) }
    private var playlistStore: PlaylistStore { PlaylistStore(modelContext: modelContext) }
    private var playlistActions: PlaylistActions {
        PlaylistActions(
            playlists: playlists,
            onAdd: { tracks, playlist in addTracks(tracks, to: playlist) },
            onNew: { tracks in
                playlistInteraction.requestCreate(
                    trackIDs: tracks.map(\.id), opensAfterCreation: false)
            })
    }

    private func addTracks(_ tracks: [Music], to playlist: StoredPlaylist) {
        do {
            try playlistStore.addTracks(tracks.map(\.id), to: playlist)
            playlistInteraction.showAddedFeedback(to: playlist.name)
        } catch {
            // SwiftData keeps the previous state when saving fails.
        }
    }

    private var upNext: [Music] { engine.upNext }

    public var body: some View {
        innerBody
            .preferredColorScheme(.dark)
            .task { await runAutoNav() }
            .task {
                guard usesStoreBrowsing else { return }
                if router.route == .albums {
                    await onBrowse(LibraryTrackQuery(sort: .albumTitle))
                } else if router.route == .artists {
                    await onBrowse(LibraryTrackQuery(sort: .artist))
                }
            }
            .onChange(of: router.route) { previous, current in
                guard usesStoreBrowsing else { return }
                if current == .artists && previous.pivot != .artists {
                    Task { await onBrowse(LibraryTrackQuery(sort: .artist)) }
                } else if current == .albums && previous.pivot != .albums {
                    Task { await onBrowse(LibraryTrackQuery(sort: .albumTitle)) }
                } else if previous == .search && current != .search {
                    Task { await onBrowse(LibraryTrackQuery()) }
                }
            }
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
                        ScanBanner(message: scanBanner, onRetry: onRetry, onGrantAccess: onGrantAccess)
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

            #if os(macOS)
            macPlaylistOverlays
            if let feedback = playlistInteraction.addedFeedback {
                VStack {
                    Spacer()
                    MacPlaylistFeedback(message: feedback)
                        .padding(.bottom, 92)
                }
                .transition(.opacity)
                .task(id: feedback) {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    guard !Task.isCancelled else { return }
                    playlistInteraction.clearFeedback(feedback)
                }
            }
            #else
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
            #endif
        }
    }

    #if os(macOS)
    @ViewBuilder
    private var macPlaylistOverlays: some View {
        if let request = playlistInteraction.createRequest {
            MacPlaylistNameSheet(
                title: "New Playlist", confirmation: "Create",
                onCancel: playlistInteraction.cancelSheets,
                onConfirm: { name in
                    do {
                        let playlist = try playlistStore.createPlaylist(named: name)
                        if !request.trackIDs.isEmpty {
                            try playlistStore.addTracks(request.trackIDs, to: playlist)
                            playlistInteraction.showAddedFeedback(to: playlist.name)
                        }
                        playlistInteraction.completeCreation(with: playlist.id, router: router)
                    } catch {}
                })
                .id("\(request.opensAfterCreation)-\(request.trackIDs.joined(separator: ","))")
        }
        if let request = playlistInteraction.renameRequest,
           let playlist = playlists.first(where: { $0.id == request.playlistID }) {
            MacPlaylistNameSheet(
                title: "Rename Playlist", confirmation: "Rename", initialName: request.currentName,
                onCancel: playlistInteraction.cancelSheets,
                onConfirm: { name in
                    do {
                        try playlistStore.renamePlaylist(playlist, to: name)
                        playlistInteraction.cancelSheets()
                    } catch {}
                })
                .id(request.playlistID)
        }
        if let playlistID = playlistInteraction.deletePlaylistID,
           let playlist = playlists.first(where: { $0.id == playlistID }) {
            MacDeletePlaylistSheet(
                playlistName: playlist.name,
                onCancel: playlistInteraction.cancelSheets,
                onDelete: {
                    do {
                        try playlistStore.deletePlaylist(playlist)
                        playlistInteraction.completeDeletion(router: router)
                    } catch {}
                })
                .id(playlistID)
        }
        if let playlistID = playlistInteraction.pickerPlaylistID,
           let playlist = playlists.first(where: { $0.id == playlistID }) {
            MacPlaylistPicker(
                loadTracks: {
                    if let resolvePlaylistPickerTracks {
                        return await resolvePlaylistPickerTracks("")
                    }
                    return library.albums.flatMap(\.tracks)
                },
                onCancel: playlistInteraction.cancelSheets,
                onAdd: { tracks in
                    addTracks(tracks, to: playlist)
                    playlistInteraction.cancelSheets()
                })
                .id(playlistID)
        }
    }
    #endif

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
            LibraryStatusView(status: libraryStatus, onRetry: onRetry, onPickFolder: onPickFolder,
                              onGrantAccess: onGrantAccess)
        } else if needsLibraryFolder {
            FolderEmptyState(onPickFolder: onPickFolder)
        } else {
            switch router.route {
            case .home:
                HomeScreen(library: library,
                           spacing: spacing,
                           engine: engine,
                           showArrows: platform == .mac,
                           onOpen: openAlbum,
                           onArtist: openArtist,
                           onPlayAlbum: playAlbum)
            case .albums:
                AlbumsScreen(library: library, spacing: spacing,
                             totalTrackCount: totalTrackCount,
                             hasMoreTracks: hasMoreTracks,
                             loadedTrackCount: loadedTrackCount,
                             usesStoreOrdering: usesStoreBrowsing,
                             onLoadMore: onLoadMore,
                             onSort: { sort in
                                 await onBrowse(LibraryTrackQuery(sort: sort.trackSort))
                             },
                             onOpen: openAlbum)
            case .album(let id):
                // Resolve by exact id, fall back to title prefix match (for
                // env-driven test routes), then to the first album so the
                // screen always renders when the library has content.
                let resolved = resolvedAlbums[id]
                    ?? library.albums.first(where: { $0.id == id })
                    ?? library.albums.first(where: { $0.title.lowercased().contains(id.lowercased()) })
                    ?? library.albums.first
                if let album = resolved {
                    AlbumScreen(album: album, spacing: spacing, engine: engine,
                                onArtist: openArtist(named:),
                                playlistActions: platform == .mac ? playlistActions : nil)
                } else {
                    Text("Album not found.").foregroundColor(ResonantColors.ink2)
                }
            case .playlists:
                PlaylistsScreen(
                    library: library, spacing: spacing,
                    onOpen: { router.go(.playlist($0.id.uuidString)) },
                    onCreateTapped: {
                        #if os(macOS)
                        playlistInteraction.requestCreate(opensAfterCreation: true)
                        #else
                        showCreatePlaylist = true
                        #endif
                    },
                    onRename: { playlist in
                        playlistInteraction.requestRename(
                            playlistID: playlist.id, currentName: playlist.name)
                    },
                    onDelete: { playlistInteraction.requestDeletion(playlistID: $0.id) },
                    resolveTracks: resolveTracks)
            case .playlist(let id):
                PlaylistByIDScreen(
                    idString: id,
                    library: library,
                    spacing: spacing,
                    engine: engine,
                    resolveTracks: resolveTracks,
                    playlistActions: platform == .mac ? playlistActions : nil,
                    onAddTracks: { playlistInteraction.requestPicker(playlistID: UUID(uuidString: id) ?? UUID()) },
                    onRename: { playlist in
                        playlistInteraction.requestRename(
                            playlistID: playlist.id, currentName: playlist.name)
                    },
                    onDelete: { playlistInteraction.requestDeletion(playlistID: $0.id) },
                    onRemoveEntry: { playlist, entry in
                        try? playlistStore.removeEntry(entry, from: playlist)
                    },
                    onMoveEntry: { playlist, entry, destination in
                        try? playlistStore.moveEntry(entry, to: destination, in: playlist)
                    })
            case .artists:
                #if os(macOS)
                MacArtistsScreen(library: library, spacing: spacing,
                                 totalTrackCount: totalTrackCount,
                                 hasMoreTracks: hasMoreTracks,
                                 loadedTrackCount: loadedTrackCount,
                                 onLoadMore: onLoadMore,
                                 onOpen: openArtist)
                #else
                ArtistsScreen(library: library, spacing: spacing,
                              onOpen: { router.go(.artist($0.name)) })
                #endif
            case .artist(let name):
                let resolved = resolvedArtists[name]
                    ?? library.artists.first(where: { $0.name == name })
                    ?? library.artists.first(where: { $0.name.lowercased().contains(name.lowercased()) })
                    ?? library.artists.first
                if let artist = resolved {
                    #if os(macOS)
                    MacArtistScreen(artist: artist, library: library, spacing: spacing, engine: engine,
                                    onAlbum: openAlbum,
                                    onArtist: openArtist,
                                    playlistActions: playlistActions)
                    #else
                    ArtistScreen(artist: artist, library: library, spacing: spacing,
                                 onAlbum: openAlbum,
                                 onArtist: openArtist)
                    #endif
                } else {
                    Text("Artist not found.").foregroundColor(ResonantColors.ink2)
                }
            case .search:
                SearchScreen(library: library, spacing: spacing, router: router,
                             totalTrackCount: totalTrackCount,
                             hasMoreTracks: hasMoreTracks,
                             loadedTrackCount: loadedTrackCount,
                             usesStoreBrowsing: usesStoreBrowsing,
                             onLoadMore: onLoadMore,
                             onSearch: { query in
                                 await onBrowse(LibraryTrackQuery(searchText: query))
                             },
                             onOpen: openAlbum)
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
    let resolveTracks: (([String]) async -> [Music])?
    let playlistActions: PlaylistActions?
    let onAddTracks: () -> Void
    let onRename: (StoredPlaylist) -> Void
    let onDelete: (StoredPlaylist) -> Void
    let onRemoveEntry: (StoredPlaylist, StoredPlaylistEntry) -> Void
    let onMoveEntry: (StoredPlaylist, StoredPlaylistEntry, Int) -> Void
    @Query var playlists: [StoredPlaylist]
    @State private var resolvedLibrary: ResonantLibrary?
    @State private var resolvedEntryIDs: [String]?

    var body: some View {
        if let playlist = playlists.first(where: { $0.id.uuidString == idString }) {
            let entryIDs = PlaylistEntryOrdering.sorted(playlist.entries).map(\.resolvedTrackID)
            Group {
                if resolveTracks == nil || resolvedEntryIDs == entryIDs {
                    PlaylistScreen(
                        playlist: playlist,
                        library: resolveTracks == nil
                            ? library
                            : resolvedLibrary ?? ResonantLibrary(albums: [], artists: []),
                        spacing: spacing,
                        engine: engine,
                        playlistActions: playlistActions,
                        onAddTracks: onAddTracks,
                        onRename: { onRename(playlist) },
                        onDelete: { onDelete(playlist) },
                        onRemoveEntry: onRemoveEntry,
                        onMoveEntry: onMoveEntry
                    )
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .task(id: entryIDs) {
                resolvedEntryIDs = nil
                guard let resolveTracks else {
                    resolvedEntryIDs = entryIDs
                    return
                }
                guard !entryIDs.isEmpty else {
                    resolvedLibrary = ResonantLibrary(albums: [], artists: [])
                    resolvedEntryIDs = entryIDs
                    return
                }
                let tracks = await resolveTracks(entryIDs)
                let albums = await Task.detached { LibraryGrouping.albums(from: tracks) }.value
                resolvedLibrary = ResonantLibrary(albums: albums, artists: [])
                resolvedEntryIDs = entryIDs
            }
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
    let onGrantAccess: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(ResonantColors.ink2)
                .lineLimit(2)
            Spacer(minLength: 12)
            if let onGrantAccess {
                Button("Grant Access…", action: onGrantAccess)
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(2.2)
                    .textCase(.uppercase)
                    .foregroundColor(ResonantColors.magenta)
            }
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
    let onGrantAccess: (() -> Void)?

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
                HStack(spacing: 18) {
                    retryButton("Retry")
                    if let onGrantAccess {
                        Button("Grant Access…", action: onGrantAccess)
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .tracking(2.2)
                            .textCase(.uppercase)
                            .foregroundColor(ResonantColors.magenta)
                            .padding(.top, 8)
                    }
                }
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
