import Foundation
import SwiftData

/// One Library Track. Lightweight on purpose: artwork lives in
/// `StoredTrackArtwork` and is only loaded on demand, so fetching Tracks
/// never materializes image bytes.
@Model
public final class StoredTrack {
    /// Stable Track Identity. Survives same-path replacement and same-volume
    /// moves (see ADR-0009).
    @Attribute(.unique) public var id: UUID
    /// Normalized absolute file path.
    @Attribute(.unique) public var path: String
    /// Library Source root that owns this Track.
    public var sourcePath: String

    // File fingerprint: normalized path + modification date + size.
    public var modificationDate: Date
    public var fileSize: Int64
    // File-resource identity (archived `URLResourceValues` identifiers).
    public var volumeID: Data?
    public var fileID: Data?

    public var title: String
    public var artist: String?
    public var albumArtist: String?
    public var albumTitle: String?
    public var year: Int?
    public var trackNumber: Int?
    public var discNumber: Int?
    public var genre: String?
    public var duration: Double
    public var hasArtwork: Bool
    /// Version of the metadata extractor that produced the fields above.
    public var metadataVersion: Int

    @Relationship(deleteRule: .cascade, inverse: \StoredTrackArtwork.track)
    public var artwork: StoredTrackArtwork?

    public init(
        id: UUID,
        path: String,
        sourcePath: String,
        modificationDate: Date,
        fileSize: Int64,
        volumeID: Data?,
        fileID: Data?,
        title: String,
        artist: String?,
        albumArtist: String?,
        albumTitle: String?,
        year: Int?,
        trackNumber: Int? = nil,
        discNumber: Int? = nil,
        genre: String? = nil,
        duration: Double,
        hasArtwork: Bool,
        metadataVersion: Int
    ) {
        self.id = id
        self.path = path
        self.sourcePath = sourcePath
        self.modificationDate = modificationDate
        self.fileSize = fileSize
        self.volumeID = volumeID
        self.fileID = fileID
        self.title = title
        self.artist = artist
        self.albumArtist = albumArtist
        self.albumTitle = albumTitle
        self.year = year
        self.trackNumber = trackNumber
        self.discNumber = discNumber
        self.genre = genre
        self.duration = duration
        self.hasArtwork = hasArtwork
        self.metadataVersion = metadataVersion
    }
}

/// Cover art for one Track, stored outside the main store file.
@Model
public final class StoredTrackArtwork {
    @Attribute(.externalStorage) public var data: Data
    public var track: StoredTrack?

    public init(data: Data, track: StoredTrack? = nil) {
        self.data = data
        self.track = track
    }
}

/// Singleton Library bookkeeping. Identity migration and metadata extraction
/// versions are tracked independently so bumping one never re-triggers the
/// other.
@Model
public final class StoredLibraryState {
    /// 0 = legacy path-hash Playlist entries may still exist; 1 = none left.
    public var identityMigrationVersion: Int
    /// Extractor version the whole Library was last extracted with.
    public var metadataVersion: Int

    public init(identityMigrationVersion: Int = 0, metadataVersion: Int = 0) {
        self.identityMigrationVersion = identityMigrationVersion
        self.metadataVersion = metadataVersion
    }
}
