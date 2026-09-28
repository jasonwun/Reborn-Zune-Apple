import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// DEBUG perf probe. Enabled only when `REBORN_ZUNE_DEBUG_PERF=1` is set —
/// every call short-circuits on the static flag otherwise, so production
/// runs pay one Bool read per probe site.
///
/// Marks print `RZPERF mark <label> t+<ms>` where t+ is milliseconds since
/// **process launch** (via KERN_PROC_PID, not first-touch), so cold-start
/// measurements include the time before any SwiftUI code ran.
/// Durations print `RZPERF dur <label> <ms>ms ...`.
///
/// Everything except `once` is nonisolated (immutable statics + stateless
/// writes) so probes can be called from any context; `once` mutates the
/// dedup set and stays MainActor (all its call sites are View bodies).
public enum PerfProbe {
    private static let enabled = ProcessInfo.processInfo.environment["REBORN_ZUNE_DEBUG_PERF"] == "1"

    /// Process start time as a `Date` (boot time + process start offset).
    private static let launchDate: Date = {
        #if canImport(Darwin)
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        if sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0 {
            // p_starttime is an absolute UNIX timestamp (seconds since 1970).
            let tv = info.kp_proc.p_starttime
            return Date(timeIntervalSince1970: TimeInterval(tv.tv_sec) + TimeInterval(tv.tv_usec) / 1_000_000)
        }
        #endif
        return Date()
    }()

    @MainActor private static var seen = Set<String>()

    /// Emit a timestamped mark line.
    public static func mark(_ label: String) {
        guard enabled else { return }
        write("RZPERF mark \(label) t+\(elapsed())ms")
    }

    /// Emit the mark only the first time this label is seen (process-wide).
    @MainActor
    public static func once(_ label: String) {
        guard enabled, !seen.contains(label) else { return }
        seen.insert(label)
        mark(label)
    }

    /// Start a duration measurement. Pair with `toc(_:since:detail:)`.
    public static func tic() -> TimeInterval {
        enabled ? Date().timeIntervalSinceReferenceDate : 0
    }

    /// End a duration measurement started with `tic()`.
    public static func toc(_ label: String, since tic: TimeInterval, detail: String = "") {
        guard enabled, tic != 0 else { return }
        let ms = Int((Date().timeIntervalSinceReferenceDate - tic) * 1000)
        let suffix = detail.isEmpty ? "" : " \(detail)"
        write("RZPERF dur \(label) \(ms)ms\(suffix) t+\(elapsed())ms")
    }

    private static func elapsed() -> Int {
        Int(Date().timeIntervalSince(launchDate) * 1000)
    }

    private static func write(_ line: String) {
        if let data = (line + "\n").data(using: .utf8) {
            FileHandle.standardOutput.write(data)
        }
    }
}
