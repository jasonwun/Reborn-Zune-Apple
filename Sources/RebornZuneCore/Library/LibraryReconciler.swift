import Foundation

/// A persisted Track as seen by the reconciler (no artwork).
public struct TrackSnapshot: Sendable, Equatable {
    public var id: UUID
    public var path: String
    public var sourcePath: String
    public var modificationDate: Date
    public var fileSize: Int64
    public var volumeID: Data?
    public var fileID: Data?
    public var title: String
    public var artist: String?
    public var albumArtist: String?
    public var albumTitle: String?
    public var year: Int?
    public var duration: Double
    public var hasArtwork: Bool
    public var metadataVersion: Int
}

/// What a scan decided for one file.
public struct PlannedTrack: Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case retained, moved, added }
    public var id: UUID
    public var file: DiscoveredFile
    public var kind: Kind
    /// True when AVFoundation extraction must run for this file.
    public var needsExtraction: Bool
    /// True when the stored row must be rewritten (extraction, move, or a
    /// changed file-resource identity at the same path).
    public var needsWrite: Bool
}

public struct ReconciliationPlan: Sendable, Equatable {
    public var tracks: [PlannedTrack]
    /// Previously known Tracks with no counterpart in the scan.
    public var missing: [UUID]
}

/// Pure identity logic (ADR-0009): decides which discovered file is which
/// Track, with no I/O.
public enum LibraryReconciler {
    public static func plan(
        known: [TrackSnapshot],
        discovered: [DiscoveredFile],
        forceExtraction: Bool = false,
        makeID: () -> UUID = UUID.init
    ) -> ReconciliationPlan {
        // Defensive: one entry per normalized path.
        var seen = Set<String>()
        let files = discovered.filter { seen.insert($0.path).inserted }

        let knownByPath = Dictionary(known.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
        let discoveredPaths = Set(files.map(\.path))

        var tracks: [PlannedTrack] = []
        var newFiles: [DiscoveredFile] = []

        for file in files {
            if let old = knownByPath[file.path] {
                let unchanged = old.modificationDate == file.modificationDate
                    && old.fileSize == file.fileSize
                    && old.metadataVersion >= currentMetadataVersion
                tracks.append(PlannedTrack(
                    id: old.id, file: file, kind: .retained,
                    needsExtraction: forceExtraction || !unchanged,
                    needsWrite: forceExtraction || !unchanged
                        || old.volumeID != file.volumeID || old.fileID != file.fileID))
            } else {
                newFiles.append(file)
            }
        }
        let disappeared = known.filter { !discoveredPaths.contains($0.path) }

        // Move matching: strictly one-to-one on (volume, file identity) among
        // unmatched new paths and disappeared paths only.
        struct Key: Hashable { let volume: Data; let file: Data }
        func key(volume: Data?, file: Data?) -> Key? {
            guard let volume, let file else { return nil }
            return Key(volume: volume, file: file)
        }
        var newByKey: [Key: [DiscoveredFile]] = [:]
        for f in newFiles { if let k = key(volume: f.volumeID, file: f.fileID) { newByKey[k, default: []].append(f) } }
        var goneByKey: [Key: [TrackSnapshot]] = [:]
        for t in disappeared { if let k = key(volume: t.volumeID, file: t.fileID) { goneByKey[k, default: []].append(t) } }

        var movedPaths = Set<String>()
        var movedIDs = Set<UUID>()
        for (k, news) in newByKey {
            guard news.count == 1, let gone = goneByKey[k], gone.count == 1 else { continue }
            let old = gone[0], file = news[0]
            let unchanged = old.modificationDate == file.modificationDate
                && old.fileSize == file.fileSize
                && old.metadataVersion >= currentMetadataVersion
            tracks.append(PlannedTrack(
                id: old.id, file: file, kind: .moved,
                needsExtraction: forceExtraction || !unchanged,
                needsWrite: true))
            movedPaths.insert(file.path)
            movedIDs.insert(old.id)
        }

        for file in newFiles where !movedPaths.contains(file.path) {
            tracks.append(PlannedTrack(id: makeID(), file: file, kind: .added, needsExtraction: true, needsWrite: true))
        }
        let missing = disappeared.map(\.id).filter { !movedIDs.contains($0) }
        return ReconciliationPlan(tracks: tracks, missing: missing)
    }
}
