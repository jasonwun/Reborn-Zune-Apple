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
        modelContext.autosaveEnabled = false
        do {
            try apply(plan: plan, extracted: extracted, sourcePath: sourcePath)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func apply(plan: ReconciliationPlan, extracted: [String: ExtractedMetadata],
                       sourcePath: String) throws {
        let state = try libraryState()

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

        // Confirmed-missing cleanup: Tracks and their Playlist references.
        let missing = Set(plan.missing)
        if !missing.isEmpty {
            for chunk in plan.missing.chunked(500) {
                for t in try modelContext.fetch(
                    FetchDescriptor<StoredTrack>(predicate: #Predicate { chunk.contains($0.id) })) {
                    modelContext.delete(t)
                }
            }
            let linked = try modelContext.fetch(
                FetchDescriptor<StoredPlaylistEntry>(predicate: #Predicate { $0.trackID != nil }))
            for entry in linked {
                if let id = entry.trackID, missing.contains(id) { modelContext.delete(entry) }
            }
        }

        // Legacy path-hash re-keying: exact current-path matches only, and only
        // to Tracks that really exist. A current file whose extraction failed
        // is left untouched so a later scan can still re-key it.
        let legacy = try modelContext.fetch(
            FetchDescriptor<StoredPlaylistEntry>(predicate: #Predicate { $0.trackID == nil }))
        if !legacy.isEmpty {
            var byHash: [String: UUID] = [:]
            var deferred = Set<String>()
            for p in plan.tracks {
                let paths = p.file.rawPath == p.file.path ? [p.file.path] : [p.file.path, p.file.rawPath]
                let exists = p.kind != .added || extracted[p.file.path] != nil
                for path in paths {
                    let hash = Music.legacyID(forPath: path)
                    if exists { byHash[hash] = p.id } else { deferred.insert(hash) }
                }
            }
            for entry in legacy {
                if let id = byHash[entry.musicID] {
                    entry.trackID = id
                } else if !deferred.contains(entry.musicID) {
                    // Successful scan, no current path matches: confirmed missing.
                    modelContext.delete(entry)
                }
            }
            if legacy.contains(where: { $0.trackID == nil && !$0.isDeleted }) == false {
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
