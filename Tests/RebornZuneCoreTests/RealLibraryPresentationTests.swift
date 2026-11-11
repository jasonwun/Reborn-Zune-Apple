import XCTest
@testable import RebornZuneCore

@MainActor
final class RealLibraryPresentationTests: XCTestCase {
    func testSimilarArtistsRequireMatchingRealGenre() {
        let library = ResonantLibrary.from(tracks: [
            track(title: "A", artist: "Artist A", album: "Album A", genre: "Jazz"),
            track(title: "B", artist: "Artist B", album: "Album B", genre: "Jazz"),
            track(title: "C", artist: "Artist C", album: "Album C", genre: "Rock"),
            track(title: "D", artist: "Artist D", album: "Album D", genre: nil),
        ])
        let artistA = library.artists.first { $0.name == "Artist A" }!
        let untagged = library.artists.first { $0.name == "Artist D" }!

        XCTAssertEqual(artistA.genre, "Jazz")
        XCTAssertEqual(RealLibraryPresentation.similarArtists(to: artistA, in: library).map(\.name), ["Artist B"])
        XCTAssertTrue(RealLibraryPresentation.similarArtists(to: untagged, in: library).isEmpty)
    }

    func testSearchUsesOnlyRealGenresAndOmitsMissingSubtitleGenre() {
        let library = ResonantLibrary.from(tracks: [
            track(title: "A1", artist: "Artist A", album: "Album A", genre: "Jazz"),
            track(title: "A2", artist: "Artist A", album: "Album A", genre: "Jazz"),
            track(title: "B", artist: "Artist B", album: "Album B", genre: "Rock"),
            track(title: "D", artist: "Artist D", album: "Album D", genre: nil),
        ])

        XCTAssertEqual(RealLibraryPresentation.genres(in: library), ["Jazz", "Rock"])
        XCTAssertEqual(
            RealLibraryPresentation.albumSubtitle(for: library.albums.first { $0.title == "Album A" }!),
            "Artist A · 2024 · Jazz"
        )
        XCTAssertEqual(
            RealLibraryPresentation.albumSubtitle(for: library.albums.first { $0.title == "Album D" }!),
            "Artist D · 2024"
        )
        XCTAssertEqual(RealLibraryPresentation.albums(matching: "jazz", in: library).map(\.title), ["Album A"])
    }

    func testHomePanelContentComesOnlyFromRealAlbums() {
        let tracks = (1...4).map { index in
            track(title: "Track \(index)", artist: "Artist \(index)", album: "Album \(index)", genre: nil)
        }
        let library = ResonantLibrary.from(tracks: tracks)

        let panels = RealLibraryPresentation.homePanels(in: library)
        XCTAssertEqual(panels.map(\.album.title), ["Album 1", "Album 2", "Album 3", "Album 4"])
        XCTAssertEqual(panels.map(\.eyebrow), Array(repeating: "ALBUM · IN YOUR LIBRARY", count: 4))
        XCTAssertEqual(panels.first?.title, "Album")
        XCTAssertEqual(panels.first?.subtitle, "1")
        XCTAssertEqual(panels.first?.meta, "Artist 1 · 1 TRACKS · 1:00")
        XCTAssertEqual(panels.first?.reason, "From your Library.")
        XCTAssertEqual(panels.first?.details, [RealHomeDetail(label: "TRACKS", lines: ["1"]), RealHomeDetail(label: "RELEASE", lines: ["2024"])])
    }

    private func track(title: String, artist: String, album: String, genre: String?) -> Music {
        let url = URL(fileURLWithPath: "/real/\(album)/\(title).mp3")
        return Music(
            id: url.path, url: url, title: title, artist: artist,
            albumArtist: artist, albumTitle: album, year: 2024,
            genre: genre, duration: 60, artworkData: nil
        )
    }
}
