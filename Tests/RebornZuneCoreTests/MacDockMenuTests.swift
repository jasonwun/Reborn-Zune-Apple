#if os(macOS)
import XCTest
import AppKit
@testable import RebornZuneCore

@MainActor
final class MacDockMenuTests: XCTestCase {
    private func makeTrack(_ index: Int) -> Music {
        let url = URL(fileURLWithPath: "/tmp/reborn-zune-tests/dock-\(index).m4a")
        return Music(id: "dock-\(index)", url: url, title: "Dock \(index)", artist: nil,
                     albumArtist: nil, albumTitle: nil, year: nil, duration: 100, artworkData: nil)
    }

    func testDockTransportUsesCurrentPublicPlaybackState() throws {
        let engine = PlaybackEngine()
        let tracks = [makeTrack(20), makeTrack(21)]
        engine.setQueue(tracks)
        let dock = MacDockMenuController(engine: engine) { [] }

        var menu = dock.makeMenu()
        XCTAssertEqual(menu.items.first?.title, "Play")
        let play = try XCTUnwrap(menu.items.first)
        NSApplication.shared.sendAction(try XCTUnwrap(play.action), to: play.target, from: play)
        XCTAssertEqual(engine.state, .playing)

        menu = dock.makeMenu()
        XCTAssertEqual(menu.items.first?.title, "Pause")
        let next = try XCTUnwrap(menu.items.first { $0.title == "Next Track" })
        NSApplication.shared.sendAction(try XCTUnwrap(next.action), to: next.target, from: next)
        XCTAssertEqual(engine.currentItem, tracks[1])
        let previous = try XCTUnwrap(menu.items.first { $0.title == "Previous Track" })
        NSApplication.shared.sendAction(try XCTUnwrap(previous.action), to: previous.target, from: previous)
        XCTAssertEqual(engine.currentItem, tracks[0])
    }

    func testRecentSelectionPlaysTrackAndEmptyHistoryIsDisabled() {
        let engine = PlaybackEngine()
        let tracks = (0..<12).map(makeTrack)
        let dock = MacDockMenuController(engine: engine) { tracks + [tracks[0]] }
        let menu = dock.makeMenu()
        let recentItem = try! XCTUnwrap(menu.items.first { $0.title == "Recently Played" })
        let recentMenu = try! XCTUnwrap(recentItem.submenu)

        XCTAssertEqual(recentMenu.items.count, 10)
        XCTAssertEqual(recentMenu.items.first?.title, "Dock 0")
        XCTAssertNotNil(recentMenu.items[1].target)
        XCTAssertNotNil(recentMenu.items[1].action)
        XCTAssertTrue(recentMenu.items[1].isEnabled)
        NSApplication.shared.sendAction(
            recentMenu.items[1].action!, to: recentMenu.items[1].target, from: recentMenu.items[1]
        )
        XCTAssertEqual(engine.currentItem, tracks[1])
        XCTAssertEqual(engine.state, .playing)

        let emptyDock = MacDockMenuController(engine: engine) { [] }
        let emptyRecent = emptyDock.makeMenu().items.first { $0.title == "Recently Played" }?.submenu
        XCTAssertEqual(emptyRecent?.items.first?.title, "No Recent Tracks")
        XCTAssertEqual(emptyRecent?.items.first?.isEnabled, false)
    }
}
#endif
