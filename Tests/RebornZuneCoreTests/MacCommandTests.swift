import XCTest
@testable import RebornZuneCore

@MainActor
final class MacCommandTests: XCTestCase {
    func testPlaybackShortcutDoesNotFireWhileEditingText() {
        let engine = PlaybackEngine()
        let router = ResonantRouter()
        let commands = MacCommandHandler(engine: engine, router: router)
        let url = URL(fileURLWithPath: "/tmp/reborn-zune-tests/text-shortcut.m4a")
        let track = Music(id: "text-shortcut", url: url, title: "Text Shortcut", artist: nil,
                          albumArtist: nil, albumTitle: nil, year: nil, duration: 100, artworkData: nil)
        engine.setQueue([track])
        engine.play()

        commands.perform(.togglePlayPause, source: .shortcut, isTextEditing: true)

        XCTAssertEqual(engine.state, .playing)
        commands.perform(.togglePlayPause, source: .shortcut, isTextEditing: false)
        XCTAssertEqual(engine.state, .paused)
    }

    func testTransportCommandsRouteThroughPublicPlaybackBehavior() {
        let engine = PlaybackEngine()
        let router = ResonantRouter()
        let commands = MacCommandHandler(engine: engine, router: router)
        let tracks = (0..<3).map { index in
            let url = URL(fileURLWithPath: "/tmp/reborn-zune-tests/transport-\(index).m4a")
            return Music(id: "transport-\(index)", url: url, title: "Track \(index)", artist: nil,
                         albumArtist: nil, albumTitle: nil, year: nil, duration: 100, artworkData: nil)
        }
        engine.setQueue(tracks)
        engine.volume = 0.5

        commands.perform(.nextTrack, source: .shortcut, isTextEditing: true)
        XCTAssertEqual(engine.currentItem, tracks[0])
        commands.perform(.nextTrack)
        commands.perform(.previousTrack)
        XCTAssertEqual(engine.currentItem, tracks[0])
        commands.perform(.skipForward)
        commands.perform(.skipBackward)
        commands.perform(.increaseVolume)
        commands.perform(.decreaseVolume)
        commands.perform(.toggleShuffle)
        commands.perform(.setRepeat(.one))

        XCTAssertEqual(engine.currentTime, 0, accuracy: 0.0001)
        XCTAssertEqual(engine.volume, 0.5, accuracy: 0.0001)
        XCTAssertTrue(engine.isShuffling)
        XCTAssertEqual(engine.repeatMode, .one)
    }

    func testNavigationCommandsSelectPivotsNowPlayingAndBack() {
        let router = ResonantRouter()
        let commands = MacCommandHandler(engine: PlaybackEngine(), router: router)
        let expectedRoutes: [(MacCommand, ResonantRouter.Route)] = [
            (.showAlbums, .albums),
            (.showPlaylists, .playlists),
            (.showArtists, .artists),
            (.showSearch, .search),
            (.showHome, .home),
        ]
        for (command, route) in expectedRoutes {
            commands.perform(command)
            XCTAssertEqual(router.route, route)
        }

        commands.perform(.focusSearch)
        XCTAssertEqual(router.searchFocusRequestID, 1)
        commands.perform(.showNowPlaying)
        XCTAssertEqual(router.route, .nowPlaying)
        commands.perform(.back)
        XCTAssertEqual(router.route, .search)
    }

    func testFocusingSearchNavigatesAndRequestsFieldFocusEachTime() {
        let router = ResonantRouter()

        router.focusSearch()
        XCTAssertEqual(router.route, .search)
        XCTAssertEqual(router.searchFocusRequestID, 1)

        router.focusSearch()
        XCTAssertEqual(router.route, .search)
        XCTAssertEqual(router.searchFocusRequestID, 2)
    }
}
