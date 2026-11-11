import Foundation
import SwiftData

/// One actual playback start. Qualification is recorded once, without
/// persisting the continuously changing active-playback progress.
@Model
public final class StoredPlayHistoryEntry {
    @Attribute(.unique) public var id: UUID
    public var trackID: UUID
    public var startedAt: Date
    public var qualifiedAt: Date?

    public init(id: UUID = UUID(), trackID: UUID, startedAt: Date, qualifiedAt: Date? = nil) {
        self.id = id
        self.trackID = trackID
        self.startedAt = startedAt
        self.qualifiedAt = qualifiedAt
    }
}

/// Long-term per-Track aggregates, independent of bounded history retention.
@Model
public final class StoredTrackPlaybackStats {
    @Attribute(.unique) public var trackID: UUID
    public var playCount: Int
    public var lastPlayedAt: Date

    public init(trackID: UUID, playCount: Int = 0, lastPlayedAt: Date) {
        self.trackID = trackID
        self.playCount = playCount
        self.lastPlayedAt = lastPlayedAt
    }
}
