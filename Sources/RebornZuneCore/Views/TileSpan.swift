import Foundation

/// The bit-normalized size a tile occupies in the variable-span grid.
///
/// Mirrors the spans used by the original UWP `Reborn-Zune` app, with one
/// addition for M5.5: a 2×2 "small" tile, which the Zune references show is
/// actually the most common "feature" size between the dominant 1×1 unit and
/// the rare 3×3/4×4 medium/large tiles. The raw value is the side length in
/// cells.
public enum TileSpan: Int, Sendable, Hashable {
    case unit = 1   // 1×1
    case small = 2  // 2×2
    case medium = 3 // 3×3
    case large = 4  // 4×4
}

public extension TileSpan {
    /// Random span using the M5.5 reference-driven distribution:
    /// 70% unit, 20% small, 8% medium, 2% large. Uses the provided RNG
    /// (defaults to `SystemRandomNumberGenerator`).
    ///
    /// Implementation draws an integer in `[0, 100)` and thresholds:
    /// `< 2` → large (2%), `< 10` → medium (8%), `< 30` → small (20%),
    /// otherwise unit (70%).
    static func random<G: RandomNumberGenerator>(using rng: inout G) -> TileSpan {
        let value = Int.random(in: 0..<100, using: &rng)
        if value < 2 {
            return .large
        } else if value < 10 {
            return .medium
        } else if value < 30 {
            return .small
        } else {
            return .unit
        }
    }

    /// Random span using `SystemRandomNumberGenerator`.
    static func random() -> TileSpan {
        var rng = SystemRandomNumberGenerator()
        return random(using: &rng)
    }
}
