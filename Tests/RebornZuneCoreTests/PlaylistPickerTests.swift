import XCTest
@testable import RebornZuneCore

final class PlaylistPickerTests: XCTestCase {
    private func track(_ id: String, _ title: String, artist: String, album: String) -> Music {
        Music(id: id, url: URL(fileURLWithPath: "/tmp/\(id).m4a"), title: title,
              artist: artist, albumArtist: artist, albumTitle: album, year: nil,
              duration: 60, artworkData: nil)
    }

    func testSelectionConfirmsInDisplayOrderRatherThanClickOrder() {
        let first = track("a", "Alpha", artist: "One", album: "First")
        let second = track("b", "Beta", artist: "Two", album: "Second")
        let third = track("c", "Gamma", artist: "Three", album: "Third")
        var picker = PlaylistPickerState(tracks: [first, second, third])

        picker.toggleSelection(for: third)
        picker.toggleSelection(for: first)

        XCTAssertEqual(picker.selectedTracks.map(\.id), ["a", "c"])
        picker.toggleSelection(for: third)
        XCTAssertEqual(picker.selectedTracks.map(\.id), ["a"])
    }

    func testSearchMatchesTitleArtistAndAlbumWithoutHidingOtherChoices() {
        let alpha = track("a", "Alpha", artist: "One", album: "First")
        let beta = track("b", "Beta", artist: "Two", album: "Second")
        let gamma = track("c", "Gamma", artist: "Three", album: "Third")
        var picker = PlaylistPickerState(tracks: [alpha, beta, gamma])

        picker.query = "two"
        XCTAssertEqual(picker.displayedTracks.map(\.id), ["b"])
        picker.toggleSelection(for: beta)
        picker.query = "third"
        XCTAssertEqual(picker.displayedTracks.map(\.id), ["c"])
        picker.toggleSelection(for: gamma)
        XCTAssertEqual(picker.selectedTracks.map(\.id), ["b", "c"],
                       "filtering neither clears selections nor disables duplicates already in a Playlist")
    }
}
