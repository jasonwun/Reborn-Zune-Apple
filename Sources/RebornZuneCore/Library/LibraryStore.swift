import Foundation
import SwiftData

public enum LibraryTrackSort: Sendable, Equatable {
    case title
    case albumTitle
    case artist
    case year
}

public struct LibraryTrackQuery: Sendable, Equatable {
    public var searchText: String?
    public var albumTitle: String?
    public var albumArtist: String?
    public var artistName: String?
    /// Matches rows whose artist and albumArtist are both absent.
    public var includeUnattributedArtist: Bool
    public var sort: LibraryTrackSort

    public init(
        searchText: String? = nil,
        albumTitle: String? = nil,
        albumArtist: String? = nil,
        artistName: String? = nil,
        includeUnattributedArtist: Bool = false,
        sort: LibraryTrackSort = .title
    ) {
        self.searchText = searchText
        self.albumTitle = albumTitle
        self.albumArtist = albumArtist
        self.artistName = artistName
        self.includeUnattributedArtist = includeUnattributedArtist
        self.sort = sort
    }
}

/// Background owner of all Library reads and writes. Hands lightweight
/// `Sendable` DTOs across the actor boundary; model objects never leave.
@ModelActor
public actor LibraryStore {
    private static let batchSize = 1000

    /// Known rows for one source, fetched in batches for reconciliation.
    public func snapshots(sourcePath: String) throws -> [TrackSnapshot] {
        var result: [TrackSnapshot] = []
        var offset = 0
        while true {
            var descriptor = FetchDescriptor<StoredTrack>(
                predicate: #Predicate { $0.sourcePath == sourcePath },
                sortBy: [SortDescriptor(\.path)])
            descriptor.fetchLimit = Self.batchSize
            descriptor.fetchOffset = offset
            let batch = try modelContext.fetch(descriptor)
            if batch.isEmpty { break }
            result.append(contentsOf: batch.map(Self.snapshot))
            offset += batch.count
            if batch.count < Self.batchSize { break }
        }
        return result
    }

    /// One deterministic, title-sorted page. The predicate and pagination are
    /// evaluated by SwiftData; artwork remains in its separate store.
    public func snapshots(
        matching query: LibraryTrackQuery,
        offset: Int,
        limit: Int
    ) throws -> [TrackSnapshot] {
        // SwiftData treats fetchLimit == 0 as unlimited, not as an empty page.
        guard limit > 0 else { return [] }
        var descriptor = trackDescriptor(matching: query)
        switch query.sort {
        case .title:
            descriptor.sortBy = [SortDescriptor(\.title), SortDescriptor(\.path)]
        case .albumTitle:
            descriptor.sortBy = [
                SortDescriptor(\.albumTitle), SortDescriptor(\.title), SortDescriptor(\.path),
            ]
        case .artist:
            descriptor.sortBy = [
                SortDescriptor(\.albumArtist), SortDescriptor(\.artist),
                SortDescriptor(\.albumTitle), SortDescriptor(\.title), SortDescriptor(\.path),
            ]
        case .year:
            descriptor.sortBy = [
                SortDescriptor(\.year, order: .reverse), SortDescriptor(\.albumTitle),
                SortDescriptor(\.title), SortDescriptor(\.path),
            ]
        }
        descriptor.fetchOffset = max(0, offset)
        descriptor.fetchLimit = max(0, limit)
        return try modelContext.fetch(descriptor).map(Self.snapshot)
    }

    public func count(matching query: LibraryTrackQuery) throws -> Int {
        try modelContext.fetchCount(trackDescriptor(matching: query))
    }

    private func trackDescriptor(matching query: LibraryTrackQuery) -> FetchDescriptor<StoredTrack> {
        let searchText = query.searchText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasSearch = !searchText.isEmpty
        let hasAlbum = query.albumTitle != nil && query.albumArtist != nil
        let albumTitle = query.albumTitle ?? ""
        let albumArtist = query.albumArtist ?? ""
        if hasAlbum {
            let unknownAlbum = albumTitle == "Unknown Album"
            let unknownArtist = albumArtist == "Unknown Artist"
            if unknownArtist || unknownAlbum {
                // Grouping applies the privileged-artist fallback after the
                // fetch, so this predicate intentionally includes every
                // artist for the requested title and lets grouping select it.
                return FetchDescriptor<StoredTrack>(predicate: #Predicate {
                    unknownAlbum
                        ? ($0.albumTitle == nil || $0.albumTitle == albumTitle)
                        : $0.albumTitle == albumTitle
                })
            }
            return FetchDescriptor<StoredTrack>(predicate: #Predicate {
                $0.albumTitle == albumTitle
                    && ($0.albumArtist == albumArtist
                        || ($0.albumArtist == nil && $0.artist == albumArtist))
            })
        }
        if query.includeUnattributedArtist {
            return FetchDescriptor<StoredTrack>(predicate: #Predicate {
                $0.albumArtist == nil && $0.artist == nil
            })
        }
        if let artistName = query.artistName {
            return FetchDescriptor<StoredTrack>(predicate: #Predicate {
                $0.albumArtist == artistName || $0.artist == artistName
            })
        }
        guard hasSearch else { return FetchDescriptor<StoredTrack>() }
        // Explicit nil checks preserve SQL translation while avoiding a
        // chain of optional method calls in each disjunct.
        return FetchDescriptor<StoredTrack>(predicate: #Predicate {
            $0.title.localizedStandardContains(searchText)
                || ($0.artist != nil && $0.artist!.localizedStandardContains(searchText))
                || ($0.albumArtist != nil && $0.albumArtist!.localizedStandardContains(searchText))
                || ($0.albumTitle != nil && $0.albumTitle!.localizedStandardContains(searchText))
                || ($0.genre != nil && $0.genre!.localizedStandardContains(searchText))
        })
    }

    /// Selected Track Identities for detail surfaces such as Playlists.
    public func snapshots(withIDs ids: [UUID]) throws -> [TrackSnapshot] {
        var result: [TrackSnapshot] = []
        for chunk in ids.chunked(500) {
            let tracks = try modelContext.fetch(FetchDescriptor<StoredTrack>(
                predicate: #Predicate { chunk.contains($0.id) },
                sortBy: [SortDescriptor(\.title), SortDescriptor(\.path)]))
            result.append(contentsOf: tracks.map(Self.snapshot))
        }
        return result
    }

    public func sourceStates() throws -> [LibrarySourceState] {
        let stored = try modelContext.fetch(FetchDescriptor<StoredLibrarySource>(
            sortBy: [SortDescriptor(\.path)]))
        return stored.map {
            LibrarySourceState(path: $0.path, bookmarkData: $0.bookmarkData,
                               isAvailable: $0.isAvailable,
                               committedTrackCount: $0.committedTrackCount)
        }
    }

    public func needsSourceSeed() throws -> Bool {
        try modelContext.fetch(FetchDescriptor<StoredAppSettings>()).first?.hasSeededLibrarySources != true
    }

    /// Seeds initial sources once. Later launches deliberately preserve zero sources.
    public func seedSourcesIfNeeded(_ initial: [LibrarySourceState]) throws {
        let settings = try modelContext.fetch(FetchDescriptor<StoredAppSettings>()).first
            ?? StoredAppSettings()
        if settings.modelContext == nil { modelContext.insert(settings) }
        guard !settings.hasSeededLibrarySources else { return }
        if try modelContext.fetch(FetchDescriptor<StoredLibrarySource>()).isEmpty {
            for source in initial {
                modelContext.insert(StoredLibrarySource(
                    path: source.path, bookmarkData: source.bookmarkData,
                    isAvailable: source.isAvailable,
                    committedTrackCount: source.committedTrackCount))
            }
        }
        settings.hasSeededLibrarySources = true
        settings.updatedAt = .now
        try modelContext.save()
    }

    public func addSource(_ source: LibrarySourceState) throws {
        modelContext.insert(StoredLibrarySource(
            path: source.path, bookmarkData: source.bookmarkData,
            isAvailable: source.isAvailable,
            committedTrackCount: source.committedTrackCount))
        do { try modelContext.save() } catch {
            modelContext.rollback()
            throw error
        }
    }

    public func updateBookmark(path: String, data: Data) throws {
        let configurations = try modelContext.fetch(FetchDescriptor<StoredLibrarySource>(
            predicate: #Predicate { $0.path == path }))
        for configuration in configurations { configuration.bookmarkData = data }
        try modelContext.save()
    }

    public func removeSource(path: String) throws {
        modelContext.autosaveEnabled = false
        do {
            let tracks = try modelContext.fetch(FetchDescriptor<StoredTrack>(
                predicate: #Predicate { $0.sourcePath == path }))
            try deleteTracksAndLinkedData(Set(tracks.map(\.id)))
            let configurations = try modelContext.fetch(FetchDescriptor<StoredLibrarySource>(
                predicate: #Predicate { $0.path == path }))
            for configuration in configurations { modelContext.delete(configuration) }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// Checks only requested identities, used to reconcile an explicit Queue
    /// after a committed deletion without fetching the whole Library.
    public func existingTrackIDs(among ids: Set<UUID>) throws -> Set<UUID> {
        var result: Set<UUID> = []
        for chunk in Array(ids).chunked(500) {
            let tracks = try modelContext.fetch(
                FetchDescriptor<StoredTrack>(predicate: #Predicate { chunk.contains($0.id) }))
            result.formUnion(tracks.map(\.id))
        }
        return result
    }

    /// Artwork bytes for the given Tracks (on demand).
    public func artwork(for ids: [UUID]) throws -> [UUID: Data] {
        var result: [UUID: Data] = [:]
        for chunk in ids.chunked(500) {
            let tracks = try modelContext.fetch(
                FetchDescriptor<StoredTrack>(predicate: #Predicate { chunk.contains($0.id) }))
            for t in tracks {
                if let data = t.artwork?.data { result[t.id] = data }
            }
        }
        return result
    }

    /// Applies one scan atomically: either every change is saved or none is.
    public func commit(
        plan: ReconciliationPlan,
        extracted: [String: ExtractedMetadata],
        sourcePath: String
    ) throws {
        try commit(scans: [LibrarySourceScan(sourcePath: sourcePath, plan: plan,
                                             extracted: extracted, isAvailable: true)])
    }

    /// Commits a complete union snapshot and all source counts in one save.
    func commit(scans: [LibrarySourceScan]) throws {
        modelContext.autosaveEnabled = false
        do {
            for scan in scans {
                try apply(scan.plan, extracted: scan.extracted, sourcePath: scan.sourcePath)
            }
            try updateCommittedSources(scans)
            try migrateLegacyEntries(scans)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func apply(_ plan: ReconciliationPlan, extracted: [String: ExtractedMetadata],
                       sourcePath: String) throws {
        // Updates to existing Tracks.
        let touched = plan.tracks.filter { $0.kind != .added && $0.needsWrite }
        var existing: [UUID: StoredTrack] = [:]
        for chunk in touched.map(\.id).chunked(500) {
            for t in try modelContext.fetch(
                FetchDescriptor<StoredTrack>(predicate: #Predicate { chunk.contains($0.id) })) {
                existing[t.id] = t
            }
        }
        // Moves can swap paths between rows; free every moving row's path first.
        for p in touched where p.kind == .moved {
            existing[p.id]?.path = "\u{0}moving-\(p.id.uuidString)"
        }
        for p in touched {
            guard let track = existing[p.id] else { continue }
            track.path = p.file.path
            track.sourcePath = sourcePath
            track.volumeID = p.file.volumeID
            track.fileID = p.file.fileID
            if p.needsExtraction, let meta = extracted[p.file.path] {
                track.modificationDate = p.file.modificationDate
                track.fileSize = p.file.fileSize
                Self.apply(meta, to: track)
            }
        }

        // New Tracks. A file whose extraction failed is skipped and retried next scan.
        for p in plan.tracks where p.kind == .added {
            guard let meta = extracted[p.file.path] else { continue }
            let track = StoredTrack(
                id: p.id, path: p.file.path, sourcePath: sourcePath,
                modificationDate: p.file.modificationDate, fileSize: p.file.fileSize,
                volumeID: p.file.volumeID, fileID: p.file.fileID,
                title: meta.title, artist: nil, albumArtist: nil, albumTitle: nil,
                year: nil, duration: 0, hasArtwork: false, metadataVersion: currentMetadataVersion)
            modelContext.insert(track)
            Self.apply(meta, to: track)
        }

        try deleteTracksAndLinkedData(Set(plan.missing))
    }

    private func deleteTracksAndLinkedData(_ missing: Set<UUID>) throws {
        guard !missing.isEmpty else { return }
        for chunk in Array(missing).chunked(500) {
            for track in try modelContext.fetch(
                FetchDescriptor<StoredTrack>(predicate: #Predicate { chunk.contains($0.id) })) {
                modelContext.delete(track)
            }
        }
        for chunk in Array(missing).chunked(500) {
            for entry in try modelContext.fetch(FetchDescriptor<StoredPlayHistoryEntry>(
                predicate: #Predicate { chunk.contains($0.trackID) })) {
                modelContext.delete(entry)
            }
            for stats in try modelContext.fetch(FetchDescriptor<StoredTrackPlaybackStats>(
                predicate: #Predicate { chunk.contains($0.trackID) })) {
                modelContext.delete(stats)
            }
        }
        let linked = try modelContext.fetch(
            FetchDescriptor<StoredPlaylistEntry>(predicate: #Predicate { $0.trackID != nil }))
        for entry in linked {
            if let id = entry.trackID, missing.contains(id) { modelContext.delete(entry) }
        }
    }

    private func updateCommittedSources(_ scans: [LibrarySourceScan]) throws {
        let stored = try modelContext.fetch(FetchDescriptor<StoredLibrarySource>())
        let byPath = Dictionary(uniqueKeysWithValues: stored.map { ($0.path, $0) })
        for scan in scans {
            guard let source = byPath[scan.sourcePath] else { continue }
            source.isAvailable = scan.isAvailable
            source.committedTrackCount = scan.isAvailable
                ? scan.plan.tracks.filter {
                    $0.kind != .added || scan.extracted[$0.file.path] != nil
                }.count
                : 0
        }
    }

    private func migrateLegacyEntries(_ scans: [LibrarySourceScan]) throws {
        let state = try libraryState()
        let legacy = try modelContext.fetch(
            FetchDescriptor<StoredPlaylistEntry>(predicate: #Predicate { $0.trackID == nil }))
        if !legacy.isEmpty {
            var byHash: [String: UUID] = [:]
            var deferred = Set<String>()
            for scan in scans {
                for p in scan.plan.tracks {
                    let paths = p.file.rawPath == p.file.path
                        ? [p.file.path] : [p.file.path, p.file.rawPath]
                    let exists = p.kind != .added || scan.extracted[p.file.path] != nil
                    for path in paths {
                        let hash = Music.legacyID(forPath: path)
                        if exists { byHash[hash] = p.id } else { deferred.insert(hash) }
                    }
                }
            }
            for entry in legacy {
                if let id = byHash[entry.musicID] {
                    entry.trackID = id
                } else if !deferred.contains(entry.musicID) {
                    modelContext.delete(entry)
                }
            }
            if !legacy.contains(where: { $0.trackID == nil && !$0.isDeleted }) {
                state.identityMigrationVersion = max(state.identityMigrationVersion, 1)
            }
        } else {
            state.identityMigrationVersion = max(state.identityMigrationVersion, 1)
        }
        state.metadataVersion = currentMetadataVersion
    }

    private func libraryState() throws -> StoredLibraryState {
        if let s = try modelContext.fetch(FetchDescriptor<StoredLibraryState>()).first { return s }
        let s = StoredLibraryState()
        modelContext.insert(s)
        return s
    }

    private static func apply(_ meta: ExtractedMetadata, to track: StoredTrack) {
        track.title = meta.title
        track.artist = meta.artist
        track.albumArtist = meta.albumArtist
        track.albumTitle = meta.albumTitle
        track.year = meta.year
        track.trackNumber = meta.trackNumber
        track.discNumber = meta.discNumber
        track.genre = meta.genre
        track.duration = meta.duration
        track.metadataVersion = currentMetadataVersion
        if let data = meta.artworkData {
            if let art = track.artwork { art.data = data } else { track.artwork = StoredTrackArtwork(data: data) }
            track.hasArtwork = true
        } else {
            track.artwork = nil
            track.hasArtwork = false
        }
    }

    private static func snapshot(_ t: StoredTrack) -> TrackSnapshot {
        TrackSnapshot(
            id: t.id, path: t.path, sourcePath: t.sourcePath,
            modificationDate: t.modificationDate, fileSize: t.fileSize,
            volumeID: t.volumeID, fileID: t.fileID, title: t.title, artist: t.artist,
            albumArtist: t.albumArtist, albumTitle: t.albumTitle, year: t.year,
            duration: t.duration, hasArtwork: t.hasArtwork, metadataVersion: t.metadataVersion,
            trackNumber: t.trackNumber, discNumber: t.discNumber, genre: t.genre)
    }
}

extension Array {
    func chunked(_ size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
