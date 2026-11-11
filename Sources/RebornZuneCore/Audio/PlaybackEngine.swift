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
    private var player: AVQueuePlayer?

    @ObservationIgnored
    private var timeObserverToken: Any?

    @ObservationIgnored
    private var endObserver: NSObjectProtocol?

    @ObservationIgnored
    private let nowPlaying = NowPlayingCenter()

    @ObservationIgnored
    private var sessionConfigured = false

    @ObservationIgnored
    private let logger = Logger(subsystem: "dev.yjd.rebornzune", category: "PlaybackEngine")

    // MARK: - Init

    public init() {
        nowPlaying.registerCommands(
            play: { [weak self] in self?.play() },
            pause: { [weak self] in self?.pause() },
            toggle: { [weak self] in self?.togglePlayPause() },
            next: { [weak self] in self?.next() },
            previous: { [weak self] in self?.previous() }
        )
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
        guard let player else {
            // No player but we have a queue and an index — rebuild and play.
            if !queue.isEmpty, let i = currentIndex {
                rebuildPlayer(startingAt: i)
                self.player?.play()
                transition(to: .playing)
                publishNowPlaying()
            }
            return
        }
        configureSessionIfNeeded()
        player.play()
        transition(to: .playing)
        publishNowPlaying()
    }

    public func pause() {
        player?.pause()
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

        if repeatMode == .one, let i = currentIndex {
            // Repeat-one: do not advance the queue position.
            seek(to: 0)
            updateCurrentItem(to: queue[i])
            publishNowPlaying()
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
                if state == .playing { player?.play() }
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
        if state == .playing { player?.play() }
        publishNowPlaying()
    }

    public func previous() {
        guard !queue.isEmpty, let i = currentIndex else { return }

        if repeatMode == .one {
            seek(to: 0)
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
                if state == .playing { player?.play() }
            case .off, .one:
                // Conventional: previous at index 0 restarts current track.
                seek(to: 0)
            }
            publishNowPlaying()
            return
        }
        currentIndex = prevIndex
        rebuildPlayer(startingAt: prevIndex)
        updateCurrentItem(to: queue[prevIndex])
        if state == .playing { player?.play() }
        publishNowPlaying()
    }

    /// Jump to a specific track in the queue if present. No-op if not in queue.
    public func skip(to item: Music) {
        guard let idx = queue.firstIndex(of: item) else { return }
        currentIndex = idx
        rebuildPlayer(startingAt: idx)
        updateCurrentItem(to: queue[idx])
        if state == .playing { player?.play() }
        publishNowPlaying()
    }

    /// Seek to a position in the current item (clamped to 0...duration).
    public func seek(to seconds: TimeInterval) {
        let clamped = max(0, min(seconds, duration))
        currentTime = clamped
        guard let player else { return }
        let cmTime = CMTime(seconds: clamped, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    // MARK: - Internal helpers

    private func transition(to newState: PlaybackState) {
        guard state != newState else { return }
        state = newState
    }

    private func updateCurrentItem(to item: Music?) {
        currentItem = item
        duration = item?.duration ?? 0
        currentTime = 0
    }

    private func publishNowPlaying() {
        let rate: Double = (state == .playing) ? 1.0 : 0.0
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

        let slice = Array(queue.suffix(from: startIndex))
        let items = slice.compactMap { music -> AVPlayerItem? in
            // Validate URL is reachable; if not, log + skip.
            let url = music.url
            if !url.isFileURL || FileManager.default.fileExists(atPath: url.path) {
                return AVPlayerItem(url: url)
            }
            logger.error("Skipping unreachable item: \(music.title, privacy: .public)")
            return nil
        }

        let avPlayer = AVQueuePlayer(items: items)
        // Default rate is 1.0; we keep automaticallyWaitsToMinimizeStalling on.
        self.player = avPlayer
        installPeriodicTimeObserver()
        installEndOfQueueObserver()
    }

    private func installPeriodicTimeObserver() {
        guard let player else { return }
        let interval = CMTime(seconds: 0.2, preferredTimescale: 600) // ~5 Hz
        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: interval, queue: .main
        ) { [weak self] time in
            // Hop back onto the main actor explicitly so Swift 6 strict
            // concurrency is satisfied — the closure runs on .main but
            // isn't tagged @MainActor.
            Task { @MainActor in
                guard let self else { return }
                let seconds = time.seconds
                if seconds.isFinite {
                    self.currentTime = seconds
                }
                if let item = player.currentItem {
                    let d = item.duration.seconds
                    if d.isFinite, d > 0, abs(d - self.duration) > 0.01 {
                        self.duration = d
                    }
                }
            }
        }
    }

    private func installEndOfQueueObserver() {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleItemEnd()
            }
        }
    }

    private func handleItemEnd() {
        // Repeat-one wraps the same track. Otherwise advance.
        if repeatMode == .one {
            seek(to: 0)
            player?.play()
            return
        }
        next()
    }

    private func tearDownPlayer() {
        if let token = timeObserverToken, let player {
            player.removeTimeObserver(token)
        }
        timeObserverToken = nil
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        endObserver = nil
        player?.pause()
        player?.removeAllItems()
        player = nil
    }
}
