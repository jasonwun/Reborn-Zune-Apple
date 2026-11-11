import SwiftUI

@MainActor
@Observable
public final class ResonantRouter {
    public enum Route: Equatable, Hashable, Sendable {
        case home
        case albums
        case playlists
        case artists
        case search
        case album(String)        // album id
        case playlist(String)     // playlist id
        case artist(String)       // artist name
        case nowPlaying

        public var pivot: Route? {
            switch self {
            case .home, .albums, .playlists, .artists, .search:
                return self
            case .album:    return .albums
            case .playlist: return .playlists
            case .artist:   return .artists
            case .nowPlaying: return nil
            }
        }

        public var label: String {
            switch self {
            case .home:       return "Today"
            case .albums:     return "Albums"
            case .playlists:  return "Playlists"
            case .artists:    return "Artists"
            case .search:     return "Search"
            case .album:      return "Album"
            case .playlist:   return "Playlist"
            case .artist:     return "Artist"
            case .nowPlaying: return "Now Playing"
            }
        }
    }

    public private(set) var route: Route = .home
    /// Changes on every explicit Search-focus command, including repeated Cmd-F.
    public private(set) var searchFocusRequestID: UInt = 0
    private var history: [Route] = []
    private let historyMax = 50

    public init(initial: Route? = nil) {
        if let r = initial { route = r }
    }

    /// Parse `REBORN_ZUNE_DEBUG_INITIAL_ROUTE` for screenshot harness use.
    /// Supported: `home / albums / playlists / artists / search / nowPlaying`
    /// plus `album:<id> / playlist:<id> / artist:<name>`.
    public static func envInitialRoute() -> Route? {
        guard let raw = ProcessInfo.processInfo.environment["REBORN_ZUNE_DEBUG_INITIAL_ROUTE"] else {
            return nil
        }
        return parse(raw)
    }

    /// Parse a route string in the `envInitialRoute` format. Also used by
    /// the `REBORN_ZUNE_DEBUG_AUTO_NAV` perf hook.
    public static func parse(_ raw: String) -> Route? {
        let parts = raw.split(separator: ":", maxSplits: 1).map(String.init)
        switch parts.first {
        case "home":       return .home
        case "albums":     return .albums
        case "playlists":  return .playlists
        case "artists":    return .artists
        case "search":     return .search
        case "nowPlaying": return .nowPlaying
        case "album":      return parts.count > 1 ? .album(parts[1]) : .albums
        case "playlist":   return parts.count > 1 ? .playlist(parts[1]) : .playlists
        case "artist":     return parts.count > 1 ? .artist(parts[1]) : .artists
        default:           return nil
        }
    }

    public var canGoBack: Bool { !history.isEmpty }
    public var backLabel: String? { history.last?.label }
    public var activePivot: Route? { route.pivot }

    public func go(_ next: Route) {
        guard next != route else { return }
        PerfProbe.mark("route.go.\(next.label)")
        history.append(route)
        if history.count > historyMax {
            history.removeFirst(history.count - historyMax)
        }
        route = next
    }

    /// Open Search and ask its field to take focus, even when already selected.
    public func focusSearch() {
        go(.search)
        searchFocusRequestID &+= 1
    }

    public func back() {
        guard let prev = history.popLast() else { return }
        route = prev
    }
}
