import SwiftData
import XCTest
@testable import RebornZuneCore

final class LibrarySearchStoreTests: XCTestCase {
    private var container: ModelContainer!

    override func setUpWithError() throws {
        container = try RebornZunePersistence.makeInMemoryContainer()
    }

    override func tearDownWithError() throws {
        container = nil
    }

    func testSongSearchMatchesRealFieldsAcrossTokenOrderAndDiacritics() async throws {
        let context = ModelContext(container)
        insertTrack(
            context,
            title: "Café del Mar",
            artist: "東京 Ska",
            albumArtist: "Album Artist",
            albumTitle: "After Hours",
            genre: "Ambient"
        )
        insertTrack(
            context,
            title: "Unrelated",
            artist: "Nobody",
            albumArtist: "Nobody",
            albumTitle: "Elsewhere",
            genre: nil
        )
        try context.save()
        let search = LibrarySearchStore(modelContainer: container)

        for query in ["after cafe", "東京", "ska 東京", "ambient mar"] {
            let results = try await search.search(query)
            XCTAssertEqual(results.songs.map(\.title), ["Café del Mar"], query)
        }
        let unrelated = try await search.search("not-in-any-real-field")
        XCTAssertTrue(unrelated.songs.isEmpty)
    }

    func testSongRankingUsesMinimumScoreSumAndLocalizedTieBreakers() async throws {
        let context = ModelContext(container)
        insertTrack(context, title: "Song of Love", artist: "Someone", albumArtist: nil, albumTitle: "Z", genre: nil)
        insertTrack(context, title: "Love Song", artist: "Love Song", albumArtist: nil, albumTitle: "Z", genre: nil)
        insertTrack(context, title: "Love Song", artist: "Song", albumArtist: nil, albumTitle: "Z", genre: nil)
        insertTrack(context, title: "Love", artist: "Songwriter", albumArtist: nil, albumTitle: "Z", genre: nil)
        insertTrack(context, title: "Love", artist: "Song", albumArtist: nil, albumTitle: "Z", genre: nil)
        try context.save()
        let search = LibrarySearchStore(modelContainer: container)

        let first = try await search.search("love song")
        let second = try await search.search("  SONG   love ")

        XCTAssertEqual(first.songs.map(\.title), ["Love", "Love", "Love Song", "Love Song", "Song of Love"])
        XCTAssertEqual(first.songs.map(\.artist), ["Song", "Songwriter", "Song", "Love Song", "Someone"])
        XCTAssertEqual(second.songs, first.songs)
    }

    func testArtistAndAlbumSearchUsesOwnedAlbumsAndAggregateRealFields() async throws {
        let context = ModelContext(container)
        insertTrack(context, title: "One", artist: "Guest Singer", albumArtist: "Björk", albumTitle: "Homogenic", genre: "Electronic")
        insertTrack(context, title: "Two", artist: "Other Guest", albumArtist: "Björk", albumTitle: "Homogenic", genre: "Rock")
        insertTrack(context, title: "Three", artist: "Björk", albumArtist: "Björk", albumTitle: "Debut", genre: nil)
        insertTrack(context, title: "Four", artist: "Fallback Artist", albumArtist: nil, albumTitle: "First", genre: nil)
        try context.save()
        let search = LibrarySearchStore(modelContainer: container)

        let artists = try await search.search("bjork")
        XCTAssertEqual(artists.artists.map(\.name), ["Björk"])
        XCTAssertEqual(artists.artists.map(\.albumCount), [2])
        XCTAssertEqual(artists.artists.map(\.genre), ["Electronic"])
        XCTAssertEqual(artists.albums.map(\.title), ["Debut", "Homogenic"])

        let aggregate = try await search.search("singer rock")
        XCTAssertTrue(aggregate.songs.isEmpty)
        XCTAssertEqual(aggregate.albums.map(\.title), ["Homogenic"])
        XCTAssertEqual(aggregate.albums.map(\.genre), ["Electronic"])
        XCTAssertTrue(aggregate.artists.isEmpty)

        let fallback = try await search.search("fallback")
        XCTAssertEqual(fallback.artists.map(\.name), ["Fallback Artist"])
        XCTAssertEqual(fallback.albums.map(\.title), ["First"])
    }

    func testSearchReturnsCompleteRankedSnapshotBeyondOverviewCaps() async throws {
        let context = ModelContext(container)
        for index in 0..<12 {
            insertTrack(context, title: "Needle \(index)", artist: "Needle", albumArtist: "Needle", albumTitle: "Album \(index)", genre: nil)
        }
        try context.save()
        let search = LibrarySearchStore(modelContainer: container)

        let results = try await search.search("needle")

        XCTAssertEqual(results.songs.count, 12)
        XCTAssertEqual(results.albums.count, 12)
        XCTAssertEqual(results.artists.count, 1)
        let repeated = try await search.search("  NEEDLE ")
        XCTAssertEqual(results.songs, repeated.songs)
    }

    func testGenreDiscoveryUsesRealTrackCountsAndLimit() async throws {
        let context = ModelContext(container)
        for index in 0..<3 { insertTrack(context, title: "R\(index)", artist: nil, albumArtist: nil, albumTitle: nil, genre: "Rock") }
        for index in 0..<2 { insertTrack(context, title: "J\(index)", artist: nil, albumArtist: nil, albumTitle: nil, genre: "Jazz") }
        insertTrack(context, title: "A", artist: nil, albumArtist: nil, albumTitle: nil, genre: "Ambient")
        insertTrack(context, title: "None", artist: nil, albumArtist: nil, albumTitle: nil, genre: nil)
        for index in 0..<20 { insertTrack(context, title: "G\(index)", artist: nil, albumArtist: nil, albumTitle: nil, genre: "Genre \(index)") }
        try context.save()
        let search = LibrarySearchStore(modelContainer: container)

        let genres = try await search.genres()

        XCTAssertEqual(genres.count, 15)
        XCTAssertEqual(genres.prefix(3).map(\.name), ["Rock", "Jazz", "Ambient"])
        XCTAssertEqual(genres.prefix(3).map(\.count), [3, 2, 1])
    }

    private func insertTrack(
        _ context: ModelContext,
        title: String,
        artist: String?,
        albumArtist: String?,
        albumTitle: String?,
        genre: String?
    ) {
        let path = "/fake/\(UUID().uuidString).mp3"
        context.insert(StoredTrack(
            id: UUID(), path: path, sourcePath: "/fake",
            modificationDate: Date(timeIntervalSince1970: 1), fileSize: 1,
            volumeID: nil, fileID: nil, title: title, artist: artist,
            albumArtist: albumArtist, albumTitle: albumTitle, year: 2024,
            genre: genre, duration: 60, hasArtwork: false,
            metadataVersion: currentMetadataVersion))
    }
}
