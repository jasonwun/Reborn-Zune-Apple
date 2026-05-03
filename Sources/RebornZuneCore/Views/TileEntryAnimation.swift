import Foundation

/// The 14-wave staggered entry animation used by the original
/// `VariableSizedWrapPanel.InitializeComposition` (lines 691–908). Each wave
/// delays by `waveDelayStep` (80 ms in the UWP), fades opacity 0 → 1 over
/// `opacityDuration` (450 ms), and scales 0.7 → 1 over `scaleDuration`
/// (600 ms). Tiles are partitioned into `waveCount` (14) pseudo-random
/// waves; assignment is deterministic given a seed.
public struct TileEntryAnimation: Sendable {
    public let waveCount: Int
    public let waveDelayStep: TimeInterval
    public let opacityDuration: TimeInterval
    public let scaleDuration: TimeInterval

    public init(
        waveCount: Int = 14,
        waveDelayStep: TimeInterval = 0.08,
        opacityDuration: TimeInterval = 0.45,
        scaleDuration: TimeInterval = 0.6
    ) {
        precondition(waveCount > 0, "TileEntryAnimation waveCount must be > 0")
        precondition(waveDelayStep >= 0, "TileEntryAnimation waveDelayStep must be >= 0")
        precondition(opacityDuration >= 0, "TileEntryAnimation opacityDuration must be >= 0")
        precondition(scaleDuration >= 0, "TileEntryAnimation scaleDuration must be >= 0")
        self.waveCount = waveCount
        self.waveDelayStep = waveDelayStep
        self.opacityDuration = opacityDuration
        self.scaleDuration = scaleDuration
    }

    /// Returns the (delay, opacityDuration, scaleDuration) for the wave at
    /// index `waveIndex`. Index is taken modulo `waveCount`.
    public func parameters(forWave waveIndex: Int) -> (
        delay: TimeInterval,
        opacityDuration: TimeInterval,
        scaleDuration: TimeInterval
    ) {
        let normalized = ((waveIndex % waveCount) + waveCount) % waveCount
        return (
            delay: TimeInterval(normalized) * waveDelayStep,
            opacityDuration: opacityDuration,
            scaleDuration: scaleDuration
        )
    }
}

/// Tiny linear-congruential RNG used for deterministic wave assignment and
/// synthetic-tile generation. Uses the Numerical Recipes constants. Seeding
/// with the same `state` produces an identical sequence — required so
/// snapshots reproduce.
///
/// Named `ZuneSeededRNG` (rather than just `SeededRNG`) to avoid clashing
/// with the same-named local helper used by `TileSpanTests` in the test
/// target.
public struct ZuneSeededRNG: RandomNumberGenerator, Sendable {
    public var state: UInt64

    public init(seed: UInt64) {
        // Avoid 0 state which would render the LCG eternally degenerate; map
        // to a stable nonzero value (golden-ratio constant).
        self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    public mutating func next() -> UInt64 {
        state &*= 6364136223846793005
        state &+= 1442695040888963407
        return state
    }
}
