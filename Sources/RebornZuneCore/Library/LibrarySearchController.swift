import Foundation
import Observation

/// Host adapters for the macOS Search surface. All heavy query work remains
/// behind LibraryCoordinator's actor API; these closures are invoked on MainActor.
@MainActor
public struct LibrarySearchClient {
    public let search: (String) async throws -> LibrarySearchResults
    public let genres: () async throws -> [LibrarySearchGenre]
    public let music: ([TrackSnapshot]) async -> [Music]
    public let artwork: ([UUID]) async -> [UUID: Data]

    public init(
        search: @escaping (String) async throws -> LibrarySearchResults,
        genres: @escaping () async throws -> [LibrarySearchGenre],
        music: @escaping ([TrackSnapshot]) async -> [Music],
        artwork: @escaping ([UUID]) async -> [UUID: Data]
    ) {
        self.search = search
        self.genres = genres
        self.music = music
        self.artwork = artwork
    }
}

public enum LibrarySearchMode: Equatable, Sendable {
    case grouped
    case songs
    case artists
    case albums
}

public enum LibrarySearchPhase: Equatable, Sendable {
    case idle
    case ready
    case failed
}

/// In-session owner of Global Search text, mode, selection, and asynchronous
/// query generations. It is deliberately not persisted across relaunch.
@MainActor
@Observable
public final class LibrarySearchController {
    public private(set) var query = ""
    public private(set) var results = LibrarySearchResults()
    public private(set) var genres: [LibrarySearchGenre] = []
    public private(set) var mode: LibrarySearchMode = .grouped
    public private(set) var phase: LibrarySearchPhase = .idle
    public private(set) var generation: UInt = 0
    public private(set) var isSearching = false
    public private(set) var showsLoadingIndicator = false
    /// Last selected/visible result used to restore scroll after navigation.
    public var scrollAnchorID: String?

    @ObservationIgnored private let searchOperation: (String) async throws -> LibrarySearchResults
    @ObservationIgnored private let genresOperation: () async throws -> [LibrarySearchGenre]
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var indicatorTask: Task<Void, Never>?
    @ObservationIgnored private let sleepOperation: @Sendable (UInt64) async throws -> Void
    private var selection: Selection?

    private enum Selection: Equatable {
        case song(UUID)
        case artist(String)
        case album(String)
    }

    public init(
        search: @escaping (String) async throws -> LibrarySearchResults,
        genres: @escaping () async throws -> [LibrarySearchGenre] = { [] },
        sleep: @escaping @Sendable (UInt64) async throws -> Void = { nanoseconds in
            try await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.searchOperation = search
        self.genresOperation = genres
        self.sleepOperation = sleep
    }

    public var selectedSongID: UUID? {
        if case .song(let id) = selection { return id }
        return nil
    }

    public var selectedResultID: String? {
        switch selection {
        case .song(let id): return "song:\(id.uuidString)"
        case .artist(let id): return "artist:\(id)"
        case .album(let id): return "album:\(id)"
        case nil: return nil
        }
    }

    public func updateQuery(_ text: String) {
        start(text: text, debounceNanoseconds: 200_000_000, preserveSelection: false)
    }

    public func retry() async {
        await runCurrent(debounceNanoseconds: 0, preserveSelection: true)
    }

    /// Committed Library updates rerun immediately. Selection survives only
    /// when the exact stable Song/Artist/Album identity remains in the result.
    public func refreshForLibraryUpdate() async {
        if LibrarySearchNormalizer.tokens(for: query).isEmpty {
            await loadGenres()
        } else {
            await runCurrent(debounceNanoseconds: 0, preserveSelection: true)
        }
    }

    public func loadGenres() async {
        do {
            let loaded = try await genresOperation()
            guard !Task.isCancelled else { return }
            genres = loaded
            if LibrarySearchNormalizer.tokens(for: query).isEmpty { phase = .ready }
        } catch is CancellationError {
        } catch {
            #if DEBUG
            print("Global Search genre loading failed: \(error)")
            #endif
            if LibrarySearchNormalizer.tokens(for: query).isEmpty { phase = .failed }
        }
    }

    public func showAll(_ newMode: LibrarySearchMode) {
        guard newMode != .grouped else { return }
        mode = newMode
        selection = nil
        scrollAnchorID = nil
    }

    public func backToResults() {
        mode = .grouped
        selection = nil
        scrollAnchorID = nil
    }

    public func select(songID: UUID) {
        selection = .song(songID)
        scrollAnchorID = selectedResultID
    }

    public func select(artistID: String) {
        selection = .artist(artistID)
        scrollAnchorID = selectedResultID
    }

    public func select(albumID: String) {
        selection = .album(albumID)
        scrollAnchorID = selectedResultID
    }

    public func clearSelection() {
        selection = nil
    }

    public func escape() {
        mode = .grouped
        scrollAnchorID = nil
        start(text: "", debounceNanoseconds: 0, preserveSelection: false)
    }

    private func runCurrent(debounceNanoseconds: UInt64, preserveSelection: Bool) async {
        start(text: query, debounceNanoseconds: debounceNanoseconds, preserveSelection: preserveSelection)
        await searchTask?.value
    }

    private func start(text: String, debounceNanoseconds: UInt64, preserveSelection: Bool) {
        generation &+= 1
        let currentGeneration = generation
        searchTask?.cancel()
        indicatorTask?.cancel()
        query = text
        results = LibrarySearchResults()
        isSearching = false
        showsLoadingIndicator = false
        phase = .idle
        if !preserveSelection { selection = nil }
        let trimmed = LibrarySearchNormalizer.normalize(text)
        guard !trimmed.isEmpty else {
            selection = nil
            scrollAnchorID = nil
            searchTask = nil
            Task { await self.loadGenres() }
            return
        }

        searchTask = Task { [weak self] in
            guard let self else { return }
            if debounceNanoseconds > 0 {
                do { try await self.sleepOperation(debounceNanoseconds) }
                catch { return }
            }
            guard !Task.isCancelled, self.generation == currentGeneration else { return }
            self.isSearching = true
            self.indicatorTask = Task { [weak self] in
                guard let self else { return }
                do { try await self.sleepOperation(150_000_000) }
                catch { return }
                guard !Task.isCancelled else { return }
                if self.generation == currentGeneration, self.isSearching == true {
                    self.showsLoadingIndicator = true
                }
            }
            do {
                let loaded = try await self.searchOperation(trimmed)
                try Task.checkCancellation()
                guard self.generation == currentGeneration else { return }
                self.results = loaded
                self.reconcileSelection()
                self.phase = .ready
            } catch is CancellationError {
                return
            } catch {
                guard self.generation == currentGeneration else { return }
                #if DEBUG
                print("Global Search query failed: \(error)")
                #endif
                self.phase = .failed
            }
            guard self.generation == currentGeneration else { return }
            self.isSearching = false
            self.showsLoadingIndicator = false
            self.indicatorTask?.cancel()
        }
    }

    private func reconcileSelection() {
        switch selection {
        case .song(let id):
            if !results.songs.contains(where: { $0.id == id }) { selection = nil }
        case .artist(let id):
            if !results.artists.contains(where: { $0.id == id }) { selection = nil }
        case .album(let id):
            if !results.albums.contains(where: { $0.id == id }) { selection = nil }
        case nil:
            break
        }
        if selection == nil { scrollAnchorID = nil }
    }
}
