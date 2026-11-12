import XCTest
@testable import RebornZuneCore

@MainActor
final class LibrarySearchCoordinatorTests: XCTestCase {
    func testCommittedLibraryUpdateRerunsAgainstFreshNormalizedRecords() async throws {
        let container = try RebornZunePersistence.makeInMemoryContainer()
        let source = FakeSource()
        source.files = [DiscoveredFile(
            path: "/fake/a.mp3", modificationDate: Date(timeIntervalSince1970: 1),
            fileSize: 10, volumeID: nil, fileID: nil)]
        source.metadata = ExtractedMetadata(
            title: "Old Title", artist: "Old Artist", albumArtist: "Old Artist",
            albumTitle: "Old Album", genre: "Old Genre", duration: 60)
        let coordinator = LibraryCoordinator(container: container, source: source)
        await coordinator.start()

        let initial = try await coordinator.search(matching: "old")
        XCTAssertEqual(initial.songs.map(\.title), ["Old Title"])
        XCTAssertEqual(initial.artists.map(\.name), ["Old Artist"])
        XCTAssertEqual(initial.albums.map(\.title), ["Old Album"])

        source.metadata = ExtractedMetadata(
            title: "New Title", artist: "New Artist", albumArtist: "New Artist",
            albumTitle: "New Album", genre: "New Genre", duration: 60)
        source.files = [DiscoveredFile(
            path: "/fake/a.mp3", modificationDate: Date(timeIntervalSince1970: 2),
            fileSize: 10, volumeID: nil, fileID: nil)]
        await coordinator.refresh()

        let old = try await coordinator.search(matching: "old")
        let updated = try await coordinator.search(matching: "new")
        XCTAssertTrue(old.isEmpty)
        XCTAssertEqual(updated.songs.map(\.title), ["New Title"])
        XCTAssertEqual(updated.artists.map(\.name), ["New Artist"])
        XCTAssertEqual(updated.albums.map(\.title), ["New Album"])
    }
}
