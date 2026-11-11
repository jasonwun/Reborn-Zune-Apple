import Foundation

public enum LibraryGrouping {
    /// Group `tracks` into `Album`s by `(albumTitle, privilegedArtist)`.
    ///
    /// - `albumTitle` defaults to `"Unknown Album"` when the track has no album tag.
    /// - `privilegedArtist` resolves per the rule:
    ///     1. Use `albumArtist` if non-nil and not `"Unknown Artist"`.
    ///     2. Else use `artist` if non-nil and not `"Unknown Artist"`.
    ///     3. Else `"Unknown Artist"`.
    /// - Album.year is the earliest non-nil year among the album's tracks.
    /// - Album.tracks is sorted by disc (default 1), track (unnumbered last),
    ///   then localized case-insensitive title.
    public static func albums(from tracks: [Music]) -> [Album] {
        guard !tracks.isEmpty else { return [] }

        struct Key: Hashable {
            let albumTitle: String
            let privilegedArtist: String
        }

        var buckets: [Key: [Music]] = [:]
        var insertionOrder: [Key] = []

        for track in tracks {
            let albumTitle = track.albumTitle ?? "Unknown Album"
            let privileged = privilegedArtist(albumArtist: track.albumArtist, artist: track.artist)
            let key = Key(albumTitle: albumTitle, privilegedArtist: privileged)
            if buckets[key] == nil {
                buckets[key] = []
                insertionOrder.append(key)
            }
            buckets[key]?.append(track)
        }

        return insertionOrder.map { key in
            let bucket = buckets[key] ?? []
            let sorted = bucket.sorted { lhs, rhs in
                let lhsDisc = lhs.discNumber ?? 1
                let rhsDisc = rhs.discNumber ?? 1
                if lhsDisc != rhsDisc { return lhsDisc < rhsDisc }
                let lhsTrack = lhs.trackNumber ?? Int.max
                let rhsTrack = rhs.trackNumber ?? Int.max
                if lhsTrack != rhsTrack { return lhsTrack < rhsTrack }
                let titleOrder = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
                if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
                return lhs.id < rhs.id
            }
            let earliestYear = bucket.compactMap { $0.year }.min()
            return Album(
                id: Album.makeID(title: key.albumTitle, albumArtist: key.privilegedArtist),
                title: key.albumTitle,
                albumArtist: key.privilegedArtist,
                year: earliestYear,
                tracks: sorted
            )
        }
    }

    /// Group `albums` into `Artist`s by `albumArtist`.
    public static func artists(from albums: [Album]) -> [Artist] {
        guard !albums.isEmpty else { return [] }

        var buckets: [String: [Album]] = [:]
        var insertionOrder: [String] = []
        for album in albums {
            if buckets[album.albumArtist] == nil {
                buckets[album.albumArtist] = []
                insertionOrder.append(album.albumArtist)
            }
            buckets[album.albumArtist]?.append(album)
        }

        return insertionOrder.map { name in
            let owned = buckets[name] ?? []
            return Artist(
                id: Artist.makeID(name: name),
                name: name,
                albums: owned
            )
        }
    }

    /// The privilegedArtist rule from the UWP `LibraryViewModel`.
    static func privilegedArtist(albumArtist: String?, artist: String?) -> String {
        if let albumArtist, albumArtist != "Unknown Artist" {
            return albumArtist
        }
        if let artist, artist != "Unknown Artist" {
            return artist
        }
        return "Unknown Artist"
    }
}
