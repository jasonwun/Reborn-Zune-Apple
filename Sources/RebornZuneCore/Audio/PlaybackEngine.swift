import Foundation
import AVFoundation
import Observation
import os

/// Observable, SwiftUI-friendly wrapper around `AVQueuePlayer` that drives
/// app-level playback. Wires Now Playing + remote commands and configures
/// the iOS/iPadOS/tvOS audio session for backgrounded playback.
///
/// Single source of truth for the queue: the engine retains the unshuffled
/// `originalQueue` plus the active (possibly shuffled) `queue`. The
/// `AVQueuePlayer` is rebuilt whenever the active queue changes; this trades
/// some setup cost on `next()`/`previous()` for predictable state.
@MainActor
@Observable
public final class PlaybackEngine {
    // MARK: - Published state

    public private(set) var state: PlaybackState = .stopped
    public private(set) var currentItem: Music?
    public private(set) var queue: [Music] = []
    public private(set) var currentTime: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0
    /// Active seconds observed for the current start event; never persisted continuously.
    public private(set) var activePlaybackTime: TimeInterval = 0
    /// Output volume in AVPlayer's normalized 0...1 range.
    public var volume: Double = 1 {
        didSet {
            let clamped = min(max(volume, 0), 1)
            if volume != clamped {
                volume = clamped
            } else {
                player?.volume = volume
            }
        }
    }

    public var isShuffling: Bool = false {
        didSet {
            guard oldValue != isShuffling else { return }
            rebuildQueueForShuffleChange()
        }
    }

    public var repeatMode: RepeatMode = .off

    // MARK: - Internals

    /// Backing for `isShuffling`'s didSet so we can avoid spurious rebuilds.
    @ObservationIgnored
    private var originalQueue: [Music] = []

    /// Index in `queue` of the track currently playing (or about to play).
    /// `nil` means stopped / queue empty.
    @ObservationIgnored
    private var currentIndex: Int?

    @ObservationIgnored
    private var player: QueuePlayer?

    @ObservationIgnored
    private let playerFactory: () -> QueuePlayer

    @ObservationIgnored
    private let timeSource: () -> TimeInterval

    @ObservationIgnored
    private var lastActiveObservation: TimeInterval?

    @ObservationIgnored
    private let nowPlaying: any NowPlayingCentering

    @ObservationIgnored
    private var sessionConfigured = false

    @ObservationIgnored
    private let logger = Logger(subsystem: "dev.yjd.rebornzune", category: "PlaybackEngine")

    /// Receives explicit transitions instead of inferring them from item or position changes.
    @ObservationIgnored
    public var playbackSignalHandler: ((PlaybackSignal) -> Void)?

    @ObservationIgnored
    private var activeStartID: UUID?

    // MARK: - Init

    public convenience init(fileAccess: (@MainActor (URL) throws -> any LibraryBookmarkSession)? = nil) {
        self.init(playerFactory: { AVQueuePlayerAdapter(fileAccess: fileAccess) })
    }

    init(
        playerFactory: @escaping () -> QueuePlayer,
        timeSource: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        nowPlaying: any NowPlayingCentering = NowPlayingCenter()
    ) {
        self.playerFactory = playerFactory
        self.timeSource = timeSource
        self.nowPlaying = nowPlaying
        nowPlaying.registerCommands(RemoteCommandHandlers(
            play: { [weak self] in self?.play() },
            pause: { [weak self] in self?.pause() },
            toggle: { [weak self] in self?.togglePlayPause() },
            next: { [weak self] in self?.next() },
            previous: { [weak self] in self?.previous() },
            seek: { [weak self] position in self?.seek(to: position) },
            shuffle: { [weak self] isShuffling in self?.isShuffling = isShuffling },
            repeat: { [weak self] mode in self?.repeatMode = mode }
        ))
    }

    // No deinit observer cleanup: under Swift 6 strict concurrency a
    // non-isolated deinit can't touch `@MainActor` non-Sendable storage
    // (the observer token + AVQueuePlayer). The notification observers use
    // `[weak self]` so they cannot use-after-free; callers that want to
    // proactively release resources should call `setQueue([])`.

    // MARK: - Queue management

    /// Replace the queue. `startingAt` is the index in the unshuffled queue
    /// to begin playback from; if `isShuffling` is true the position is
    /// preserved relative to the shuffled order (the item at the requested
    /// unshuffled index becomes the first item in the shuffled queue).
    public func setQueue(_ items: [Music], startingAt index: Int = 0) {
        originalQueue = items
        if items.isEmpty {
            queue = []
            currentIndex = nil
            updateCurrentItem(to: nil)
            transition(to: .stopped)
            tearDownPlayer()
            publishNowPlaying()
            return
        }

        let clampedStart = max(0, min(index, items.count - 1))
        if isShuffling {
            queue = makeShuffledQueue(originalQueue, pinningFirst: clampedStart)
            currentIndex = 0
        } else {
            queue = items
            currentIndex = clampedStart
        }

        rebuildPlayer(startingAt: currentIndex ?? 0)
        if let i = currentIndex {
            updateCurrentItem(to: queue[i])
        }
        // Engine starts paused after setQueue; caller decides when to play.
        transition(to: .paused)
        publishNowPlaying()
    }

    /// Play an Artist's complete Track collection in shuffled order.
    public func shuffleArtist(_ tracks: [Music]) {
        guard !tracks.isEmpty else { return }
        isShuffling = true
        setQueue(tracks)
        play()
    }

    /// Removes deleted Library Tracks while preserving every unrelated Queue entry.
    /// Removing the current Track stops playback without selecting a replacement.
    public func removeTracks(withIDs ids: Set<String>) {
        guard !ids.isEmpty else { return }
        let removesCurrent = currentItem.map { ids.contains($0.id) } ?? false
        originalQueue.removeAll { ids.contains($0.id) }
        queue.removeAll { ids.contains($0.id) }

        if removesCurrent {
            currentIndex = nil
            updateCurrentItem(to: nil)
            transition(to: .stopped)
            tearDownPlayer()
            publishNowPlaying()
        } else if let currentItem, let index = queue.firstIndex(of: currentItem) {
            currentIndex = index
            if player != nil {
                let position = currentTime
                let resumesPlayback = state == .playing
                rebuildPlayer(startingAt: index)
                seek(to: position)
                if resumesPlayback { player?.play() }
                publishNowPlaying()
            }
        }
    }

    // MARK: - Transport

    public func play() {
        if player == nil {
            // No player but we have a queue and an index — rebuild and play.
            guard !queue.isEmpty, let i = currentIndex else { return }
            rebuildPlayer(startingAt: i)
        }
        configureSessionIfNeeded()
        if activeStartID == nil {
            emitStart(reason: .actual)
        } else if state != .playing {
            emit(.resume(trackID: currentItem?.id ?? ""))
        }
        if state != .playing { lastActiveObservation = timeSource() }
        player?.play()
        transition(to: .playing)
        publishNowPlaying()
    }

    public func pause() {
        accumulateActivePlayback()
        lastActiveObservation = nil
        player?.pause()
        if let player {
            let exactPosition = max(player.currentTime, 0)
            currentTime = duration > 0 ? min(exactPosition, duration) : exactPosition
        }
        if state == .playing {
            transition(to: .paused)
        }
        publishNowPlaying()
    }

    public func togglePlayPause() {
        switch state {
        case .playing:
            pause()
        case .paused, .stopped, .buffering:
            play()
        }
    }

    public func next() {
        guard !queue.isEmpty else { return }

        if repeatMode == .one, currentIndex != nil {
            // A transport restart is distinct from a natural repeat-one restart.
            restartCurrentTrack(reason: .manualRestart)
            return
        }

        guard let i = currentIndex else { return }
        let nextIndex = i + 1
        if nextIndex >= queue.count {
            switch repeatMode {
            case .all:
                currentIndex = 0
                rebuildPlayer(startingAt: 0)
                updateCurrentItem(to: queue[0])
                startLoadedItemIfPlaying()
                publishNowPlaying()
            case .off, .one:
                // End of queue with no repeat → stop.
                currentIndex = nil
                tearDownPlayer()
                updateCurrentItem(to: nil)
                transition(to: .stopped)
                publishNowPlaying()
            }
            return
        }
        currentIndex = nextIndex
        rebuildPlayer(startingAt: nextIndex)
        updateCurrentItem(to: queue[nextIndex])
        startLoadedItemIfPlaying()
        publishNowPlaying()
    }

    public func previous() {
        guard !queue.isEmpty, let i = currentIndex else { return }

        if repeatMode == .one {
            restartCurrentTrack(reason: .manualRestart)
            return
        }

        let prevIndex = i - 1
        if prevIndex < 0 {
            switch repeatMode {
            case .all:
                let last = queue.count - 1
                currentIndex = last
                rebuildPlayer(startingAt: last)
                updateCurrentItem(to: queue[last])
                startLoadedItemIfPlaying()
            case .off, .one:
                // Conventional: previous at index 0 restarts current track.
                restartCurrentTrack(reason: .manualRestart)
            }
            publishNowPlaying()
            return
        }
        currentIndex = prevIndex
        rebuildPlayer(startingAt: prevIndex)
        updateCurrentItem(to: queue[prevIndex])
        startLoadedItemIfPlaying()
        publishNowPlaying()
    }

    /// Jump to a specific track in the queue if present. No-op if not in queue.
    public func skip(to item: Music) {
        guard let idx = queue.firstIndex(of: item) else { return }
        currentIndex = idx
        rebuildPlayer(startingAt: idx)
        updateCurrentItem(to: queue[idx])
        startLoadedItemIfPlaying()
        publishNowPlaying()
    }

    /// Seek to a position in the current item (clamped to 0...duration).
    public func seek(to seconds: TimeInterval) {
        accumulateActivePlayback()
        let clamped = max(0, min(seconds, duration))
        currentTime = clamped
        player?.seek(to: clamped)
        if let currentItem { emit(.seek(trackID: currentItem.id)) }
        publishNowPlaying()
    }

    /// Skip forward by the standard fifteen-second keyboard/menu increment.
    public func skipForward() {
        seek(to: currentTime + 15)
    }

    /// Skip backward by the standard fifteen-second keyboard/menu increment.
    public func skipBackward() {
        seek(to: currentTime - 15)
    }

    /// Raise output volume by five percentage points.
    public func increaseVolume() {
        volume += 0.05
    }

    /// Lower output volume by five percentage points.
    public func decreaseVolume() {
        volume -= 0.05
    }

    // MARK: - Internal helpers

    private func transition(to newState: PlaybackState) {
        guard state != newState else { return }
        state = newState
    }

    private func updateCurrentItem(to item: Music?) {
        accumulateActivePlayback()
        activeStartID = nil
        activePlaybackTime = 0
        lastActiveObservation = nil
        currentItem = item
        duration = item?.duration ?? 0
        currentTime = 0
        if let item { emit(.load(trackID: item.id)) }
    }

    private func emitStart(reason: PlaybackStartReason) {
        guard let currentItem else { return }
        let id = UUID()
        activeStartID = id
        activePlaybackTime = 0
        lastActiveObservation = timeSource()
        emit(.start(id: id, trackID: currentItem.id, reason: reason))
    }

    private func accumulateActivePlayback() {
        guard state == .playing, let activeStartID, let currentItem else {
            lastActiveObservation = nil
            return
        }
        let now = timeSource()
        if let lastActiveObservation {
            activePlaybackTime += max(0, now - lastActiveObservation)
        }
        lastActiveObservation = now
        emit(.activePlayback(
            id: activeStartID,
            trackID: currentItem.id,
            elapsed: activePlaybackTime,
            duration: duration > 0 ? duration : nil
        ))
    }

    private func emit(_ signal: PlaybackSignal) {
        playbackSignalHandler?(signal)
    }

    private func publishNowPlaying(rate actualRate: Double? = nil) {
        let rate = actualRate ?? ((state == .playing) ? 1.0 : 0.0)
        nowPlaying.update(item: currentItem, currentTime: currentTime, duration: duration, rate: rate)
    }

    private func configureSessionIfNeeded() {
        guard !sessionConfigured else { return }
        sessionConfigured = true
        do {
            try AudioSessionConfigurator.configureForPlayback()
        } catch {
            // Per spec: silently swallow session-config errors; logging only.
            logger.error("Audio session config failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func rebuildQueueForShuffleChange() {
        guard !originalQueue.isEmpty else { return }
        let pinned = currentItem
        if isShuffling {
            // Shuffle, pinning the current item to position 0 so playback
            // doesn't jump to a different track.
            let pinIndex = pinned.flatMap { originalQueue.firstIndex(of: $0) } ?? 0
            queue = makeShuffledQueue(originalQueue, pinningFirst: pinIndex)
            currentIndex = 0
        } else {
            queue = originalQueue
            // Find the current item's index in the unshuffled list.
            currentIndex = pinned.flatMap { queue.firstIndex(of: $0) } ?? 0
        }
        // Don't rebuild the AVQueuePlayer mid-shuffle-toggle: the current
        // item didn't change, so audio output is preserved. We only need
        // to update internal state. This is a tiny inconsistency vs queueing
        // up future tracks in the new shuffled order, which would require
        // teardown — matches spec hint that shuffle is a UX concern.
    }

    /// Fisher-Yates shuffle pinning a chosen item to index 0.
    private func makeShuffledQueue(_ source: [Music], pinningFirst pinIndex: Int) -> [Music] {
        guard !source.isEmpty else { return [] }
        let pin = max(0, min(pinIndex, source.count - 1))
        var rest = source
        let pinnedItem = rest.remove(at: pin)

        var rng = SystemRandomNumberGenerator()
        // Fisher-Yates on `rest`.
        if rest.count > 1 {
            for i in stride(from: rest.count - 1, through: 1, by: -1) {
                let j = Int(rng.next(upperBound: UInt64(i + 1)))
                if i != j { rest.swapAt(i, j) }
            }
        }
        return [pinnedItem] + rest
    }

    private func rebuildPlayer(startingAt startIndex: Int) {
        tearDownPlayer()
        guard !queue.isEmpty, startIndex >= 0, startIndex < queue.count else { return }

        let player = playerFactory()
        player.onTimeUpdate = { [weak self] seconds, duration in
            self?.accumulateActivePlayback()
            self?.currentTime = seconds
            if let duration, abs(duration - (self?.duration ?? 0)) > 0.01 {
                self?.duration = duration
            }
        }
        player.onPlaybackStatusChange = { [weak self] status in
            guard let self else { return }
            if self.state == .playing && (status.isBuffering || status.rate == 0) {
                self.accumulateActivePlayback()
                self.lastActiveObservation = nil
            } else if self.state != .playing && !status.isBuffering && status.rate > 0 {
                self.lastActiveObservation = self.timeSource()
            }
            self.currentTime = max(0, status.position)
            if status.isBuffering {
                self.transition(to: .buffering)
            } else if status.rate > 0 {
                self.transition(to: .playing)
            } else if self.state != .stopped {
                self.transition(to: .paused)
            }
            self.publishNowPlaying(rate: status.isBuffering ? 0 : status.rate)
        }
        player.onItemEnd = { [weak self] in self?.handleItemEnd() }
        self.player = player
        player.volume = volume
        player.replaceItems(with: queue.suffix(from: startIndex).map(\.url))
    }

    private func startLoadedItemIfPlaying() {
        guard state == .playing else { return }
        player?.play()
        emitStart(reason: .actual)
    }

    private func restartCurrentTrack(reason: PlaybackStartReason) {
        accumulateActivePlayback()
        activeStartID = nil
        seek(to: 0)
        if state == .playing { emitStart(reason: reason) }
        publishNowPlaying()
    }

    private func handleItemEnd() {
        // Repeat-one wraps the same track. Otherwise advance.
        if repeatMode == .one {
            accumulateActivePlayback()
            activeStartID = nil
            seek(to: 0)
            player?.play()
            emitStart(reason: .repeatOneRestart)
            return
        }
        next()
    }

    private func tearDownPlayer() {
        player?.invalidate()
        player = nil
    }
}
