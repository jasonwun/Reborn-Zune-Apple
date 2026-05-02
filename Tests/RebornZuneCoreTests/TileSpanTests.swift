import XCTest
@testable import RebornZuneCore

/// Simple LCG used by tests that need a deterministic, seedable RNG.
/// `SystemRandomNumberGenerator` cannot be seeded, and the spec calls out
/// this exact construction in the M3 notes.
struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &*= 6364136223846793005
        state &+= 1442695040888963407
        return state
    }
}

final class TileSpanTests: XCTestCase {
    func testDistributionWithSeededRNG() {
        var rng = SeededRNG(state: 0xC0FFEE_C0FFEE)
        let n = 10_000
        var counts: [TileSpan: Int] = [.unit: 0, .medium: 0, .large: 0]
        for _ in 0..<n {
            counts[TileSpan.random(using: &rng), default: 0] += 1
        }

        let unitFraction = Double(counts[.unit] ?? 0) / Double(n)
        let mediumFraction = Double(counts[.medium] ?? 0) / Double(n)
        let largeFraction = Double(counts[.large] ?? 0) / Double(n)

        // Spec target: 87.5% unit, 10% medium, 2.5% large. Tolerate ±2%.
        XCTAssertEqual(unitFraction, 0.875, accuracy: 0.02)
        XCTAssertEqual(mediumFraction, 0.10, accuracy: 0.02)
        XCTAssertEqual(largeFraction, 0.025, accuracy: 0.02)

        XCTAssertEqual(counts.values.reduce(0, +), n)
    }

    func testRawValuesMatchSpanSides() {
        XCTAssertEqual(TileSpan.unit.rawValue, 1)
        XCTAssertEqual(TileSpan.medium.rawValue, 3)
        XCTAssertEqual(TileSpan.large.rawValue, 4)
    }

    func testSeededRNGIsDeterministic() {
        var a = SeededRNG(state: 42)
        var b = SeededRNG(state: 42)
        let drawsA = (0..<128).map { _ in TileSpan.random(using: &a) }
        let drawsB = (0..<128).map { _ in TileSpan.random(using: &b) }
        XCTAssertEqual(drawsA, drawsB)
    }
}
