import Foundation
import SwiftData

public struct PlayHistoryEntry: Equatable, Sendable {
    public let id: UUID
    public let trackID: UUID
    public let startedAt: Date
    public let qualifiedAt: Date?
}

public struct TrackPlaybackStats: Equatable, Sendable {
    public let trackID: UUID
    public let playCount: Int
    public let lastPlayedAt: Date
}

/// Records explicit playback transitions and resolves persisted listening
/// history against the currently available Library.
@MainActor
public final class PlayHistory {
    private static let retentionLimit = 500

    private let modelContext: ModelContext
    private let now: () -> Date

    public init(container: ModelContainer, now: @escaping () -> Date = Date.init) {
        self.modelContext = ModelContext(container)
        self.now = now
    }

    public func record(_ signal: PlaybackSignal) throws {
        switch signal {
        case .start(let id, let rawTrackID, _):
            guard let trackID = UUID(uuidString: rawTrackID) else { return }
            let startedAt = now()
            modelContext.insert(StoredPlayHistoryEntry(id: id, trackID: trackID, startedAt: startedAt))
            let stats = try stats(for: trackID)
                ?? StoredTrackPlaybackStats(trackID: trackID, lastPlayedAt: startedAt)
            if stats.modelContext == nil { modelContext.insert(stats) }
            stats.lastPlayedAt = startedAt
            try pruneHistory()
            try modelContext.save()
        case .activePlayback(let id, let rawTrackID, let elapsed, let duration):
            guard let trackID = UUID(uuidString: rawTrackID),
                  let entry = try modelContext.fetch(FetchDescriptor<StoredPlayHistoryEntry>(
                    predicate: #Predicate { $0.id == id })).first,
                  entry.trackID == trackID,
                  entry.qualifiedAt == nil,
                  elapsed >= (duration.map { min(30, $0 * 0.5) } ?? 30),
                  let stats = try stats(for: trackID) else { return }
            entry.qualifiedAt = now()
            stats.playCount += 1
            try modelContext.save()
        case .load, .resume, .seek:
            return
        }
    }

    private func stats(for trackID: UUID) throws -> StoredTrackPlaybackStats? {
        try modelContext.fetch(FetchDescriptor<StoredTrackPlaybackStats>(
            predicate: #Predicate { $0.trackID == trackID })).first
    }

    private func sortedHistory() throws -> [StoredPlayHistoryEntry] {
        try modelContext.fetch(FetchDescriptor<StoredPlayHistoryEntry>())
            .sorted { ($0.startedAt, $0.id.uuidString) > ($1.startedAt, $1.id.uuidString) }
    }

    private func pruneHistory() throws {
        for entry in try sortedHistory().dropFirst(Self.retentionLimit) { modelContext.delete(entry) }
    }

    /// Latest-start-first history snapshots.
    public func historyEntries() throws -> [PlayHistoryEntry] {
        try sortedHistory().map { PlayHistoryEntry(id: $0.id, trackID: $0.trackID,
                                                   startedAt: $0.startedAt, qualifiedAt: $0.qualifiedAt) }
    }

    /// Resolves up to ten latest distinct Tracks directly from the committed Library,
    /// independently of which browsing page the host has currently loaded.
    public func recentTracks() throws -> [Music] {
        var seen = Set<UUID>()
        let ids = try historyEntries().compactMap { entry in
            seen.insert(entry.trackID).inserted ? entry.trackID : nil
        }
        guard !ids.isEmpty else { return [] }

        var available: [UUID: StoredTrack] = [:]
        for chunk in ids.chunked(500) {
            let tracks = try modelContext.fetch(FetchDescriptor<StoredTrack>(
                predicate: #Predicate { chunk.contains($0.id) }))
            for track in tracks { available[track.id] = track }
        }
        return ids.compactMap { available[$0] }.prefix(10).map { track in
            Music(id: track.id.uuidString, url: URL(fileURLWithPath: track.path), title: track.title,
                  artist: track.artist, albumArtist: track.albumArtist, albumTitle: track.albumTitle,
                  year: track.year, trackNumber: track.trackNumber, discNumber: track.discNumber,
                  genre: track.genre, duration: track.duration, artworkData: track.artwork?.data)
        }
    }

    /// Up to ten latest distinct available Tracks, with repeats moved to the front.
    public func recentTracks(from availableTracks: [Music]) throws -> [Music] {
        let available = Dictionary(uniqueKeysWithValues: availableTracks.map { ($0.id, $0) })
        var seen = Set<UUID>()
        var result: [Music] = []
        for entry in try historyEntries() where seen.insert(entry.trackID).inserted {
            if let track = available[entry.trackID.uuidString] { result.append(track) }
            if result.count == 10 { break }
        }
        return result
    }

    public func playbackStats() throws -> [TrackPlaybackStats] {
        try modelContext.fetch(FetchDescriptor<StoredTrackPlaybackStats>())
            .sorted { $0.trackID.uuidString < $1.trackID.uuidString }
            .map { TrackPlaybackStats(trackID: $0.trackID, playCount: $0.playCount,
                                      lastPlayedAt: $0.lastPlayedAt) }
    }
}
