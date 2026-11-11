import Foundation
import CryptoKit

public struct Album: Identifiable, Hashable, Sendable {
    public let id: String              // hash of (albumTitle, privilegedArtist)
    public let title: String           // "Unknown Album" if source had no album tag
    public let albumArtist: String     // see "privilegedArtist" rule
    public let year: Int?              // earliest non-nil year among tracks
    public let tracks: [Music]         // ordered by disc, track, then title

    public var artworkData: Data? {
        tracks.first?.artworkData
    }

    /// The most common real genre among this Album's Tracks, or nil when
    /// none of them carries a genre tag.
    public var genre: String? { Self.commonGenre(in: tracks) }

    static func commonGenre(in tracks: [Music]) -> String? {
        genreCounts(in: tracks).first?.genre
    }

    static func genreCounts(in tracks: [Music]) -> [(genre: String, count: Int)] {
        let counts = tracks.compactMap(\.genre).reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        return counts.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
        }.map { (genre: $0.key, count: $0.value) }
    }

    public init(id: String, title: String, albumArtist: String, year: Int?, tracks: [Music]) {
        self.id = id
        self.title = title
        self.albumArtist = albumArtist
        self.year = year
        self.tracks = tracks
    }

    /// Display rows with real track numbers, positional fallbacks, and Disc
    /// headings only when the Album contains multiple distinct discs.
    public var trackPresentation: [AlbumTrackPresentation] {
        let showsDiscs = Set(tracks.map { $0.discNumber ?? 1 }).count > 1
        var previousDisc: Int?
        return tracks.enumerated().map { index, track in
            let disc = track.discNumber ?? 1
            let heading = showsDiscs && disc != previousDisc ? "Disc \(disc)" : nil
            previousDisc = disc
            return AlbumTrackPresentation(
                track: track,
                discHeading: heading,
                displayNumber: track.trackNumber ?? index + 1,
                queueIndex: index
            )
        }
    }

    /// Compute the deterministic album ID from its title and privileged artist.
    static func makeID(title: String, albumArtist: String) -> String {
        let payload = "\(title)\u{1F}\(albumArtist)"
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

public struct AlbumTrackPresentation: Identifiable, Hashable, Sendable {
    public let track: Music
    public let discHeading: String?
    public let displayNumber: Int
    public let queueIndex: Int

    public var id: Int { queueIndex }

    public init(track: Music, discHeading: String?, displayNumber: Int, queueIndex: Int) {
        self.track = track
        self.discHeading = discHeading
        self.displayNumber = displayNumber
        self.queueIndex = queueIndex
    }
}
