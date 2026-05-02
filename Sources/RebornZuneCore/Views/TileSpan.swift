import Foundation

/// The bit-normalized size a tile occupies in the variable-span grid.
///
/// Mirrors the spans used by the original UWP `Reborn-Zune` app:
/// 1×1 unit tiles, 3×3 medium tiles, and 4×4 large tiles. The raw value is
/// the side length in cells.
public enum TileSpan: Int, Sendable, Hashable {
    case unit = 1   // 1×1
    case medium = 3 // 3×3
    case large = 4  // 4×4
}

public extension TileSpan {
    /// Random span using the same probability distribution as the UWP original:
    /// 87.5% unit, 10% medium, 2.5% large. Uses the provided RNG (defaults to
    /// `SystemRandomNumberGenerator`).
    ///
    /// The UWP source draws an integer in `[0, 200)`:
    /// `< 5` → large (2.5%), `< 25` → medium (10%), otherwise unit (87.5%).
    /// We replicate that exact thresholding here so the distribution matches.
    static func random<G: RandomNumberGenerator>(using rng: inout G) -> TileSpan {
        let value = Int.random(in: 0..<200, using: &rng)
        if value < 5 {
            return .large
        } else if value < 25 {
            return .medium
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
