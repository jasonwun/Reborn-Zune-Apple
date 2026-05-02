import Foundation
import CryptoKit

public struct Album: Identifiable, Hashable, Sendable {
    public let id: String              // hash of (albumTitle, privilegedArtist)
    public let title: String           // "Unknown Album" if source had no album tag
    public let albumArtist: String     // see "privilegedArtist" rule
    public let year: Int?              // earliest non-nil year among tracks
    public let tracks: [Music]         // ordered by title ascending

    public var artworkData: Data? {
        tracks.first?.artworkData
    }

    public init(id: String, title: String, albumArtist: String, year: Int?, tracks: [Music]) {
        self.id = id
        self.title = title
        self.albumArtist = albumArtist
        self.year = year
        self.tracks = tracks
    }

    /// Compute the deterministic album ID from its title and privileged artist.
    static func makeID(title: String, albumArtist: String) -> String {
        let payload = "\(title)\u{1F}\(albumArtist)"
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
