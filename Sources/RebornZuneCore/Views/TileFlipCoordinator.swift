import Foundation
import Observation

/// Wall-level flip scheduler that picks one random tile every `period`
/// seconds and increments its entry in `flipPulses`. Each `TileView`
/// observes its own slot in `flipPulses` and runs a flip animation when
/// the value changes.
///
/// This mirrors the UWP `TilePage.xaml.cs:202-220` behavior:
///
/// ```csharp
/// TimeSpan period = TimeSpan.FromSeconds(5);
/// // ...
/// int tileIdx = rnd.Next((int)(TileVM.Tiles.Count * 0.8));
/// var tile = TileVM.Tiles[tileIdx] as Tile;
/// tile.UpdateThumbnail(_compositor, imgSource);
/// ```
///
/// The 0.8 multiplier excludes the trailing 20% of tiles from the flip
/// pool — a UWP design choice we preserve for parity. With 250 tiles this
/// produces 0.2 flips/sec, against the M5–M5.7 per-tile-timer model's
/// ~50 flips/sec.
///
/// M16.10: an optional `pool` provider narrows the eligible indices to
/// the tiles currently inside the window viewport. The wall is
/// screen-anchored and larger than the window (M16.1/M16.8), so the old
/// "first 80% of all tiles" rule concentrated every flip in the wall's
/// top-left band — a region the window frequently does not cover, which
/// made the wall look dead. The provider is evaluated at each tick
/// (cheap: ~1k rect-intersection tests per tick) and never touches
/// SwiftUI state, so window drags stay out of the update loop. Returning
/// nil falls back to the default first-80%-of-all pool.
@MainActor
@Observable
public final class TileFlipCoordinator {
    /// Per-tile pulse counter. Incrementing `flipPulses[i]` signals
    /// `TileView` at index `i` to run one flip.
    public private(set) var flipPulses: [Int] = []

    /// The currently running scheduler task. Held so subsequent `start`
    /// or `stop` calls can cancel it.
    private var task: Task<Void, Never>? = nil

    /// Optional viewport-aware pool provider (M16.10). Called on the main
    /// actor at each tick; nil return means "use the default pool".
    private var poolProvider: (@MainActor () -> [Int]?)? = nil

    public init() {}

    /// Start the flip scheduler. Picks one random tile every `period`
    /// seconds (± `jitter`, resampled per tick — M17.6: the user wanted
    /// the cadence to feel organic rather than metronomic) from the pool
    /// (default: the first 80% of `tileCount`, matching UWP behavior) and
    /// increments its slot in `flipPulses`.
    ///
    /// Idempotent: calling `start` while another schedule is running
    /// cancels the previous task and resets `flipPulses` to all-zero of
    /// the new size.
    public func start(
        tileCount: Int,
        period: TimeInterval = 5.0,
        jitter: TimeInterval = 0,
        pool: (@MainActor () -> [Int]?)? = nil
    ) {
        task?.cancel()
        flipPulses = Array(repeating: 0, count: max(0, tileCount))
        poolProvider = pool
        guard tileCount > 0, period > 0 else {
            task = nil
            return
        }
        let eligibleCount = max(1, Int(Double(tileCount) * 0.8))
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                var wait = period
                if jitter > 0 {
                    wait += Double.random(in: -jitter...jitter)
                }
                let tickNanos = UInt64(max(0.05, wait) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: tickNanos)
                if Task.isCancelled { return }
                guard let self else { return }
                // Snapshot the current slate; a `start` reentry between
                // ticks would have replaced the array.
                guard self.flipPulses.count >= eligibleCount,
                      eligibleCount > 0 else { continue }
                // M16.10: ask the pool provider (viewport-aware) first;
                // nil → the UWP default of the first 80% of all tiles.
                var candidates: [Int]? = nil
                if let provider = self.poolProvider {
                    candidates = provider()
                }
                let pool = (candidates ?? Array(0..<eligibleCount))
                    .filter { $0 >= 0 && $0 < self.flipPulses.count }
                guard !pool.isEmpty else { continue }
                var rng = SystemRandomNumberGenerator()
                let idx = pool[Int(rng.next(upperBound: UInt(pool.count)))]
                self.flipPulses[idx] &+= 1
            }
        }
    }

    /// Cancel the scheduler. Existing pulses are not reset — children
    /// that were mid-flip continue undisturbed.
    public func stop() {
        task?.cancel()
        task = nil
        poolProvider = nil
    }
}
