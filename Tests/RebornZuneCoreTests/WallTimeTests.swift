#if os(macOS)
import XCTest
@testable import RebornZuneCore

/// M17.2: `WindowActivityMonitor`'s suspension accounting behind
/// `WallTime` — the wall's animation clock must freeze during a drag and
/// resume from the same value, never jump forward.
final class WallTimeTests: XCTestCase {

    @MainActor
    func testWallNowAdvancesWhenIdle() {
        let m = WindowActivityMonitor.shared
        XCTAssertFalse(m.isActive)
        let t0 = m.wallNow
        let t1 = m.wallNow
        XCTAssertGreaterThanOrEqual(t1, t0)
    }

    @MainActor
    func testWallNowFreezesWhileActive() async throws {
        let m = WindowActivityMonitor.shared
        m.noteActivity()
        let frozen = m.wallNow
        try await Task.sleep(nanoseconds: 120_000_000)
        m.noteActivity() // keep the suspension alive
        try await Task.sleep(nanoseconds: 120_000_000)
        m.noteActivity()
        XCTAssertEqual(m.wallNow, frozen, accuracy: 0.001)
    }

    @MainActor
    func testWallNowResumesContinuouslyAfterSuspension() async throws {
        let m = WindowActivityMonitor.shared
        let totalBefore = m.suspendedTotal
        let rawStart = Date.timeIntervalSinceReferenceDate
        m.noteActivity()
        let frozen = m.wallNow
        try await Task.sleep(nanoseconds: 120_000_000)
        // Let the watchdog (250 ms) end the suspension.
        try await Task.sleep(nanoseconds: 550_000_000)
        XCTAssertFalse(m.isActive)
        // The suspension interval was accounted…
        XCTAssertGreaterThan(m.suspendedTotal - totalBefore, 0.2)
        // …so the clock advanced by LESS than the raw elapsed time: the
        // drag window was subtracted, it did not jump forward on resume.
        let rawElapsed = Date.timeIntervalSinceReferenceDate - rawStart
        let advanced = m.wallNow - frozen
        XCTAssertGreaterThan(advanced, 0)
        XCTAssertLessThan(advanced, rawElapsed - 0.2)
    }
}
#endif
