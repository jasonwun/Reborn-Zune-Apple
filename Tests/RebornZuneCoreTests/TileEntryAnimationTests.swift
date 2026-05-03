import XCTest
@testable import RebornZuneCore

final class TileEntryAnimationTests: XCTestCase {
    func testWaveDelaysAreEvenlyStepped() {
        let entry = TileEntryAnimation()
        let wave0 = entry.parameters(forWave: 0)
        let wave13 = entry.parameters(forWave: 13)

        XCTAssertEqual(wave0.delay, 0.0, accuracy: 1e-9)
        XCTAssertEqual(wave13.delay, 1.040, accuracy: 1e-9)
        XCTAssertEqual(wave0.opacityDuration, 0.45, accuracy: 1e-9)
        XCTAssertEqual(wave0.scaleDuration, 0.6, accuracy: 1e-9)
    }

    func testWaveModuloWraps() {
        let entry = TileEntryAnimation()
        let wave0 = entry.parameters(forWave: 0)
        let wave14 = entry.parameters(forWave: 14)
        let wave28 = entry.parameters(forWave: 28)

        XCTAssertEqual(wave0.delay, wave14.delay, accuracy: 1e-9)
        XCTAssertEqual(wave0.delay, wave28.delay, accuracy: 1e-9)
    }

    func testCustomStepProducesProportionalDelays() {
        let entry = TileEntryAnimation(waveDelayStep: 0.1)
        let wave5 = entry.parameters(forWave: 5)
        XCTAssertEqual(wave5.delay, 0.5, accuracy: 1e-9)
    }

    func testNegativeWaveIndexWraps() {
        let entry = TileEntryAnimation()
        // -1 mod 14 should be 13
        let wave = entry.parameters(forWave: -1)
        XCTAssertEqual(wave.delay, 1.040, accuracy: 1e-9)
    }

    func testCustomDurationsArePropagated() {
        let entry = TileEntryAnimation(
            waveCount: 10,
            waveDelayStep: 0.05,
            opacityDuration: 0.2,
            scaleDuration: 0.3
        )
        let wave = entry.parameters(forWave: 4)
        XCTAssertEqual(wave.delay, 0.2, accuracy: 1e-9)
        XCTAssertEqual(wave.opacityDuration, 0.2, accuracy: 1e-9)
        XCTAssertEqual(wave.scaleDuration, 0.3, accuracy: 1e-9)
    }

    func testZuneSeededRNGIsDeterministic() {
        var rngA = ZuneSeededRNG(seed: 42)
        var rngB = ZuneSeededRNG(seed: 42)
        for _ in 0..<10 {
            XCTAssertEqual(rngA.next(), rngB.next())
        }
    }

    func testZuneSeededRNGZeroSeedIsStable() {
        var rng = ZuneSeededRNG(seed: 0)
        let first = rng.next()
        let second = rng.next()
        // Just confirm it doesn't return zero forever.
        XCTAssertNotEqual(first, 0)
        XCTAssertNotEqual(second, 0)
        XCTAssertNotEqual(first, second)
    }
}
