import XCTest
@testable import RebornZuneCore

/// M16 follow-up: the demo library must carry real, decodable artwork.
/// Before this, every demo track had `artworkData = nil`, which made the
/// Now Playing tile wall render solid black and hid the lighting effect.
final class ResonantDemoLibraryTests: XCTestCase {
    func testEveryDemoTrackHasDecodableArtwork() {
        let tracks = ResonantDemoLibrary.makeMusic()
        XCTAssertEqual(tracks.count, 129)
        for track in tracks {
            XCTAssertNotNil(track.artworkData, "\(track.id) has no artwork")
            XCTAssertNotNil(
                MusicTileBuilder.decodeArtwork(track.artworkData),
                "\(track.id) artwork does not decode"
            )
        }
    }

    func testDemoLibraryProducesNoBlackTiles() {
        let tiles = MusicTileBuilder.tiles(from: ResonantDemoLibrary.makeMusic())
        XCTAssertFalse(tiles.isEmpty)
        for tile in tiles {
            XCTAssertNotNil(tile.images.first ?? nil, "tile would render solid black")
        }
    }

    func testSynthesizedArtworkVariesPerAlbum() {
        let a = ResonantDemoLibrary.synthesizedArtwork(albumIndex: 0)
        let b = ResonantDemoLibrary.synthesizedArtwork(albumIndex: 1)
        XCTAssertNotNil(a)
        XCTAssertNotNil(b)
        XCTAssertNotEqual(a, b)
    }
}
