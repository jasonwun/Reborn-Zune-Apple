import XCTest
@testable import RebornZuneCore

@MainActor
final class LibrarySearchInteractionTests: XCTestCase {
    func testTextChangeClearsVisibleResultsAndDiscardsSupersededGeneration() async throws {
        let controller = LibrarySearchController(search: { query in
            if query == "old" {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                return LibrarySearchResults(songs: [Self.snapshot(title: "Old")])
            }
            return LibrarySearchResults(songs: [Self.snapshot(title: "New")])
        })

        controller.updateQuery("old")
        try await Task.sleep(nanoseconds: 260_000_000)
        controller.updateQuery("new")
        XCTAssertTrue(controller.results.isEmpty)
        try await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertEqual(controller.results.songs.map(\.title), ["New"])
        XCTAssertEqual(controller.generation, 2)
        XCTAssertFalse(controller.showsLoadingIndicator)
    }

    func testLoadingIndicatorAppearsOnlyAfter150MillisecondsOfIncompleteQuery() async throws {
        let controller = LibrarySearchController(search: { _ in
            try await Task.sleep(nanoseconds: 400_000_000)
            return LibrarySearchResults()
        })

        controller.updateQuery("slow")
        try await Task.sleep(nanoseconds: 260_000_000)
        XCTAssertFalse(controller.showsLoadingIndicator)
        try await Task.sleep(nanoseconds: 160_000_000)
        XCTAssertTrue(controller.showsLoadingIndicator)
        try await Task.sleep(nanoseconds: 240_000_000)
        XCTAssertFalse(controller.showsLoadingIndicator)
    }

    func testShowAllRetainsQueryAndLibraryRefreshPreservesOnlyStableSelection() async throws {
        var songs = [Self.snapshot(title: "Keep"), Self.snapshot(title: "Remove")]
        let controller = LibrarySearchController(search: { _ in
            LibrarySearchResults(songs: songs)
        })
        controller.updateQuery("needle")
        try await Task.sleep(nanoseconds: 240_000_000)
        let keptID = controller.results.songs[0].id

        controller.showAll(.songs)
        controller.select(songID: keptID)
        songs = [songs[0]]
        await controller.refreshForLibraryUpdate()

        XCTAssertEqual(controller.query, "needle")
        XCTAssertEqual(controller.mode, .songs)
        XCTAssertEqual(controller.selectedSongID, keptID)
        XCTAssertEqual(controller.results.songs.map(\.title), ["Keep"])

        controller.select(songID: keptID)
        songs = [Self.snapshot(title: "Replacement")]
        await controller.refreshForLibraryUpdate()
        XCTAssertNil(controller.selectedSongID)

        controller.backToResults()
        XCTAssertEqual(controller.mode, .grouped)
        controller.escape()
        XCTAssertEqual(controller.query, "")
        XCTAssertEqual(controller.mode, .grouped)
        XCTAssertNil(controller.selectedSongID)
    }

    func testKeyboardNavigationFollowsGroupedRowsAndCardGrids() {
        let items = [
            LibrarySearchNavigationItem(id: "s0", group: .songs, index: 0, columns: 1),
            LibrarySearchNavigationItem(id: "s1", group: .songs, index: 1, columns: 1),
            LibrarySearchNavigationItem(id: "a0", group: .artists, index: 0, columns: 5),
            LibrarySearchNavigationItem(id: "a1", group: .artists, index: 1, columns: 5),
            LibrarySearchNavigationItem(id: "b0", group: .albums, index: 0, columns: 5),
            LibrarySearchNavigationItem(id: "b1", group: .albums, index: 1, columns: 5),
        ]

        XCTAssertEqual(LibrarySearchNavigation.move(from: nil, direction: .down, in: items), "s0")
        XCTAssertEqual(LibrarySearchNavigation.move(from: "s0", direction: .down, in: items), "s1")
        XCTAssertEqual(LibrarySearchNavigation.move(from: "s1", direction: .down, in: items), "a0")
        XCTAssertEqual(LibrarySearchNavigation.move(from: "a0", direction: .right, in: items), "a1")
        XCTAssertEqual(LibrarySearchNavigation.move(from: "a1", direction: .down, in: items), "b1")
        XCTAssertEqual(LibrarySearchNavigation.move(from: "b1", direction: .up, in: items), "a1")
        XCTAssertNil(LibrarySearchNavigation.move(from: "s0", direction: .up, in: items))
        XCTAssertEqual(LibrarySearchNavigation.move(from: "a0", direction: .left, in: items), "a0")
    }

    private static func snapshot(title: String) -> TrackSnapshot {
        let id = UUID()
        return TrackSnapshot(
            id: id, path: "/fake/\(title).mp3", sourcePath: "/fake",
            modificationDate: Date(timeIntervalSince1970: 1), fileSize: 1,
            volumeID: nil, fileID: nil, title: title, artist: "Artist",
            albumArtist: "Artist", albumTitle: "Album", year: 2024,
            duration: 60, hasArtwork: false, metadataVersion: currentMetadataVersion)
    }
}
