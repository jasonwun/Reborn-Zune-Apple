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
    public var upNext: [Music] {
        guard let currentIndex, currentIndex + 1 < queue.count else { return [] }
        return Array(queue[(currentIndex + 1)...])
    }
    public private(set) var currentTime: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0
    public var persistenceSnapshot: PlaybackQueueSnapshot {
        PlaybackQueueSnapshot(
            originalTrackIDs: originalQueue.compactMap { UUID(uuidString: $0.id) },
            activeTrackIDs: queue.compactMap { UUID(uuidString: $0.id) },
            currentIndex: currentIndex,
            position: currentTime,
            isShuffling: isShuffling,
            originalEntryIDs: originalEntryIDs,
            activeEntryIDs: activeEntryIDs
        )
    }
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

    @ObservationIgnored
    private var originalEntryIDs: [UUID] = []

    @ObservationIgnored
    private var activeEntryIDs: [UUID] = []

    /// Index in `queue` of the track currently playing (or about to play).
    /// `nil` means stopped / queue empty.
    @ObservationIgnored
    public private(set) var currentIndex: Int?

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

    /// Called after transport, Queue, and seek changes so hosts can persist a snapshot.
    @ObservationIgnored
    public var queuePersistenceHandler: ((PlaybackQueueSnapshot) -> Void)?

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
        originalEntryIDs = items.map { _ in UUID() }
        activeEntryIDs = originalEntryIDs
        if items.isEmpty {
            queue = []
            activeEntryIDs = []
            currentIndex = nil
            updateCurrentItem(to: nil)
            transition(to: .stopped)
            tearDownPlayer()
            publishNowPlaying()
            return
        }

        let clampedStart = max(0, min(index, items.count - 1))
        if isShuffling {
            let order = makeShuffledOrder(count: items.count, pinningFirst: clampedStart)
            queue = order.map { originalQueue[$0] }
            activeEntryIDs = order.map { originalEntryIDs[$0] }
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

    /// Restores resolved Tracks in their persisted active order, paused at the saved position.
    public func restoreQueue(_ snapshot: PlaybackQueueSnapshot, resolving resolve: (UUID) -> Music?) {
        tearDownPlayer()
        originalQueue = []
        originalEntryIDs = []
        queue = []
        activeEntryIDs = []
        currentIndex = nil
        isShuffling = snapshot.isShuffling

        let resolvedOriginal = snapshot.originalTrackIDs.enumerated().compactMap { index, id in
            resolve(id).map { (sourceIndex: index, item: $0) }
        }
        originalQueue = resolvedOriginal.map(\.item)
        originalEntryIDs = resolvedOriginal.map {
            snapshot.originalEntryIDs.count == snapshot.originalTrackIDs.count
                ? snapshot.originalEntryIDs[$0.sourceIndex]
                : UUID()
        }
        let resolvedActive = snapshot.activeTrackIDs.enumerated().compactMap { index, id in
            resolve(id).map { (sourceIndex: index, item: $0) }
        }
        queue = resolvedActive.map(\.item)
        var availableIDsByTrack: [UUID: [UUID]] = [:]
        for (offset, resolved) in resolvedOriginal.enumerated() {
            let trackID = snapshot.originalTrackIDs[resolved.sourceIndex]
            availableIDsByTrack[trackID, default: []].append(originalEntryIDs[offset])
        }
        activeEntryIDs = resolvedActive.map { resolved in
            let trackID = snapshot.activeTrackIDs[resolved.sourceIndex]
            let persistedID = snapshot.activeEntryIDs.count == snapshot.activeTrackIDs.count
                ? snapshot.activeEntryIDs[resolved.sourceIndex]
                : nil
            if let persistedID, originalEntryIDs.contains(persistedID) {
                availableIDsByTrack[trackID]?.removeAll { $0 == persistedID }
                return persistedID
            }
            if var ids = availableIDsByTrack[trackID], !ids.isEmpty {
                let id = ids.removeFirst()
                availableIDsByTrack[trackID] = ids
                return id
            }
            return persistedID ?? UUID()
        }
        currentIndex = snapshot.currentIndex.flatMap { savedIndex in
            resolvedActive.firstIndex { $0.sourceIndex == savedIndex }
        }

        guard let currentIndex else {
            updateCurrentItem(to: nil)
            transition(to: .stopped)
            publishNowPlaying()
            return
        }
        updateCurrentItem(to: queue[currentIndex])
        rebuildPlayer(startingAt: currentIndex)
        seek(to: snapshot.position)
        transition(to: .paused)
        publishNowPlaying()
    }

    /// Inserts a Track immediately after the current Track without changing playback.
    public func playNext(_ item: Music) {
        playNext([item])
    }

    /// Inserts a snapshot of Tracks immediately after the current Track.
    public func playNext(_ items: [Music]) {
        insert(items, afterCurrent: true)
    }

    /// Appends a Track to the logical Queue without changing playback.
    public func playLater(_ item: Music) {
        playLater([item])
    }

    /// Appends a snapshot of Tracks to the logical Queue.
    public func playLater(_ items: [Music]) {
        insert(items, afterCurrent: false)
    }

    private func insert(_ items: [Music], afterCurrent: Bool) {
        guard !items.isEmpty else { return }
        let currentEntryID = currentIndex.map { activeEntryIDs[$0] }
        let activeIndex = afterCurrent ? (currentIndex.map { $0 + 1 } ?? 0) : queue.count
        let entryIDs = items.map { _ in UUID() }
        queue.insert(contentsOf: items, at: activeIndex)
        activeEntryIDs.insert(contentsOf: entryIDs, at: activeIndex)

        let originalIndex: Int
        if afterCurrent {
            originalIndex = currentEntryID.flatMap { originalEntryIDs.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
        } else {
            originalIndex = originalQueue.count
        }
        originalQueue.insert(contentsOf: items, at: originalIndex)
        originalEntryIDs.insert(contentsOf: entryIDs, at: originalIndex)

        if currentIndex == nil {
            currentIndex = activeIndex
            updateCurrentItem(to: queue[activeIndex])
            transition(to: .paused)
            reconcileCurrentPlayer()
        } else {
            reconcileCurrentPlayer()
        }
    }

    private func reconcileCurrentPlayer() {
        guard let currentIndex else { return }
        let resumesPlayback = state == .playing || state == .buffering
        rebuildPlayer(startingAt: currentIndex)
        seek(to: currentTime)
        if resumesPlayback { player?.play() }
        publishNowPlaying()
    }

    /// Play an Artist's complete Track collection in shuffled order.
    public func shuffleArtist(_ tracks: [Music]) {
        guard !tracks.isEmpty else { return }
        isShuffling = true
        setQueue(tracks)
        play()
    }

    /// Moves upcoming Tracks using SwiftUI's `onMove` offsets. The current Track is not movable.
    public func moveUpNext(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard let currentIndex else { return }
        let start = currentIndex + 1
        let upcomingCount = queue.count - start
        guard source.allSatisfy({ $0 >= 0 && $0 < upcomingCount }),
              destination >= 0, destination <= upcomingCount else { return }
        queue.move(fromOffsets: IndexSet(source.map { $0 + start }), toOffset: destination + start)
        activeEntryIDs.move(fromOffsets: IndexSet(source.map { $0 + start }), toOffset: destination + start)
        if !isShuffling {
            originalQueue = queue
            originalEntryIDs = activeEntryIDs
        }
        reconcileCurrentPlayer()
    }

    /// Removes one upcoming Track by its zero-based Up Next offset.
    public func removeUpNext(at offset: Int) {
        guard let currentIndex, offset >= 0, currentIndex + 1 + offset < queue.count else { return }
        queue.remove(at: currentIndex + 1 + offset)
        let removedEntryID = activeEntryIDs.remove(at: currentIndex + 1 + offset)
        if isShuffling {
            removeOriginalEntry(withID: removedEntryID)
        } else {
            originalQueue = queue
            originalEntryIDs = activeEntryIDs
        }
        reconcileCurrentPlayer()
    }

    /// Removes every upcoming Track while preserving the current Track and playback state.
    public func clearUpNext() {
        guard let currentIndex, currentIndex + 1 < queue.count else { return }
        queue.removeSubrange((currentIndex + 1)...)
        let removedEntryIDs = activeEntryIDs[(currentIndex + 1)...]
        activeEntryIDs.removeSubrange((currentIndex + 1)...)
        if isShuffling {
            for id in removedEntryIDs { removeOriginalEntry(withID: id) }
        } else {
            originalQueue = queue
            originalEntryIDs = activeEntryIDs
        }
        reconcileCurrentPlayer()
    }

    private func removeOriginalEntry(withID id: UUID) {
        guard let index = originalEntryIDs.firstIndex(of: id) else { return }
        originalQueue.remove(at: index)
        originalEntryIDs.remove(at: index)
    }

    /// Removes deleted Library Tracks while preserving every unrelated Queue entry.
    /// Removing the current Track stops playback without selecting a replacement.
    public func removeTracks(withIDs ids: Set<String>) {
        guard !ids.isEmpty else { return }
        let removesCurrent = currentItem.map { ids.contains($0.id) } ?? false
        let currentEntryID = currentIndex.map { activeEntryIDs[$0] }
        let retainedOriginal = zip(originalQueue, originalEntryIDs).filter { !ids.contains($0.0.id) }
        originalQueue = retainedOriginal.map(\.0)
        originalEntryIDs = retainedOriginal.map(\.1)
        let retainedActive = zip(queue, activeEntryIDs).filter { !ids.contains($0.0.id) }
        queue = retainedActive.map(\.0)
        activeEntryIDs = retainedActive.map(\.1)

        if removesCurrent {
            currentIndex = nil
            updateCurrentItem(to: nil)
            transition(to: .stopped)
            tearDownPlayer()
            publishNowPlaying()
        } else if let currentEntryID, let index = activeEntryIDs.firstIndex(of: currentEntryID) {
            currentIndex = index
            if player != nil { reconcileCurrentPlayer() }
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
        queuePersistenceHandler?(persistenceSnapshot)
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
        let pinnedEntryID = currentIndex.map { activeEntryIDs[$0] }
        if isShuffling {
            // Pin the current entry so duplicate Track occurrences stay distinct.
            let pinIndex = pinnedEntryID.flatMap { originalEntryIDs.firstIndex(of: $0) } ?? 0
            let order = makeShuffledOrder(count: originalQueue.count, pinningFirst: pinIndex)
            queue = order.map { originalQueue[$0] }
            activeEntryIDs = order.map { originalEntryIDs[$0] }
            currentIndex = 0
        } else {
            queue = originalQueue
            activeEntryIDs = originalEntryIDs
            currentIndex = pinnedEntryID.flatMap { activeEntryIDs.firstIndex(of: $0) } ?? 0
        }
        reconcileCurrentPlayer()
    }

    /// Fisher-Yates index shuffle pinning a chosen entry to index 0.
    private func makeShuffledOrder(count: Int, pinningFirst pinIndex: Int) -> [Int] {
        guard count > 0 else { return [] }
        let pin = max(0, min(pinIndex, count - 1))
        var rest = Array(0..<count)
        let pinnedItem = rest.remove(at: pin)

        var rng = SystemRandomNumberGenerator()
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
        // Keep the complete logical Queue while materializing only current+2.
        player.replaceItems(with: queue.suffix(from: startIndex).prefix(3).map(\.url))
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
