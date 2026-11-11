import XCTest
import MediaPlayer
@testable import RebornZuneCore

@MainActor
final class PlaybackEngineTests: XCTestCase {

    // MARK: - Fixtures

    private func makeMusic(_ name: String) -> Music {
        let url = URL(fileURLWithPath: "/tmp/reborn-zune-tests/\(name).m4a")
        return Music(
            id: Music.makeID(for: url),
            url: url,
            title: name,
            artist: "Test Artist",
            albumArtist: nil,
            albumTitle: "Test Album",
            year: nil,
            duration: 1.0,
            artworkData: nil
        )
    }

    // MARK: - Tests

    func testPlaybackBalancesSecurityScopesAcrossAdvanceAndTrackRemoval() throws {
        let bookmarks = FakeBookmarkAccess()
        let engine = PlaybackEngine(fileAccess: { url in
            try bookmarks.startAccessing(bookmark: Data("playback".utf8), at: url)
        })
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let audioURL = repositoryRoot.appendingPathComponent("Apps/tvOS/Resources/silence.m4a")
        let tracks = (0..<5).map { index in
            Music(id: UUID().uuidString, url: audioURL, title: "scope\(index)",
                  artist: nil, albumArtist: nil, albumTitle: nil, year: nil,
                  duration: 5, artworkData: nil)
        }

        engine.setQueue(tracks)
        XCTAssertEqual(bookmarks.starts, 5, "each loaded AVPlayerItem owns access")
        XCTAssertEqual(bookmarks.stops, 0, "AVPlayer may read lazily after the scan scope stops")

        engine.next()
        XCTAssertEqual(bookmarks.starts, 9)
        XCTAssertEqual(bookmarks.stops, 5, "advancing releases the previous AVQueuePlayer items")

        engine.removeTracks(withIDs: Set(tracks.map(\.id)))
        XCTAssertEqual(bookmarks.starts, bookmarks.stops)
        XCTAssertEqual(bookmarks.stops, 9)
    }

    func testInitialStateIsStoppedNoItem() {
        let engine = PlaybackEngine()
        XCTAssertEqual(engine.state, .stopped)
        XCTAssertNil(engine.currentItem)
        XCTAssertEqual(engine.queue, [])
        XCTAssertEqual(engine.currentTime, 0)
        XCTAssertEqual(engine.duration, 0)
        XCTAssertFalse(engine.isShuffling)
        XCTAssertEqual(engine.repeatMode, .off)
    }

    func testSetQueueAdvancesToFirstTrack() {
        let engine = PlaybackEngine()
        let a = makeMusic("a"), b = makeMusic("b"), c = makeMusic("c")
        engine.setQueue([a, b, c])
        XCTAssertEqual(engine.currentItem, a)
        XCTAssertEqual(engine.queue, [a, b, c])
    }

    func testSetQueueWithStartingAt() {
        let engine = PlaybackEngine()
        let a = makeMusic("a"), b = makeMusic("b"), c = makeMusic("c")
        engine.setQueue([a, b, c], startingAt: 1)
        XCTAssertEqual(engine.currentItem, b)
    }

    func testNextAdvancesQueue() {
        let engine = PlaybackEngine()
        let a = makeMusic("a"), b = makeMusic("b"), c = makeMusic("c")
        engine.setQueue([a, b, c])
        XCTAssertEqual(engine.currentItem, a)
        engine.next()
        XCTAssertEqual(engine.currentItem, b)
    }

    func testPreviousReverses() {
        let engine = PlaybackEngine()
        let a = makeMusic("a"), b = makeMusic("b"), c = makeMusic("c")
        engine.setQueue([a, b, c], startingAt: 1)
        XCTAssertEqual(engine.currentItem, b)
        engine.previous()
        XCTAssertEqual(engine.currentItem, a)
    }

    func testNextAtEndStopsWithRepeatOff() {
        let engine = PlaybackEngine()
        let a = makeMusic("a"), b = makeMusic("b"), c = makeMusic("c")
        engine.setQueue([a, b, c], startingAt: 2) // at last
        XCTAssertEqual(engine.currentItem, c)
        engine.repeatMode = .off
        engine.next()
        XCTAssertEqual(engine.state, .stopped)
        XCTAssertNil(engine.currentItem)
    }

    func testNextAtEndWrapsWithRepeatAll() {
        let engine = PlaybackEngine()
        let a = makeMusic("a"), b = makeMusic("b"), c = makeMusic("c")
        engine.setQueue([a, b, c], startingAt: 2) // at last
        engine.repeatMode = .all
        engine.next()
        XCTAssertEqual(engine.currentItem, a)
    }

    func testRepeatOneStaysOnTrack() {
        let engine = PlaybackEngine()
        let a = makeMusic("a"), b = makeMusic("b"), c = makeMusic("c")
        engine.setQueue([a, b, c], startingAt: 1) // at b
        engine.repeatMode = .one
        engine.next()
        XCTAssertEqual(engine.currentItem, b)
    }

    func testSkipToInQueue() {
        let engine = PlaybackEngine()
        let a = makeMusic("a"), b = makeMusic("b"), c = makeMusic("c")
        engine.setQueue([a, b, c])
        engine.skip(to: c)
        XCTAssertEqual(engine.currentItem, c)
    }

    func testSkipToOutOfQueueIsNoOp() {
        let engine = PlaybackEngine()
        let a = makeMusic("a"), b = makeMusic("b"), c = makeMusic("c")
        let unknown = makeMusic("not-in-queue")
        engine.setQueue([a, b, c])
        engine.skip(to: unknown)
        XCTAssertEqual(engine.currentItem, a) // unchanged
    }

    func testShuffleProducesQueuePermutation() {
        let engine = PlaybackEngine()
        let items = (0..<8).map { makeMusic("track\($0)") }
        engine.setQueue(items)
        engine.isShuffling = true
        // The shuffled queue must be a permutation of the input.
        XCTAssertEqual(Set(engine.queue), Set(items))
        XCTAssertEqual(engine.queue.count, items.count)
    }

    func testShuffleArtistPlaysWholeArtistQueueInShuffledOrder() {
        let engine = PlaybackEngine()
        let tracks = (0..<8).map { makeMusic("artist-track-\($0)") }

        engine.shuffleArtist(tracks)

        XCTAssertTrue(engine.isShuffling)
        XCTAssertEqual(Set(engine.queue), Set(tracks))
        XCTAssertEqual(engine.queue.count, tracks.count)
        XCTAssertEqual(engine.currentItem, engine.queue.first)
        XCTAssertEqual(engine.state, .playing)
    }

    func testEmptySetQueueResetsState() {
        let engine = PlaybackEngine()
        let a = makeMusic("a")
        engine.setQueue([a])
        XCTAssertEqual(engine.currentItem, a)
        engine.setQueue([])
        XCTAssertEqual(engine.state, .stopped)
        XCTAssertNil(engine.currentItem)
        XCTAssertEqual(engine.queue, [])
    }

    func testRemovingCurrentTrackStopsAndPreservesUnrelatedQueueEntries() {
        let engine = PlaybackEngine()
        let a = makeMusic("a"), b = makeMusic("b"), c = makeMusic("c")
        engine.setQueue([a, b, c], startingAt: 1)
        engine.play()

        engine.removeTracks(withIDs: [b.id])

        XCTAssertEqual(engine.state, .stopped)
        XCTAssertNil(engine.currentItem)
        XCTAssertEqual(engine.queue, [a, c])
        XCTAssertTrue(MPNowPlayingInfoCenter.default().nowPlayingInfo?.isEmpty != false)
    }

    func testRemovingOtherTrackKeepsCurrentPlaybackAndQueueOrder() {
        let engine = PlaybackEngine()
        let a = makeMusic("a"), b = makeMusic("b"), c = makeMusic("c")
        engine.setQueue([a, b, c], startingAt: 1)
        engine.play()
        engine.seek(to: 0.5)

        engine.removeTracks(withIDs: [a.id])

        XCTAssertEqual(engine.state, .playing)
        XCTAssertEqual(engine.currentItem, b)
        XCTAssertEqual(engine.currentTime, 0.5)
        XCTAssertEqual(engine.queue, [b, c])
    }

    func testTogglePlayPauseFromPaused() {
        let engine = PlaybackEngine()
        let a = makeMusic("a")
        engine.setQueue([a]) // sets state to .paused
        XCTAssertEqual(engine.state, .paused)
        engine.togglePlayPause()
        XCTAssertEqual(engine.state, .playing)
        engine.togglePlayPause()
        XCTAssertEqual(engine.state, .paused)
    }

    func testSeekClampsToZero() {
        let engine = PlaybackEngine()
        let a = makeMusic("a")
        engine.setQueue([a])
        engine.seek(to: -100)
        XCTAssertEqual(engine.currentTime, 0)
    }
}
