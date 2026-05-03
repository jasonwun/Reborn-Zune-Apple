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
@MainActor
@Observable
public final class TileFlipCoordinator {
    /// Per-tile pulse counter. Incrementing `flipPulses[i]` signals
    /// `TileView` at index `i` to run one flip.
    public private(set) var flipPulses: [Int] = []

    /// The currently running scheduler task. Held so subsequent `start`
    /// or `stop` calls can cancel it.
    private var task: Task<Void, Never>? = nil

    public init() {}

    /// Start the flip scheduler. Picks one random tile every `period`
    /// seconds from the first 80% of `tileCount` (matching UWP behavior)
    /// and increments its slot in `flipPulses`.
    ///
    /// Idempotent: calling `start` while another schedule is running
    /// cancels the previous task and resets `flipPulses` to all-zero of
    /// the new size.
    public func start(tileCount: Int, period: TimeInterval = 5.0) {
        task?.cancel()
        flipPulses = Array(repeating: 0, count: max(0, tileCount))
        guard tileCount > 0, period > 0 else {
            task = nil
            return
        }
        let eligibleCount = max(1, Int(Double(tileCount) * 0.8))
        let nanos = UInt64(period * 1_000_000_000)
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: nanos)
                if Task.isCancelled { return }
                guard let self else { return }
                // Snapshot the current slate; a `start` reentry between
                // ticks would have replaced the array.
                guard self.flipPulses.count >= eligibleCount,
                      eligibleCount > 0 else { continue }
                var rng = SystemRandomNumberGenerator()
                let idx = Int(rng.next(upperBound: UInt(eligibleCount)))
                self.flipPulses[idx] &+= 1
            }
        }
    }

    /// Cancel the scheduler. Existing pulses are not reset — children
    /// that were mid-flip continue undisturbed.
    public func stop() {
        task?.cancel()
        task = nil
    }
}
