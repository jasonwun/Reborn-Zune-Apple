import Foundation

/// Coarse playback state surfaced to the UI layer. Mirrors AVPlayer's
/// timeControlStatus but with explicit `.stopped` for end-of-queue.
public enum PlaybackState: Sendable, Equatable {
    case stopped
    case playing
    case paused
    case buffering
}

/// Repeat semantics for the queue.
public enum RepeatMode: Sendable, Equatable {
    case off
    case all   // wraps to first track after last
    case one   // current track loops indefinitely
}
