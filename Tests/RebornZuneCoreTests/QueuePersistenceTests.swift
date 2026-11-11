import XCTest
import SwiftData
@testable import RebornZuneCore

@MainActor
final class QueuePersistenceTests: XCTestCase {
    func testQueueSnapshotSurvivesStoreRecreation() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("queue-tests-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }
        let ids = [UUID(), UUID(), UUID()]
        let entryIDs = [UUID(), UUID(), UUID()]
        let snapshot = PlaybackQueueSnapshot(
            originalTrackIDs: ids,
            activeTrackIDs: [ids[2], ids[0], ids[1]],
            currentIndex: 1,
            position: 12.5,
            isShuffling: true,
            originalEntryIDs: entryIDs,
            activeEntryIDs: [entryIDs[2], entryIDs[0], entryIDs[1]]
        )

        let firstContainer = try RebornZunePersistence.makePersistentContainer(at: url)
        try QueueStore(container: firstContainer).save(snapshot)
        let secondContainer = try RebornZunePersistence.makePersistentContainer(at: url)

        XCTAssertEqual(try QueueStore(container: secondContainer).load(), snapshot)
    }
}
