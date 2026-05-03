import XCTest
@testable import RebornZuneCore

/// M5.8 tests for the wall-level flip scheduler. The coordinator is
/// `@MainActor`, so all calls and asserts hop through the main actor.
@MainActor
final class TileFlipCoordinatorTests: XCTestCase {
    /// `start(tileCount:)` initializes `flipPulses` to an array of zeros
    /// of the requested length.
    func testStartInitializesPulses() async {
        let coordinator = TileFlipCoordinator()
        coordinator.start(tileCount: 10, period: 60)
        XCTAssertEqual(coordinator.flipPulses.count, 10)
        XCTAssertTrue(coordinator.flipPulses.allSatisfy { $0 == 0 })
        coordinator.stop()
    }

    /// Pulse increments only happen in the first 80% of the array — the
    /// trailing 20% is permanently quiet, matching UWP `tileIdx =
    /// rnd.Next((int)(TileVM.Tiles.Count * 0.8))`.
    func testEligibleSubsetIsFirst80Percent() async throws {
        let coordinator = TileFlipCoordinator()
        let count = 100
        // Period 30 ms — burst-test enough ticks to land in the eligible
        // subset many times. We're not asserting absolute count, only
        // that no tail-20% slot ever gets hit.
        coordinator.start(tileCount: count, period: 0.03)
        try await Task.sleep(nanoseconds: 600_000_000)  // 600 ms ≈ 20 ticks
        coordinator.stop()
        let eligibleCount = max(1, Int(Double(count) * 0.8))
        for i in eligibleCount..<count {
            XCTAssertEqual(
                coordinator.flipPulses[i], 0,
                "Tile index \(i) is outside the 80% eligible window but " +
                "was pulsed; UWP parity requires the trailing 20% to be quiet."
            )
        }
        // Also: at least one pulse should have fired in the eligible
        // window (sanity that the scheduler ran at all).
        let totalPulses = coordinator.flipPulses[0..<eligibleCount].reduce(0, +)
        XCTAssertGreaterThan(totalPulses, 0, "Scheduler did not fire any pulses in 600 ms.")
    }

    /// After `stop()`, no further pulse changes occur.
    func testStopCancelsTask() async throws {
        let coordinator = TileFlipCoordinator()
        coordinator.start(tileCount: 50, period: 0.03)
        try await Task.sleep(nanoseconds: 200_000_000)  // give it time to run
        coordinator.stop()
        let snapshot = coordinator.flipPulses
        // Wait long enough that, had the task survived, several more
        // ticks would have fired.
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(coordinator.flipPulses, snapshot,
                       "stop() should cancel the scheduler; pulses changed afterward.")
    }

    /// Calling `start` twice cancels the previous task. The second start
    /// resets `flipPulses` to all-zero of the new size; only the second
    /// task should ever advance it from there.
    func testIdempotentStart() async throws {
        let coordinator = TileFlipCoordinator()
        coordinator.start(tileCount: 50, period: 0.03)
        try await Task.sleep(nanoseconds: 200_000_000)
        // Second start with a different size — should reset pulses to
        // all-zero of length 20 and only the new task should run.
        coordinator.start(tileCount: 20, period: 60)  // long period so the new task is effectively idle
        XCTAssertEqual(coordinator.flipPulses.count, 20)
        XCTAssertTrue(coordinator.flipPulses.allSatisfy { $0 == 0 },
                      "Second start did not reset pulses to zero.")
        // Wait — the first task must have been cancelled, so pulses stay zero.
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(coordinator.flipPulses.allSatisfy { $0 == 0 },
                      "First task survived a second start() call.")
        coordinator.stop()
    }

    /// `start(tileCount: 0)` is a safe no-op — empty array, no task.
    func testStartWithZeroTileCountIsNoOp() async {
        let coordinator = TileFlipCoordinator()
        coordinator.start(tileCount: 0, period: 0.05)
        XCTAssertEqual(coordinator.flipPulses, [])
        coordinator.stop()
    }
}
