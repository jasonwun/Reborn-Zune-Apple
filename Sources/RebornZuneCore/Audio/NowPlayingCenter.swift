import Foundation
import MediaPlayer

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct RemoteCommandHandlers {
    let play: () -> Void
    let pause: () -> Void
    let toggle: () -> Void
    let next: () -> Void
    let previous: () -> Void
    let seek: (TimeInterval) -> Void
    let shuffle: (Bool) -> Void
    let `repeat`: (RepeatMode) -> Void
}

@MainActor
protocol NowPlayingCentering: AnyObject {
    func registerCommands(_ handlers: RemoteCommandHandlers)
    func update(item: Music?, currentTime: TimeInterval, duration: TimeInterval, rate: Double)
}

/// Wraps `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter` so the engine
/// can publish track info and receive remote commands (lock-screen,
/// AirPods, Siri Remote, Control Center). Intentionally `internal` —
/// engine owns the lifecycle; external callers don't touch it.
@MainActor
final class NowPlayingCenter: NowPlayingCentering {
    private var registered = false
    private var handlers: RemoteCommandHandlers?

    init() {}

    /// Wire remote command handlers. Idempotent — safe to call repeatedly;
    /// the second call replaces handlers without registering twice.
    func registerCommands(_ handlers: RemoteCommandHandlers) {
        self.handlers = handlers

        if registered { return }
        registered = true

        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true
        #if os(macOS)
        center.changePlaybackPositionCommand.isEnabled = true
        center.changeShuffleModeCommand.isEnabled = true
        center.changeRepeatModeCommand.isEnabled = true
        #endif

        center.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.handlers?.play() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.handlers?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.handlers?.toggle() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.handlers?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.handlers?.previous() }
            return .success
        }
        #if os(macOS)
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self, let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            let position = event.positionTime
            Task { @MainActor in self.handlers?.seek(position) }
            return .success
        }
        center.changeShuffleModeCommand.addTarget { [weak self] event in
            guard let self, let event = event as? MPChangeShuffleModeCommandEvent else {
                return .commandFailed
            }
            let isShuffling = event.shuffleType != .off
            Task { @MainActor in self.handlers?.shuffle(isShuffling) }
            return .success
        }
        center.changeRepeatModeCommand.addTarget { [weak self] event in
            guard let self, let event = event as? MPChangeRepeatModeCommandEvent else {
                return .commandFailed
            }
            let mode: RepeatMode = switch event.repeatType {
            case .off: .off
            case .one: .one
            case .all: .all
            @unknown default: .off
            }
            Task { @MainActor in self.handlers?.repeat(mode) }
            return .success
        }
        #endif
    }

    /// Update Now Playing info on track change. Pass nil to clear.
    func update(item: Music?, currentTime: TimeInterval, duration: TimeInterval, rate: Double) {
        let center = MPNowPlayingInfoCenter.default()

        guard let item else {
            center.nowPlayingInfo = nil
            return
        }

        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = item.title
        if let artist = item.artist {
            info[MPMediaItemPropertyArtist] = artist
        }
        if let album = item.albumTitle {
            info[MPMediaItemPropertyAlbumTitle] = album
        }
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = rate

        if let data = item.artworkData {
            if let artwork = makeArtwork(from: data) {
                info[MPMediaItemPropertyArtwork] = artwork
            }
        }

        center.nowPlayingInfo = info
    }

    private func makeArtwork(from data: Data) -> MPMediaItemArtwork? {
        // The boundsSize handler closure is invoked on MediaPlayer's own
        // background queue, NOT on the main actor. With Swift 6 strict
        // concurrency, an implicitly-@MainActor-isolated closure called
        // off-main trips `dispatch_assert_queue_fail` at runtime.
        //
        // Fix: make the closure `@Sendable` and have it capture only `Data`
        // (which is Sendable). The NSImage / UIImage is constructed inside
        // the closure on whatever queue MediaPlayer chose, then returned
        // by value — no MainActor crossing.
        #if canImport(UIKit)
        guard let probe = UIImage(data: data) else { return nil }
        return MPMediaItemArtwork(boundsSize: probe.size) { @Sendable _ in
            UIImage(data: data) ?? UIImage()
        }
        #elseif canImport(AppKit)
        guard let probe = NSImage(data: data) else { return nil }
        return MPMediaItemArtwork(boundsSize: probe.size) { @Sendable _ in
            NSImage(data: data) ?? NSImage()
        }
        #else
        return nil
        #endif
    }
}
