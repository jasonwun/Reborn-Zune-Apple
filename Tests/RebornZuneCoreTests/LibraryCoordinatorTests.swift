import XCTest
import SwiftData
@testable import RebornZuneCore

/// Fake Library Source: scripted discovery results, counted extractions.
final class FakeSource: LibraryFileSource, @unchecked Sendable {
    let sourcePath = "/fake"
    private let lock = NSLock()
    private var _files: [DiscoveredFile] = []
    private var _error: Error?
    private var _extractions: [String] = []
    private var _failExtraction = Set<String>()
    private var _delay: UInt64 = 0
    private var _metadata: ExtractedMetadata?

    var files: [DiscoveredFile] { get { lock.withLock { _files } } set { lock.withLock { _files = newValue } } }
    var error: Error? { get { lock.withLock { _error } } set { lock.withLock { _error = newValue } } }
    var extractions: [String] { lock.withLock { _extractions } }
    var delayNanos: UInt64 { get { lock.withLock { _delay } } set { lock.withLock { _delay = newValue } } }
    var metadata: ExtractedMetadata? { get { lock.withLock { _metadata } } set { lock.withLock { _metadata = newValue } } }
    func failExtraction(of path: String) { lock.withLock { _ = _failExtraction.insert(path) } }

    func discover() async throws -> [DiscoveredFile] {
        if let e = error { throw e }
        return files
    }
    func extract(_ file: DiscoveredFile) async throws -> ExtractedMetadata {
        let d = delayNanos
        if d > 0 { try await Task.sleep(nanoseconds: d) }
        let fail = lock.withLock { _extractions.append(file.path); return _failExtraction.contains(file.path) }
        if fail { throw CocoaError(.fileReadCorruptFile) }
        if let metadata { return metadata }
        return ExtractedMetadata(title: (file.path as NSString).lastPathComponent,
                                 artist: "Artist", albumTitle: "Album", duration: 60,
                                 artworkData: Data([1, 2, 3]))
    }
}

struct Boom: LocalizedError { var errorDescription: String? { "Boom" } }

@MainActor
final class LibraryCoordinatorTests: XCTestCase {
    private var dir: URL!
    private var storeURL: URL!
    private let t0 = Date(timeIntervalSince1970: 5_000)

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("lib-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storeURL = dir.appendingPathComponent("test.store")
    }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: dir) }

    private func container() throws -> ModelContainer {
        try RebornZunePersistence.makePersistentContainer(at: storeURL)
    }
    private func file(_ name: String, id: String? = nil, mod: Date? = nil) -> DiscoveredFile {
        DiscoveredFile(path: "/fake/\(name)", modificationDate: mod ?? t0, fileSize: 10,
                       volumeID: Data("v".utf8), fileID: Data((id ?? name).utf8))
    }
    private func coordinator(_ c: ModelContainer, _ s: FakeSource) -> LibraryCoordinator {
        LibraryCoordinator(container: c, source: s)
    }

    func testImportPersistsAcrossRelaunchWithSameIdentitiesBeforeRefresh() async throws {
        let source = FakeSource()
        source.files = [file("a.mp3"), file("b.mp3")]
        let first = coordinator(try container(), source)
        await first.start()
        XCTAssertEqual(first.phase, .ready)
        XCTAssertEqual(first.tracks.count, 2)
        let ids = Set(first.tracks.map(\.id))
        XCTAssertTrue(ids.allSatisfy { UUID(uuidString: $0) != nil })
        XCTAssertNotNil(first.tracks.first?.artworkData)

        // Relaunch: new container on the same store; the scan itself fails,
        // yet the committed Library is visible with the same identities.
        let relaunchSource = FakeSource()
        relaunchSource.error = Boom()
        let second = coordinator(try container(), relaunchSource)
        await second.start()
        XCTAssertEqual(Set(second.tracks.map(\.id)), ids)
        XCTAssertEqual(second.phase, .ready)
        XCTAssertEqual(second.scanError, "Boom")
    }

    func testLaunchPublishesOnePageAndLoadsMoreOnDemand() async throws {
        let source = FakeSource()
        source.files = (0..<101).map { file(String(format: "%03d.mp3", $0)) }
        let c = coordinator(try container(), source)

        await c.start()

        XCTAssertEqual(c.totalTrackCount, 101)
        XCTAssertEqual(c.tracks.count, 100)
        XCTAssertTrue(c.hasMoreTracks)

        await c.loadNextPage()

        XCTAssertEqual(c.tracks.count, 101)
        XCTAssertFalse(c.hasMoreTracks)
        XCTAssertEqual(Set(c.tracks.map(\.id)).count, 101)
    }

    func testBrowsingUsesStorePredicateInsteadOfFilteringLoadedPage() async throws {
        let source = FakeSource()
        source.files = (0..<101).map { file(String(format: "%03d.mp3", $0)) }
        let c = coordinator(try container(), source)
        await c.start()
        XCTAssertFalse(c.tracks.contains { $0.title == "100.mp3" })

        await c.browse(matching: LibraryTrackQuery(searchText: "100"))

        XCTAssertEqual(c.totalTrackCount, 1)
        XCTAssertEqual(c.tracks.map(\.title), ["100.mp3"])
        XCTAssertFalse(c.hasMoreTracks)
    }

    func testNewerBrowseQueryDoesNotAcceptOlderPageResults() async throws {
        let source = FakeSource()
        source.files = (0..<101).map { file(String(format: "%03d.mp3", $0)) }
        let c = coordinator(try container(), source)
        await c.start()

        let oldPage = Task { await c.loadNextPage() }
        await Task.yield()
        await c.browse(matching: LibraryTrackQuery(searchText: "100"))
        await oldPage.value

        XCTAssertEqual(c.totalTrackCount, 1)
        XCTAssertEqual(c.tracks.map(\.title), ["100.mp3"])
    }

    func testAlbumDetailLoadsTracksBeyondTheBrowsingPage() async throws {
        let source = FakeSource()
        source.files = (0..<101).map { file(String(format: "%03d.mp3", $0)) }
        let c = coordinator(try container(), source)
        await c.start()
        let partial = try XCTUnwrap(ResonantLibrary.from(tracks: c.tracks).albums.first)
        XCTAssertEqual(partial.tracks.count, 100)

        let loaded = await c.loadAlbum(partial)
        let album = try XCTUnwrap(loaded)

        XCTAssertEqual(album.id, partial.id)
        XCTAssertEqual(album.tracks.count, 101)
    }

    func testArtistDetailLoadsTracksBeyondTheBrowsingPage() async throws {
        let source = FakeSource()
        source.files = (0..<101).map { file(String(format: "%03d.mp3", $0)) }
        let c = coordinator(try container(), source)
        await c.start()
        let partial = try XCTUnwrap(ResonantLibrary.from(tracks: c.tracks).artists.first)
        XCTAssertEqual(partial.albums.flatMap(\.tracks).count, 100)

        let loaded = await c.loadArtist(partial)

        XCTAssertEqual(loaded?.id, partial.id)
        XCTAssertEqual(loaded?.albums.flatMap(\.tracks).count, 101)
    }

    func testUnknownAlbumDetailUsesTheSameFallbackGroupingRules() async throws {
        let source = FakeSource()
        source.files = [file("a.mp3")]
        source.metadata = ExtractedMetadata(title: "Untitled", duration: 60)
        let c = coordinator(try container(), source)
        await c.start()
        let partial = try XCTUnwrap(ResonantLibrary.from(tracks: c.tracks).albums.first)
        XCTAssertEqual(partial.title, "Unknown Album")
        XCTAssertEqual(partial.albumArtist, "Unknown Artist")

        let loaded = await c.loadAlbum(partial)

        XCTAssertEqual(loaded?.tracks.map(\.title), ["Untitled"])
    }

    func testInitialImportPersistsTrackDiscAndGenreAcrossRelaunch() async throws {
        let container = try container()
        let source = FakeSource()
        source.files = [file("a.mp3")]
        source.metadata = ExtractedMetadata(
            title: "Real Title", artist: "Artist", albumTitle: "Album",
            trackNumber: 4, discNumber: 2, genre: "Jazz", duration: 60
        )
        let first = coordinator(container, source)
        await first.start()

        XCTAssertEqual(first.tracks.first?.trackNumber, 4)
        XCTAssertEqual(first.tracks.first?.discNumber, 2)
        XCTAssertEqual(first.tracks.first?.genre, "Jazz")

        let unavailable = FakeSource()
        unavailable.error = Boom()
        let second = coordinator(container, unavailable)
        await second.start()
        XCTAssertEqual(second.tracks.first?.trackNumber, 4)
        XCTAssertEqual(second.tracks.first?.discNumber, 2)
        XCTAssertEqual(second.tracks.first?.genre, "Jazz")
    }

    func testEmptyScanIsEmptyNotFailedAndNeverDemo() async throws {
        let source = FakeSource()
        let c = coordinator(try container(), source)
        await c.start()
        XCTAssertEqual(c.phase, .empty)
        XCTAssertTrue(c.tracks.isEmpty)
        XCTAssertNil(c.scanError)
    }

    func testFailedFirstScanIsFailedWithRetry() async throws {
        let source = FakeSource()
        source.error = Boom()
        let c = coordinator(try container(), source)
        await c.start()
        XCTAssertEqual(c.phase, .failed)
        XCTAssertEqual(c.scanError, "Boom")
        source.error = nil
        source.files = [file("a.mp3")]
        await c.retry()
        XCTAssertEqual(c.phase, .ready)
        XCTAssertNil(c.scanError)
        XCTAssertEqual(c.tracks.count, 1)
    }

    func testFailureAfterImportPreservesLibraryAndSkipsCleanup() async throws {
        let source = FakeSource()
        source.files = [file("a.mp3"), file("b.mp3")]
        let c = coordinator(try container(), source)
        await c.start()
        source.error = LibraryScanError.incompleteEnumeration("/fake")
        source.files = []
        await c.refresh()
        XCTAssertEqual(c.tracks.count, 2)
        XCTAssertEqual(c.phase, .ready)
        XCTAssertNotNil(c.scanError)
    }

    func testIncrementalScanSkipsUnchangedExtraction() async throws {
        let source = FakeSource()
        source.files = [file("a.mp3"), file("b.mp3")]
        let c = coordinator(try container(), source)
        await c.start()
        XCTAssertEqual(source.extractions.count, 2)
        await c.refresh()
        XCTAssertEqual(source.extractions.count, 2, "unchanged files are not re-extracted")
        source.files = [file("a.mp3", mod: t0 + 9), file("b.mp3")]
        await c.refresh()
        XCTAssertEqual(source.extractions.count, 3)
        XCTAssertEqual(c.tracks.count, 2)
    }

    func testMetadataVersionBackfillsOnceThenReturnsToIncrementalScanning() async throws {
        let container = try container()
        let source = FakeSource()
        source.files = [file("a.mp3")]
        let coordinator = coordinator(container, source)
        await coordinator.start()
        XCTAssertEqual(source.extractions.count, 1)

        let context = ModelContext(container)
        let stored = try XCTUnwrap(context.fetch(FetchDescriptor<StoredTrack>()).first)
        stored.metadataVersion = 1
        stored.trackNumber = nil
        stored.discNumber = nil
        stored.genre = nil
        try context.save()
        source.metadata = ExtractedMetadata(
            title: "Real Title", trackNumber: 6, discNumber: 2, genre: "Ambient"
        )

        await coordinator.refresh()
        XCTAssertEqual(currentMetadataVersion, 2)
        XCTAssertEqual(source.extractions.count, 2, "version 1 rows are re-extracted despite an unchanged fingerprint")
        XCTAssertEqual(coordinator.tracks.first?.trackNumber, 6)
        XCTAssertEqual(coordinator.tracks.first?.discNumber, 2)
        XCTAssertEqual(coordinator.tracks.first?.genre, "Ambient")

        await coordinator.refresh()
        XCTAssertEqual(source.extractions.count, 2, "the backfill does not repeat after rows reach version 2")
    }

    func testMoveKeepsIdentityAndCopyGetsNewOne() async throws {
        let source = FakeSource()
        source.files = [file("a.mp3", id: "F1")]
        let c = coordinator(try container(), source)
        await c.start()
        let original = c.tracks[0].id
        source.files = [file("moved/a.mp3", id: "F1")]
        await c.refresh()
        XCTAssertEqual(c.tracks.map(\.id), [original])
        XCTAssertEqual(c.tracks[0].url.path, "/fake/moved/a.mp3")
        source.files = [file("moved/a.mp3", id: "F1"), file("copy.mp3", id: "F2")]
        await c.refresh()
        XCTAssertEqual(c.tracks.count, 2)
        XCTAssertEqual(Set(c.tracks.map(\.id)).count, 2)
        XCTAssertTrue(c.tracks.contains { $0.id == original })
    }

    func testConfirmedMissingDeletesTrackAndItsPlaylistReferencesOnly() async throws {
        let container = try container()
        let source = FakeSource()
        source.files = [file("a.mp3"), file("b.mp3")]
        let c = coordinator(container, source)
        await c.start()
        let a = c.tracks.first { $0.title == "a.mp3" }!.id
        let b = c.tracks.first { $0.title == "b.mp3" }!.id

        let ctx = ModelContext(container)
        let pl = StoredPlaylist(name: "P")
        ctx.insert(pl)
        ctx.insert(StoredPlaylistEntry(orderIndex: 0, musicID: "x", trackID: UUID(uuidString: a), playlist: pl))
        ctx.insert(StoredPlaylistEntry(orderIndex: 1, musicID: "y", trackID: UUID(uuidString: b), playlist: pl))
        try ctx.save()

        source.files = [file("b.mp3")]
        await c.refresh()
        XCTAssertEqual(c.tracks.map(\.id), [b])
        let entries = try ModelContext(container).fetch(FetchDescriptor<StoredPlaylistEntry>())
        XCTAssertEqual(entries.map(\.trackID), [UUID(uuidString: b)])
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<StoredPlaylist>()).count, 1)
    }

    func testConfirmedMissingDeletesHistoryAndStatsButFailedScanPreservesThem() async throws {
        let container = try container()
        let source = FakeSource()
        source.files = [file("a.mp3"), file("b.mp3")]
        let coordinator = coordinator(container, source)
        await coordinator.start()
        let a = try XCTUnwrap(coordinator.tracks.first { $0.title == "a.mp3" }?.id)
        let b = try XCTUnwrap(coordinator.tracks.first { $0.title == "b.mp3" }?.id)
        let history = PlayHistory(container: container, now: { self.t0 })
        for id in [a, b] {
            try history.record(.start(id: UUID(), trackID: id, reason: .actual))
        }

        source.error = Boom()
        source.files = []
        await coordinator.refresh()
        XCTAssertEqual(try history.historyEntries().count, 2)
        XCTAssertEqual(try history.playbackStats().count, 2)

        source.error = nil
        source.files = [file("b.mp3")]
        await coordinator.refresh()
        XCTAssertEqual(try history.historyEntries().map(\.trackID), [UUID(uuidString: b)])
        XCTAssertEqual(try history.playbackStats().map(\.trackID), [UUID(uuidString: b)])
    }

    func testPlaylistTracksLoadByIdentityOutsideTheBrowsingPage() async throws {
        let container = try container()
        let source = FakeSource()
        source.files = (0..<101).map { file(String(format: "%03d.mp3", $0)) }
        let c = coordinator(container, source)
        await c.start()
        let store = LibraryStore(modelContainer: container)
        let stored = try await store.snapshots(sourcePath: "/fake")
        let target = try XCTUnwrap(stored.first { $0.title == "100.mp3" })

        let tracks = await c.loadTracks(withIDs: [target.id.uuidString])

        XCTAssertEqual(tracks.map(\.title), ["100.mp3"])
        XCTAssertEqual(tracks.map(\.id), [target.id.uuidString])
    }

    func testCommittedIdentityLookupOnlyReturnsRequestedExistingTracks() async throws {
        let source = FakeSource()
        source.files = [file("a.mp3"), file("b.mp3")]
        let c = coordinator(try container(), source)
        await c.start()
        let requested = Set(c.tracks.map(\.id) + [UUID().uuidString])

        let existing = await c.existingTrackIDs(among: requested)

        XCTAssertEqual(existing, Set(c.tracks.map(\.id)))
    }

    func testLegacyHashEntriesRekeyOnExactPathMatchOnly() async throws {
        let container = try container()
        let ctx = ModelContext(container)
        let pl = StoredPlaylist(name: "Old")
        ctx.insert(pl)
        ctx.insert(StoredPlaylistEntry(orderIndex: 0, musicID: Music.legacyID(forPath: "/fake/a.mp3"), playlist: pl))
        ctx.insert(StoredPlaylistEntry(orderIndex: 1, musicID: Music.legacyID(forPath: "/fake/gone.mp3"), playlist: pl))
        try ctx.save()

        let source = FakeSource()
        source.files = [file("a.mp3"), file("b.mp3")]
        let c = coordinator(container, source)
        await c.start()
        let aID = c.tracks.first { $0.title == "a.mp3" }!.id

        let check = ModelContext(container)
        let entries = try check.fetch(FetchDescriptor<StoredPlaylistEntry>())
        XCTAssertEqual(entries.count, 1, "unmatched legacy entry is confirmed missing")
        XCTAssertEqual(entries[0].trackID, UUID(uuidString: aID))
        let state = try check.fetch(FetchDescriptor<StoredLibraryState>()).first
        XCTAssertEqual(state?.identityMigrationVersion, 1)
        XCTAssertEqual(state?.metadataVersion, currentMetadataVersion)
    }

    func testLegacyEntryForUnextractableCurrentFileIsNotRekeyedToGhostOrDeleted() async throws {
        let container = try container()
        let ctx = ModelContext(container)
        let pl = StoredPlaylist(name: "Old")
        ctx.insert(pl)
        ctx.insert(StoredPlaylistEntry(orderIndex: 0, musicID: Music.legacyID(forPath: "/fake/bad.mp3"), playlist: pl))
        try ctx.save()

        let source = FakeSource()
        source.files = [file("bad.mp3"), file("ok.mp3")]
        source.failExtraction(of: "/fake/bad.mp3")
        let c = coordinator(container, source)
        await c.start()
        XCTAssertEqual(c.tracks.map(\.title), ["ok.mp3"])
        let entries = try ModelContext(container).fetch(FetchDescriptor<StoredPlaylistEntry>())
        XCTAssertEqual(entries.count, 1, "kept for a later scan")
        XCTAssertNil(entries[0].trackID, "must not point at a Track that does not exist")
        let state = try ModelContext(container).fetch(FetchDescriptor<StoredLibraryState>()).first
        XCTAssertEqual(state?.identityMigrationVersion, 0, "migration is not complete while a legacy entry remains")

        source.failExtraction(of: "")  // no-op; next scan succeeds below
        let healed = FakeSource()
        healed.files = [file("bad.mp3"), file("ok.mp3")]
        let c2 = coordinator(container, healed)
        await c2.start()
        let after = try ModelContext(container).fetch(FetchDescriptor<StoredPlaylistEntry>())
        XCTAssertNotNil(after.first?.trackID)
        XCTAssertEqual(after.first?.trackID.map(\.uuidString), c2.tracks.first { $0.title == "bad.mp3" }?.id)
    }

    func testFailedScanLeavesLegacyEntriesUntouched() async throws {
        let container = try container()
        let ctx = ModelContext(container)
        let pl = StoredPlaylist(name: "Old")
        ctx.insert(pl)
        ctx.insert(StoredPlaylistEntry(orderIndex: 0, musicID: Music.legacyID(forPath: "/fake/a.mp3"), playlist: pl))
        try ctx.save()

        let source = FakeSource()
        source.error = Boom()
        let c = coordinator(container, source)
        await c.start()
        let entries = try ModelContext(container).fetch(FetchDescriptor<StoredPlaylistEntry>())
        XCTAssertEqual(entries.count, 1)
        XCTAssertNil(entries[0].trackID)
        XCTAssertTrue(try ModelContext(container).fetch(FetchDescriptor<StoredLibraryState>()).isEmpty)
    }

    func testFailedExtractionOfExistingFileKeepsTrackAndRetries() async throws {
        let source = FakeSource()
        source.files = [file("a.mp3")]
        let c = coordinator(try container(), source)
        await c.start()
        let id = c.tracks[0].id
        source.files = [file("a.mp3", mod: t0 + 1)]
        source.failExtraction(of: "/fake/a.mp3")
        await c.refresh()
        XCTAssertEqual(c.tracks.map(\.id), [id], "a corrupt re-read must not drop the Track")
    }

    func testCancelledScanCommitsNothing() async throws {
        let source = FakeSource()
        source.files = [file("a.mp3"), file("b.mp3")]
        source.delayNanos = 300_000_000
        let c = coordinator(try container(), source)
        let run = Task { await c.start() }
        try await Task.sleep(nanoseconds: 80_000_000)
        c.cancelScan()
        await run.value
        XCTAssertTrue(c.tracks.isEmpty)
        XCTAssertNotNil(c.scanError)
        XCTAssertEqual(c.phase, .failed)
    }

    func testArtworkIsNotInTrackFetchAndLoadsOnDemand() async throws {
        let container = try container()
        let source = FakeSource()
        source.files = [file("a.mp3")]
        let c = coordinator(container, source)
        await c.start()
        let rows = try ModelContext(container).fetch(FetchDescriptor<StoredTrack>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows[0].hasArtwork)
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<StoredTrackArtwork>()).count, 1)
    }
}

/// Real temporary files: file-resource identity behavior of `FolderFileSource`.
final class FolderFileSourceIdentityTests: XCTestCase {
    private var root: URL!
    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ffs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: root) }

    func testDiscoversRecursivelyWithFingerprintAndIdentity() async throws {
        let sub = root.appendingPathComponent("deep/er")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try Data("abc".utf8).write(to: sub.appendingPathComponent("x.mp3"))
        try Data("abc".utf8).write(to: root.appendingPathComponent("notes.txt"))
        let found = try await FolderFileSource(root: root).discover()
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].fileSize, 3)
        XCTAssertNotNil(found[0].fileID)
        XCTAssertNotNil(found[0].volumeID)
    }

    func testRenameKeepsIdentityHardLinkAndCopyDiffer() async throws {
        let fm = FileManager.default
        let a = root.appendingPathComponent("a.mp3")
        try Data("abc".utf8).write(to: a)
        let src = FolderFileSource(root: root)
        let before = try await src.discover()[0]

        let renamed = root.appendingPathComponent("renamed.mp3")
        try fm.moveItem(at: a, to: renamed)
        let afterMove = try await src.discover()
        XCTAssertEqual(afterMove.count, 1)
        XCTAssertEqual(afterMove[0].fileID, before.fileID)
        XCTAssertEqual(afterMove[0].volumeID, before.volumeID)

        try fm.copyItem(at: renamed, to: root.appendingPathComponent("copy.mp3"))
        try fm.linkItem(at: renamed, to: root.appendingPathComponent("link.mp3"))
        let all = try await src.discover()
        let byName = Dictionary(uniqueKeysWithValues: all.map { (($0.path as NSString).lastPathComponent, $0) })
        XCTAssertEqual(byName["link.mp3"]?.fileID, byName["renamed.mp3"]?.fileID)
        XCTAssertNotEqual(byName["copy.mp3"]?.fileID, byName["renamed.mp3"]?.fileID)
    }

    func testMissingRootThrowsInsteadOfReportingEmpty() async {
        let src = FolderFileSource(root: root.appendingPathComponent("nope"))
        do {
            _ = try await src.discover()
            XCTFail("expected throw")
        } catch let error as LibraryScanError {
            guard case .sourceUnavailable = error else {
                return XCTFail("A missing root must authorize unavailable cleanup, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPermissionFailureIsNotSourceUnavailable() async throws {
        let url = root.appendingPathComponent("one.mp3")
        try Data("abc".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: root.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path) }

        do {
            _ = try await FolderFileSource(root: root).discover()
            XCTFail("Expected a permission failure")
        } catch let error as LibraryScanError {
            guard case .incompleteEnumeration = error else {
                return XCTFail("Permission/read failures must preserve the Library, got \(error)")
            }
        }
    }

    func testDiscoversNewFormatsButNotOggOrStandaloneOpus() async throws {
        let supported = ["mp3", "m4a", "mp4", "aac", "flac", "wav", "aiff"]
        for ext in supported + ["ogg", "opus"] {
            try Data("audio".utf8).write(to: root.appendingPathComponent("track.\(ext)"))
        }

        let found = try await FolderFileSource(root: root).discover()

        XCTAssertEqual(Set(found.map { $0.url.pathExtension }), Set(supported))
    }

    func testEmptyRootIsEmptyNotAnError() async throws {
        let found = try await FolderFileSource(root: root).discover()
        XCTAssertTrue(found.isEmpty)
    }
}
