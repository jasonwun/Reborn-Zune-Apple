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

    public var next: RepeatMode {
        switch self {
        case .off: return .all
        case .all: return .one
        case .one: return .off
        }
    }
}

/// Why a new listening event began. Resume and seek never use this type.
public enum PlaybackStartReason: Sendable, Equatable {
    case actual
    case manualRestart
    case repeatOneRestart
}

/// Explicit playback transitions for listeners such as Play History.
public enum PlaybackSignal: Sendable, Equatable {
    case load(trackID: String)
    case start(id: UUID, trackID: String, reason: PlaybackStartReason)
    case resume(trackID: String)
    case seek(trackID: String)
    case activePlayback(id: UUID, trackID: String, elapsed: TimeInterval, duration: TimeInterval?)
}
