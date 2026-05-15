import SwiftUI

@MainActor
public struct TvResonantApp: View {
    let engine: PlaybackEngine
    let library: ResonantLibrary
    let tiles: [TileWallEntry]
    let lightingAnimator: LightingAnimator?

    @State private var router = ResonantRouter()

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
            ResonantColors.paper.ignoresSafeArea()

            VStack(spacing: 0) {
                if router.route != .nowPlaying {
                    TvTopNav(router: router)
                }
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var content: some View {
        switch router.route {
        case .home, .playlists:
            // No playlists on TV — route to home.
            TvHomeScreen(library: library,
                         engine: engine,
                         onAlbum: { router.go(.album($0.id)) },
                         onArtist: { router.go(.artist($0.name)) })
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
        case .playlist:
            TvHomeScreen(library: library, engine: engine,
                         onAlbum: { router.go(.album($0.id)) },
                         onArtist: { router.go(.artist($0.name)) })
        }
    }
}
