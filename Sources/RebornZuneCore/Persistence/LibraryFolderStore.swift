import Foundation

/// Persists the last user-picked music library folder so the app can restore
/// it on next launch. Uses a security-scoped bookmark on macOS / iPadOS so the
/// URL stays valid across launches.
///
/// tvOS targets have no user filesystem and never reach this code path.
public enum LibraryFolderStore {
    private static let key = "RebornZune.libraryFolderBookmark"

    /// Persist a folder URL chosen via `.fileImporter` so it can be re-opened
    /// next launch. Stores a security-scoped bookmark; failures are silently
    /// dropped (the worst outcome is the user re-picking next launch).
    public static func write(_ folder: URL) {
        #if os(macOS)
        let options: URL.BookmarkCreationOptions = [.withSecurityScope]
        #elseif os(iOS)
        let options: URL.BookmarkCreationOptions = []
        #else
        let options: URL.BookmarkCreationOptions = []
        #endif

        guard let data = try? folder.bookmarkData(
            options: options,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// Restore the last-saved folder URL, or `nil` if none/expired.
    /// Resolves the security-scoped bookmark and starts access for the caller.
    /// Caller is responsible for `stopAccessingSecurityScopedResource()` if
    /// the URL is no longer needed (we don't enforce — leak is bounded by
    /// process lifetime).
    public static func read() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }

        var stale = false
        #if os(macOS)
        let options: URL.BookmarkResolutionOptions = [.withSecurityScope]
        #else
        let options: URL.BookmarkResolutionOptions = []
        #endif

        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: options,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return nil }

        // Stale bookmarks may still resolve; we ignore the staleness flag for
        // simplicity. Re-pick triggers a fresh write.

        _ = url.startAccessingSecurityScopedResource()
        return url
    }

    /// Clear the saved folder. Useful for debug / testing.
    public static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
