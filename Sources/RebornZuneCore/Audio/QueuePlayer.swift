import AVFoundation
import Foundation
import os

struct QueuePlaybackStatus: Equatable {
    let position: TimeInterval
    let rate: Double
    let isBuffering: Bool
}

/// Minimal player seam used by PlaybackEngine. Tests can observe playback
/// without depending on AVQueuePlayer's asynchronous internals.
@MainActor
protocol QueuePlayer: AnyObject {
    var volume: Double { get set }
    var currentTime: TimeInterval { get }
    var onTimeUpdate: ((TimeInterval, TimeInterval?) -> Void)? { get set }
    /// Actual rate/buffering transitions, separate from periodic UI time updates.
    var onPlaybackStatusChange: ((QueuePlaybackStatus) -> Void)? { get set }
    var onItemEnd: (() -> Void)? { get set }
    func replaceItems(with urls: [URL])
    func play()
    func pause()
    func seek(to seconds: TimeInterval)
    func invalidate()
}

@MainActor
final class AVQueuePlayerAdapter: QueuePlayer {
    var currentTime: TimeInterval {
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? max(0, seconds) : 0
    }

    var volume: Double {
        get { Double(player.volume) }
        set { player.volume = Float(newValue) }
    }
    var onTimeUpdate: ((TimeInterval, TimeInterval?) -> Void)?
    var onPlaybackStatusChange: ((QueuePlaybackStatus) -> Void)?
    var onItemEnd: (() -> Void)?

    private let player = AVQueuePlayer()
    private var playerObservations: [NSKeyValueObservation] = []
    private var itemObservations: [NSKeyValueObservation] = []
    private var lastPlaybackStatus: QueuePlaybackStatus?
    private var timeObserverToken: Any?
    private var endObserver: NSObjectProtocol?
    private let fileAccess: (@MainActor (URL) throws -> any LibraryBookmarkSession)?
    private var fileAccessSessions: [any LibraryBookmarkSession] = []
    private let logger = Logger(subsystem: "dev.yjd.rebornzune", category: "PlaybackEngine")

    init(fileAccess: (@MainActor (URL) throws -> any LibraryBookmarkSession)? = nil) {
        self.fileAccess = fileAccess
        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.2, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                let seconds = time.seconds
                let rawDuration = self.player.currentItem?.duration.seconds
                let duration = rawDuration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
                if seconds.isFinite { self.onTimeUpdate?(seconds, duration) }
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.onItemEnd?() }
        }
        #if os(macOS)
        playerObservations = [
            player.observe(\.rate) { [weak self] _, _ in
                Task { @MainActor in self?.publishPlaybackStatus() }
            },
            player.observe(\.timeControlStatus) { [weak self] _, _ in
                Task { @MainActor in self?.publishPlaybackStatus() }
            },
            player.observe(\.currentItem) { [weak self] _, _ in
                Task { @MainActor in
                    self?.observeCurrentItem()
                    self?.publishPlaybackStatus()
                }
            }
        ]
        #endif
    }

    func replaceItems(with urls: [URL]) {
        player.pause()
        player.removeAllItems()
        for url in urls {
            do {
                let session = try fileAccess?(url)
                // Validate only after starting access: without the security
                // scope, Sandbox can make an authorized file look absent.
                guard !url.isFileURL || FileManager.default.fileExists(atPath: url.path) else {
                    session?.stop()
                    logger.error("Skipping unreachable item: \(url.lastPathComponent, privacy: .public)")
                    continue
                }
                if let session { fileAccessSessions.append(session) }
                player.insert(AVPlayerItem(url: url), after: nil)
            } catch {
                logger.error("Skipping inaccessible item: \(url.lastPathComponent, privacy: .public)")
            }
        }
    }

    func play() { player.play() }
    func pause() { player.pause() }

    private func observeCurrentItem() {
        itemObservations.removeAll()
        guard let item = player.currentItem else { return }
        itemObservations = [
            item.observe(\.isPlaybackBufferEmpty) { [weak self] _, _ in
                Task { @MainActor in self?.publishPlaybackStatus() }
            },
            item.observe(\.isPlaybackLikelyToKeepUp) { [weak self] _, _ in
                Task { @MainActor in self?.publishPlaybackStatus() }
            }
        ]
    }

    private func publishPlaybackStatus() {
        let item = player.currentItem
        let isBuffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
            || (player.timeControlStatus == .playing
                && item?.isPlaybackBufferEmpty == true
                && item?.isPlaybackLikelyToKeepUp == false)
        let status = QueuePlaybackStatus(
            position: currentTime,
            rate: Double(player.rate),
            isBuffering: isBuffering
        )
        // Position is deliberately excluded: only rate/buffering transitions publish.
        guard lastPlaybackStatus?.rate != status.rate
            || lastPlaybackStatus?.isBuffering != status.isBuffering else { return }
        lastPlaybackStatus = status
        onPlaybackStatusChange?(status)
    }

    func seek(to seconds: TimeInterval) {
        player.seek(
            to: CMTime(seconds: seconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    func invalidate() {
        if let timeObserverToken { player.removeTimeObserver(timeObserverToken) }
        timeObserverToken = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player.pause()
        player.removeAllItems()
        playerObservations.removeAll()
        itemObservations.removeAll()
        lastPlaybackStatus = nil
        onTimeUpdate = nil
        onPlaybackStatusChange = nil
        onItemEnd = nil
        let sessions = fileAccessSessions
        fileAccessSessions.removeAll()
        for session in sessions { session.stop() }
    }
}
