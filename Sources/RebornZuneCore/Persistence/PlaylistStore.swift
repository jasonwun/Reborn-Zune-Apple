import Foundation
import SwiftData

public enum PlaylistEntryOrdering {
    public static func sorted(_ entries: [StoredPlaylistEntry]) -> [StoredPlaylistEntry] {
        entries.sorted { lhs, rhs in
            if lhs.orderIndex != rhs.orderIndex { return lhs.orderIndex < rhs.orderIndex }
            if lhs.addedAt != rhs.addedAt { return lhs.addedAt < rhs.addedAt }
            return lhs.entryID.uuidString < rhs.entryID.uuidString
        }
    }
}

public struct PlaylistResolvedEntry: Identifiable {
    public let entry: StoredPlaylistEntry
    public let track: Music
    public var id: UUID { entry.entryID }

    public init(entry: StoredPlaylistEntry, track: Music) {
        self.entry = entry
        self.track = track
    }
}

public enum PlaylistStoreError: Error, Equatable {
    case emptyName
}

/// Public persistence behavior for manual Playlists.
@MainActor
public final class PlaylistStore {
    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    @discardableResult
    public func createPlaylist(named name: String) throws -> StoredPlaylist {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw PlaylistStoreError.emptyName }
        let playlist = StoredPlaylist(name: trimmedName)
        modelContext.insert(playlist)
        try modelContext.save()
        return playlist
    }

    public func renamePlaylist(_ playlist: StoredPlaylist, to name: String) throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw PlaylistStoreError.emptyName }
        playlist.name = trimmedName
        try modelContext.save()
    }

    public func deletePlaylist(_ playlist: StoredPlaylist) throws {
        modelContext.delete(playlist)
        try modelContext.save()
    }

    @discardableResult
    public func addTracks(_ trackIDs: [String], to playlist: StoredPlaylist) throws -> [StoredPlaylistEntry] {
        normalizeOrder(for: playlist)
        let startIndex = orderedEntries(for: playlist).count
        let added = trackIDs.enumerated().map { offset, trackID in
            StoredPlaylistEntry(
                orderIndex: startIndex + offset,
                musicID: trackID,
                trackID: UUID(uuidString: trackID),
                playlist: playlist)
        }
        added.forEach(modelContext.insert)
        normalizeOrder(for: playlist)
        try modelContext.save()
        return added
    }

    public func removeEntry(_ entry: StoredPlaylistEntry, from playlist: StoredPlaylist) throws {
        modelContext.delete(entry)
        normalizeOrder(for: playlist)
        try modelContext.save()
    }

    public func moveEntry(_ entry: StoredPlaylistEntry, to destination: Int,
                          in playlist: StoredPlaylist) throws {
        var entries = orderedEntries(for: playlist)
        guard let source = entries.firstIndex(where: { $0.entryID == entry.entryID }) else { return }
        entries.remove(at: source)
        entries.insert(entry, at: max(0, min(destination, entries.count)))
        for (index, entry) in entries.enumerated() { entry.orderIndex = index }
        try modelContext.save()
    }

    /// Deterministic manual order, including malformed legacy rows.
    public func orderedEntries(for playlist: StoredPlaylist) -> [StoredPlaylistEntry] {
        PlaylistEntryOrdering.sorted(playlist.entries.filter { !$0.isDeleted })
    }

    public func resolvedEntries(for playlist: StoredPlaylist,
                                tracks: [Music]) -> [PlaylistResolvedEntry] {
        let tracksByID = Dictionary(tracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return orderedEntries(for: playlist).compactMap { entry in
            guard let track = tracksByID[entry.resolvedTrackID] else { return nil }
            return PlaylistResolvedEntry(entry: entry, track: track)
        }
    }

    private func normalizeOrder(for playlist: StoredPlaylist) {
        for (index, entry) in orderedEntries(for: playlist).enumerated() {
            entry.orderIndex = index
        }
    }
}
