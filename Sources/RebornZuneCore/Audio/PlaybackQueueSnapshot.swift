import Foundation

/// Stable, persistable representation of both logical Queue sequences.
public struct PlaybackQueueSnapshot: Equatable, Sendable {
    public var originalTrackIDs: [UUID]
    public var activeTrackIDs: [UUID]
    public var currentIndex: Int?
    public var position: TimeInterval
    public var isShuffling: Bool
    /// Per-entry identities preserve duplicate Track occurrences across edits and relaunch.
    public var originalEntryIDs: [UUID]
    public var activeEntryIDs: [UUID]

    public init(
        originalTrackIDs: [UUID],
        activeTrackIDs: [UUID],
        currentIndex: Int?,
        position: TimeInterval,
        isShuffling: Bool,
        originalEntryIDs: [UUID] = [],
        activeEntryIDs: [UUID] = []
    ) {
        self.originalTrackIDs = originalTrackIDs
        self.activeTrackIDs = activeTrackIDs
        self.currentIndex = currentIndex
        self.position = position
        self.isShuffling = isShuffling
        self.originalEntryIDs = originalEntryIDs
        self.activeEntryIDs = activeEntryIDs
    }
}
