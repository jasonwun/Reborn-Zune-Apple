import Foundation

public protocol LibraryBookmarkSession: Sendable {
    var url: URL { get }
    var refreshedBookmark: Data? { get }
    func stop()
}

/// Security-scope boundary. Every successful start produces exactly one session
/// whose `stop` is called by `BookmarkedFileSource` on every exit path.
public protocol LibraryBookmarkAccessing: Sendable {
    func createBookmark(for url: URL) throws -> Data
    func startAccessing(bookmark: Data, at url: URL) throws -> any LibraryBookmarkSession
}

public enum LibraryBookmarkError: LocalizedError {
    case accessDenied(String)

    public var errorDescription: String? {
        switch self {
        case .accessDenied(let path):
            return "Reborn Zune could not access \(path). Your Library is unchanged. Check the folder permission and retry."
        }
    }
}

public struct SystemLibraryBookmarkAccess: LibraryBookmarkAccessing {
    public init() {}

    public func createBookmark(for url: URL) throws -> Data {
        #if os(macOS)
        let options: URL.BookmarkCreationOptions = [.withSecurityScope]
        #else
        let options: URL.BookmarkCreationOptions = []
        #endif
        return try url.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    public func startAccessing(bookmark: Data, at url: URL) throws -> any LibraryBookmarkSession {
        var stale = false
        #if os(macOS)
        let options: URL.BookmarkResolutionOptions = [.withSecurityScope]
        #else
        let options: URL.BookmarkResolutionOptions = []
        #endif
        let resolved = try URL(resolvingBookmarkData: bookmark, options: options,
                               relativeTo: nil, bookmarkDataIsStale: &stale)
        let refreshed = stale ? try? createBookmark(for: resolved) : nil
        guard resolved.startAccessingSecurityScopedResource() else {
            throw LibraryBookmarkError.accessDenied(resolved.path)
        }
        return SystemLibraryBookmarkSession(url: resolved, refreshedBookmark: refreshed)
    }
}

private final class SystemLibraryBookmarkSession: LibraryBookmarkSession, @unchecked Sendable {
    let url: URL
    let refreshedBookmark: Data?
    private let lock = NSLock()
    private var stopped = false

    init(url: URL, refreshedBookmark: Data?) {
        self.url = url
        self.refreshedBookmark = refreshedBookmark
    }

    func stop() {
        let shouldStop = lock.withLock {
            if stopped { return false }
            stopped = true
            return true
        }
        if shouldStop { url.stopAccessingSecurityScopedResource() }
    }
}

/// Used by non-persisted callers and tests that do not model security scopes.
public struct NoLibraryBookmarkAccess: LibraryBookmarkAccessing {
    public init() {}
    public func createBookmark(for url: URL) throws -> Data { Data(url.path.utf8) }
    public func startAccessing(bookmark: Data, at url: URL) throws -> any LibraryBookmarkSession {
        NoLibraryBookmarkSession(url: url)
    }
}

private struct NoLibraryBookmarkSession: LibraryBookmarkSession {
    let url: URL
    let refreshedBookmark: Data? = nil
    func stop() {}
}

struct BookmarkedFileSource: LibraryFileSource, Sendable {
    let sourcePath: String
    let bookmark: Data
    let access: any LibraryBookmarkAccessing
    let makeSource: @Sendable (URL) -> any LibraryFileSource
    let persistBookmark: @Sendable (Data) async -> Void

    func discover() async throws -> [DiscoveredFile] {
        try await withAccess { try await $0.discover() }
    }

    func extract(_ file: DiscoveredFile) async throws -> ExtractedMetadata {
        try await withAccess { try await $0.extract(file) }
    }

    private func withAccess<T: Sendable>(
        _ operation: (any LibraryFileSource) async throws -> T
    ) async throws -> T {
        let session: any LibraryBookmarkSession
        do {
            session = try access.startAccessing(bookmark: bookmark,
                                                at: URL(fileURLWithPath: sourcePath))
        } catch {
            throw LibraryScanError.rootFailure(at: sourcePath, error: error)
        }
        defer { session.stop() }
        let source = makeSource(session.url)
        do {
            let result = try await operation(source)
            await persistRefreshedBookmark(session)
            return result
        } catch {
            await persistRefreshedBookmark(session)
            throw error
        }
    }

    private func persistRefreshedBookmark(_ session: any LibraryBookmarkSession) async {
        if let refreshed = session.refreshedBookmark { await persistBookmark(refreshed) }
    }
}
