import Foundation

#if os(iOS) || os(tvOS)
import AVFoundation
#endif

/// Configures `AVAudioSession` for background-capable music playback. No-op
/// on macOS (which has no `AVAudioSession`).
@MainActor
enum AudioSessionConfigurator {
    /// Configure session for background-capable music playback on
    /// iOS/iPadOS/tvOS. No-op on macOS.
    static func configureForPlayback() throws {
        #if os(iOS) || os(tvOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setActive(true)
        #endif
    }
}
