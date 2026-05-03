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
        var small = 0
        var medium = 0
        var large = 0
        for tile in tiles {
            switch tile.span {
            case .unit: unit += 1
            case .small: small += 1
            case .medium: medium += 1
            case .large: large += 1
            }
        }

        let unitFraction = Double(unit) / Double(count)
        let smallFraction = Double(small) / Double(count)
        let mediumFraction = Double(medium) / Double(count)
        let largeFraction = Double(large) / Double(count)

        // M5.5 reference-driven probabilities:
        // 70% unit, 20% small, 8% medium, 2% large; ±2% tolerance.
        XCTAssertEqual(unitFraction, 0.70, accuracy: 0.02)
        XCTAssertEqual(smallFraction, 0.20, accuracy: 0.02)
        XCTAssertEqual(mediumFraction, 0.08, accuracy: 0.02)
        XCTAssertEqual(largeFraction, 0.02, accuracy: 0.02)
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
