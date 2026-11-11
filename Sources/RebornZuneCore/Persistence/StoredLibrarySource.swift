import Foundation
import SwiftData

/// Persisted configuration and latest committed scan state for one Library Source.
@Model
public final class StoredLibrarySource {
    @Attribute(.unique) public var path: String
    /// Independently resolvable security-scoped bookmark for this source.
    public var bookmarkData: Data?
    public var isAvailable: Bool
    public var committedTrackCount: Int

    public init(path: String, bookmarkData: Data? = nil, isAvailable: Bool = true,
                committedTrackCount: Int = 0) {
        self.path = path
        self.bookmarkData = bookmarkData
        self.isAvailable = isAvailable
        self.committedTrackCount = committedTrackCount
    }
}
