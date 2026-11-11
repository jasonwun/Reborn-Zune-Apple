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

    @MainActor
    private final class FakeQueuePlayer: QueuePlayer {
        var itemURLs: [URL] = []
        var seekPositions: [TimeInterval] = []
        var isPlaying = false
        var onTimeUpdate: ((TimeInterval, TimeInterval?) -> Void)?
        var onItemEnd: (() -> Void)?

        func replaceItems(with urls: [URL]) { itemURLs = urls }
        func play() { isPlaying = true }
        func pause() { isPlaying = false }
        func seek(to seconds: TimeInterval) { seekPositions.append(seconds) }
        func invalidate() { itemURLs = []; isPlaying = false }
        func finishCurrentItem() { onItemEnd?() }
    }

    private func makeEngine(player: FakeQueuePlayer) -> PlaybackEngine {
        PlaybackEngine(playerFactory: { player })
    }

    private func makeUUIDMusic(_ name: String) -> Music {
        Music(
            id: UUID().uuidString,
            url: URL(fileURLWithPath: "/tmp/reborn-zune-tests/\(name).m4a"),
            title: name,
            artist: "Test Artist",
            albumArtist: nil,
            albumTitle: "Test Album",
            year: nil,
            duration: 10,
            artworkData: nil
        )
    }

    private func makeSilenceTrack(_ name: String) -> Music {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return Music(
            id: UUID().uuidString,
            url: repositoryRoot.appendingPathComponent("Apps/tvOS/Resources/silence.m4a"),
            title: name,
            artist: nil,
            albumArtist: nil,
            albumTitle: nil,
            year: nil,
            duration: 5,
            artworkData: nil
        )
    }

    // MARK: - Tests

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

    func testPlayNextAndPlayLaterEditUpcomingOrder() {
        let engine = PlaybackEngine()
        let a = makeMusic("a"), b = makeMusic("b"), c = makeMusic("c")
        let next = makeMusic("next"), later = makeMusic("later")
        engine.setQueue([a, b, c])

        engine.playNext(next)
        engine.playLater(later)

        XCTAssertEqual(engine.queue, [a, next, b, c, later])
        XCTAssertEqual(engine.currentItem, a)
        XCTAssertEqual(engine.upNext, [next, b, c, later])
    }

    func testUpNextReorderDeleteAndClearRetainCurrentTrack() {
        let engine = PlaybackEngine()
        let a = makeMusic("a"), b = makeMusic("b"), c = makeMusic("c"), d = makeMusic("d")
        engine.setQueue([a, b, c, d])

        engine.moveUpNext(fromOffsets: [0], toOffset: 2)
        XCTAssertEqual(engine.queue, [a, c, b, d])

        engine.removeUpNext(at: 1)
        XCTAssertEqual(engine.queue, [a, c, d])
        XCTAssertEqual(engine.currentItem, a)

        engine.clearUpNext()
        XCTAssertEqual(engine.queue, [a])
        XCTAssertEqual(engine.currentItem, a)
        XCTAssertEqual(engine.state, .paused)
    }

    func testPlayerWindowContainsCurrentPlusTwoAndRefillsInActiveOrder() {
        let player = FakeQueuePlayer()
        let engine = makeEngine(player: player)
        let items = (0..<6).map { makeMusic("window\($0)") }

        engine.setQueue(items)
        XCTAssertEqual(player.itemURLs, items.prefix(3).map(\.url))

        engine.next()
        XCTAssertEqual(engine.currentItem, items[1])
        XCTAssertEqual(player.itemURLs, Array(items[1...3]).map(\.url))
    }

    func testShuffleEditsReconcilePlayerAndToggleOffRestoresOriginalOrder() {
        let player = FakeQueuePlayer()
        let engine = makeEngine(player: player)
        let a = makeMusic("a"), b = makeMusic("b"), c = makeMusic("c"), d = makeMusic("d")
        let inserted = makeMusic("inserted"), later = makeMusic("later")
        engine.setQueue([a, b, c, d], startingAt: 1)
        engine.seek(to: 0.4)

        engine.isShuffling = true
        XCTAssertEqual(engine.currentItem, b)
        XCTAssertEqual(player.itemURLs, Array(engine.queue.prefix(3)).map(\.url))

        engine.playNext(inserted)
        engine.playLater(later)
        XCTAssertEqual(engine.queue[1], inserted)
        XCTAssertEqual(engine.queue.last, later)
        XCTAssertEqual(player.itemURLs, Array(engine.queue.prefix(3)).map(\.url))

        engine.moveUpNext(fromOffsets: [1], toOffset: 2)
        engine.isShuffling = false

        XCTAssertEqual(engine.queue, [a, b, inserted, c, d, later])
        XCTAssertEqual(engine.currentItem, b)
        XCTAssertEqual(player.itemURLs, [b, inserted, c].map(\.url))
        XCTAssertEqual(engine.currentTime, 0.4)
    }

    func testPreviousRepeatAndNaturalEndUseDisplayedOrderAndCurrentPlusTwo() {
        let player = FakeQueuePlayer()
        let engine = makeEngine(player: player)
        let items = (0..<5).map { makeMusic("transport\($0)") }
        engine.setQueue(items, startingAt: 1)
        engine.play()

        engine.previous()
        XCTAssertEqual(engine.currentItem, items[0])
        XCTAssertEqual(player.itemURLs, items.prefix(3).map(\.url))

        engine.skip(to: items[4])
        engine.repeatMode = .all
        player.finishCurrentItem()
        XCTAssertEqual(engine.currentItem, items[0])
        XCTAssertEqual(player.itemURLs, items.prefix(3).map(\.url))

        engine.repeatMode = .one
        player.finishCurrentItem()
        XCTAssertEqual(engine.currentItem, items[0])
        XCTAssertEqual(player.seekPositions.last, 0)
        XCTAssertTrue(player.isPlaying)
    }

    func testRestoreDropsUnresolvedReferencesAndRestoresPausedWindowAndPosition() {
        let player = FakeQueuePlayer()
        let engine = makeEngine(player: player)
        let a = makeUUIDMusic("a"), b = makeUUIDMusic("b")
        let c = makeUUIDMusic("c"), d = makeUUIDMusic("d")
        let missing = UUID()
        let activeIDs = [UUID(uuidString: a.id)!, missing, UUID(uuidString: b.id)!, UUID(uuidString: c.id)!, UUID(uuidString: d.id)!]
        let snapshot = PlaybackQueueSnapshot(
            originalTrackIDs: activeIDs,
            activeTrackIDs: activeIDs,
            currentIndex: 2,
            position: 4.25,
            isShuffling: false
        )
        let tracks = [a, b, c, d]

        engine.restoreQueue(snapshot) { id in tracks.first { $0.id == id.uuidString } }

        XCTAssertEqual(engine.queue, tracks)
        XCTAssertEqual(engine.currentItem, b)
        XCTAssertEqual(engine.currentIndex, 1)
        XCTAssertEqual(engine.currentTime, 4.25)
        XCTAssertEqual(engine.state, .paused)
        XCTAssertEqual(player.itemURLs, [b, c, d].map(\.url))
        XCTAssertEqual(engine.persistenceSnapshot.position, 4.25)
    }

    func testRestoreKeepsPersistedIndexWhenCurrentTrackIsDuplicated() {
        let engine = PlaybackEngine()
        let a = makeUUIDMusic("duplicate"), b = makeUUIDMusic("other")
        let aID = UUID(uuidString: a.id)!, bID = UUID(uuidString: b.id)!
        let snapshot = PlaybackQueueSnapshot(
            originalTrackIDs: [aID, aID, bID],
            activeTrackIDs: [aID, aID, bID],
            currentIndex: 1,
            position: 3,
            isShuffling: false
        )
        let tracks = [a, b]

        engine.restoreQueue(snapshot) { id in tracks.first { $0.id == id.uuidString } }

        XCTAssertEqual(engine.currentIndex, 1)
        XCTAssertEqual(engine.upNext, [b])
    }

    func testShuffleRemovalTargetsDuplicateEntryAndKeepsCurrentAnchor() {
        let engine = PlaybackEngine()
        let a = makeMusic("a"), b = makeMusic("b"), c = makeMusic("c")
        engine.setQueue([a, b, a, c])
        engine.isShuffling = true
        let duplicateOffset = try! XCTUnwrap(engine.upNext.firstIndex(of: a))

        engine.removeUpNext(at: duplicateOffset)
        engine.isShuffling = false

        XCTAssertEqual(engine.queue, [a, b, c])
        XCTAssertEqual(engine.currentIndex, 0)
        XCTAssertEqual(engine.upNext, [b, c])
    }

    func testRealAudioPlaybackAdvancesTime() async throws {
        let track = makeSilenceTrack("Silence")
        let engine = PlaybackEngine()
        engine.setQueue([track])

        engine.play()
        try await Task.sleep(nanoseconds: 700_000_000)

        XCTAssertEqual(engine.state, .playing)
        XCTAssertGreaterThan(engine.currentTime, 0)
        engine.pause()
    }

    func testLegacySnapshotRebuildsSharedDuplicateEntryIdentities() {
        let engine = PlaybackEngine()
        let a = makeUUIDMusic("a"), b = makeUUIDMusic("b"), c = makeUUIDMusic("c")
        let tracks = [a, b, c]
        let ids = tracks.map { UUID(uuidString: $0.id)! }
        let snapshot = PlaybackQueueSnapshot(
            originalTrackIDs: [ids[0], ids[1], ids[0], ids[2]],
            activeTrackIDs: [ids[0], ids[0], ids[1], ids[2]],
            currentIndex: 0,
            position: 0,
            isShuffling: true
        )
        engine.restoreQueue(snapshot) { id in tracks.first { $0.id == id.uuidString } }
        let duplicateOffset = try! XCTUnwrap(engine.upNext.firstIndex(of: a))

        engine.removeUpNext(at: duplicateOffset)
        engine.isShuffling = false

        XCTAssertEqual(engine.queue, [a, b, c])
        XCTAssertEqual(engine.currentIndex, 0)
        XCTAssertEqual(engine.upNext, [b, c])
    }

    func testRealAudioNaturallyAdvancesToDisplayedNextTrack() async throws {
        let tracks = [makeSilenceTrack("One"), makeSilenceTrack("Two"), makeSilenceTrack("Three")]
        let engine = PlaybackEngine()
        engine.setQueue(tracks)
        engine.play()

        for _ in 0..<70 where engine.currentItem?.id != tracks[1].id {
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        XCTAssertEqual(engine.currentItem, tracks[1])
        XCTAssertEqual(engine.upNext, [tracks[2]])
        XCTAssertEqual(engine.state, .playing)
        engine.pause()
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
