import Foundation

/// Version of the metadata extraction schema. Bump to force a one-time full
/// re-extraction; independent of identity migration and search versions.
public let currentMetadataVersion = 1

/// A supported audio file found on disk, with the data needed for
/// fingerprinting and move matching.
public struct DiscoveredFile: Sendable, Equatable {
    /// Normalized absolute path.
    public var path: String
    /// Path as enumerated (may differ from `path` in normalization); only
    /// used to match legacy path-hash Playlist entries.
    public var rawPath: String
    public var modificationDate: Date
    public var fileSize: Int64
    /// Archived `volumeIdentifier`; nil when unavailable.
    public var volumeID: Data?
    /// Archived `fileResourceIdentifier`; nil when unavailable.
    public var fileID: Data?

    public init(path: String, rawPath: String? = nil, modificationDate: Date, fileSize: Int64,
                volumeID: Data? = nil, fileID: Data? = nil) {
        self.path = path
        self.rawPath = rawPath ?? path
        self.modificationDate = modificationDate
        self.fileSize = fileSize
        self.volumeID = volumeID
        self.fileID = fileID
    }

    public var url: URL { URL(fileURLWithPath: path) }
}

/// Tags read from one audio file.
public struct ExtractedMetadata: Sendable, Equatable {
    public var title: String
    public var artist: String?
    public var albumArtist: String?
    public var albumTitle: String?
    public var year: Int?
    public var duration: TimeInterval
    public var artworkData: Data?

    public init(title: String, artist: String? = nil, albumArtist: String? = nil,
                albumTitle: String? = nil, year: Int? = nil, duration: TimeInterval = 0,
                artworkData: Data? = nil) {
        self.title = title
        self.artist = artist
        self.albumArtist = albumArtist
        self.albumTitle = albumTitle
        self.year = year
        self.duration = duration
        self.artworkData = artworkData
    }
}

/// The seam between the Library coordinator and the filesystem. Production
/// uses `FolderFileSource`; tests inject fakes.
public protocol LibraryFileSource: Sendable {
    /// Path of the Library Source root that owns discovered files.
    var sourcePath: String { get }
    /// Enumerate every supported audio file. MUST throw when the enumeration
    /// is incomplete for any reason (permission, IO) — an empty array means
    /// the source was fully read and holds no audio.
    func discover() async throws -> [DiscoveredFile]
    /// Read tags for one file. Throwing skips only that file.
    func extract(_ file: DiscoveredFile) async throws -> ExtractedMetadata
}

public enum LibraryScanError: LocalizedError, Equatable {
    case sourceUnavailable(String)
    case incompleteEnumeration(String)

    public var errorDescription: String? {
        switch self {
        case .sourceUnavailable(let path):
            return "The folder \(path) could not be opened. Check that it exists and that Reborn Zune is allowed to read it."
        case .incompleteEnumeration(let path):
            return "Some files in \(path) could not be read, so the scan was not applied. Your existing Library is unchanged."
        }
    }

    static func rootFailure(at path: String, error: Error) -> LibraryScanError {
        let nsError = error as NSError
        let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        let posixCode = underlying?.domain == NSPOSIXErrorDomain
            ? underlying.map { Int($0.code) } : nil
        let cocoaMissing = nsError.domain == NSCocoaErrorDomain
            && (nsError.code == NSFileNoSuchFileError || nsError.code == NSFileReadNoSuchFileError)
        let osStatusMissing = underlying?.domain == NSOSStatusErrorDomain && underlying?.code == -43 // fnfErr
        let isMissing = cocoaMissing || osStatusMissing
            || posixCode == Optional(Int(ENOENT)) || posixCode == Optional(Int(ENOTDIR))
        return isMissing ? .sourceUnavailable(path) : .incompleteEnumeration(path)
    }
}

/// Recursively enumerates one folder.
public struct FolderFileSource: LibraryFileSource {
    public let root: URL
    public var sourcePath: String { Self.normalize(root) }

    public init(root: URL) { self.root = root }

    public static func normalize(_ url: URL) -> String {
        url.standardizedFileURL.path
    }

    public func discover() async throws -> [DiscoveredFile] {
        let fm = FileManager.default
        // Ask for the contents directly: `fileExists` cannot distinguish a
        // missing root from an access error. Only ENOENT/ENOTDIR authorizes
        // unavailable-source cleanup; every other failure preserves the Library.
        do { _ = try fm.contentsOfDirectory(atPath: root.path) } catch {
            throw LibraryScanError.rootFailure(at: root.path, error: error)
        }

        return try Self.walk(root)
    }

    private static func walk(_ root: URL) throws -> [DiscoveredFile] {
        let fm = FileManager.default
        let supported = Set(SupportedAudioExtension.allCases.map { $0.rawValue })
        let keys: [URLResourceKey] = [
            .isRegularFileKey, .contentModificationDateKey, .fileSizeKey,
            .fileResourceIdentifierKey, .volumeIdentifierKey,
        ]
        let failures = ErrorBox()
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in failures.set(); return true }
        ) else { throw LibraryScanError.incompleteEnumeration(root.path) }

        var files: [DiscoveredFile] = []
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            guard supported.contains(url.pathExtension.lowercased()) else { continue }
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else {
                failures.set(); continue
            }
            guard values.isRegularFile == true else { continue }
            files.append(DiscoveredFile(
                path: Self.normalize(url),
                rawPath: url.path,
                modificationDate: values.contentModificationDate ?? .distantPast,
                fileSize: Int64(values.fileSize ?? 0),
                volumeID: Self.archive(values.volumeIdentifier),
                fileID: Self.archive(values.fileResourceIdentifier)
            ))
        }
        if failures.isSet { throw LibraryScanError.incompleteEnumeration(root.path) }
        return files
    }

    public func extract(_ file: DiscoveredFile) async throws -> ExtractedMetadata {
        try await MetadataExtractor.extractMetadata(from: file.url)
    }

    static func archive(_ value: Any?) -> Data? {
        guard let object = value as? (NSObjectProtocol & NSCoding) else { return nil }
        return try? NSKeyedArchiver.archivedData(withRootObject: object, requiringSecureCoding: false)
    }
}

private final class ErrorBox: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    func set() { lock.lock(); flag = true; lock.unlock() }
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return flag }
}
