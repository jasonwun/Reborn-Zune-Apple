import Foundation

/// M17.2: the tile wall's animation clock.
///
/// All wall animations (entry wave, tile flips, the lighting orbit) read
/// this instead of the raw wall clock. On macOS it freezes while the
/// window is dragged/resized — M16.9 suspends wall rendering then, and
/// previously every animation derived its progress from absolute time,
/// so on resume each one jumped to "where it would have been" (lights
/// and colors snapped, mid-drag flips silently completed). `WallTime`
/// subtracts the suspended intervals, so a resumed animation continues
/// from the exact frame it froze on.
///
/// Off macOS there is no drag suspension and this is the plain clock.
@MainActor
enum WallTime {
    static var now: TimeInterval {
        #if os(macOS)
        WindowActivityMonitor.shared.wallNow
        #else
        Date.timeIntervalSinceReferenceDate
        #endif
    }
}
