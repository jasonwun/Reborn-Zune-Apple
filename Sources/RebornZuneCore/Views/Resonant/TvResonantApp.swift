import SwiftUI

@MainActor
public struct TvResonantApp: View {
    let engine: PlaybackEngine
    let library: ResonantLibrary
    let tiles: [TileWallEntry]
    let lightingAnimator: LightingAnimator?

    @State private var router = ResonantRouter(initial: ResonantRouter.envInitialRoute())
    /// Mirrors `tvos-shell.jsx`'s focus grid — top-nav row owns its
    /// own FocusState binding so route changes can land focus on the
    /// matching pivot instead of leaving it stranded wherever the
    /// user last was.
    @FocusState private var topNavFocus: PivotID?

    public init(engine: PlaybackEngine,
                library: ResonantLibrary,
                tiles: [TileWallEntry],
                lightingAnimator: LightingAnimator?) {
        self.engine = engine
        self.library = library
        self.tiles = tiles
        self.lightingAnimator = lightingAnimator
    }

    private var upNext: [Music] {
        let q = engine.queue
        guard !q.isEmpty, let current = engine.currentItem,
              let idx = q.firstIndex(where: { $0.id == current.id }) else { return [] }
        return Array(q[(idx + 1)...].prefix(8))
    }

    public var body: some View {
        ZStack {
            // Design v2: tvOS dark paper is pure #000000, not the warm
            // #0E0D0A that mac/iPad share. The CSS spec is
            // `[data-platform="tv"][data-theme="dark"] { --paper: #000000 }`.
            // Living-room OLED + 10ft viewing wants the true black.
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                if router.route != .nowPlaying {
                    TvTopNav(router: router, focus: $topNavFocus)
                }
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .preferredColorScheme(.dark)
        // tvOS sims and devices both render at 1920×1080 → bucket as
        // .expanded .landscape (displayFontScale 1.0). Inject it
        // explicitly so any view reading \.resonantLayout gets the
        // correct scale instead of the default .regular (0.92).
        .environment(\.resonantLayout,
                     ResonantLayout(deviceClass: .expanded, orientation: .landscape))
        // First appearance: focus the pivot the launch route belongs to
        // (covers REBORN_ZUNE_DEBUG_INITIAL_ROUTE deep-links + cold
        // launches). Wrapped in `Task { @MainActor }` so the focus is
        // set after the `@FocusState` view is in the hierarchy — setting
        // it inline during `body` evaluation is a no-op.
        .task {
            if let p = PivotID.from(route: router.route) {
                topNavFocus = p
            }
        }
        // Route change → re-focus the matching pivot. Same effect as
        // tvos-shell.jsx's `useEffect([activeRoute])` syncer.
        .onChange(of: router.route) { _, newRoute in
            if let p = PivotID.from(route: newRoute) {
                topNavFocus = p
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch router.route {
        case .home:
            TvHomeScreen(library: library,
                         engine: engine,
                         onAlbum: { router.go(.album($0.id)) },
                         onArtist: { router.go(.artist($0.name)) })
        case .playlists:
            // Design's `kind: 'pl'` browse — grid of CoverMosaic tiles
            // pulled from SwiftData playlists (synced from mac/iPad).
            TvPlaylistsScreen(library: library,
                              onOpen: { router.go(.playlist($0.id.uuidString)) })
        case .albums:
            TvBrowseScreen(kind: .albums,
                           library: library,
                           onOpenAlbum: { router.go(.album($0.id)) },
                           onOpenArtist: { router.go(.artist($0.name)) })
        case .artists:
            TvBrowseScreen(kind: .artists,
                           library: library,
                           onOpenAlbum: { router.go(.album($0.id)) },
                           onOpenArtist: { router.go(.artist($0.name)) })
        case .album(let id):
            if let album = library.albums.first(where: { $0.id == id }) {
                TvAlbumScreen(album: album, engine: engine,
                              onArtist: { router.go(.artist($0)) })
            } else {
                Text("Album not found").foregroundColor(ResonantColors.ink2)
            }
        case .artist(let name):
            if let artist = library.artists.first(where: { $0.name == name }) {
                TvArtistScreen(artist: artist, library: library,
                               onAlbum: { router.go(.album($0.id)) })
            } else {
                Text("Artist not found").foregroundColor(ResonantColors.ink2)
            }
        case .search:
            TvSearchScreen(library: library,
                           onOpen: { router.go(.album($0.id)) })
        case .nowPlaying:
            TvNowPlayingScreen(tiles: tiles,
                               lightingAnimator: lightingAnimator,
                               engine: engine,
                               upNext: upNext,
                               onDismiss: {
                                   if router.canGoBack { router.back() }
                                   else { router.go(.home) }
                               })
        case .playlist(let id):
            // Individual playlist detail — the design has `tv-playlist.jsx`
            // for this, not yet ported. For now reuse the shared
            // `PlaylistScreen` looked up by id; if it doesn't resolve,
            // fall back to the playlists tab so the user can try again.
            TvPlaylistByIDScreen(idString: id, library: library, engine: engine,
                                 onBack: { router.go(.playlists) })
        }
    }
}
