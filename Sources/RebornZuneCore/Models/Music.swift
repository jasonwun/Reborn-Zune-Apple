import Foundation
import CryptoKit

public struct Music: Identifiable, Hashable, Sendable {
    public let id: String              // stable; derived from URL.path
    public let url: URL                // location on disk (or in-bundle)
    public let title: String           // never empty; falls back to filename
    public let artist: String?
    public let albumArtist: String?
    public let albumTitle: String?
    public let year: Int?
    public let trackNumber: Int?
    public let discNumber: Int?
    public let genre: String?
    public let duration: TimeInterval  // seconds; 0 if unknown
    public let artworkData: Data?      // raw image bytes from the file's metadata; nil if absent

    public init(
        id: String, url: URL, title: String, artist: String?,
        albumArtist: String?, albumTitle: String?, year: Int?,
        trackNumber: Int? = nil, discNumber: Int? = nil, genre: String? = nil,
        duration: TimeInterval, artworkData: Data?
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.artist = artist
        self.albumArtist = albumArtist
        self.albumTitle = albumTitle
        self.year = year
        self.trackNumber = trackNumber
        self.discNumber = discNumber
        self.genre = genre
        self.duration = duration
        self.artworkData = artworkData
    }
}

extension Music {
    /// Deterministic ID for a track at `url`. Computed as the SHA-256 hash of the URL's
    /// filesystem path so that two `Music` instances representing the same file always
    /// share an `id`.
    public static func makeID(for url: URL) -> String {
        legacyID(forPath: url.path)
    }

    /// Legacy path-hash key for `path`; used to re-key old Playlist entries.
    public static func legacyID(forPath path: String) -> String {
        let digest = SHA256.hash(data: Data(path.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
