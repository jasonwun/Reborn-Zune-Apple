import Foundation

/// User-facing, committed state of one configured Library Source.
public struct LibrarySourceState: Identifiable, Equatable, Sendable {
    public var id: String { path }
    public let path: String
    public let bookmarkData: Data?
    public let isAvailable: Bool
    public let committedTrackCount: Int

    public init(path: String, bookmarkData: Data? = nil, isAvailable: Bool = true,
                committedTrackCount: Int = 0) {
        self.path = path
        self.bookmarkData = bookmarkData
        self.isAvailable = isAvailable
        self.committedTrackCount = committedTrackCount
    }
}

public enum LibrarySourceError: LocalizedError, Equatable {
    case overlappingSource(candidate: String, conflict: String)
    case grantMismatch(selected: String, expected: String)

    public var errorDescription: String? {
        switch self {
        case .overlappingSource(let candidate, let conflict):
            return "The folder \(candidate) overlaps the existing Library Source \(conflict). Choose a folder that is not the same as, inside, or above an existing source."
        case .grantMismatch(let selected, let expected):
            return "The selected folder \(selected) does not match the Library Source \(expected). Choose the requested folder to grant access."
        }
    }
}

enum LibrarySourcePath {
    static func normalize(_ url: URL) -> String {
        url.standardizedFileURL.path
    }

    static func contains(_ path: String, in root: String) -> Bool {
        isPrefix(components(root), of: components(path))
    }

    static func conflict(for candidate: String, among existing: [String]) -> String? {
        let candidateComponents = components(candidate)
        return existing.first { path in
            let existingComponents = components(path)
            return isPrefix(candidateComponents, of: existingComponents)
                || isPrefix(existingComponents, of: candidateComponents)
        }
    }

    private static func components(_ path: String) -> [String] {
        URL(fileURLWithPath: path).standardizedFileURL.pathComponents
    }

    private static func isPrefix(_ prefix: [String], of path: [String]) -> Bool {
        prefix.count <= path.count && zip(prefix, path).allSatisfy(==)
    }
}
