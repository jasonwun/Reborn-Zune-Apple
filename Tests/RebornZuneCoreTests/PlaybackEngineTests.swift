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
