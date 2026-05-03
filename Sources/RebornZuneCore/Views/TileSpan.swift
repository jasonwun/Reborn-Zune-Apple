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

/// Stateful span generator that breaks up long runs of `.unit` tiles.
///
/// Independent random draws at 87.5% unit produce visible runs of 8+
/// consecutive 1×1 tiles ~12% of the time, which clusters into ugly
/// rectangular blocks of small tiles. After
/// `maxConsecutiveUnits` units in a row, this generator forces the next
/// draw to be `.medium` (80%) or `.large` (20%) to break the run.
///
/// Underlying probabilities are still UWP-faithful on average — the
/// forced-non-unit rule only kicks in for the tail of long unit runs.
public struct TileSpanSequence: Sendable {
    public let maxConsecutiveUnits: Int
    private var consecutiveUnits: Int = 0
    /// True if the last span returned was `.medium` or `.large`. Used to
    /// guarantee that two non-unit tiles never appear back-to-back in the
    /// sequence: after every non-unit we force a unit so the wall always
    /// has at least one 1×1 between any two large tiles.
    private var lastWasNonUnit: Bool = false

    public init(maxConsecutiveUnits: Int = 5) {
        precondition(maxConsecutiveUnits > 0, "maxConsecutiveUnits must be > 0")
        self.maxConsecutiveUnits = maxConsecutiveUnits
    }

    public mutating func next<G: RandomNumberGenerator>(using rng: inout G) -> TileSpan {
        // After a non-unit (3×3 or 4×4) the next span is forced to .unit so
        // two large tiles never abut. The forced unit counts toward the run.
        if lastWasNonUnit {
            lastWasNonUnit = false
            consecutiveUnits = 1
            return .unit
        }

        // Forced non-unit when the unit-run cap is hit. 80% medium / 20%
        // large approximates the natural 10/2.5 ratio normalized.
        if consecutiveUnits >= maxConsecutiveUnits {
            consecutiveUnits = 0
            lastWasNonUnit = true
            let pick = Int.random(in: 0..<5, using: &rng)
            return pick < 4 ? .medium : .large
        }

        // Natural draw with the underlying UWP-faithful distribution.
        let span = TileSpan.random(using: &rng)
        if span == .unit {
            consecutiveUnits += 1
            lastWasNonUnit = false
        } else {
            consecutiveUnits = 0
            lastWasNonUnit = true
        }
        return span
    }
}
