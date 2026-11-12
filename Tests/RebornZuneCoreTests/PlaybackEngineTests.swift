import XCTest
import MediaPlayer
@testable import RebornZuneCore

@MainActor
final class PlaybackEngineTests: XCTestCase {

    // MARK: - Fixtures

    private func makeMusic(_ name: String, duration: TimeInterval = 1.0) -> Music {
        let url = URL(fileURLWithPath: "/tmp/reborn-zune-tests/\(name).m4a")
        return Music(
            id: Music.makeID(for: url),
            url: url,
            title: name,
            artist: "Test Artist",
            albumArtist: nil,
            albumTitle: "Test Album",
            year: nil,
            duration: duration,
            artworkData: nil
        )
    }

    @MainActor
    private final class FakeQueuePlayer: QueuePlayer {
        var itemURLs: [URL] = []
        var seekPositions: [TimeInterval] = []
        var volume: Double = 1
        var isPlaying = false
        var currentTime: TimeInterval = 0
        var onTimeUpdate: ((TimeInterval, TimeInterval?) -> Void)?
        var onPlaybackStatusChange: ((QueuePlaybackStatus) -> Void)?
        var onItemEnd: (() -> Void)?

        func replaceItems(with urls: [URL]) { itemURLs = urls }
        func play() { isPlaying = true }
        func pause() { isPlaying = false }
        func seek(to seconds: TimeInterval) { seekPositions.append(seconds) }
        func invalidate() { itemURLs = []; isPlaying = false }
        func finishCurrentItem() { onItemEnd?() }
    }

    @MainActor
    private final class FakeNowPlayingCenter: NowPlayingCentering {
        var handlers: RemoteCommandHandlers?

        func registerCommands(_ handlers: RemoteCommandHandlers) {
            self.handlers = handlers
        }

        func update(item: Music?, currentTime: TimeInterval, duration: TimeInterval, rate: Double) {}

        func seek(to position: TimeInterval) { handlers?.seek(position) }
        func shuffle(_ isShuffling: Bool) { handlers?.shuffle(isShuffling) }
        func repeatMode(_ mode: RepeatMode) { handlers?.repeat(mode) }
    }

    private func makeEngine(
        player: FakeQueuePlayer,
        now: @escaping () -> TimeInterval = { 0 },
        nowPlaying: FakeNowPlayingCenter? = nil
    ) -> PlaybackEngine {
        let center: any NowPlayingCentering = nowPlaying ?? NowPlayingCenter()
        return PlaybackEngine(
            playerFactory: { player },
            timeSource: now,
            nowPlaying: center
        )
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
            duration: 30,
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
        XCTAssertEqual(bookmarks.starts, 3, "each item in the current-plus-two window owns access")
        XCTAssertEqual(bookmarks.stops, 0, "AVPlayer may read lazily after the scan scope stops")

        engine.next()
        XCTAssertEqual(bookmarks.starts, 6, "advancing refills the three-item window")
        XCTAssertEqual(bookmarks.stops, 3, "advancing releases the previous AVQueuePlayer items")

        engine.removeTracks(withIDs: Set(tracks.map(\.id)))
        XCTAssertEqual(bookmarks.starts, bookmarks.stops)
        XCTAssertEqual(bookmarks.stops, 6)
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
        XCTAssertEqual(engine.queue, items)
        XCTAssertEqual(player.itemURLs, items.prefix(3).map(\.url))

        engine.next()
        XCTAssertEqual(engine.currentItem, items[1])
        XCTAssertEqual(player.itemURLs, Array(items[1...3]).map(\.url))
    }

    func testLargeQueueMaterializesOnlyCurrentPlusTwoPlayerItems() {
        let player = FakeQueuePlayer()
        let engine = makeEngine(player: player)
        let tracks = (0..<50_000).map { makeMusic("release-track-\($0)") }

        engine.setQueue(tracks)

        XCTAssertEqual(engine.queue.count, 50_000)
        XCTAssertEqual(player.itemURLs, tracks.prefix(3).map(\.url))
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
        XCTAssertEqual(player.itemURLs, engine.queue.prefix(3).map(\.url))

        engine.playNext(inserted)
        engine.playLater(later)
        XCTAssertEqual(engine.queue[1], inserted)
        XCTAssertEqual(engine.queue.last, later)
        XCTAssertEqual(player.itemURLs, engine.queue.prefix(3).map(\.url))

        engine.moveUpNext(fromOffsets: [1], toOffset: 2)
        engine.isShuffling = false

        XCTAssertEqual(engine.queue, [a, b, inserted, c, d, later])
        XCTAssertEqual(engine.currentItem, b)
        XCTAssertEqual(player.itemURLs, [b, inserted, c].map(\.url))
        XCTAssertEqual(engine.currentTime, 0.4)
    }

    func testShuffleRemovalTargetsDuplicateEntryAndKeepsCurrentAnchor() throws {
        let engine = PlaybackEngine()
        let a = makeMusic("a"), b = makeMusic("b"), c = makeMusic("c")
        engine.setQueue([a, b, a, c])
        engine.isShuffling = true
        let duplicateOffset = try XCTUnwrap(engine.upNext.firstIndex(of: a))

        engine.removeUpNext(at: duplicateOffset)
        engine.isShuffling = false

        XCTAssertEqual(engine.queue, [a, b, c])
        XCTAssertEqual(engine.currentIndex, 0)
        XCTAssertEqual(engine.upNext, [b, c])
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

    func testQueueChangesPublishPersistableSnapshots() {
        let engine = PlaybackEngine()
        let a = makeUUIDMusic("persist-a"), b = makeUUIDMusic("persist-b")
        var snapshots: [PlaybackQueueSnapshot] = []
        engine.queuePersistenceHandler = { snapshots.append($0) }

        engine.setQueue([a, b])
        engine.playNext(b)
        engine.seek(to: 7)

        XCTAssertEqual(snapshots.last?.activeTrackIDs, [UUID(uuidString: a.id)!, UUID(uuidString: b.id)!, UUID(uuidString: b.id)!])
        XCTAssertEqual(snapshots.last?.position, 7)
        XCTAssertEqual(snapshots.last?.activeEntryIDs.count, 3)
    }

    func testLegacySnapshotRebuildsSharedDuplicateEntryIdentities() throws {
        let engine = PlaybackEngine()
        let a = makeUUIDMusic("legacy-a"), b = makeUUIDMusic("legacy-b"), c = makeUUIDMusic("legacy-c")
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
        let duplicateOffset = try XCTUnwrap(engine.upNext.firstIndex(of: a))

        engine.removeUpNext(at: duplicateOffset)
        engine.isShuffling = false

        XCTAssertEqual(engine.queue, [a, b, c])
        XCTAssertEqual(engine.currentIndex, 0)
        XCTAssertEqual(engine.upNext, [b, c])
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

    func testVolumeIsClampedAndAppliedToPlayer() {
        let player = FakeQueuePlayer()
        let engine = makeEngine(player: player)
        engine.setQueue([makeMusic("volume")])

        engine.volume = 0.35
        XCTAssertEqual(engine.volume, 0.35)
        XCTAssertEqual(player.volume, 0.35)

        engine.volume = 2
        XCTAssertEqual(engine.volume, 1)
        XCTAssertEqual(player.volume, 1)

        engine.volume = -1
        XCTAssertEqual(engine.volume, 0)
        XCTAssertEqual(player.volume, 0)
    }

    func testTrackChangesAndRestartsEmitExplicitStartReasons() {
        let player = FakeQueuePlayer()
        let engine = makeEngine(player: player)
        let tracks = [makeMusic("first"), makeMusic("second")]
        var signals: [PlaybackSignal] = []
        engine.playbackSignalHandler = { signals.append($0) }
        engine.setQueue(tracks)
        engine.play()

        engine.next()
        engine.previous()
        engine.previous()
        engine.repeatMode = .one
        player.finishCurrentItem()

        let startReasons: [PlaybackStartReason] = signals.compactMap { signal in
            guard case .start(_, _, let reason) = signal else { return nil }
            return reason
        }
        XCTAssertEqual(startReasons, [.actual, .actual, .actual, .manualRestart, .repeatOneRestart])
    }

    func testActivePlaybackSignalExcludesSeekJumpsAndHandlesUnknownDuration() {
        let player = FakeQueuePlayer()
        var now: TimeInterval = 0
        let engine = makeEngine(player: player, now: { now })
        var signals: [PlaybackSignal] = []
        engine.playbackSignalHandler = { signals.append($0) }
        engine.setQueue([makeMusic("unknown", duration: 0)])
        engine.play()

        now = 10
        player.onTimeUpdate?(0.25, nil)
        now = 20
        engine.seek(to: 0.5)
        now = 50
        player.onTimeUpdate?(80, nil)

        let observations = signals.compactMap { signal -> (id: UUID, elapsed: TimeInterval, duration: TimeInterval?)? in
            guard case .activePlayback(let id, _, let elapsed, let duration) = signal else { return nil }
            return (id, elapsed, duration)
        }
        XCTAssertEqual(observations.last?.elapsed, 50)
        XCTAssertNil(observations.last?.duration)
        XCTAssertEqual(observations.last?.id, observations.first?.id)
    }

    func testRepeatedPlayDoesNotDiscardUnobservedActivePlayback() {
        let player = FakeQueuePlayer()
        var now: TimeInterval = 0
        let engine = makeEngine(player: player, now: { now })
        engine.setQueue([makeMusic("repeat-play")])
        engine.play()

        now = 10
        engine.play()
        now = 20
        engine.pause()

        XCTAssertEqual(engine.activePlaybackTime, 20, accuracy: 0.0001)
    }

    func testActivePlaybackAccumulatesOnlyWhilePlaying() {
        let player = FakeQueuePlayer()
        var now: TimeInterval = 0
        let engine = makeEngine(player: player, now: { now })
        engine.setQueue([makeMusic("active")])
        engine.play()

        now = 10
        player.onTimeUpdate?(10, 100)
        now = 20
        engine.pause()
        now = 40
        player.onTimeUpdate?(10, 100)
        engine.play()
        now = 45
        player.onTimeUpdate?(15, 100)

        XCTAssertEqual(engine.activePlaybackTime, 25, accuracy: 0.0001)
    }

    func testLoadStartResumeAndSeekHaveDistinctSignals() {
        let player = FakeQueuePlayer()
        let engine = makeEngine(player: player)
        let track = makeMusic("signals")
        var signals: [PlaybackSignal] = []
        engine.playbackSignalHandler = { signals.append($0) }

        engine.setQueue([track])
        engine.play()
        engine.pause()
        engine.play()
        engine.seek(to: 0.5)

        XCTAssertEqual(signals.filter { if case .load = $0 { true } else { false } }.count, 1)
        let startReasons: [PlaybackStartReason] = signals.compactMap { signal in
            guard case .start(_, _, let reason) = signal else { return nil }
            return reason
        }
        XCTAssertEqual(startReasons, [.actual])
        XCTAssertEqual(signals.filter { if case .resume = $0 { true } else { false } }.count, 1)
        XCTAssertEqual(signals.filter { if case .seek = $0 { true } else { false } }.count, 1)
    }

    func testPlayHistoryRecordsOnlyActualStartsAcrossTransportActions() throws {
        let player = FakeQueuePlayer()
        let engine = makeEngine(player: player)
        let id = UUID()
        let track = Music(id: id.uuidString, url: URL(fileURLWithPath: "/tmp/history.m4a"),
                          title: "History", artist: nil, albumArtist: nil, albumTitle: nil,
                          year: nil, duration: 100, artworkData: nil)
        var wallTime = Date(timeIntervalSince1970: 60_000)
        let history = PlayHistory(
            container: try RebornZunePersistence.makeInMemoryContainer(), now: { wallTime })
        engine.playbackSignalHandler = { try! history.record($0) }

        engine.setQueue([track])
        XCTAssertEqual(try history.historyEntries().count, 0, "loading is not listening")
        engine.play()
        engine.pause()
        wallTime = wallTime.addingTimeInterval(1)
        engine.play()
        engine.seek(to: 50)
        XCTAssertEqual(try history.historyEntries().count, 1, "resume and seek reuse the start")

        wallTime = wallTime.addingTimeInterval(1)
        engine.previous()
        wallTime = wallTime.addingTimeInterval(1)
        engine.repeatMode = .one
        player.finishCurrentItem()

        let entries = try history.historyEntries()
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(Set(entries.map(\.id)).count, 3)
        XCTAssertTrue(entries.allSatisfy { $0.trackID == id })
        XCTAssertEqual(try history.playbackStats().first?.lastPlayedAt, wallTime)
    }

    func testPlayHistoryQualificationIgnoresPausedTimeAndSeekJumps() throws {
        let player = FakeQueuePlayer()
        var activeNow: TimeInterval = 0
        let engine = makeEngine(player: player, now: { activeNow })
        let id = UUID()
        let track = Music(id: id.uuidString, url: URL(fileURLWithPath: "/tmp/active-history.m4a"),
                          title: "Active History", artist: nil, albumArtist: nil, albumTitle: nil,
                          year: nil, duration: 100, artworkData: nil)
        let history = PlayHistory(container: try RebornZunePersistence.makeInMemoryContainer())
        engine.playbackSignalHandler = { try! history.record($0) }
        engine.setQueue([track])
        engine.play()

        activeNow = 10
        player.onTimeUpdate?(10, 100)
        engine.pause()
        activeNow = 40
        engine.play()
        engine.seek(to: 80)
        activeNow = 59
        player.onTimeUpdate?(80, 100)

        XCTAssertEqual(try history.playbackStats().first?.playCount, 0)
        activeNow = 60
        engine.pause()
        XCTAssertEqual(try history.playbackStats().first?.playCount, 1)
        XCTAssertEqual(try history.historyEntries().count, 1)
    }

    func testVolumeCommandsChangeFivePercentAndClampAtEndpoints() {
        let engine = makeEngine(player: FakeQueuePlayer())
        engine.volume = 0.5

        engine.increaseVolume()
        XCTAssertEqual(engine.volume, 0.55, accuracy: 0.0001)
        engine.decreaseVolume()
        engine.decreaseVolume()
        XCTAssertEqual(engine.volume, 0.45, accuracy: 0.0001)
        engine.volume = 0.99
        engine.increaseVolume()
        XCTAssertEqual(engine.volume, 1, accuracy: 0.0001)
        engine.volume = 0.01
        engine.decreaseVolume()
        XCTAssertEqual(engine.volume, 0, accuracy: 0.0001)
    }

    func testRelativeSkipsMoveFifteenSecondsWithinTrackBounds() {
        let player = FakeQueuePlayer()
        let engine = makeEngine(player: player)
        engine.setQueue([makeMusic("relative-skip", duration: 100)])
        engine.seek(to: 10)

        engine.skipForward()
        XCTAssertEqual(engine.currentTime, 25, accuracy: 0.0001)
        engine.skipBackward()
        engine.skipBackward()
        XCTAssertEqual(engine.currentTime, 0, accuracy: 0.0001)
        engine.seek(to: 95)
        engine.skipForward()
        XCTAssertEqual(engine.currentTime, 100, accuracy: 0.0001)
    }

    func testRemoteSeekShuffleAndRepeatDrivePublicPlaybackState() {
        let center = FakeNowPlayingCenter()
        let engine = makeEngine(player: FakeQueuePlayer(), nowPlaying: center)
        engine.setQueue([makeMusic("remote-modes", duration: 100)])

        center.seek(to: 42)
        center.shuffle(true)
        center.repeatMode(.one)

        XCTAssertEqual(engine.currentTime, 42, accuracy: 0.0001)
        XCTAssertTrue(engine.isShuffling)
        XCTAssertEqual(engine.repeatMode, .one)
    }

    func testPlayerRateAndBufferingChangesPublishImmediately() {
        let player = FakeQueuePlayer()
        let engine = makeEngine(player: player)
        engine.setQueue([makeMusic("player-events", duration: 100)])
        engine.play()

        player.onPlaybackStatusChange?(QueuePlaybackStatus(position: 18.25, rate: 0.5, isBuffering: false))

        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo
        XCTAssertEqual(info?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? TimeInterval, 18.25)
        XCTAssertEqual(info?[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 0.5)

        player.onPlaybackStatusChange?(QueuePlaybackStatus(position: 18.25, rate: 0, isBuffering: true))
        info = MPNowPlayingInfoCenter.default().nowPlayingInfo
        XCTAssertEqual(engine.state, .buffering)
        XCTAssertEqual(info?[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 0)
    }

    func testPeriodicTimeUpdatesDoNotRepublishNowPlayingProgress() {
        let player = FakeQueuePlayer()
        let engine = makeEngine(player: player)
        engine.setQueue([makeMusic("event-driven", duration: 100)])
        engine.play()
        let publishedPosition = MPNowPlayingInfoCenter.default().nowPlayingInfo?[
            MPNowPlayingInfoPropertyElapsedPlaybackTime
        ] as? TimeInterval

        player.onTimeUpdate?(25, 100)

        XCTAssertEqual(engine.currentTime, 25, accuracy: 0.0001)
        XCTAssertEqual(MPNowPlayingInfoCenter.default().nowPlayingInfo?[
            MPNowPlayingInfoPropertyElapsedPlaybackTime
        ] as? TimeInterval, publishedPosition)

        engine.seek(to: 40)
        XCTAssertEqual(MPNowPlayingInfoCenter.default().nowPlayingInfo?[
            MPNowPlayingInfoPropertyElapsedPlaybackTime
        ] as? TimeInterval, 40)
    }

    func testPausePublishesExactPlayerPositionAtZeroRate() {
        let player = FakeQueuePlayer()
        let engine = makeEngine(player: player)
        engine.setQueue([makeMusic("exact-pause", duration: 100)])
        engine.play()
        player.currentTime = 12.345678

        engine.pause()

        let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
        XCTAssertEqual(info?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? TimeInterval, 12.345678)
        XCTAssertEqual(info?[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 0)
    }

    func testPausedRealItemDoesNotEnterBuffering() async throws {
        let engine = PlaybackEngine()
        engine.setQueue([makeSilenceTrack("paused-buffer")])

        try await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertEqual(engine.state, .paused)
        XCTAssertEqual(MPNowPlayingInfoCenter.default().nowPlayingInfo?[
            MPNowPlayingInfoPropertyPlaybackRate
        ] as? Double, 0)
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

    func testRealAudioNaturallyAdvancesToDisplayedNextTrack() async throws {
        let tracks = [makeSilenceTrack("One"), makeSilenceTrack("Two"), makeSilenceTrack("Three")]
        let engine = PlaybackEngine()
        engine.setQueue(tracks)
        engine.play()

        for _ in 0..<70 where engine.currentItem?.id != tracks[1].id || engine.state != .playing {
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        XCTAssertEqual(engine.currentItem, tracks[1])
        XCTAssertEqual(engine.state, .playing)
        engine.pause()
    }
}
