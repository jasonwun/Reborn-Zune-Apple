import XCTest
import MediaPlayer
@testable import RebornZuneCore

@MainActor
final class NowPlayingCenterTests: XCTestCase {

    private func makeMusic(_ title: String, artist: String? = "Some Artist", album: String? = "Some Album") -> Music {
        let url = URL(fileURLWithPath: "/tmp/reborn-zune-tests/\(title).m4a")
        return Music(
            id: Music.makeID(for: url),
            url: url,
            title: title,
            artist: artist,
            albumArtist: nil,
            albumTitle: album,
            year: nil,
            duration: 100,
            artworkData: nil
        )
    }

    func testRegisterEnablesAllSupportedRemoteCommands() {
        let center = NowPlayingCenter()

        center.registerCommands(RemoteCommandHandlers(
            play: {}, pause: {}, toggle: {}, next: {}, previous: {},
            seek: { _ in }, shuffle: { _ in }, repeat: { _ in }
        ))

        let commands = MPRemoteCommandCenter.shared()
        XCTAssertTrue(commands.playCommand.isEnabled)
        XCTAssertTrue(commands.pauseCommand.isEnabled)
        XCTAssertTrue(commands.togglePlayPauseCommand.isEnabled)
        XCTAssertTrue(commands.nextTrackCommand.isEnabled)
        XCTAssertTrue(commands.previousTrackCommand.isEnabled)
        XCTAssertTrue(commands.changePlaybackPositionCommand.isEnabled)
        XCTAssertTrue(commands.changeShuffleModeCommand.isEnabled)
        XCTAssertTrue(commands.changeRepeatModeCommand.isEnabled)
    }

    func testUpdateProducesExpectedKeys() {
        let center = NowPlayingCenter()
        let music = makeMusic("My Song", artist: "Artist X", album: "Album Y")
        center.update(item: music, currentTime: 12.5, duration: 100, rate: 1.0)

        let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
        XCTAssertNotNil(info)
        XCTAssertEqual(info?[MPMediaItemPropertyTitle] as? String, "My Song")
        XCTAssertEqual(info?[MPMediaItemPropertyArtist] as? String, "Artist X")
        XCTAssertEqual(info?[MPMediaItemPropertyAlbumTitle] as? String, "Album Y")
        XCTAssertEqual(info?[MPMediaItemPropertyPlaybackDuration] as? TimeInterval, 100)
        XCTAssertEqual(info?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? TimeInterval, 12.5)
        XCTAssertEqual(info?[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 1.0)
    }

    func testUpdateWithNilClearsInfo() {
        let center = NowPlayingCenter()
        // First populate.
        center.update(item: makeMusic("Anything"), currentTime: 0, duration: 100, rate: 1.0)
        XCTAssertNotNil(MPNowPlayingInfoCenter.default().nowPlayingInfo)

        // Then clear.
        center.update(item: nil, currentTime: 0, duration: 0, rate: 0)
        let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
        XCTAssertTrue(info == nil || info?.isEmpty == true,
                      "Expected nowPlayingInfo to be nil or empty after clearing")
    }
}
