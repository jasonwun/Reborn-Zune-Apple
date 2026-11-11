import XCTest
import SwiftData
@testable import RebornZuneCore

/// Schema + relationship sanity tests for M8 SwiftData entities. Uses an
/// in-memory container so the test suite stays isolated from any user
/// data and can run on CI.
@MainActor
final class PersistenceModelsTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let container = try RebornZunePersistence.makeInMemoryContainer()
        return ModelContext(container)
    }

    func testInsertAndFetchPlaylist() throws {
        let ctx = try makeContext()
        let playlist = StoredPlaylist(name: "Late Night")
        ctx.insert(playlist)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<StoredPlaylist>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.name, "Late Night")
        XCTAssertTrue(fetched.first?.entries.isEmpty ?? false)
    }

    func testCascadeDeletesEntriesWithPlaylist() throws {
        let ctx = try makeContext()
        let playlist = StoredPlaylist(name: "Weekend")
        ctx.insert(playlist)

        let entry1 = StoredPlaylistEntry(orderIndex: 0, musicID: "/path/a.mp3", playlist: playlist)
        let entry2 = StoredPlaylistEntry(orderIndex: 1, musicID: "/path/b.mp3", playlist: playlist)
        ctx.insert(entry1)
        ctx.insert(entry2)
        try ctx.save()

        XCTAssertEqual(try ctx.fetch(FetchDescriptor<StoredPlaylistEntry>()).count, 2)

        ctx.delete(playlist)
        try ctx.save()

        // Cascade rule on the inverse relationship should remove the entries too.
        XCTAssertTrue(try ctx.fetch(FetchDescriptor<StoredPlaylist>()).isEmpty)
        XCTAssertTrue(try ctx.fetch(FetchDescriptor<StoredPlaylistEntry>()).isEmpty)
    }

    func testEntriesPreserveOrderIndex() throws {
        let ctx = try makeContext()
        let playlist = StoredPlaylist(name: "Mix")
        ctx.insert(playlist)
        for (i, id) in ["/c.mp3", "/a.mp3", "/b.mp3"].enumerated() {
            ctx.insert(StoredPlaylistEntry(orderIndex: i, musicID: id, playlist: playlist))
        }
        try ctx.save()

        let descriptor = FetchDescriptor<StoredPlaylistEntry>(
            sortBy: [SortDescriptor(\.orderIndex)]
        )
        let sorted = try ctx.fetch(descriptor)
        XCTAssertEqual(sorted.map(\.musicID), ["/c.mp3", "/a.mp3", "/b.mp3"])
    }

    func testStoredAppSettingsRoundTrip() throws {
        let ctx = try makeContext()
        let settings = StoredAppSettings(lastShufflePolicy: "off", lastRepeatMode: "all")
        ctx.insert(settings)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<StoredAppSettings>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.lastShufflePolicy, "off")
        XCTAssertEqual(fetched.first?.lastRepeatMode, "all")
    }

    func testSchemaContainsAllEntities() {
        XCTAssertEqual(RebornZunePersistence.schema.entities.count, 7)
        let names = Set(RebornZunePersistence.schema.entities.map(\.name))
        XCTAssertTrue(names.contains("StoredPlaylist"))
        XCTAssertTrue(names.contains("StoredPlaylistEntry"))
        XCTAssertTrue(names.contains("StoredAppSettings"))
        XCTAssertTrue(names.contains("StoredTrack"))
        XCTAssertTrue(names.contains("StoredTrackArtwork"))
        XCTAssertTrue(names.contains("StoredLibraryState"))
        XCTAssertTrue(names.contains("StoredLibrarySource"))
    }
}
