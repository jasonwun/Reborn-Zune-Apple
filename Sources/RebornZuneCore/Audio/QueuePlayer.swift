import AVFoundation
import Foundation
import os

/// Minimal player seam used by PlaybackEngine. Tests can observe playback
/// without depending on AVQueuePlayer's asynchronous internals.
@MainActor
protocol QueuePlayer: AnyObject {
    var volume: Double { get set }
    var onTimeUpdate: ((TimeInterval, TimeInterval?) -> Void)? { get set }
    var onItemEnd: (() -> Void)? { get set }
    func replaceItems(with urls: [URL])
    func play()
    func pause()
    func seek(to seconds: TimeInterval)
    func invalidate()
}

@MainActor
final class AVQueuePlayerAdapter: QueuePlayer {
    var volume: Double {
        get { Double(player.volume) }
        set { player.volume = Float(newValue) }
    }
    var onTimeUpdate: ((TimeInterval, TimeInterval?) -> Void)?
    var onItemEnd: (() -> Void)?

    private let player = AVQueuePlayer()
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
        onTimeUpdate = nil
        onItemEnd = nil
        let sessions = fileAccessSessions
        fileAccessSessions.removeAll()
        for session in sessions { session.stop() }
    }
}
