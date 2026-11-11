import Foundation
import SwiftData

/// Background owner of all Library reads and writes. Hands lightweight
/// `Sendable` DTOs across the actor boundary; model objects never leave.
@ModelActor
public actor LibraryStore {
    private static let batchSize = 1000

    /// All committed Tracks, fetched in batches. Artwork is never touched.
    public func snapshots() throws -> [TrackSnapshot] {
        var result: [TrackSnapshot] = []
        var offset = 0
        while true {
            var descriptor = FetchDescriptor<StoredTrack>(sortBy: [SortDescriptor(\.path)])
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
            duration: t.duration, hasArtwork: t.hasArtwork, metadataVersion: t.metadataVersion)
    }
}

extension Array {
    func chunked(_ size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
