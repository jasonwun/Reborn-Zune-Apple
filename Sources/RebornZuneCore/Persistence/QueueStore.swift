import Foundation
import SwiftData

@Model
public final class StoredQueueState {
    public var originalTrackIDs: [UUID]
    public var activeTrackIDs: [UUID]
    /// A negative value represents no current Track; kept stable for lightweight migration.
    public var currentIndex: Int
    public var position: TimeInterval
    public var isShuffling: Bool
    public var originalEntryIDs: [UUID]?
    public var activeEntryIDs: [UUID]?

    public init(
        originalTrackIDs: [UUID] = [],
        activeTrackIDs: [UUID] = [],
        currentIndex: Int = -1,
        position: TimeInterval = 0,
        isShuffling: Bool = false,
        originalEntryIDs: [UUID]? = nil,
        activeEntryIDs: [UUID]? = nil
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

/// Synchronous, single-row Queue persistence. Writes must finish during termination.
@MainActor
public final class QueueStore {
    private let context: ModelContext

    public init(container: ModelContainer) {
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    public func load() throws -> PlaybackQueueSnapshot? {
        guard let state = try context.fetch(FetchDescriptor<StoredQueueState>()).first else { return nil }
        return PlaybackQueueSnapshot(
            originalTrackIDs: state.originalTrackIDs,
            activeTrackIDs: state.activeTrackIDs,
            currentIndex: state.currentIndex >= 0 ? state.currentIndex : nil,
            position: state.position,
            isShuffling: state.isShuffling,
            originalEntryIDs: state.originalEntryIDs ?? [],
            activeEntryIDs: state.activeEntryIDs ?? []
        )
    }

    public func save(_ snapshot: PlaybackQueueSnapshot) throws {
        let state = try context.fetch(FetchDescriptor<StoredQueueState>()).first ?? StoredQueueState()
        if state.modelContext == nil { context.insert(state) }
        state.originalTrackIDs = snapshot.originalTrackIDs
        state.activeTrackIDs = snapshot.activeTrackIDs
        state.currentIndex = snapshot.currentIndex ?? -1
        state.position = snapshot.position
        state.isShuffling = snapshot.isShuffling
        state.originalEntryIDs = snapshot.originalEntryIDs
        state.activeEntryIDs = snapshot.activeEntryIDs
        try context.save()
    }
}
