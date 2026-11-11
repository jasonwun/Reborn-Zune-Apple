import Foundation
import SwiftData

// MARK: - Playlist

/// A user-created playlist. M8 spec says playlists live on macOS/iPadOS
/// only — tvOS skips persistence entirely (its bundle is read-only and
/// the showcase doesn't need playlist editing UI).
@Model
public final class StoredPlaylist {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \StoredPlaylistEntry.playlist)
    public var entries: [StoredPlaylistEntry]

    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = .now,
        entries: [StoredPlaylistEntry] = []
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.entries = entries
    }
}

/// One track within a playlist. References the source file via a stable
/// path-based key (`musicID`, derived deterministically from `URL.path`
/// in `Music`); on lookup the consumer matches `musicID` against current
/// `Music.id` values from the active library scan.
///
/// Stored as a separate entity (rather than e.g. an inline array of
/// strings on `StoredPlaylist`) so we can preserve insertion order and
/// support track-level metadata in the future.
@Model
public final class StoredPlaylistEntry {
    public var orderIndex: Int
    /// Legacy path-hash key (see `Music.makeID(for:)`). Kept only so old
    /// entries can be re-keyed to `trackID` on an exact current-path match.
    public var musicID: String
    /// Stable Track Identity (`StoredTrack.id`). `nil` until a legacy entry
    /// has been re-keyed by a successful Library scan.
    public var trackID: UUID?
    public var addedAt: Date
    public var playlist: StoredPlaylist?

    public init(
        orderIndex: Int,
        musicID: String,
        trackID: UUID? = nil,
        addedAt: Date = .now,
        playlist: StoredPlaylist? = nil
    ) {
        self.orderIndex = orderIndex
        self.musicID = musicID
        self.trackID = trackID
        self.addedAt = addedAt
        self.playlist = playlist
    }
}

// MARK: - App settings

/// Persisted user-level preferences. There's exactly one row of this
/// type (a singleton-by-convention); fetch with
/// `try ModelContext.first(StoredAppSettings.self)` and create one if
/// missing.
///
/// Library folder bookmark already lives in UserDefaults via
/// `LibraryFolderStore`. This entity is for future preferences that
/// don't fit there (e.g. shuffle / repeat preference, theme).
@Model
public final class StoredAppSettings {
    public var lastShufflePolicy: String
    public var lastRepeatMode: String
    public var updatedAt: Date
    /// Distinguishes first launch from an intentional zero-source Library.
    public var hasSeededLibrarySources: Bool

    public init(
        lastShufflePolicy: String = "off",
        lastRepeatMode: String = "off",
        updatedAt: Date = .now,
        hasSeededLibrarySources: Bool = false
    ) {
        self.lastShufflePolicy = lastShufflePolicy
        self.lastRepeatMode = lastRepeatMode
        self.updatedAt = updatedAt
        self.hasSeededLibrarySources = hasSeededLibrarySources
    }
}

// MARK: - Container factory

/// Constructs the application's `ModelContainer`. Call once per app and
/// pass the result via `.modelContainer(...)` to a SwiftUI `Scene`.
///
/// On tvOS the persistent store is created in the app's caches directory
/// (where SwiftData writes by default) but no app code currently
/// references the entities — the container exists so the app can grow
/// into per-device persistence later without a schema-migration cliff.
public enum RebornZunePersistence {
    public static let schema = Schema([
        StoredPlaylist.self,
        StoredPlaylistEntry.self,
        StoredAppSettings.self,
        StoredTrack.self,
        StoredTrackArtwork.self,
        StoredLibraryState.self,
        StoredLibrarySource.self,
        StoredPlayHistoryEntry.self,
        StoredTrackPlaybackStats.self
    ])

    /// In-memory container, useful for tests + previews.
    public static func makeInMemoryContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: config)
    }

    /// Persistent on-disk container at the platform default location
    /// (`Application Support/default.store` on macOS/iPadOS).
    public static func makePersistentContainer() throws -> ModelContainer {
        try ModelContainer(for: schema)
    }

    /// Persistent on-disk container at an explicit store location (tests and
    /// debug isolation).
    public static func makePersistentContainer(at url: URL) throws -> ModelContainer {
        try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
    }
}
