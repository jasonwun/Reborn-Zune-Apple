import Foundation
import Observation
import SwiftData

/// Runs one incremental scan: discover → reconcile → extract changed files →
/// commit atomically. Any throw leaves the committed Library untouched.
public enum LibraryScanner {
    public static let maxConcurrentExtractions = 8

    public static func scan(source: any LibraryFileSource, store: LibraryStore) async throws {
        let sourcePath = source.sourcePath
        let known = try await store.snapshots().filter { $0.sourcePath == sourcePath }
        let discovered = try await source.discover()
        try Task.checkCancellation()

        let plan = LibraryReconciler.plan(known: known, discovered: discovered)
        let extracted = try await extract(plan.tracks.filter(\.needsExtraction).map(\.file), from: source)
        try Task.checkCancellation()

        try await store.commit(plan: plan, extracted: extracted, sourcePath: sourcePath)
    }

    private static func extract(_ files: [DiscoveredFile], from source: any LibraryFileSource)
        async throws -> [String: ExtractedMetadata]
    {
        try await withThrowingTaskGroup(of: (String, ExtractedMetadata?).self) { group in
            var results: [String: ExtractedMetadata] = [:]
            results.reserveCapacity(files.count)
            var index = 0

            func addNext() {
                let file = files[index]
                index += 1
                group.addTask {
                    try Task.checkCancellation()
                    do { return (file.path, try await source.extract(file)) }
                    catch is CancellationError { throw CancellationError() }
                    catch { return (file.path, nil) }
                }
            }
            while index < files.count && index < maxConcurrentExtractions { addNext() }
            while let (path, meta) = try await group.next() {
                if let meta { results[path] = meta }
                if index < files.count { addNext() }
            }
            return results
        }
    }
}

/// Shared Library coordination: owns the persisted Library, runs scans, and
/// publishes the committed state that hosts render.
@MainActor
@Observable
public final class LibraryCoordinator {
    public enum Phase: Equatable, Sendable {
        /// First scan in progress and nothing committed yet.
        case loading
        /// A Library with at least one Track is available.
        case ready
        /// A scan succeeded and found no supported audio.
        case empty
        /// No committed Library and the latest scan failed.
        case failed
    }

    public private(set) var phase: Phase = .loading
    public private(set) var tracks: [Music] = []
    /// Message from the latest failed scan; cleared when a scan starts.
    public private(set) var scanError: String?
    public private(set) var isScanning = false
    public let sourcePath: String

    @ObservationIgnored private let store: LibraryStore
    @ObservationIgnored private let source: any LibraryFileSource
    @ObservationIgnored private var started = false
    @ObservationIgnored private var scanTask: Task<Void, Never>?

    public init(container: ModelContainer, source: any LibraryFileSource) {
        self.store = LibraryStore(modelContainer: container)
        self.source = source
        self.sourcePath = source.sourcePath
    }

    /// Shows the committed Library immediately, then refreshes incrementally.
    public func start() async {
        guard !started else { return }
        started = true
        await publishCommitted()
        await refresh()
    }

    /// Runs one serialized incremental scan. A request while one is running
    /// waits for that scan rather than starting another.
    public func refresh() async {
        if let running = scanTask { await running.value; return }
        isScanning = true
        scanError = nil
        let store = store, source = source
        let task = Task { [weak self] in
            do {
                try await LibraryScanner.scan(source: source, store: store)
                await self?.publishCommitted()
            } catch is CancellationError {
                self?.scanError = "The scan was interrupted. Your Library is unchanged."
            } catch {
                self?.scanError = error.localizedDescription
            }
            self?.finishScan()
        }
        scanTask = task
        await task.value
    }

    public func retry() async { await refresh() }

    public func cancelScan() { scanTask?.cancel() }

    private func finishScan() {
        isScanning = false
        scanTask = nil
        updatePhase(scanSucceeded: scanError == nil)
    }

    private func updatePhase(scanSucceeded: Bool) {
        if !tracks.isEmpty { phase = .ready }
        else if scanSucceeded { phase = .empty }
        else { phase = .failed }
    }

    private func publishCommitted() async {
        guard let snapshots = try? await store.snapshots() else { return }
        let ids = Self.artworkRepresentatives(snapshots)
        let artwork = (try? await store.artwork(for: ids)) ?? [:]
        let built = await Self.buildMusic(snapshots, artwork: artwork)
        tracks = built
        if !built.isEmpty { phase = .ready }
    }

    /// One artwork-bearing Track per album; its bytes are shared by every
    /// Track of that album so memory stays proportional to album count.
    nonisolated static func artworkRepresentatives(_ snapshots: [TrackSnapshot]) -> [UUID] {
        var seen = Set<String>()
        var ids: [UUID] = []
        for s in snapshots where s.hasArtwork {
            if seen.insert(albumKey(s)).inserted { ids.append(s.id) }
        }
        return ids
    }

    nonisolated private static func albumKey(_ s: TrackSnapshot) -> String {
        "\(s.albumTitle ?? "")\u{0}\(s.albumArtist ?? s.artist ?? "")"
    }

    nonisolated private static func buildMusic(_ snapshots: [TrackSnapshot], artwork: [UUID: Data])
        async -> [Music]
    {
        var byAlbum: [String: Data] = [:]
        let repIDs = Set(artwork.keys)
        for s in snapshots where repIDs.contains(s.id) {
            if let d = artwork[s.id] { byAlbum[albumKey(s)] = d }
        }
        let music = snapshots.map { s in
            Music(id: s.id.uuidString, url: URL(fileURLWithPath: s.path), title: s.title,
                  artist: s.artist, albumArtist: s.albumArtist, albumTitle: s.albumTitle,
                  year: s.year, duration: s.duration, artworkData: byAlbum[albumKey(s)])
        }
        return music.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
}
