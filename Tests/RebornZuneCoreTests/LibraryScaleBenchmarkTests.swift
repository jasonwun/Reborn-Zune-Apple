import Darwin
import SwiftData
import XCTest
@testable import RebornZuneCore

/// Opt-in scale evidence for issue #31. This is excluded from normal test runs
/// because seeding a realistic 50,000-row store is intentionally expensive.
@MainActor
final class LibraryScaleBenchmarkTests: XCTestCase {
    /// A main-run-loop probe, unlike a MainActor task probe it does not count
    /// several individually short actor continuations as one synchronous stall.
    private final class MainThreadStallMonitor: @unchecked Sendable {
        private let lock = NSLock()
        private var maximum: Duration = .zero
        private var previous = ContinuousClock.now
        private let timer = DispatchSource.makeTimerSource(queue: .main)

        init() {
            timer.schedule(deadline: .now() + .milliseconds(1), repeating: .milliseconds(1))
            timer.setEventHandler { [self] in
                let now = ContinuousClock.now
                lock.withLock {
                    maximum = max(maximum, now - previous)
                    previous = now
                }
            }
            timer.resume()
        }

        var maximumStall: Duration { lock.withLock { maximum } }

        func stop() { timer.cancel() }
    }

    private final class SuspendedSource: LibraryFileSource, Sendable {
        let sourcePath: String

        init(sourcePath: String) {
            self.sourcePath = sourcePath
        }

        func discover() async throws -> [DiscoveredFile] {
            try await withTaskCancellationHandler {
                while true { try await Task.sleep(nanoseconds: 60_000_000_000) }
            } onCancel: {}
        }

        func extract(_ file: DiscoveredFile) async throws -> ExtractedMetadata {
            throw CancellationError()
        }
    }

    func testLaunchToBrowsableAt50000Tracks() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["REBORN_ZUNE_RUN_SCALE_BENCHMARK"] == "1")
        let preserve = ProcessInfo.processInfo.environment["REBORN_ZUNE_SCALE_DIRECTORY"]
        let directory = preserve.map(URL.init(fileURLWithPath:))
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("library-scale-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            if preserve == nil { try? FileManager.default.removeItem(at: directory) }
        }
        let storeURL = directory.appendingPathComponent("library.store")
        let container = try RebornZunePersistence.makePersistentContainer(at: storeURL)
        try seedTracks(50_000, container: container)
        let baseline = Self.peakResidentMemory()
        let coordinator = LibraryCoordinator(
            container: container, source: SuspendedSource(sourcePath: "/benchmark"))
        let monitor = MainThreadStallMonitor()

        let clock = ContinuousClock()
        let start = clock.now
        let launch = Task { await coordinator.start() }
        let deadline = start + .seconds(10)
        while coordinator.phase != .ready || coordinator.tracks.isEmpty {
            if clock.now >= deadline {
                XCTFail("Timed out waiting for the committed Library: \(coordinator.scanError ?? "unknown error")")
                return
            }
            try await Task.sleep(for: .milliseconds(1))
        }
        let launchToBrowsable = clock.now - start
        coordinator.cancelScan()
        await launch.value

        XCTAssertEqual(coordinator.totalTrackCount, 50_000)
        XCTAssertEqual(coordinator.tracks.count, 100)
        XCTAssertTrue(coordinator.hasMoreTracks)
        let launchPeak = Self.peakResidentMemory()
        let launchStall = Self.milliseconds(monitor.maximumStall)
        monitor.stop()
        var maximumMainApply = Duration.zero

        // Exercise the same DTO/grouping/tile work as the macOS host while
        // changing predicates, sorting, and loading ten additional pages.
        for query in [
            LibraryTrackQuery(searchText: "Artist 249"),
            LibraryTrackQuery(sort: .albumTitle),
            LibraryTrackQuery(sort: .artist),
            LibraryTrackQuery(sort: .year),
            LibraryTrackQuery(),
        ] {
            let operationStart = clock.now
            await coordinator.browse(matching: query)
            await Task.yield()  // Store publication and host derivation are separate tasks.
            let queryEnd = clock.now
            let derived = await Self.derivePresentation(from: coordinator.tracks)
            let groupingEnd = clock.now
            let applyStart = clock.now
            _ = ResonantLibrary(albums: derived.0, artists: derived.1)
            _ = derived.2
            maximumMainApply = max(maximumMainApply, clock.now - applyStart)
            let tileEnd = clock.now
            print("SCALE_BENCHMARK operation=query query_ms=\(Self.milliseconds(queryEnd - operationStart)) grouping_ms=\(Self.milliseconds(groupingEnd - queryEnd)) tiles_ms=\(Self.milliseconds(tileEnd - groupingEnd))")
        }
        for _ in 0..<10 {
            let operationStart = clock.now
            await coordinator.loadNextPage()
            await Task.yield()  // Store publication and host derivation are separate tasks.
            let queryEnd = clock.now
            let derived = await Self.derivePresentation(from: coordinator.tracks)
            let groupingEnd = clock.now
            let applyStart = clock.now
            _ = ResonantLibrary(albums: derived.0, artists: derived.1)
            _ = derived.2
            maximumMainApply = max(maximumMainApply, clock.now - applyStart)
            let tileEnd = clock.now
            print("SCALE_BENCHMARK operation=page query_ms=\(Self.milliseconds(queryEnd - operationStart)) grouping_ms=\(Self.milliseconds(groupingEnd - queryEnd)) tiles_ms=\(Self.milliseconds(tileEnd - groupingEnd))")
        }
        let peak = Self.peakResidentMemory()
        let stallMilliseconds = Self.milliseconds(maximumMainApply)
        print("SCALE_BENCHMARK tracks=50000 launch_to_browsable_ms=\(Self.milliseconds(launchToBrowsable))")
        print("SCALE_BENCHMARK baseline_peak_mib=\(Self.mebibytes(baseline)) launch_peak_mib=\(Self.mebibytes(launchPeak)) peak_mib=\(Self.mebibytes(peak))")
        print("SCALE_BENCHMARK launch_max_main_thread_scheduling_gap_ms=\(launchStall)")
        print("SCALE_BENCHMARK browse_max_synchronous_main_apply_ms=\(stallMilliseconds)")
        print("SCALE_BENCHMARK store=\(storeURL.path)")
        XCTAssertLessThan(launchStall, 50)
        XCTAssertLessThan(stallMilliseconds, 50)
    }

    private static func derivePresentation(from tracks: [Music]) async
        -> ([Album], [Artist], [TileWallEntry])
    {
        await Task.detached(priority: .userInitiated) {
            let albums = LibraryGrouping.albums(from: tracks)
            return (albums, LibraryGrouping.artists(from: albums), MusicTileBuilder.tiles(from: tracks))
        }.value
    }

    private func seedTracks(_ count: Int, container: ModelContainer) throws {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let modificationDate = Date(timeIntervalSince1970: 1_700_000_000)
        for index in 0..<count {
            let track = StoredTrack(
                id: UUID(), path: String(format: "/benchmark/%05d.mp3", index),
                sourcePath: "/benchmark", modificationDate: modificationDate,
                fileSize: 1_000_000, volumeID: Data("volume".utf8),
                fileID: Data(String(index).utf8),
                title: String(format: "Track %05d", index),
                artist: "Artist \(index % 250)", albumArtist: "Artist \(index % 250)",
                albumTitle: "Album \(index % 1000)", year: 2000 + index % 25,
                trackNumber: index % 12 + 1, discNumber: 1, genre: "Genre \(index % 12)",
                duration: 180, hasArtwork: true, metadataVersion: currentMetadataVersion)
            track.artwork = StoredTrackArtwork(data: Data(repeating: UInt8(index % 251), count: 64))
            context.insert(track)
            if (index + 1) % 1000 == 0 { try context.save() }
        }
        try context.save()
    }

    private static func peakResidentMemory() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.resident_size_max : 0
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1000 + Double(components.attoseconds) / 1_000_000_000_000_000
    }

    private static func mebibytes(_ bytes: UInt64) -> Double {
        Double(bytes) / 1_048_576
    }
}
