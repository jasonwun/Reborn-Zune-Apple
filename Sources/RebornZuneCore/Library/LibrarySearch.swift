import Foundation
import SwiftData

public let currentSearchNormalizationVersion = 1

public enum LibrarySearchNormalizer {
    public static func normalize(_ value: String) -> String {
        // Large local Libraries are commonly ASCII. Avoid Foundation locale
        // setup and Character-by-Character whitespace processing on that hot
        // path; non-ASCII metadata retains full case/diacritic folding.
        if value.utf8.allSatisfy({ $0 < 128 }) {
            var output: [UInt8] = []
            output.reserveCapacity(value.utf8.count)
            var needsSpace = false
            for byte in value.utf8 {
                if byte == 32 || (byte >= 9 && byte <= 13) {
                    needsSpace = !output.isEmpty
                    continue
                }
                if needsSpace { output.append(32) }
                needsSpace = false
                output.append(byte >= 65 && byte <= 90 ? byte + 32 : byte)
            }
            return String(decoding: output, as: UTF8.self)
        }
        return value.folding(options: [.caseInsensitive, .diacriticInsensitive],
                             locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    public static func tokens(for query: String) -> [String] {
        normalize(query).split(whereSeparator: \.isWhitespace).map(String.init)
    }
}

public struct LibrarySearchResults: Sendable, Equatable {
    public let songs: [TrackSnapshot]
    public let artists: [LibrarySearchArtist]
    public let albums: [LibrarySearchAlbum]

    public init(songs: [TrackSnapshot] = [], artists: [LibrarySearchArtist] = [],
                albums: [LibrarySearchAlbum] = []) {
        self.songs = songs
        self.artists = artists
        self.albums = albums
    }

    public var isEmpty: Bool { songs.isEmpty && artists.isEmpty && albums.isEmpty }
}

public struct LibrarySearchArtist: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let albumCount: Int
    public let genre: String?

    public init(id: String, name: String, albumCount: Int, genre: String?) {
        self.id = id
        self.name = name
        self.albumCount = albumCount
        self.genre = genre
    }
}

public struct LibrarySearchAlbum: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let albumArtist: String
    public let year: Int?
    public let genre: String?
    /// One lightweight representative used only for on-demand visible artwork.
    public let artworkTrackID: UUID?

    public init(id: String, title: String, albumArtist: String, year: Int?, genre: String?,
                artworkTrackID: UUID? = nil) {
        self.id = id
        self.title = title
        self.albumArtist = albumArtist
        self.year = year
        self.genre = genre
        self.artworkTrackID = artworkTrackID
    }
}

public struct LibrarySearchGenre: Identifiable, Sendable, Equatable {
    public let name: String
    public let count: Int
    public var id: String { name }

    public init(name: String, count: Int) {
        self.name = name
        self.count = count
    }
}

/// Background Global Search actor. SQLite narrows candidates through the
/// persisted search document; complete relevance ranking happens before the UI
/// applies its 10/5/5 presentation caps. No artwork is fetched here.
public actor LibrarySearchStore {
    private static let batchSize = 1000
    private let modelContainer: ModelContainer
    private let modelContext: ModelContext

    public init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        self.modelContext = ModelContext(modelContainer)
    }

    private struct SongEntry {
        let snapshot: TrackSnapshot
        let fields: [String]
        let titleSort: String
        let artistSort: String
        let albumSort: String
    }

    private struct ArtistEntry {
        let artist: LibrarySearchArtist
        let fields: [String]
        let nameSort: String
    }

    private struct AlbumEntry {
        let album: LibrarySearchAlbum
        let fields: [String]
        let titleSort: String
        let artistSort: String
    }

    private struct MemoryIndex {
        let songs: [SongEntry]
        let artists: [ArtistEntry]
        let albums: [AlbumEntry]
    }

    /// Lazy fallback enabled after the normalized SQLite baseline missed the
    /// 50,000-Track release targets. Persisted records remain authoritative;
    /// this actor-local index is rebuilt after every committed Library change.
    private var memoryIndex: MemoryIndex?

    public func search(_ query: String) throws -> LibrarySearchResults {
        let tokens = LibrarySearchNormalizer.tokens(for: query)
        guard !tokens.isEmpty else { return LibrarySearchResults() }
        try ensureCurrentSearchKeys()
        let index = try currentMemoryIndex()
        try Task.checkCancellation()
        let songs = try rankedSongs(tokens: tokens, index: index)
        let artists = try rankedArtists(tokens: tokens, index: index)
        let albums = try rankedAlbums(tokens: tokens, index: index)
        return LibrarySearchResults(songs: songs, artists: artists, albums: albums)
    }

    private struct AlbumAggregate {
        var title: String
        var artist: String
        var year: Int?
        var trackArtists = Set<String>()
        var genres: [String: Int] = [:]
        var artworkTrackID: UUID?
    }

    private struct ArtistAggregate {
        var albumIDs = Set<String>()
        var genres: [String: Int] = [:]
    }

    public func genres() throws -> [LibrarySearchGenre] {
        try ensureCurrentSearchKeys()
        let index = try currentMemoryIndex()
        var counts: [String: Int] = [:]
        for song in index.songs {
            if let genre = song.snapshot.genre { counts[genre, default: 0] += 1 }
        }
        return counts.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            let order = lhs.key.localizedCaseInsensitiveCompare(rhs.key)
            return order == .orderedSame ? lhs.key < rhs.key : order == .orderedAscending
        }.prefix(15).map { LibrarySearchGenre(name: $0.key, count: $0.value) }
    }

    private func ensureCurrentSearchKeys() throws {
        let state = try modelContext.fetch(FetchDescriptor<StoredLibraryState>()).first
            ?? StoredLibraryState()
        if state.modelContext == nil { modelContext.insert(state) }
        guard state.searchNormalizationVersion != currentSearchNormalizationVersion else { return }
        memoryIndex = nil

        for artist in try modelContext.fetch(FetchDescriptor<StoredArtist>()) { modelContext.delete(artist) }
        for album in try modelContext.fetch(FetchDescriptor<StoredAlbum>()) { modelContext.delete(album) }
        var albums: [String: AlbumAggregate] = [:]
        var albumIDs: [String: String] = [:]
        var artists: [String: ArtistAggregate] = [:]
        var offset = 0
        while true {
            try Task.checkCancellation()
            // A fresh context keeps registered objects from replacing SQLite's
            // requested order. Offset paging avoids Swift/SQLite cursor-collation
            // mismatches while Search keys are saved in bounded batches.
            let batchContext = ModelContext(modelContainer)
            var descriptor = FetchDescriptor<StoredTrack>(sortBy: [SortDescriptor(\.path)])
            descriptor.fetchLimit = Self.batchSize
            descriptor.fetchOffset = offset
            let batch = try batchContext.fetch(descriptor)
            if batch.isEmpty { break }
            for track in batch {
                Self.updateSearchKeys(for: track)
                let title = track.albumTitle ?? "Unknown Album"
                let artist = LibraryGrouping.privilegedArtist(
                    albumArtist: track.albumArtist, artist: track.artist)
                let albumKey = "\(title)\u{0}\(artist)"
                let albumID = albumIDs[albumKey] ?? {
                    let id = Album.makeID(title: title, albumArtist: artist)
                    albumIDs[albumKey] = id
                    return id
                }()
                var album = albums[albumID] ?? AlbumAggregate(title: title, artist: artist, year: nil)
                if let year = track.year { album.year = album.year.map { min($0, year) } ?? year }
                if let trackArtist = track.artist { album.trackArtists.insert(trackArtist) }
                if let genre = track.genre { album.genres[genre, default: 0] += 1 }
                if album.artworkTrackID == nil && track.hasArtwork { album.artworkTrackID = track.id }
                albums[albumID] = album
                var artistAggregate = artists[artist] ?? ArtistAggregate()
                artistAggregate.albumIDs.insert(albumID)
                if let genre = track.genre { artistAggregate.genres[genre, default: 0] += 1 }
                artists[artist] = artistAggregate
            }
            try batchContext.save()
            offset += batch.count
            if batch.count < Self.batchSize { break }
        }
        for (id, album) in albums {
            let trackArtists = album.trackArtists.sorted {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            }
            let genres = album.genres.keys.sorted {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            }
            let fields = [album.title, album.artist] + trackArtists + genres
            modelContext.insert(StoredAlbum(
                id: id, title: album.title, albumArtist: album.artist, year: album.year,
                genre: Self.commonGenre(album.genres), artworkTrackID: album.artworkTrackID,
                trackArtists: trackArtists, genres: genres,
                titleSearchKey: LibrarySearchNormalizer.normalize(album.title),
                albumArtistSearchKey: LibrarySearchNormalizer.normalize(album.artist),
                trackArtistSearchKeys: trackArtists.map(LibrarySearchNormalizer.normalize),
                genreSearchKeys: genres.map(LibrarySearchNormalizer.normalize),
                searchDocumentKey: fields.map(LibrarySearchNormalizer.normalize)
                    .filter { !$0.isEmpty }.joined(separator: " "),
                searchNormalizationVersion: currentSearchNormalizationVersion))
        }
        for (name, artist) in artists {
            let key = LibrarySearchNormalizer.normalize(name)
            modelContext.insert(StoredArtist(
                id: Artist.makeID(name: name), name: name, albumCount: artist.albumIDs.count,
                genre: Self.commonGenre(artist.genres), nameSearchKey: key,
                searchDocumentKey: key,
                searchNormalizationVersion: currentSearchNormalizationVersion))
        }
        state.searchNormalizationVersion = currentSearchNormalizationVersion
        try modelContext.save()
    }

    private static func commonGenre(_ counts: [String: Int]) -> String? {
        counts.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            let order = lhs.key.localizedCaseInsensitiveCompare(rhs.key)
            return order == .orderedSame ? lhs.key < rhs.key : order == .orderedAscending
        }.first?.key
    }

    private func currentMemoryIndex() throws -> MemoryIndex {
        if let memoryIndex { return memoryIndex }
        var songs: [SongEntry] = []
        var trackOffset = 0
        while true {
            try Task.checkCancellation()
            let batchContext = ModelContext(modelContainer)
            var descriptor = FetchDescriptor<StoredTrack>(sortBy: [SortDescriptor(\.path)])
            descriptor.fetchLimit = Self.batchSize
            descriptor.fetchOffset = trackOffset
            let batch = try batchContext.fetch(descriptor)
            if batch.isEmpty { break }
            for track in batch {
                let snapshot = LibraryStore.snapshotForSearch(track)
                songs.append(SongEntry(
                    snapshot: snapshot,
                    fields: [track.titleSearchKey, track.artistSearchKey,
                             track.albumArtistSearchKey, track.albumTitleSearchKey,
                             track.genreSearchKey],
                    titleSort: Self.sortKey(track.title),
                    artistSort: Self.sortKey(track.artist ?? ""),
                    albumSort: Self.sortKey(track.albumTitle ?? "")))
            }
            trackOffset += batch.count
            if batch.count < Self.batchSize { break }
        }

        var artists: [ArtistEntry] = []
        var artistOffset = 0
        while true {
            try Task.checkCancellation()
            let batchContext = ModelContext(modelContainer)
            var descriptor = FetchDescriptor<StoredArtist>(
                sortBy: [SortDescriptor(\.name), SortDescriptor(\.id)])
            descriptor.fetchLimit = Self.batchSize
            descriptor.fetchOffset = artistOffset
            let batch = try batchContext.fetch(descriptor)
            if batch.isEmpty { break }
            for stored in batch {
                artists.append(ArtistEntry(
                    artist: LibrarySearchArtist(id: stored.id, name: stored.name,
                                                albumCount: stored.albumCount, genre: stored.genre),
                    fields: [stored.nameSearchKey], nameSort: Self.sortKey(stored.name)))
            }
            artistOffset += batch.count
            if batch.count < Self.batchSize { break }
        }

        var albums: [AlbumEntry] = []
        var albumOffset = 0
        while true {
            try Task.checkCancellation()
            let batchContext = ModelContext(modelContainer)
            var descriptor = FetchDescriptor<StoredAlbum>(
                sortBy: [SortDescriptor(\.title), SortDescriptor(\.id)])
            descriptor.fetchLimit = Self.batchSize
            descriptor.fetchOffset = albumOffset
            let batch = try batchContext.fetch(descriptor)
            if batch.isEmpty { break }
            for stored in batch {
                albums.append(AlbumEntry(
                    album: LibrarySearchAlbum(
                        id: stored.id, title: stored.title, albumArtist: stored.albumArtist,
                        year: stored.year, genre: stored.genre,
                        artworkTrackID: stored.artworkTrackID),
                    fields: [stored.titleSearchKey, stored.albumArtistSearchKey]
                        + stored.trackArtistSearchKeys + stored.genreSearchKeys,
                    titleSort: Self.sortKey(stored.title),
                    artistSort: Self.sortKey(stored.albumArtist)))
            }
            albumOffset += batch.count
            if batch.count < Self.batchSize { break }
        }
        let index = MemoryIndex(songs: songs, artists: artists, albums: albums)
        memoryIndex = index
        return index
    }

    private static func sortKey(_ value: String) -> String {
        // Locale-aware lowercase is computed once per persisted record rather
        // than invoking an ICU comparator for every O(n log n) comparison.
        value.localizedLowercase
    }

    static func updateSearchKeys(for track: StoredTrack) {
        let fields = [track.title, track.artist, track.albumArtist, track.albumTitle, track.genre]
        let keys = fields.map { LibrarySearchNormalizer.normalize($0 ?? "") }
        track.titleSearchKey = keys[0]
        track.artistSearchKey = keys[1]
        track.albumArtistSearchKey = keys[2]
        track.albumTitleSearchKey = keys[3]
        track.genreSearchKey = keys[4]
        track.searchDocumentKey = keys.filter { !$0.isEmpty }.joined(separator: " ")
        track.searchNormalizationVersion = currentSearchNormalizationVersion
    }

    private func rankedSongs(tokens: [String], index: MemoryIndex) throws -> [TrackSnapshot] {
        var ranked: [(entry: SongEntry, minimum: Int, sum: Int)] = []
        for (offset, entry) in index.songs.enumerated() {
            if offset.isMultiple(of: 1000) { try Task.checkCancellation() }
            guard let score = Self.score(tokens: tokens, fields: entry.fields) else { continue }
            ranked.append((entry, score.minimum, score.sum))
        }
        ranked.sort(by: { lhs, rhs in
            if lhs.minimum != rhs.minimum { return lhs.minimum > rhs.minimum }
            if lhs.sum != rhs.sum { return lhs.sum > rhs.sum }
            if lhs.entry.titleSort != rhs.entry.titleSort {
                return lhs.entry.titleSort < rhs.entry.titleSort
            }
            if lhs.entry.artistSort != rhs.entry.artistSort {
                return lhs.entry.artistSort < rhs.entry.artistSort
            }
            if lhs.entry.albumSort != rhs.entry.albumSort {
                return lhs.entry.albumSort < rhs.entry.albumSort
            }
            return lhs.entry.snapshot.id.uuidString < rhs.entry.snapshot.id.uuidString
        })
        return ranked.map(\.entry.snapshot)
    }

    private func rankedArtists(tokens: [String], index: MemoryIndex) throws -> [LibrarySearchArtist] {
        var ranked: [(entry: ArtistEntry, minimum: Int, sum: Int)] = []
        for entry in index.artists {
            guard let score = Self.score(tokens: tokens, fields: entry.fields) else { continue }
            ranked.append((entry, score.minimum, score.sum))
        }
        ranked.sort { lhs, rhs in
            if lhs.minimum != rhs.minimum { return lhs.minimum > rhs.minimum }
            if lhs.sum != rhs.sum { return lhs.sum > rhs.sum }
            if lhs.entry.nameSort != rhs.entry.nameSort {
                return lhs.entry.nameSort < rhs.entry.nameSort
            }
            return lhs.entry.artist.id < rhs.entry.artist.id
        }
        return ranked.map(\.entry.artist)
    }

    private func rankedAlbums(tokens: [String], index: MemoryIndex) throws -> [LibrarySearchAlbum] {
        var ranked: [(entry: AlbumEntry, minimum: Int, sum: Int)] = []
        for entry in index.albums {
            guard let score = Self.score(tokens: tokens, fields: entry.fields) else { continue }
            ranked.append((entry, score.minimum, score.sum))
        }
        ranked.sort { lhs, rhs in
            if lhs.minimum != rhs.minimum { return lhs.minimum > rhs.minimum }
            if lhs.sum != rhs.sum { return lhs.sum > rhs.sum }
            if lhs.entry.titleSort != rhs.entry.titleSort {
                return lhs.entry.titleSort < rhs.entry.titleSort
            }
            if lhs.entry.artistSort != rhs.entry.artistSort {
                return lhs.entry.artistSort < rhs.entry.artistSort
            }
            return lhs.entry.album.id < rhs.entry.album.id
        }
        return ranked.map(\.entry.album)
    }

    static func score(tokens: [String], fields: [String]) -> (minimum: Int, sum: Int)? {
        var minimum = Int.max
        var sum = 0
        for token in tokens {
            let best = fields.reduce(0) { current, field in
                let value: Int
                if field == token { value = 3 }
                else if field.hasPrefix(token) { value = 2 }
                else if field.contains(token) { value = 1 }
                else { value = 0 }
                return max(current, value)
            }
            guard best > 0 else { return nil }
            minimum = min(minimum, best)
            sum += best
        }
        return (minimum, sum)
    }

}

extension LibraryStore {
    static func snapshotForSearch(_ track: StoredTrack) -> TrackSnapshot {
        TrackSnapshot(
            id: track.id, path: track.path, sourcePath: track.sourcePath,
            modificationDate: track.modificationDate, fileSize: track.fileSize,
            volumeID: track.volumeID, fileID: track.fileID, title: track.title,
            artist: track.artist, albumArtist: track.albumArtist, albumTitle: track.albumTitle,
            year: track.year, duration: track.duration, hasArtwork: track.hasArtwork,
            metadataVersion: track.metadataVersion, trackNumber: track.trackNumber,
            discNumber: track.discNumber, genre: track.genre)
    }
}
