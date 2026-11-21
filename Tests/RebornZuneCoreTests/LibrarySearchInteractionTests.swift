import Observation
import XCTest
@testable import RebornZuneCore

@MainActor
final class LibrarySearchInteractionTests: XCTestCase {
    func testTextChangeClearsVisibleResultsAndDiscardsSupersededGeneration() async throws {
        let sleep = ControlledSleep()
        let controller = LibrarySearchController(search: { query in
            if query == "old" {
                try await sleep.sleep(5_000_000_000)
                return LibrarySearchResults(songs: [Self.snapshot(title: "Old")])
            }
            return LibrarySearchResults(songs: [Self.snapshot(title: "New")])
        }, sleep: { nanoseconds in
            try await sleep.sleep(nanoseconds)
        })

        controller.updateQuery("old")
        await sleep.waitForPending(200_000_000)
        sleep.resume(200_000_000)
        await sleep.waitForPending(5_000_000_000)

        controller.updateQuery("new")
        await sleep.waitForPending(200_000_000)
        XCTAssertTrue(controller.results.isEmpty)
        sleep.resume(200_000_000)
        for _ in 0..<100 {
            if controller.results.songs.map(\.title) == ["New"] { break }
            await Task.yield()
        }

        XCTAssertEqual(controller.results.songs.map(\.title), ["New"])
        XCTAssertEqual(controller.generation, 2)
        XCTAssertFalse(controller.showsLoadingIndicator)
    }

    func testLoadingIndicatorAppearsOnlyAfter150MillisecondsOfIncompleteQuery() async throws {
        let sleep = ControlledSleep()
        let controller = LibrarySearchController(search: { _ in
            try await sleep.sleep(400_000_000)
            return LibrarySearchResults()
        }, sleep: { nanoseconds in
            try await sleep.sleep(nanoseconds)
        })

        controller.updateQuery("slow")
        await sleep.waitForPending(200_000_000)
        XCTAssertFalse(controller.showsLoadingIndicator)

        sleep.resume(200_000_000)
        await sleep.waitForPending(150_000_000)
        XCTAssertFalse(controller.showsLoadingIndicator)

        sleep.resume(150_000_000)
        for _ in 0..<100 {
            if controller.showsLoadingIndicator { break }
            await Task.yield()
        }
        XCTAssertTrue(controller.showsLoadingIndicator)
        await sleep.waitForPending(400_000_000)

        sleep.resume(400_000_000)
        for _ in 0..<100 {
            if !controller.showsLoadingIndicator { break }
            await Task.yield()
        }
        XCTAssertFalse(controller.showsLoadingIndicator)
    }

    func testShowAllRetainsQueryAndLibraryRefreshPreservesOnlyStableSelection() async throws {
        let sleep = ControlledSleep()
        var songs = [Self.snapshot(title: "Keep"), Self.snapshot(title: "Remove")]
        let controller = LibrarySearchController(search: { _ in
            LibrarySearchResults(songs: songs)
        }, sleep: { nanoseconds in
            try await sleep.sleep(nanoseconds)
        })
        controller.updateQuery("needle")
        await sleep.waitForPending(200_000_000)
        sleep.resume(200_000_000)
        for _ in 0..<100 {
            if controller.results.songs.count == 2 { break }
            await Task.yield()
        }
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

    func testSelectionPublishesChangesToSwiftUIObservation() {
        let controller = LibrarySearchController(search: { _ in LibrarySearchResults() })
        let song = Self.snapshot(title: "Selected")
        let publication = XCTestExpectation(description: "Selection published to SwiftUI")
        withObservationTracking {
            _ = controller.selectedResultID
        } onChange: {
            publication.fulfill()
        }

        controller.select(songID: song.id)

        wait(for: [publication], timeout: 0.1)
        XCTAssertEqual(controller.selectedSongID, song.id)
    }

    func testRepeatedDownNavigationWalksEveryShowAllResult() {
        let items = (0..<17).map {
            LibrarySearchNavigationItem(id: "song:\($0)", group: .songs, index: $0, columns: 1)
        }
        var selectedID: String?

        for expectedIndex in 0..<17 {
            selectedID = LibrarySearchNavigation.move(from: selectedID, direction: .down, in: items)
            XCTAssertEqual(selectedID, "song:\(expectedIndex)")
        }
    }

    private final class ControlledSleep: @unchecked Sendable {
        private let lock = NSLock()
        private var pending: [UInt64: CheckedContinuation<Void, Error>] = [:]

        func sleep(_ nanoseconds: UInt64) async throws {
            try await withTaskCancellationHandler(
                operation: {
                    try await withCheckedThrowingContinuation {
                        (continuation: CheckedContinuation<Void, Error>) in
                        let isCancelled = lock.withLock {
                            if Task.isCancelled { return true }
                            pending[nanoseconds] = continuation
                            return false
                        }
                        if isCancelled { continuation.resume(throwing: CancellationError()) }
                    }
                },
                onCancel: { cancel(nanoseconds) }
            )
        }

        func waitForPending(_ nanoseconds: UInt64) async {
            for _ in 0..<100 {
                if hasPending(nanoseconds) { return }
                await Task.yield()
            }
            XCTFail("Expected a pending sleep of \(nanoseconds) ns")
        }

        func resume(_ nanoseconds: UInt64) {
            take(nanoseconds)?.resume()
        }

        private func hasPending(_ nanoseconds: UInt64) -> Bool {
            lock.withLock { pending[nanoseconds] != nil }
        }

        private func take(_ nanoseconds: UInt64) -> CheckedContinuation<Void, Error>? {
            lock.withLock { pending.removeValue(forKey: nanoseconds) }
        }

        private func cancel(_ nanoseconds: UInt64) {
            take(nanoseconds)?.resume(throwing: CancellationError())
        }
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
