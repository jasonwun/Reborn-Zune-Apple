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

        // SyntheticTiles uses TileSpanSequence (maxConsecutiveUnits=5) which
        // forces a non-unit after 5 consecutive 1×1s, biasing the distribution
        // away from raw 87.5/10/2.5 toward a slightly more medium-tile-heavy
        // mix. Empirical at this seed: ~76.7% unit, ~18.8% medium, ~4.6% large.
        XCTAssertEqual(unitFraction, 0.77, accuracy: 0.04)
        XCTAssertEqual(mediumFraction, 0.18, accuracy: 0.04)
        XCTAssertEqual(largeFraction, 0.05, accuracy: 0.04)
    }

    /// Verify the run-cap actually fires: with the default
    /// `maxConsecutiveUnits = 5`, no run of 6+ consecutive `.unit` tiles
    /// should appear in the synthesized output.
    func testNoLongUnitRuns() {
        let tiles = SyntheticTiles.sample(seed: 0, count: 2_000)
        var run = 0
        var maxRun = 0
        for tile in tiles {
            if tile.span == .unit {
                run += 1
                maxRun = max(maxRun, run)
            } else {
                run = 0
            }
        }
        XCTAssertLessThanOrEqual(maxRun, 5)
    }

    /// Verify two non-unit (3×3 / 4×4) tiles never appear back-to-back in
    /// the sequence — there must be at least one .unit between them.
    func testNoAdjacentNonUnits() {
        let tiles = SyntheticTiles.sample(seed: 0, count: 2_000)
        for (lhs, rhs) in zip(tiles, tiles.dropFirst()) {
            if lhs.span != .unit && rhs.span != .unit {
                XCTFail("Non-unit pair: \(lhs.span) followed by \(rhs.span)")
                return
            }
        }
    }

    /// M5.5: synthetic tiles must be dark/medium-toned so the multiplicative
    /// lighting wash has headroom to express, like real album art in the
    /// Zune references. We sample N tiles, decode the first pixel of each
    /// frame, and assert the mean luminance falls in the album-art range.
    func testTileBrightnessRangeIsAlbumArtLike() {
        let tiles = SyntheticTiles.sample(seed: 0, count: 200)
        var totalLuma: Double = 0
        var pixelCount = 0
        for tile in tiles {
            for case let image? in tile.images {
                if let luma = sampleFirstPixelLuminance(image) {
                    totalLuma += luma
                    pixelCount += 1
                }
            }
        }
        XCTAssertGreaterThan(pixelCount, 0)
        let meanLuma = totalLuma / Double(pixelCount)
        // Spec target: mean luminance in 0.05–0.55. Real album art sits
        // around 0.15–0.40; we allow up to 0.55 to leave room for outliers.
        XCTAssertGreaterThanOrEqual(meanLuma, 0.05)
        XCTAssertLessThanOrEqual(meanLuma, 0.55)
    }

    /// Decode the first pixel of a `CGImage` and return Rec. 709 luminance
    /// in 0...1, or nil if drawing fails.
    private func sampleFirstPixelLuminance(_ image: CGImage) -> Double? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixel: [UInt8] = [0, 0, 0, 0]
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let r = Double(pixel[0]) / 255.0
        let g = Double(pixel[1]) / 255.0
        let b = Double(pixel[2]) / 255.0
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
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
