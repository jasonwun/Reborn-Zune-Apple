import Foundation
import Observation
import SwiftData

struct LibrarySourceScan: Sendable {
    let sourcePath: String
    let plan: ReconciliationPlan
    let extracted: [String: ExtractedMetadata]
    let isAvailable: Bool
}

/// Discovers every source before assigning identities, then commits all results
/// in one save. Any failed or cancelled scan leaves the committed union untouched.
public enum LibraryScanner {
    public static let maxConcurrentExtractions = 8

    public static func scan(source: any LibraryFileSource, store: LibraryStore) async throws {
        let scans = try await prepare(sources: [source], store: store)
        try await store.commit(scans: scans)
    }

    static func prepare(sources: [any LibraryFileSource], store: LibraryStore,
                        progress: @MainActor (Int) -> Void = { _ in }) async throws -> [LibrarySourceScan] {
        let known = try await store.snapshots()
        var discoveredBySource: [(source: any LibraryFileSource, files: [DiscoveredFile], available: Bool)] = []
        var uniquePaths = Set<String>()

        for source in sources {
            do {
                let discovered = try await source.discover()
                try Task.checkCancellation()
                let unique = discovered.compactMap { file -> DiscoveredFile? in
                    var normalized = file
                    normalized.path = LibrarySourcePath.normalize(file.url)
                    guard uniquePaths.insert(normalized.path).inserted else { return nil }
                    return normalized
                }
                discoveredBySource.append((source, unique, true))
                await progress(uniquePaths.count)
            } catch let error as LibraryScanError {
                guard case .sourceUnavailable = error else { throw error }
                discoveredBySource.append((source, [], false))
            }
        }

        var scans: [LibrarySourceScan] = []
        for entry in discoveredBySource {
            try Task.checkCancellation()
            let sourceKnown = known.filter { $0.sourcePath == entry.source.sourcePath }
            let plan = LibraryReconciler.plan(known: sourceKnown, discovered: entry.files)
            let extracted = entry.available
                ? try await extract(plan.tracks.filter(\.needsExtraction).map(\.file), from: entry.source)
                : [:]
            try Task.checkCancellation()
            scans.append(LibrarySourceScan(sourcePath: entry.source.sourcePath, plan: plan,
                                           extracted: extracted, isAvailable: entry.available))
        }
        return scans
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
    public private(set) var discoveredTrackCount = 0
    public private(set) var sourcePath = ""
    public private(set) var sources: [LibrarySourceState] = []

    @ObservationIgnored private let store: LibraryStore
    @ObservationIgnored private let initialSources: [any LibraryFileSource]
    @ObservationIgnored private let sourceFactory: @Sendable (URL) -> any LibraryFileSource
    @ObservationIgnored private let bookmarkAccess: any LibraryBookmarkAccessing
    @ObservationIgnored private var activeSources: [any LibraryFileSource] = []
    @ObservationIgnored private var started = false
    @ObservationIgnored private var scanTask: Task<Void, Never>?

    public init(container: ModelContainer, source: any LibraryFileSource) {
        self.store = LibraryStore(modelContainer: container)
        self.initialSources = [source]
        self.sourceFactory = { FolderFileSource(root: $0) }
        self.bookmarkAccess = NoLibraryBookmarkAccess()
        self.sourcePath = source.sourcePath
    }

    public init(container: ModelContainer, sources: [any LibraryFileSource],
                sourceFactory: @escaping @Sendable (URL) -> any LibraryFileSource = { FolderFileSource(root: $0) },
                bookmarkAccess: any LibraryBookmarkAccessing = SystemLibraryBookmarkAccess()) {
        self.store = LibraryStore(modelContainer: container)
        self.initialSources = sources
        self.sourceFactory = sourceFactory
        self.bookmarkAccess = bookmarkAccess
        self.sourcePath = sources.first?.sourcePath ?? ""
    }

    /// Shows the committed Library immediately, then refreshes incrementally.
    public func start() async {
        guard !started else { return }
        started = true
        await loadSources()
        await publishCommitted()
        await refresh()
    }

    /// Runs one serialized incremental scan. A request while one is running
    /// waits for that scan rather than starting another.
    public func refresh() async {
        if let running = scanTask { await running.value; return }
        isScanning = true
        discoveredTrackCount = 0
        scanError = nil
        let store = store, sources = activeSources
        let task = Task { [weak self] in
            do {
                let scans = try await LibraryScanner.prepare(sources: sources, store: store) { count in
                    self?.updateDiscoveredCount(count)
                }
                try await store.commit(scans: scans)
                await self?.publishCommitted()
            } catch is CancellationError {
                self?.scanError = "The scan was interrupted. Your Library is unchanged."
            } catch {
                self?.scanError = error.localizedDescription
            }
            await self?.loadSources()
            self?.finishScan()
        }
        scanTask = task
        await task.value
    }

    public func addSource(_ root: URL) async throws {
        let candidate = LibrarySourcePath.normalize(root)
        if let conflict = LibrarySourcePath.conflict(for: candidate, among: sources.map(\.path)) {
            throw LibrarySourceError.overlappingSource(candidate: candidate, conflict: conflict)
        }
        let bookmark = try bookmarkAccess.createBookmark(for: root)
        try await store.addSource(LibrarySourceState(path: candidate, bookmarkData: bookmark))
        await loadSources()
        await refresh()
    }

    public func removeSource(_ path: String) async throws {
        if let running = scanTask {
            running.cancel()
            await running.value
        }
        try await store.removeSource(path: path)
        await loadSources()
        await publishCommitted()
        updatePhase(scanSucceeded: true)
    }

    public func retry() async { await refresh() }

    public func cancelScan() { scanTask?.cancel() }

    private func updateDiscoveredCount(_ count: Int) {
        discoveredTrackCount = count
    }

    private func loadSources() async {
        do {
            if try await store.needsSourceSeed() {
                let initialStates = try initialSources.map {
                    LibrarySourceState(path: $0.sourcePath,
                                       bookmarkData: try bookmarkAccess.createBookmark(
                                        for: URL(fileURLWithPath: $0.sourcePath)))
                }
                try await store.seedSourcesIfNeeded(initialStates)
            }
            var states = try await store.sourceStates()
            for state in states where state.bookmarkData == nil {
                let bookmark = try bookmarkAccess.createBookmark(for: URL(fileURLWithPath: state.path))
                try await store.updateBookmark(path: state.path, data: bookmark)
            }
            states = try await store.sourceStates()
            sources = states
            sourcePath = states.first?.path ?? ""
            let store = store
            activeSources = try states.map { state in
                guard let bookmark = state.bookmarkData else {
                    throw LibraryBookmarkError.accessDenied(state.path)
                }
                let injected = initialSources.first { $0.sourcePath == state.path }
                let factory = sourceFactory
                return BookmarkedFileSource(
                    sourcePath: state.path, bookmark: bookmark, access: bookmarkAccess,
                    makeSource: { url in injected ?? factory(url) },
                    persistBookmark: { data in
                        try? await store.updateBookmark(path: state.path, data: data)
                    })
            }
        } catch {
            scanError = "Your Library Sources could not be loaded: \(error.localizedDescription)"
        }
    }

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
        let snapshots: [TrackSnapshot]
        do { snapshots = try await store.snapshots() } catch {
            scanError = "Your Library could not be loaded: \(error.localizedDescription)"
            return
        }
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
