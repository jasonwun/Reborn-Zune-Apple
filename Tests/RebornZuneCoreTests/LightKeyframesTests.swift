import XCTest
import simd
@testable import RebornZuneCore

final class LightKeyframesTests: XCTestCase {
    // MARK: - Palette structural shape

    func testWarmPaletteCount() {
        XCTAssertEqual(LightingPalette.warm.positions.count, 7)
        XCTAssertEqual(LightingPalette.warm.colors.count, 6)
    }

    func testCoolPaletteCount() {
        XCTAssertEqual(LightingPalette.cool.positions.count, 7)
        XCTAssertEqual(LightingPalette.cool.colors.count, 6)
    }

    // MARK: - Palette value spot-checks

    func testWarmPaletteValues() {
        let firstColor = LightingPalette.warm.colors.first!.color
        XCTAssertEqual(firstColor.x, 0.525, accuracy: 0.01)
        XCTAssertEqual(firstColor.y, 0.361, accuracy: 0.01)
        XCTAssertEqual(firstColor.z, 0.165, accuracy: 0.01)

        // 0.6 keyframe -> #62962c -> (0.384, 0.588, 0.173)
        let midColor = LightingPalette.warm.colors[3].color
        XCTAssertEqual(midColor.x, 0.384, accuracy: 0.01)
        XCTAssertEqual(midColor.y, 0.588, accuracy: 0.01)
        XCTAssertEqual(midColor.z, 0.173, accuracy: 0.01)
    }

    func testCoolPaletteValues() {
        // 0.0 keyframe -> #81268b -> (0.506, 0.149, 0.545)
        let firstColor = LightingPalette.cool.colors.first!.color
        XCTAssertEqual(firstColor.x, 0.506, accuracy: 0.01)
        XCTAssertEqual(firstColor.y, 0.149, accuracy: 0.01)
        XCTAssertEqual(firstColor.z, 0.545, accuracy: 0.01)

        // 0.4 keyframe -> #368843 -> (0.212, 0.533, 0.263)
        let midColor = LightingPalette.cool.colors[2].color
        XCTAssertEqual(midColor.x, 0.212, accuracy: 0.01)
        XCTAssertEqual(midColor.y, 0.533, accuracy: 0.01)
        XCTAssertEqual(midColor.z, 0.263, accuracy: 0.01)
    }

    func testWarmPalettePositionsNormalized() {
        // M16.5: positions are normalized field fractions; warm starts
        // near the top-left corner and loops back there.
        let positions = LightingPalette.warm.positions.map(\.position)
        XCTAssertEqual(positions[0], SIMD3<Float>(0.08, 0.08, 200))
        XCTAssertEqual(positions[1], SIMD3<Float>(0.08, 0.54, 200))
        XCTAssertEqual(positions[2], SIMD3<Float>(0.36, 0.05, 200))
        XCTAssertEqual(positions[6], SIMD3<Float>(0.08, 0.08, 200))
    }

    func testCoolPalettePositionsNormalized() {
        // M16.5: cool starts near the bottom-right corner.
        let positions = LightingPalette.cool.positions.map(\.position)
        XCTAssertEqual(positions[0], SIMD3<Float>(0.82, 0.74, 200))
        XCTAssertEqual(positions[2], SIMD3<Float>(0.82, 0.74, 200))
        XCTAssertEqual(positions[5], SIMD3<Float>(0.88, 0.54, 200))
    }

    // MARK: - Interpolation behavior

    func testKeyframeProgressBoundaries() {
        let warm = LightingPalette.warm
        XCTAssertEqual(warm.position(at: 0), warm.positions.first!.position)
        XCTAssertEqual(warm.position(at: 1), warm.positions.last!.position)
        XCTAssertEqual(warm.color(at: 0), warm.colors.first!.color)
        XCTAssertEqual(warm.color(at: 1), warm.colors.last!.color)
    }

    func testInterpolationMidpoint() {
        let keys = LightKeyframes(
            positions: [
                .init(progress: 0.0, position: SIMD3<Float>(0, 0, 0)),
                .init(progress: 1.0, position: SIMD3<Float>(100, 200, 300)),
            ],
            colors: [
                .init(progress: 0.0, color: SIMD3<Float>(0, 0, 0)),
                .init(progress: 1.0, color: SIMD3<Float>(1, 1, 1)),
            ]
        )
        let mid = keys.position(at: 0.5)
        XCTAssertEqual(mid.x, 50.0, accuracy: 1e-4)
        XCTAssertEqual(mid.y, 100.0, accuracy: 1e-4)
        XCTAssertEqual(mid.z, 150.0, accuracy: 1e-4)
    }

    func testColorInterpolation() {
        let keys = LightKeyframes(
            positions: [
                .init(progress: 0.0, position: SIMD3<Float>(0, 0, 0)),
                .init(progress: 1.0, position: SIMD3<Float>(0, 0, 0)),
            ],
            colors: [
                .init(progress: 0.0, color: SIMD3<Float>(0, 0, 0)),
                .init(progress: 1.0, color: SIMD3<Float>(1, 0.5, 0.25)),
            ]
        )
        let mid = keys.color(at: 0.5)
        XCTAssertEqual(mid.x, 0.5, accuracy: 1e-4)
        XCTAssertEqual(mid.y, 0.25, accuracy: 1e-4)
        XCTAssertEqual(mid.z, 0.125, accuracy: 1e-4)
    }

    func testInterpolationClampsOutOfRange() {
        let keys = LightKeyframes(
            positions: [
                .init(progress: 0.2, position: SIMD3<Float>(10, 20, 30)),
                .init(progress: 0.8, position: SIMD3<Float>(40, 50, 60)),
            ],
            colors: [
                .init(progress: 0.2, color: SIMD3<Float>(0, 0, 0)),
                .init(progress: 0.8, color: SIMD3<Float>(1, 1, 1)),
            ]
        )
        XCTAssertEqual(keys.position(at: -0.5), SIMD3<Float>(10, 20, 30))
        XCTAssertEqual(keys.position(at: 1.5), SIMD3<Float>(40, 50, 60))
        XCTAssertEqual(keys.color(at: -0.1), SIMD3<Float>(0, 0, 0))
        XCTAssertEqual(keys.color(at: 1.1), SIMD3<Float>(1, 1, 1))
    }

    func testWarmPalettePositionAtSecondKeyframe() {
        // 0.20 is exactly a key — interpolation should hit it exactly.
        let p = LightingPalette.warm.position(at: 0.20)
        XCTAssertEqual(p.x, 0.08, accuracy: 0.0001)
        XCTAssertEqual(p.y, 0.54, accuracy: 0.0001)
        XCTAssertEqual(p.z, 200, accuracy: 0.01)
    }
}
