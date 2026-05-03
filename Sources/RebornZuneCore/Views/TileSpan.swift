import Foundation

/// The bit-normalized size a tile occupies in the variable-span grid.
///
/// Matches the original UWP `Reborn-Zune` (and Zune client) span set:
/// 1×1 unit, 3×3 medium, 4×4 large. The 2×2 "small" tile that earlier
/// passes used has been dropped — the Zune visual only uses three sizes.
/// The raw value is the side length in cells.
public enum TileSpan: Int, Sendable, Hashable {
    case unit = 1   // 1×1
    case medium = 3 // 3×3
    case large = 4  // 4×4
}

public extension TileSpan {
    /// Random span matching the UWP `TileViewModel.Spans` distribution:
    /// 87.5% unit, 10% medium, 2.5% large. Uses the provided RNG (defaults
    /// to `SystemRandomNumberGenerator`).
    ///
    /// Implementation: draw an integer in `[0, 200)` and threshold per the
    /// original UWP source (`val < 5` → large, `val < 25` → medium, else unit).
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
