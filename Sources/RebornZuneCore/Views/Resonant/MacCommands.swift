import Foundation

/// macOS commands shared by menu and keyboard entry points.
public enum MacCommand: Sendable, Equatable {
    case togglePlayPause
    case nextTrack
    case previousTrack
    case skipForward
    case skipBackward
    case increaseVolume
    case decreaseVolume
    case toggleShuffle
    case setRepeat(RepeatMode)
    case showHome
    case showAlbums
    case showPlaylists
    case showArtists
    case showSearch
    case focusSearch
    case showNowPlaying
    case back

    var isPlaybackShortcut: Bool {
        switch self {
        case .togglePlayPause, .nextTrack, .previousTrack, .skipForward,
             .skipBackward, .increaseVolume, .decreaseVolume:
            return true
        case .toggleShuffle, .setRepeat, .showHome, .showAlbums, .showPlaylists,
             .showArtists, .showSearch, .focusSearch, .showNowPlaying, .back:
            return false
        }
    }
}

public enum MacCommandSource: Sendable, Equatable {
    case menu
    case shortcut
}

/// Routes system chrome through the same public playback and navigation API as the views.
@MainActor
public struct MacCommandHandler {
    private let engine: PlaybackEngine
    private let router: ResonantRouter

    public init(engine: PlaybackEngine, router: ResonantRouter) {
        self.engine = engine
        self.router = router
    }

    public func perform(
        _ command: MacCommand,
        source: MacCommandSource = .menu,
        isTextEditing: Bool = false
    ) {
        if source == .shortcut && isTextEditing && command.isPlaybackShortcut {
            return
        }
        switch command {
        case .togglePlayPause:
            engine.togglePlayPause()
        case .nextTrack:
            engine.next()
        case .previousTrack:
            engine.previous()
        case .skipForward:
            engine.skipForward()
        case .skipBackward:
            engine.skipBackward()
        case .increaseVolume:
            engine.increaseVolume()
        case .decreaseVolume:
            engine.decreaseVolume()
        case .toggleShuffle:
            engine.isShuffling.toggle()
        case .setRepeat(let mode):
            engine.repeatMode = mode
        case .showHome:
            router.go(.home)
        case .showAlbums:
            router.go(.albums)
        case .showPlaylists:
            router.go(.playlists)
        case .showArtists:
            router.go(.artists)
        case .showSearch:
            router.go(.search)
        case .focusSearch:
            router.focusSearch()
        case .showNowPlaying:
            router.go(.nowPlaying)
        case .back:
            router.back()
        }
    }
}
