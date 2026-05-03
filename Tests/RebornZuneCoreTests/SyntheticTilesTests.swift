import XCTest
@testable import RebornZuneCore

final class SyntheticTilesTests: XCTestCase {
    func testSeededOutputIsDeterministic() {
        let a = SyntheticTiles.sample(seed: 7, count: 32)
        let b = SyntheticTiles.sample(seed: 7, count: 32)

        XCTAssertEqual(a.count, b.count)
        for (lhs, rhs) in zip(a, b) {
            XCTAssertEqual(lhs.span, rhs.span)
            XCTAssertEqual(lhs.images.count, rhs.images.count)
        }
    }

    func testDifferentSeedsProduceDifferentOutput() {
        let a = SyntheticTiles.sample(seed: 1, count: 64)
        let b = SyntheticTiles.sample(seed: 2, count: 64)
        // At count=64 with two different seeds the span sequence is overwhelmingly
        // unlikely to match exactly. We compare span lists.
        let aSpans = a.map { $0.span }
        let bSpans = b.map { $0.span }
        XCTAssertNotEqual(aSpans, bSpans)
    }

    func testSpanDistributionIsApproximatelyUWP() {
        let count = 10_000
        let tiles = SyntheticTiles.sample(seed: 0, count: count)
        var unit = 0
        var medium = 0
        var large = 0
        for tile in tiles {
            switch tile.span {
            case .unit: unit += 1
            case .medium: medium += 1
            case .large: large += 1
            }
        }

        let unitFraction = Double(unit) / Double(count)
        let mediumFraction = Double(medium) / Double(count)
        let largeFraction = Double(large) / Double(count)

        // UWP probabilities: 87.5% unit, 10% medium, 2.5% large; ±2% tolerance.
        XCTAssertEqual(unitFraction, 0.875, accuracy: 0.02)
        XCTAssertEqual(mediumFraction, 0.10, accuracy: 0.02)
        XCTAssertEqual(largeFraction, 0.025, accuracy: 0.02)
    }

    func testEachTileHasAtLeastOneImage() {
        let tiles = SyntheticTiles.sample(seed: 5, count: 64)
        for tile in tiles {
            XCTAssertGreaterThanOrEqual(tile.images.count, 1)
            // First image should be non-nil for the snapshot path.
            XCTAssertNotNil(tile.images.first ?? nil)
        }
    }

    func testFrameCountIsTwoOrThree() {
        let tiles = SyntheticTiles.sample(seed: 11, count: 64)
        for tile in tiles {
            XCTAssertGreaterThanOrEqual(tile.images.count, 2)
            XCTAssertLessThanOrEqual(tile.images.count, 3)
        }
    }

    func testTileWallEntriesHaveUniqueIDs() {
        let tiles = SyntheticTiles.sample(seed: 0, count: 20)
        let ids = Set(tiles.map { $0.id })
        XCTAssertEqual(ids.count, tiles.count)
    }
}
