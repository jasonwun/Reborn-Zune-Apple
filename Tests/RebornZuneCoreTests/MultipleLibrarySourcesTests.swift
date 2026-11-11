import XCTest
import SwiftData
@testable import RebornZuneCore

final class MultiFakeSource: LibraryFileSource, @unchecked Sendable {
    let sourcePath: String
    private let lock = NSLock()
    private var _files: [DiscoveredFile] = []
    private var _error: Error?
    private var _delay: UInt64 = 0

    init(_ sourcePath: String) { self.sourcePath = sourcePath }
    var files: [DiscoveredFile] {
        get { lock.withLock { _files } }
        set { lock.withLock { _files = newValue } }
    }
    var error: Error? {
        get { lock.withLock { _error } }
        set { lock.withLock { _error = newValue } }
    }
    var delayNanos: UInt64 {
        get { lock.withLock { _delay } }
        set { lock.withLock { _delay = newValue } }
    }

    func discover() async throws -> [DiscoveredFile] {
        if delayNanos > 0 { try await Task.sleep(nanoseconds: delayNanos) }
        if let error { throw error }
        return files
    }

    func extract(_ file: DiscoveredFile) async throws -> ExtractedMetadata {
        ExtractedMetadata(title: URL(fileURLWithPath: file.path).lastPathComponent, duration: 60)
    }
}

final class FakeBookmarkAccess: LibraryBookmarkAccessing, @unchecked Sendable {
    private let lock = NSLock()
    private var _created: [String] = []
    private var _starts = 0
    private var _stops = 0
    private var _startError: Error?

    var allowsAutomaticBookmarkCreation = true
    var created: [String] { lock.withLock { _created } }
    var starts: Int { lock.withLock { _starts } }
    var stops: Int { lock.withLock { _stops } }
    var startError: Error? {
        get { lock.withLock { _startError } }
        set { lock.withLock { _startError = newValue } }
    }

    func createBookmark(for url: URL) throws -> Data {
        lock.withLock { _created.append(url.path) }
        return Data("bookmark:\(url.path)".utf8)
    }

    func startAccessing(bookmark: Data, at url: URL) throws -> any LibraryBookmarkSession {
        if let startError { throw startError }
        lock.withLock { _starts += 1 }
        return FakeBookmarkSession(url: url, refreshedBookmark: Data("refreshed:\(url.path)".utf8)) { [weak self] in
            self?.lock.withLock { self?._stops += 1 }
        }
    }
}

final class FakeBookmarkSession: LibraryBookmarkSession, @unchecked Sendable {
    let url: URL
    let refreshedBookmark: Data?
    private let onStop: () -> Void
    init(url: URL, refreshedBookmark: Data?, onStop: @escaping () -> Void) {
        self.url = url
        self.refreshedBookmark = refreshedBookmark
        self.onStop = onStop
    }
    func stop() { onStop() }
}

@MainActor
final class MultipleLibrarySourcesTests: XCTestCase {
    private var directory: URL!
    private var storeURL: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("multi-library-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        storeURL = directory.appendingPathComponent("test.store")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func container() throws -> ModelContainer {
        try RebornZunePersistence.makePersistentContainer(at: storeURL)
    }

    private func coordinator(
        _ container: ModelContainer,
        sources: [MultiFakeSource],
        factory: @escaping @Sendable (URL) -> any LibraryFileSource = { FolderFileSource(root: $0) },
        bookmarks: any LibraryBookmarkAccessing = NoLibraryBookmarkAccess()
    ) -> LibraryCoordinator {
        LibraryCoordinator(container: container, sources: sources, sourceFactory: factory,
                           bookmarkAccess: bookmarks)
    }

    private func file(_ source: String, _ name: String) -> DiscoveredFile {
        DiscoveredFile(
            path: "\(source)/\(name)",
            modificationDate: Date(timeIntervalSince1970: 5_000),
            fileSize: 10
        )
    }

    func testScanBuildsUnionWithCommittedCountsForEverySource() async throws {
        let first = MultiFakeSource("/fake/A")
        let second = MultiFakeSource("/fake/B")
        first.files = [file(first.sourcePath, "one.mp3")]
        second.files = [file(second.sourcePath, "two.mp3"), file(second.sourcePath, "three.mp3")]
        let coordinator = coordinator(try container(), sources: [first, second])

        await coordinator.start()

        XCTAssertEqual(coordinator.tracks.count, 3)
        XCTAssertEqual(coordinator.sources.map(\.committedTrackCount), [1, 2])
        XCTAssertEqual(coordinator.sources.reduce(0) { $0 + $1.committedTrackCount }, coordinator.tracks.count)
    }

    func testRemovingSourceDeletesOnlyItsTracksAndLinkedData() async throws {
        let first = MultiFakeSource("/fake/A")
        let second = MultiFakeSource("/fake/B")
        first.files = [file(first.sourcePath, "one.mp3")]
        second.files = [file(second.sourcePath, "two.mp3")]
        let container = try container()
        let coordinator = coordinator(container, sources: [first, second])
        await coordinator.start()
        let removedID = coordinator.tracks.first { $0.title == "one.mp3" }!.id
        let retainedID = coordinator.tracks.first { $0.title == "two.mp3" }!.id
        let context = ModelContext(container)
        let playlist = StoredPlaylist(name: "Mixed")
        context.insert(playlist)
        context.insert(StoredPlaylistEntry(orderIndex: 0, musicID: "one",
                                           trackID: UUID(uuidString: removedID), playlist: playlist))
        context.insert(StoredPlaylistEntry(orderIndex: 1, musicID: "two",
                                           trackID: UUID(uuidString: retainedID), playlist: playlist))
        try context.save()
        let history = PlayHistory(container: container)
        for id in [removedID, retainedID] {
            try history.record(.start(id: UUID(), trackID: id, reason: .actual))
        }

        try await coordinator.removeSource(first.sourcePath)

        XCTAssertEqual(coordinator.tracks.map(\.id), [retainedID])
        XCTAssertEqual(try history.historyEntries().map(\.trackID), [UUID(uuidString: retainedID)])
        XCTAssertEqual(try history.playbackStats().map(\.trackID), [UUID(uuidString: retainedID)])
        XCTAssertEqual(coordinator.sources.map(\.path), [second.sourcePath])
        let entries = try ModelContext(container).fetch(FetchDescriptor<StoredPlaylistEntry>())
        XCTAssertEqual(entries.map(\.trackID), [UUID(uuidString: retainedID)])
        XCTAssertEqual(coordinator.sources[0].committedTrackCount, 1)
    }

    func testMissingVolumeDuringBookmarkResolutionUsesUnavailableCleanup() async throws {
        let source = MultiFakeSource("/fake/Volume/Music")
        source.files = [file(source.sourcePath, "one.mp3")]
        let bookmarks = FakeBookmarkAccess()
        let coordinator = coordinator(try container(), sources: [source], bookmarks: bookmarks)
        await coordinator.start()
        XCTAssertEqual(coordinator.tracks.count, 1)

        bookmarks.startError = CocoaError(.fileNoSuchFile)
        await coordinator.refresh()

        XCTAssertTrue(coordinator.tracks.isEmpty)
        XCTAssertFalse(coordinator.sources[0].isAvailable)
        XCTAssertEqual(coordinator.sources[0].committedTrackCount, 0)
    }

    func testUnavailableRootRetainsConfigurationClearsOnlyThatSourceAndRecoversWithNewIdentity() async throws {
        let first = MultiFakeSource("/fake/A")
        let second = MultiFakeSource("/fake/B")
        first.files = [file(first.sourcePath, "one.mp3")]
        second.files = [file(second.sourcePath, "two.mp3")]
        let container = try container()
        let coordinator = coordinator(container, sources: [first, second])
        await coordinator.start()
        let oldID = coordinator.tracks.first { $0.title == "one.mp3" }!.id
        let unrelatedID = coordinator.tracks.first { $0.title == "two.mp3" }!.id
        let history = PlayHistory(container: container)
        for id in [oldID, unrelatedID] {
            try history.record(.start(id: UUID(), trackID: id, reason: .actual))
        }

        first.error = LibraryScanError.sourceUnavailable(first.sourcePath)
        await coordinator.refresh()

        XCTAssertEqual(coordinator.tracks.map(\.id), [unrelatedID])
        XCTAssertEqual(try history.historyEntries().map(\.trackID), [UUID(uuidString: unrelatedID)])
        XCTAssertEqual(try history.playbackStats().map(\.trackID), [UUID(uuidString: unrelatedID)])
        XCTAssertEqual(coordinator.sources.count, 2)
        XCTAssertFalse(coordinator.sources[0].isAvailable)
        XCTAssertEqual(coordinator.sources[0].committedTrackCount, 0)
        XCTAssertTrue(coordinator.sources[1].isAvailable)
        XCTAssertEqual(coordinator.sources[1].committedTrackCount, 1)

        first.error = nil
        await coordinator.retry()
        let recovered = try XCTUnwrap(coordinator.tracks.first { $0.title == "one.mp3" })
        XCTAssertNotEqual(recovered.id, oldID)
        XCTAssertTrue(coordinator.sources[0].isAvailable)
        XCTAssertEqual(coordinator.sources[0].committedTrackCount, 1)
    }

    func testDefaultSourceWithoutUserSelectionRequiresGrantInsteadOfAutomaticBookmark() async throws {
        let source = MultiFakeSource("/fake/Music")
        source.files = [file(source.sourcePath, "one.mp3")]
        let bookmarks = FakeBookmarkAccess()
        bookmarks.allowsAutomaticBookmarkCreation = false
        let coordinator = coordinator(try container(), sources: [source], bookmarks: bookmarks)

        await coordinator.start()

        XCTAssertEqual(coordinator.phase, .failed)
        XCTAssertTrue(coordinator.tracks.isEmpty)
        XCTAssertEqual(coordinator.sources.map(\.bookmarkData), [nil])
        XCTAssertTrue(bookmarks.created.isEmpty)
        XCTAssertEqual(coordinator.scanError,
                       LibraryBookmarkError.accessDenied(source.sourcePath).localizedDescription)
    }

    func testOpenPanelGrantPersistsPerSourceBookmarkAcrossRelaunch() async throws {
        let source = MultiFakeSource("/fake/Music")
        source.files = [file(source.sourcePath, "one.mp3")]
        let bookmarks = FakeBookmarkAccess()
        bookmarks.allowsAutomaticBookmarkCreation = false
        let container = try container()
        let coordinator = coordinator(container, sources: [source], bookmarks: bookmarks)
        await coordinator.start()

        try await coordinator.grantAccess(
            to: source.sourcePath,
            selectedURL: URL(fileURLWithPath: source.sourcePath))

        XCTAssertEqual(coordinator.phase, .ready)
        XCTAssertEqual(coordinator.tracks.count, 1)
        XCTAssertEqual(bookmarks.created, [source.sourcePath])
        XCTAssertNotNil(coordinator.sources[0].bookmarkData)
        XCTAssertEqual(bookmarks.starts, bookmarks.stops)

        let relaunched = self.coordinator(container, sources: [source], bookmarks: bookmarks)
        await relaunched.start()

        XCTAssertEqual(relaunched.phase, .ready)
        XCTAssertEqual(relaunched.tracks.map(\.id), coordinator.tracks.map(\.id))
        XCTAssertEqual(bookmarks.created, [source.sourcePath], "relaunch resolves the saved bookmark without a new grant")
        XCTAssertEqual(bookmarks.starts, bookmarks.stops)
    }

    func testDeniedBookmarkMarksSourceForGrantAndSuccessfulGrantClearsIt() async throws {
        let source = MultiFakeSource("/fake/Music")
        source.files = [file(source.sourcePath, "one.mp3")]
        let bookmarks = FakeBookmarkAccess()
        let coordinator = coordinator(try container(), sources: [source], bookmarks: bookmarks)
        await coordinator.start()

        bookmarks.startError = LibraryBookmarkError.accessDenied(source.sourcePath)
        await coordinator.refresh()

        XCTAssertEqual(coordinator.sourcePathsRequiringAuthorization, [source.sourcePath])
        XCTAssertEqual(coordinator.phase, .ready, "the last committed Library remains browsable")
        XCTAssertEqual(coordinator.tracks.count, 1)

        bookmarks.startError = nil
        try await coordinator.grantAccess(
            to: source.sourcePath,
            selectedURL: URL(fileURLWithPath: source.sourcePath))

        XCTAssertTrue(coordinator.sourcePathsRequiringAuthorization.isEmpty)
        XCTAssertNil(coordinator.scanError)
    }

    func testUnreadableDefaultSourceAlsoOffersOpenPanelGrant() async throws {
        let source = MultiFakeSource("/fake/Music")
        source.files = [file(source.sourcePath, "one.mp3")]
        let bookmarks = FakeBookmarkAccess()
        let coordinator = coordinator(try container(), sources: [source], bookmarks: bookmarks)
        await coordinator.start()

        source.error = LibraryScanError.incompleteEnumeration(source.sourcePath)
        await coordinator.refresh()

        XCTAssertEqual(coordinator.sourcePathsRequiringAuthorization, [source.sourcePath])
        XCTAssertEqual(coordinator.tracks.count, 1, "read failure preserves the committed Library")
        XCTAssertNotNil(coordinator.scanError)
    }

    func testBookmarksAreIndependentRefreshedAndBalancedOnSuccessFailureAndCancellation() async throws {
        let first = MultiFakeSource("/fake/A")
        let second = MultiFakeSource("/fake/B")
        let bookmarks = FakeBookmarkAccess()
        let coordinator = coordinator(try container(), sources: [first, second], bookmarks: bookmarks)

        await coordinator.start()

        XCTAssertEqual(Set(bookmarks.created), Set([first.sourcePath, second.sourcePath]))
        XCTAssertEqual(coordinator.sources.map(\.bookmarkData), [
            Data("refreshed:/fake/A".utf8), Data("refreshed:/fake/B".utf8),
        ])
        XCTAssertEqual(bookmarks.starts, bookmarks.stops)

        first.error = Boom()
        await coordinator.refresh()
        XCTAssertEqual(bookmarks.starts, bookmarks.stops, "failed discovery must stop access")

        first.error = nil
        first.delayNanos = 300_000_000
        let scan = Task { await coordinator.refresh() }
        try await Task.sleep(nanoseconds: 50_000_000)
        coordinator.cancelScan()
        await scan.value
        XCTAssertEqual(bookmarks.starts, bookmarks.stops, "cancellation must stop access")
    }

    func testPlaybackAccessResolvesTheOwningSourceBookmark() async throws {
        let first = MultiFakeSource("/fake/A")
        let second = MultiFakeSource("/fake/B")
        first.files = [file(first.sourcePath, "one.mp3")]
        second.files = [file(second.sourcePath, "two.mp3")]
        let bookmarks = FakeBookmarkAccess()
        let coordinator = coordinator(
            try container(), sources: [first, second], bookmarks: bookmarks)
        await coordinator.start()
        let startsAfterScanning = bookmarks.starts
        let stopsAfterScanning = bookmarks.stops

        let session = try coordinator.startPlaybackAccess(
            for: URL(fileURLWithPath: "/fake/B/album/two.mp3"))

        XCTAssertEqual(session.url.path, second.sourcePath)
        XCTAssertEqual(bookmarks.starts, startsAfterScanning + 1)
        session.stop()
        XCTAssertEqual(bookmarks.stops, stopsAfterScanning + 1)
    }

    func testProgressCountsUniqueNormalizedURLsAcrossSources() async throws {
        let first = MultiFakeSource("/fake/A")
        let second = MultiFakeSource("/fake/B")
        let one = file(first.sourcePath, "one.mp3")
        let normalizedDuplicate = DiscoveredFile(
            path: "/fake/A/../A/one.mp3", modificationDate: one.modificationDate, fileSize: 10)
        first.files = [one, normalizedDuplicate]
        second.files = [file(second.sourcePath, "two.mp3"), one]
        let coordinator = coordinator(try container(), sources: [first, second])

        await coordinator.start()

        XCTAssertEqual(coordinator.discoveredTrackCount, 2)
        XCTAssertEqual(coordinator.tracks.count, 2)
        XCTAssertEqual(Set(coordinator.tracks.map(\.id)).count, 2)
        XCTAssertEqual(coordinator.sources.map(\.committedTrackCount), [1, 1])
    }

    func testCancellationKeepsOldUnionAndCommittedCountsVisible() async throws {
        let first = MultiFakeSource("/fake/A")
        let second = MultiFakeSource("/fake/B")
        first.files = [file(first.sourcePath, "old.mp3")]
        second.files = [file(second.sourcePath, "two.mp3")]
        let coordinator = coordinator(try container(), sources: [first, second])
        await coordinator.start()
        let oldTracks = coordinator.tracks
        let oldCounts = coordinator.sources.map(\.committedTrackCount)

        first.files = [file(first.sourcePath, "new.mp3")]
        second.delayNanos = 300_000_000
        let scan = Task { await coordinator.refresh() }
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(coordinator.isScanning)
        XCTAssertEqual(coordinator.tracks, oldTracks)
        coordinator.cancelScan()
        await scan.value

        XCTAssertEqual(coordinator.tracks, oldTracks)
        XCTAssertEqual(coordinator.sources.map(\.committedTrackCount), oldCounts)
        XCTAssertNotNil(coordinator.scanError)
    }

    func testFailedSourcePreservesWholePreviousUnionAndCountsForRetry() async throws {
        let first = MultiFakeSource("/fake/A")
        let second = MultiFakeSource("/fake/B")
        first.files = [file(first.sourcePath, "one.mp3")]
        second.files = [file(second.sourcePath, "two.mp3")]
        let coordinator = coordinator(try container(), sources: [first, second])
        await coordinator.start()
        let oldTracks = coordinator.tracks

        first.files = [file(first.sourcePath, "replacement.mp3")]
        second.error = Boom()
        await coordinator.refresh()

        XCTAssertEqual(coordinator.tracks, oldTracks)
        XCTAssertEqual(coordinator.sources.map(\.committedTrackCount), [1, 1])
        XCTAssertEqual(coordinator.scanError, "Boom")

        second.error = nil
        await coordinator.retry()
        XCTAssertTrue(coordinator.tracks.contains { $0.title == "replacement.mp3" })
        XCTAssertNil(coordinator.scanError)
    }

    func testZeroSourcesSurvivesRelaunchWithoutResurrectingDefault() async throws {
        let source = MultiFakeSource("/fake/Default")
        source.files = [file(source.sourcePath, "one.mp3")]
        let container = try container()
        let coordinator = coordinator(container, sources: [source])
        await coordinator.start()
        try await coordinator.removeSource(source.sourcePath)
        XCTAssertTrue(coordinator.sources.isEmpty)
        XCTAssertTrue(coordinator.tracks.isEmpty)

        let relaunched = self.coordinator(container, sources: [source])
        await relaunched.start()

        XCTAssertTrue(relaunched.sources.isEmpty)
        XCTAssertTrue(relaunched.tracks.isEmpty)
        XCTAssertEqual(relaunched.phase, .empty)
    }

    func testAddingSourcePersistsBookmarkAndImmediatelyScansIntoUnion() async throws {
        let first = MultiFakeSource("/fake/A")
        let added = MultiFakeSource("/fake/B")
        first.files = [file(first.sourcePath, "one.mp3")]
        added.files = [file(added.sourcePath, "two.mp3")]
        let bookmarks = FakeBookmarkAccess()
        let coordinator = coordinator(
            try container(), sources: [first], factory: { _ in added }, bookmarks: bookmarks)
        await coordinator.start()

        try await coordinator.addSource(URL(fileURLWithPath: added.sourcePath))

        XCTAssertEqual(coordinator.tracks.count, 2)
        XCTAssertEqual(coordinator.sources.map(\.committedTrackCount), [1, 1])
        XCTAssertEqual(Set(bookmarks.created), Set([first.sourcePath, added.sourcePath]))
        XCTAssertNotEqual(coordinator.sources[0].bookmarkData, coordinator.sources[1].bookmarkData)
        XCTAssertEqual(bookmarks.starts, bookmarks.stops)
    }

    func testAddingRejectsDuplicateAncestorAndDescendantUsingPathComponents() async throws {
        let existing = MultiFakeSource("/fake/Music/A")
        let coordinator = coordinator(try container(), sources: [existing])
        await coordinator.start()

        for candidate in ["/fake/Music/A", "/fake/Music", "/fake/Music/A/Album"] {
            do {
                try await coordinator.addSource(URL(fileURLWithPath: candidate))
                XCTFail("Expected \(candidate) to be rejected")
            } catch let error as LibrarySourceError {
                guard case .overlappingSource(_, let conflict) = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
                XCTAssertEqual(conflict, existing.sourcePath)
            }
        }

        try await coordinator.addSource(URL(fileURLWithPath: "/fake/Music/AB"))
        XCTAssertEqual(coordinator.sources.map(\.path), [existing.sourcePath, "/fake/Music/AB"])
    }
}
