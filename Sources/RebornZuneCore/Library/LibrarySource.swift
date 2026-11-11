import Foundation

public protocol LibrarySource: Sendable {
    /// Load all audio tracks visible to this source.
    /// May throw on permission failures, missing folder, etc.
    /// Returns an empty array (NOT an error) when the source contains no audio.
    func load() async throws -> [Music]
}

/// Audio file extensions recognized by every `LibrarySource` implementation.
enum SupportedAudioExtension: String, CaseIterable {
    case mp3
    case m4a
    case mp4
    case aac
    case flac
    case wav
    case aiff
}
