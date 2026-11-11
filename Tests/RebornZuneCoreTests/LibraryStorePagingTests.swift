import SwiftData
import XCTest
@testable import RebornZuneCore

final class LibraryStorePagingTests: XCTestCase {
    private var directory: URL!
    private var container: ModelContainer!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("library-paging-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        container = try RebornZunePersistence.makePersistentContainer(
            at: directory.appendingPathComponent("library.store"))
    }

    override func tearDownWithError() throws {
        container = nil
        try? FileManager.default.removeItem(at: directory)
    }

    func testPagedFetchUsesStableTitleOrderAndReportsFilteredCount() async throws {
        let context = ModelContext(container)
        insertTrack(context, path: "/fake/c.mp3", title: "Charlie", artist: "Beta", genre: "Rock")
        insertTrack(context, path: "/fake/a.mp3", title: "Alpha", artist: "Beta", genre: "Jazz")
        insertTrack(context, path: "/fake/b.mp3", title: "Bravo", artist: "Beta", genre: "Rock")
        insertTrack(context, path: "/fake/d.mp3", title: "Delta", artist: "Other", genre: "Rock")
        try context.save()
        let store = LibraryStore(modelContainer: container)
        let query = LibraryTrackQuery(searchText: "beta")

        let firstPage = try await store.snapshots(matching: query, offset: 0, limit: 2)
        let secondPage = try await store.snapshots(matching: query, offset: 2, limit: 2)
        let count = try await store.count(matching: query)

        XCTAssertEqual(firstPage.map(\.title), ["Alpha", "Bravo"])
        XCTAssertEqual(secondPage.map(\.title), ["Charlie"])
        XCTAssertEqual(count, 3)
    }

    func testPagedFetchAppliesRequestedArtistAndYearOrdering() async throws {
        let context = ModelContext(container)
        insertTrack(context, path: "/fake/a.mp3", title: "Alpha", artist: "Beta", genre: "Rock", year: 2020)
        insertTrack(context, path: "/fake/b.mp3", title: "Bravo", artist: "Alpha", genre: "Rock", year: 2024)
        insertTrack(context, path: "/fake/c.mp3", title: "Charlie", artist: "Beta", genre: "Rock", year: 2022)
        try context.save()
        let store = LibraryStore(modelContainer: container)

        let byArtist = try await store.snapshots(
            matching: LibraryTrackQuery(sort: .artist), offset: 0, limit: 3)
        let byYear = try await store.snapshots(
            matching: LibraryTrackQuery(sort: .year), offset: 0, limit: 3)

        XCTAssertEqual(byArtist.map(\.title), ["Bravo", "Alpha", "Charlie"])
        XCTAssertEqual(byYear.map(\.title), ["Bravo", "Charlie", "Alpha"])
    }

    func testAlbumOrderingUsesAlbumTitleInsteadOfTrackTitle() async throws {
        let context = ModelContext(container)
        insertTrack(context, path: "/fake/a.mp3", title: "Alpha", artist: "Artist", genre: "Rock", albumTitle: "Zed")
        insertTrack(context, path: "/fake/z.mp3", title: "Zulu", artist: "Artist", genre: "Rock", albumTitle: "Alpha")
        try context.save()
        let store = LibraryStore(modelContainer: container)

        let tracks = try await store.snapshots(
            matching: LibraryTrackQuery(sort: .albumTitle), offset: 0, limit: 2)

        XCTAssertEqual(tracks.map(\.albumTitle), ["Alpha", "Zed"])
        XCTAssertEqual(tracks.map(\.title), ["Zulu", "Alpha"])
    }

    func testSearchMatchesEverySupportedMetadataFieldCaseInsensitively() async throws {
        let context = ModelContext(container)
        insertTrack(
            context, path: "/fake/a.mp3", title: "TitleNeedle",
            artist: "ArtistNeedle", genre: "GenreNeedle", albumTitle: "AlbumNeedle",
            albumArtist: "AlbumArtistNeedle")
        try context.save()
        let store = LibraryStore(modelContainer: container)

        for searchText in ["titleneedle", "artistneedle", "albumartistneedle", "albumneedle", "genreneedle"] {
            let query = LibraryTrackQuery(searchText: searchText)
            let tracks = try await store.snapshots(matching: query, offset: 0, limit: 10)
            let count = try await store.count(matching: query)
            XCTAssertEqual(count, 1, searchText)
            XCTAssertEqual(tracks.map(\.title), ["TitleNeedle"], searchText)
        }
        let albumArtist = try await store.snapshots(
            matching: LibraryTrackQuery(searchText: "albumartistneedle"), offset: 0, limit: 10)
        XCTAssertEqual(albumArtist.map(\.albumArtist), ["AlbumArtistNeedle"])
    }

    func testZeroLimitDoesNotTurnIntoAnUnboundedFetch() async throws {
        let context = ModelContext(container)
        insertTrack(context, path: "/fake/a.mp3", title: "Alpha", artist: "Beta", genre: "Rock")
        try context.save()
        let store = LibraryStore(modelContainer: container)

        let tracks = try await store.snapshots(matching: LibraryTrackQuery(), offset: 0, limit: 0)

        XCTAssertTrue(tracks.isEmpty)
    }

    func testScanSnapshotsAreLimitedToTheirLibrarySource() async throws {
        let context = ModelContext(container)
        insertTrack(context, path: "/fake/a.mp3", title: "Alpha", artist: "Beta", genre: "Rock")
        insertTrack(context, path: "/other/b.mp3", title: "Bravo", artist: "Beta", genre: "Rock")
        try context.save()
        let store = LibraryStore(modelContainer: container)

        let known = try await store.snapshots(sourcePath: "/fake")

        XCTAssertEqual(known.map(\.path), ["/fake/a.mp3"])
    }

    private func insertTrack(
        _ context: ModelContext,
        path: String,
        title: String,
        artist: String,
        genre: String,
        year: Int = 2024,
        albumTitle: String = "Album",
        albumArtist: String? = nil
    ) {
        context.insert(StoredTrack(
            id: UUID(), path: path, sourcePath: path.hasPrefix("/other/") ? "/other" : "/fake",
            modificationDate: Date(timeIntervalSince1970: 1), fileSize: 1,
            volumeID: nil, fileID: nil, title: title, artist: artist,
            albumArtist: albumArtist ?? artist, albumTitle: albumTitle, year: year,
            genre: genre, duration: 60, hasArtwork: false,
            metadataVersion: currentMetadataVersion))
    }
}
