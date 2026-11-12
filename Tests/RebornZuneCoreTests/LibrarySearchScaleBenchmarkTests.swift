import Darwin
import SwiftData
import XCTest
@testable import RebornZuneCore

/// Opt-in release acceptance for issue #24. Run with:
/// REBORN_ZUNE_RUN_SEARCH_BENCHMARK=1 swift test -c release --filter LibrarySearchScaleBenchmarkTests
@MainActor
final class LibrarySearchScaleBenchmarkTests: XCTestCase {
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
        func reset() {
            lock.withLock {
                maximum = .zero
                previous = ContinuousClock.now
            }
        }
        func stop() { timer.cancel() }
    }

    private final class FakePlayer: QueuePlayer {
        var volume = 1.0
        var currentTime = 0.0
        var onTimeUpdate: ((TimeInterval, TimeInterval?) -> Void)?
        var onPlaybackStatusChange: ((QueuePlaybackStatus) -> Void)?
        var onItemEnd: (() -> Void)?
        var replacedURLCount = 0
        func replaceItems(with urls: [URL]) { replacedURLCount = urls.count }
        func play() {}
        func pause() {}
        func seek(to seconds: Double) { currentTime = seconds }
        func invalidate() {}
    }

    private final class FakeNowPlaying: NowPlayingCentering {
        func registerCommands(_ handlers: RemoteCommandHandlers) {}
        func update(item: Music?, currentTime: TimeInterval, duration: TimeInterval, rate: Double) {}
    }

    private struct EmptySource: LibraryFileSource {
        let sourcePath = "/benchmark"
        func discover() async throws -> [DiscoveredFile] { [] }
        func extract(_ file: DiscoveredFile) async throws -> ExtractedMetadata {
            throw CancellationError()
        }
    }

    func testReleaseSearchAndPlaybackAt50000Tracks() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["REBORN_ZUNE_RUN_SEARCH_BENCHMARK"] == "1")
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("search-scale-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("library.store")
        let container = try RebornZunePersistence.makePersistentContainer(at: storeURL)
        let trackCount = ProcessInfo.processInfo.environment["REBORN_ZUNE_SEARCH_BENCHMARK_COUNT"]
            .flatMap(Int.init) ?? 50_000
        try seedTracks(trackCount, container: container)
        print("SEARCH_BENCHMARK seeded=\(trackCount)")
        let search = LibrarySearchStore(modelContainer: container)
        _ = try await search.search("Track 49999")  // Build the normalized baseline once.
        print("SEARCH_BENCHMARK normalized=\(trackCount)")
        let monitor = MainThreadStallMonitor()
        defer { monitor.stop() }
        await Task.yield()
        monitor.reset()
        let clock = ContinuousClock()

        var commonMilliseconds: [Double] = []
        for index in 0..<20 {
            let query = index.isMultiple(of: 4) ? "No Such Track \(index)" : "Artist \(index % 250)"
            let start = clock.now
            _ = try await search.search(query)
            commonMilliseconds.append(Self.milliseconds(clock.now - start))
        }
        commonMilliseconds.sort()
        let p95 = commonMilliseconds[Int(ceil(Double(commonMilliseconds.count) * 0.95)) - 1]
        var unicodeMilliseconds: [Double] = []
        for query in ["cafe", "東京"] {
            let start = clock.now
            let result = try await search.search(query)
            unicodeMilliseconds.append(Self.milliseconds(clock.now - start))
            XCTAssertEqual(result.songs.count, 1)
        }

        let highStart = clock.now
        let high = try await search.search("1")
        let highMilliseconds = Self.milliseconds(clock.now - highStart)
        let fullStart = clock.now
        let full = try await search.search("track")
        let fullMilliseconds = Self.milliseconds(clock.now - fullStart)
        XCTAssertEqual(full.songs.count, trackCount)

        let coordinator = LibraryCoordinator(container: container, source: EmptySource())
        let conversionStart = clock.now
        let music = await coordinator.searchMusic(from: full.songs)
        let conversionMilliseconds = Self.milliseconds(clock.now - conversionStart)
        XCTAssertEqual(music.count, trackCount)

        let player = FakePlayer()
        let engine = PlaybackEngine(playerFactory: { player }, nowPlaying: FakeNowPlaying())
        let playbackStart = clock.now
        engine.setQueue(music, startingAt: 49_999)
        engine.play()
        let playbackMilliseconds = Self.milliseconds(clock.now - playbackStart)
        let controller = LibrarySearchController(search: { _ in full })
        let showAllStart = clock.now
        controller.showAll(.songs)
        let showAllMilliseconds = Self.milliseconds(clock.now - showAllStart)
        let maximumStall = Self.milliseconds(monitor.maximumStall)

        var build = utsname()
        uname(&build)
        let hardware = withUnsafeBytes(of: &build.machine) { bytes in
            String(cString: bytes.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
        print("SEARCH_BENCHMARK tracks=\(trackCount) hardware=\(hardware) os=\(ProcessInfo.processInfo.operatingSystemVersionString)")
        print("SEARCH_BENCHMARK common_p95_ms=\(p95) high_match_ms=\(highMilliseconds) full_library_ms=\(fullMilliseconds)")
        print("SEARCH_BENCHMARK high_match_songs=\(high.songs.count) dto_conversion_ms=\(conversionMilliseconds) unicode_ms=\(unicodeMilliseconds)")
        print("SEARCH_BENCHMARK show_all_main_ms=\(showAllMilliseconds) playback_main_ms=\(playbackMilliseconds) player_items=\(player.replacedURLCount) max_main_gap_ms=\(maximumStall)")
        print("SEARCH_BENCHMARK store=\(storeURL.path)")

        XCTAssertLessThanOrEqual(p95, 300)
        XCTAssertLessThanOrEqual(unicodeMilliseconds.max() ?? 0, 300)
        XCTAssertLessThanOrEqual(showAllMilliseconds, 50)
        XCTAssertLessThanOrEqual(highMilliseconds, 750)
        XCTAssertLessThanOrEqual(fullMilliseconds, 750)
        XCTAssertLessThanOrEqual(playbackMilliseconds, 50)
        XCTAssertLessThanOrEqual(player.replacedURLCount, 3)
        XCTAssertLessThanOrEqual(maximumStall, 50)
    }

    private func seedTracks(_ count: Int, container: ModelContainer) throws {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        for index in 0..<count {
            context.insert(StoredTrack(
                id: UUID(), path: String(format: "/benchmark/%05d.mp3", index),
                sourcePath: "/benchmark", modificationDate: date, fileSize: 1_000_000,
                volumeID: nil, fileID: nil,
                title: index == 0 ? "Café 東京 Track 00000" : String(format: "Track %05d", index),
                artist: "Artist \(index % 250)", albumArtist: "Artist \(index % 250)",
                albumTitle: "Album \(index % 1000)", year: 2000 + index % 25,
                trackNumber: index % 12 + 1, discNumber: 1, genre: "Genre \(index % 12)",
                duration: 180, hasArtwork: false, metadataVersion: currentMetadataVersion))
            if (index + 1) % 1000 == 0 { try context.save() }
        }
        try context.save()
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}
