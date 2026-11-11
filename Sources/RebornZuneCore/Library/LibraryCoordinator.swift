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
            let known = try await store.snapshots(sourcePath: entry.source.sourcePath)
            let plan = LibraryReconciler.plan(known: known, discovered: entry.files)
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
    private static let pageSize = 100

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
    /// Tracks loaded explicitly for the current browsing window. Launch never
    /// materializes pages beyond `pageSize`.
    public private(set) var tracks: [Music] = []
    public private(set) var totalTrackCount = 0
    public private(set) var hasMoreTracks = false
    /// Changes only after a committed scan or source removal, never for a
    /// browsing predicate or pagination change.
    public private(set) var committedRevision = 0
    @ObservationIgnored private var isLoadingPage = false
    @ObservationIgnored private var browseQuery = LibraryTrackQuery()
    @ObservationIgnored private var browseRevision = 0
    /// Message from the latest failed scan; cleared when a scan starts.
    public private(set) var scanError: String?
    public private(set) var isScanning = false
    public private(set) var discoveredTrackCount = 0
    public private(set) var sourcePath = ""
    public private(set) var sources: [LibrarySourceState] = []
    /// Sources whose saved bookmark was denied or which still need an Open Panel grant.
    public private(set) var sourcePathsRequiringAuthorization: Set<String> = []

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
        sourcePathsRequiringAuthorization.removeAll()
        let store = store, sources = activeSources
        let task = Task { [weak self] in
            do {
                let scans = try await LibraryScanner.prepare(sources: sources, store: store) { count in
                    self?.updateDiscoveredCount(count)
                }
                try await store.commit(scans: scans)
                await self?.noteCommittedChange()
                await self?.publishCommitted()
            } catch is CancellationError {
                self?.scanError = "The scan was interrupted. Your Library is unchanged."
            } catch LibraryBookmarkError.accessDenied(let path) {
                self?.sourcePathsRequiringAuthorization.insert(path)
                self?.scanError = LibraryBookmarkError.accessDenied(path).localizedDescription
            } catch LibraryScanError.incompleteEnumeration(let path) {
                self?.sourcePathsRequiringAuthorization.insert(path)
                self?.scanError = LibraryScanError.incompleteEnumeration(path).localizedDescription
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

    /// Starts a playback-owned security scope using the bookmark of the source
    /// that owns this file. The caller must stop the returned session.
    public func startPlaybackAccess(for url: URL) throws -> any LibraryBookmarkSession {
        let path = LibrarySourcePath.normalize(url)
        guard let state = sources.first(where: { LibrarySourcePath.contains(path, in: $0.path) }),
              let bookmark = state.bookmarkData else {
            throw LibraryBookmarkError.accessDenied(path)
        }
        let session = try bookmarkAccess.startAccessing(
            bookmark: bookmark, at: URL(fileURLWithPath: state.path))
        if let refreshed = session.refreshedBookmark {
            let store = store
            Task { try? await store.updateBookmark(path: state.path, data: refreshed) }
        }
        return session
    }

    /// Replaces one source's bookmark with a folder explicitly chosen in an Open Panel.
    public func grantAccess(to sourcePath: String, selectedURL: URL) async throws {
        let selectedPath = LibrarySourcePath.normalize(selectedURL)
        guard selectedPath == LibrarySourcePath.normalize(URL(fileURLWithPath: sourcePath)) else {
            throw LibrarySourceError.grantMismatch(selected: selectedPath, expected: sourcePath)
        }
        let bookmark = try bookmarkAccess.createBookmark(for: selectedURL)
        try await store.updateBookmark(path: sourcePath, data: bookmark)
        await loadSources()
        await refresh()
    }

    public func removeSource(_ path: String) async throws {
        if let running = scanTask {
            running.cancel()
            await running.value
        }
        try await store.removeSource(path: path)
        committedRevision += 1
        await loadSources()
        await publishCommitted()
        updatePhase(scanSucceeded: true)
    }

    public func retry() async { await refresh() }

    /// Replaces the browsing window with the first page for this store query.
    public func browse(matching query: LibraryTrackQuery) async {
        browseQuery = query
        await publishCommitted()
    }

    /// Fetches and appends the next sorted page from the committed store.
    public func loadNextPage() async {
        guard hasMoreTracks, !isLoadingPage else { return }
        isLoadingPage = true
        defer { isLoadingPage = false }
        let revision = browseRevision
        let query = browseQuery
        do {
            let built = try await fetchMusicPage(offset: tracks.count, matching: query)
            guard revision == browseRevision else { return }
            tracks.append(contentsOf: built)
            hasMoreTracks = tracks.count < totalTrackCount
        } catch {
            guard revision == browseRevision else { return }
            scanError = "Your Library could not be loaded: \(error.localizedDescription)"
        }
    }

    /// Returns the requested UUID strings that still exist. A read failure
    /// preserves every requested ID so a transient error cannot clear playback.
    public func existingTrackIDs(among ids: Set<String>) async -> Set<String> {
        let uuids = Set(ids.compactMap(UUID.init(uuidString:)))
        do {
            return Set(try await store.existingTrackIDs(among: uuids).map(\.uuidString))
        } catch {
            return ids
        }
    }

    private func noteCommittedChange() async {
        committedRevision += 1
    }

    /// Loads a complete Album through a predicate rather than relying on the
    /// subset that happens to be present in the browsing pages.
    public func loadAlbum(_ album: Album) async -> Album? {
        let query = LibraryTrackQuery(albumTitle: album.title, albumArtist: album.albumArtist)
        do {
            let snapshots = try await allSnapshots(matching: query)
            let music = await makeMusic(from: snapshots)
            return LibraryGrouping.albums(from: music).first { $0.id == album.id }
        } catch {
            scanError = "The Album could not be loaded: \(error.localizedDescription)"
            return nil
        }
    }

    /// Loads every Track belonging to an Artist through a Store predicate.
    public func loadArtist(_ artist: Artist) async -> Artist? {
        let query = LibraryTrackQuery(artistName: artist.name)
        do {
            var snapshots = try await allSnapshots(matching: query)
            if artist.name == "Unknown Artist" {
                snapshots += try await allSnapshots(
                    matching: LibraryTrackQuery(includeUnattributedArtist: true))
            }
            snapshots = Dictionary(snapshots.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                .map(\.value)
            let music = await makeMusic(from: snapshots)
            let albums = LibraryGrouping.albums(from: music)
            return LibraryGrouping.artists(from: albums).first { $0.id == artist.id }
        } catch {
            scanError = "The Artist could not be loaded: \(error.localizedDescription)"
            return nil
        }
    }

    /// Loads selected Tracks for a Playlist and restores their requested order.
    public func loadTracks(withIDs ids: [String]) async -> [Music] {
        let uuids = ids.compactMap(UUID.init(uuidString:))
        do {
            let snapshots = try await store.snapshots(withIDs: uuids)
            let byID = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id, $0) })
            let ordered = uuids.compactMap { byID[$0] }
            return await makeMusic(from: ordered)
        } catch {
            scanError = "The Playlist Tracks could not be loaded: \(error.localizedDescription)"
            return []
        }
    }

    public func cancelScan() { scanTask?.cancel() }

    private func updateDiscoveredCount(_ count: Int) {
        discoveredTrackCount = count
    }

    private func loadSources() async {
        do {
            if try await store.needsSourceSeed() {
                let initialStates = try initialSources.map {
                    LibrarySourceState(
                        path: $0.sourcePath,
                        bookmarkData: bookmarkAccess.allowsAutomaticBookmarkCreation
                            ? try bookmarkAccess.createBookmark(for: URL(fileURLWithPath: $0.sourcePath))
                            : nil)
                }
                try await store.seedSourcesIfNeeded(initialStates)
            }
            var states = try await store.sourceStates()
            if bookmarkAccess.allowsAutomaticBookmarkCreation {
                for state in states where state.bookmarkData == nil {
                    let bookmark = try bookmarkAccess.createBookmark(for: URL(fileURLWithPath: state.path))
                    try await store.updateBookmark(path: state.path, data: bookmark)
                }
            }
            states = try await store.sourceStates()
            let configuredPaths = Set(states.map(\.path))
            sourcePathsRequiringAuthorization.formIntersection(configuredPaths)
            sourcePathsRequiringAuthorization.formUnion(states.filter { $0.bookmarkData == nil }.map(\.path))
            sources = states
            sourcePath = states.first?.path ?? ""
            let store = store
            activeSources = states.map { state in
                let injected = initialSources.first { $0.sourcePath == state.path }
                let factory = sourceFactory
                return BookmarkedFileSource(
                    sourcePath: state.path, bookmark: state.bookmarkData, access: bookmarkAccess,
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
        if totalTrackCount > 0 { phase = .ready }
        else if scanSucceeded { phase = .empty }
        else { phase = .failed }
    }

    private func publishCommitted() async {
        browseRevision += 1
        let revision = browseRevision
        let query = browseQuery
        do {
            let count = try await store.count(matching: query)
            let built = try await fetchMusicPage(offset: 0, matching: query)
            guard revision == browseRevision else { return }
            totalTrackCount = count
            tracks = built
            hasMoreTracks = tracks.count < totalTrackCount
            if totalTrackCount > 0 { phase = .ready }
        } catch {
            guard revision == browseRevision else { return }
            scanError = "Your Library could not be loaded: \(error.localizedDescription)"
        }
    }

    private func fetchMusicPage(offset: Int, matching query: LibraryTrackQuery) async throws -> [Music] {
        let snapshots = try await store.snapshots(
            matching: query, offset: offset, limit: Self.pageSize)
        return await makeMusic(from: snapshots)
    }

    private func allSnapshots(matching query: LibraryTrackQuery) async throws -> [TrackSnapshot] {
        let count = try await store.count(matching: query)
        return try await store.snapshots(matching: query, offset: 0, limit: count)
    }

    private func makeMusic(from snapshots: [TrackSnapshot]) async -> [Music] {
        let ids = Self.artworkRepresentatives(snapshots)
        let artwork = (try? await store.artwork(for: ids)) ?? [:]
        return await Self.buildMusic(snapshots, artwork: artwork)
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
                  year: s.year, trackNumber: s.trackNumber, discNumber: s.discNumber,
                  genre: s.genre, duration: s.duration, artworkData: byAlbum[albumKey(s)])
        }
        return music
    }
}
