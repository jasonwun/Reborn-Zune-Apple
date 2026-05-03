import Foundation
import MediaPlayer

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Wraps `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter` so the engine
/// can publish track info and receive remote commands (lock-screen,
/// AirPods, Siri Remote, Control Center). Intentionally `internal` —
/// engine owns the lifecycle; external callers don't touch it.
@MainActor
final class NowPlayingCenter {
    private var registered = false
    private var playHandler: (() -> Void)?
    private var pauseHandler: (() -> Void)?
    private var toggleHandler: (() -> Void)?
    private var nextHandler: (() -> Void)?
    private var previousHandler: (() -> Void)?

    init() {}

    /// Wire remote command handlers. Idempotent — safe to call repeatedly;
    /// the second call replaces handlers without registering twice.
    func registerCommands(
        play: @escaping () -> Void,
        pause: @escaping () -> Void,
        toggle: @escaping () -> Void,
        next: @escaping () -> Void,
        previous: @escaping () -> Void
    ) {
        playHandler = play
        pauseHandler = pause
        toggleHandler = toggle
        nextHandler = next
        previousHandler = previous

        if registered { return }
        registered = true

        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true

        center.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.playHandler?() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.pauseHandler?() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.toggleHandler?() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.nextHandler?() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.previousHandler?() }
            return .success
        }
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
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return nil }
        return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        #elseif canImport(AppKit)
        guard let image = NSImage(data: data) else { return nil }
        return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        #else
        return nil
        #endif
    }
}
