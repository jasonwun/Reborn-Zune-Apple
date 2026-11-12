import Foundation
import SwiftData

/// Directly queryable album-level Artist search record. Artists without an
/// owned Album are never emitted by the search-index builder.
@Model
public final class StoredArtist {
    @Attribute(.unique) public var id: String
    public var name: String
    public var albumCount: Int
    public var genre: String?
    public var nameSearchKey: String
    public var searchDocumentKey: String
    public var searchNormalizationVersion: Int

    public init(id: String, name: String, albumCount: Int, genre: String?,
                nameSearchKey: String, searchDocumentKey: String,
                searchNormalizationVersion: Int) {
        self.id = id
        self.name = name
        self.albumCount = albumCount
        self.genre = genre
        self.nameSearchKey = nameSearchKey
        self.searchDocumentKey = searchDocumentKey
        self.searchNormalizationVersion = searchNormalizationVersion
    }
}

/// Album search record with display metadata and independent matching fields.
/// Track Artists and genres remain separate keys so exact/prefix/substring
/// scores are calculated per real field rather than across a concatenation.
@Model
public final class StoredAlbum {
    @Attribute(.unique) public var id: String
    public var title: String
    public var albumArtist: String
    public var year: Int?
    public var genre: String?
    public var artworkTrackID: UUID?
    public var trackArtists: [String]
    public var genres: [String]
    public var titleSearchKey: String
    public var albumArtistSearchKey: String
    public var trackArtistSearchKeys: [String]
    public var genreSearchKeys: [String]
    public var searchDocumentKey: String
    public var searchNormalizationVersion: Int

    public init(id: String, title: String, albumArtist: String, year: Int?, genre: String?,
                artworkTrackID: UUID? = nil, trackArtists: [String], genres: [String], titleSearchKey: String,
                albumArtistSearchKey: String, trackArtistSearchKeys: [String],
                genreSearchKeys: [String], searchDocumentKey: String,
                searchNormalizationVersion: Int) {
        self.id = id
        self.title = title
        self.albumArtist = albumArtist
        self.year = year
        self.genre = genre
        self.artworkTrackID = artworkTrackID
        self.trackArtists = trackArtists
        self.genres = genres
        self.titleSearchKey = titleSearchKey
        self.albumArtistSearchKey = albumArtistSearchKey
        self.trackArtistSearchKeys = trackArtistSearchKeys
        self.genreSearchKeys = genreSearchKeys
        self.searchDocumentKey = searchDocumentKey
        self.searchNormalizationVersion = searchNormalizationVersion
    }
}
