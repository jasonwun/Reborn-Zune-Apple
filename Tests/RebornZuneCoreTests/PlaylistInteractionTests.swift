import XCTest
@testable import RebornZuneCore

@MainActor
final class PlaylistInteractionTests: XCTestCase {
    func testStandaloneCreateNavigatesButTrackMenuCreateStaysInPlace() {
        let state = PlaylistInteractionState()
        let router = ResonantRouter(initial: .album("album"))
        let playlistID = UUID()

        state.requestCreate(trackIDs: ["track"], opensAfterCreation: false)
        state.completeCreation(with: playlistID, router: router)
        XCTAssertEqual(router.route, .album("album"))
        XCTAssertNil(state.createRequest)

        state.requestCreate(opensAfterCreation: true)
        state.completeCreation(with: playlistID, router: router)
        XCTAssertEqual(router.route, .playlist(playlistID.uuidString))
    }

    func testDeleteReturnsOnlyMatchingDetailToGridAndEscapeCancelsSheets() {
        let state = PlaylistInteractionState()
        let playlistID = UUID()
        let otherID = UUID()
        let router = ResonantRouter(initial: .playlist(playlistID.uuidString))
        state.requestCreate(trackIDs: ["track"], opensAfterCreation: false)
        state.requestRename(playlistID: playlistID, currentName: "Name")
        state.requestDeletion(playlistID: playlistID)
        state.requestPicker(playlistID: playlistID)

        state.cancelSheets()
        XCTAssertNil(state.createRequest)
        XCTAssertNil(state.renameRequest)
        XCTAssertNil(state.deletePlaylistID)
        XCTAssertNil(state.pickerPlaylistID)
        XCTAssertEqual(router.route, .playlist(playlistID.uuidString))

        state.requestDeletion(playlistID: otherID)
        state.completeDeletion(router: router)
        XCTAssertEqual(router.route, .playlist(playlistID.uuidString))
        state.requestDeletion(playlistID: playlistID)
        state.completeDeletion(router: router)
        XCTAssertEqual(router.route, .playlists)
    }

    func testAddingShowsNamedNonmodalFeedback() {
        let state = PlaylistInteractionState()
        state.showAddedFeedback(to: "Late Night")
        XCTAssertEqual(state.addedFeedback, "Added to Late Night")
        state.clearFeedback("Added to Late Night")
        XCTAssertNil(state.addedFeedback)
    }
}
