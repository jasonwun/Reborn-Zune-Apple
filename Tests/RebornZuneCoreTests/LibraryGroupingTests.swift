import XCTest
@testable import RebornZuneCore

final class LibraryGroupingTests: XCTestCase {
    func testAlbumGroupingByAlbumAndArtist() {
        let t1 = makeTrack(path: "/m/a1.mp3", title: "Track A", albumTitle: "Greatest", albumArtist: "Band")
        let t2 = makeTrack(path: "/m/a2.mp3", title: "Track B", albumTitle: "Greatest", albumArtist: "Band")
        let t3 = makeTrack(path: "/m/a3.mp3", title: "Track C", albumTitle: "Greatest", albumArtist: "Other Band")

        let albums = LibraryGrouping.albums(from: [t1, t2, t3])
        XCTAssertEqual(albums.count, 2,
                       "Tracks with the same album title but different albumArtists must split into 2 albums.")

        let band = albums.first { $0.albumArtist == "Band" }
        let otherBand = albums.first { $0.albumArtist == "Other Band" }
        XCTAssertNotNil(band)
        XCTAssertNotNil(otherBand)
        XCTAssertEqual(band?.tracks.count, 2)
        XCTAssertEqual(otherBand?.tracks.count, 1)
        XCTAssertEqual(band?.title, "Greatest")
    }

    func testPrivilegedArtistRule() {
        // (a) only `artist` set → groups under artist.
        let onlyArtist = makeTrack(path: "/m/onlyArtist.mp3", title: "T1",
                                   albumTitle: "Album", artist: "ArtistOnly", albumArtist: nil)
        // (b) both set → prefers albumArtist.
        let bothSet = makeTrack(path: "/m/both.mp3", title: "T2",
                                albumTitle: "Album", artist: "TrackArtist", albumArtist: "AlbumArtist")
        // (c) "Unknown Artist" treated as nil for grouping.
        let unknownAlbumArtist = makeTrack(path: "/m/unknownAA.mp3", title: "T3",
                                           albumTitle: "Album", artist: "RealArtist",
                                           albumArtist: "Unknown Artist")
        // (d) Both unknown → "Unknown Artist".
        let allUnknown = makeTrack(path: "/m/allUnknown.mp3", title: "T4",
                                   albumTitle: "Album", artist: "Unknown Artist",
                                   albumArtist: "Unknown Artist")

        let albums = LibraryGrouping.albums(from: [onlyArtist, bothSet, unknownAlbumArtist, allUnknown])
        let artistsSet = Set(albums.map { $0.albumArtist })
        XCTAssertTrue(artistsSet.contains("ArtistOnly"),
                      "Track with only `artist` should group under that artist.")
        XCTAssertTrue(artistsSet.contains("AlbumArtist"),
                      "Track with both should prefer `albumArtist`.")
        XCTAssertTrue(artistsSet.contains("RealArtist"),
                      "`albumArtist == \"Unknown Artist\"` must be treated as nil so we fall back to `artist`.")
        XCTAssertTrue(artistsSet.contains("Unknown Artist"),
                      "Both unknown should produce a single \"Unknown Artist\" bucket.")
        XCTAssertEqual(albums.count, 4)
    }

    func testEarliestYearWins() {
        let t1 = makeTrack(path: "/m/y1.mp3", title: "A", albumTitle: "Years", albumArtist: "B", year: 2003)
        let t2 = makeTrack(path: "/m/y2.mp3", title: "B", albumTitle: "Years", albumArtist: "B", year: 1999)
        let t3 = makeTrack(path: "/m/y3.mp3", title: "C", albumTitle: "Years", albumArtist: "B", year: nil)

        let albums = LibraryGrouping.albums(from: [t1, t2, t3])
        XCTAssertEqual(albums.count, 1)
        XCTAssertEqual(albums.first?.year, 1999,
                       "Album.year must be the earliest non-nil year of its tracks.")
    }

    func testTrackOrdering() {
        let t1 = makeTrack(path: "/m/c.mp3", title: "Charlie", albumTitle: "Mixed", albumArtist: "B")
        let t2 = makeTrack(path: "/m/a.mp3", title: "Alpha",   albumTitle: "Mixed", albumArtist: "B")
        let t3 = makeTrack(path: "/m/b.mp3", title: "Bravo",   albumTitle: "Mixed", albumArtist: "B")

        let albums = LibraryGrouping.albums(from: [t1, t2, t3])
        XCTAssertEqual(albums.count, 1)
        XCTAssertEqual(albums.first?.tracks.map { $0.title }, ["Alpha", "Bravo", "Charlie"],
                       "Tracks within an album must be sorted by title ascending.")
    }

    func testEmptyInput() {
        XCTAssertEqual(LibraryGrouping.albums(from: []), [])
        XCTAssertEqual(LibraryGrouping.artists(from: []), [])
    }

    func testMissingAlbumTitleBecomesUnknownAlbum() {
        let t = makeTrack(path: "/m/no_album.mp3", title: "Lonely", albumTitle: nil, albumArtist: "B")
        let albums = LibraryGrouping.albums(from: [t])
        XCTAssertEqual(albums.count, 1)
        XCTAssertEqual(albums.first?.title, "Unknown Album",
                       "Missing albumTitle must become \"Unknown Album\".")
    }

    func testArtistsGroupAlbumsByAlbumArtist() {
        // Two albums by Band, one by Other Band.
        let t1 = makeTrack(path: "/m/x1.mp3", title: "T1", albumTitle: "First",  albumArtist: "Band")
        let t2 = makeTrack(path: "/m/x2.mp3", title: "T2", albumTitle: "Second", albumArtist: "Band")
        let t3 = makeTrack(path: "/m/x3.mp3", title: "T3", albumTitle: "Third",  albumArtist: "Other Band")

        let albums = LibraryGrouping.albums(from: [t1, t2, t3])
        let artists = LibraryGrouping.artists(from: albums)
        XCTAssertEqual(artists.count, 2)
        let band = artists.first { $0.name == "Band" }
        XCTAssertEqual(band?.albums.count, 2,
                       "Both Band albums must belong to the Band artist.")
        let other = artists.first { $0.name == "Other Band" }
        XCTAssertEqual(other?.albums.count, 1)
        // ID stable on name.
        XCTAssertEqual(band?.id, Artist.makeID(name: "Band"))
    }

    // MARK: - Helpers

    private func makeTrack(
        path: String,
        title: String,
        albumTitle: String?,
        artist: String? = nil,
        albumArtist: String?,
        year: Int? = nil
    ) -> Music {
        let url = URL(fileURLWithPath: path)
        return Music(
            id: Music.makeID(for: url),
            url: url,
            title: title,
            artist: artist,
            albumArtist: albumArtist,
            albumTitle: albumTitle,
            year: year,
            duration: 0,
            artworkData: nil
        )
    }
}
