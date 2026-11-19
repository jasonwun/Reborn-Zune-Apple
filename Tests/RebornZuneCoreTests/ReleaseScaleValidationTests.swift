import CoreGraphics
import Darwin
import Foundation
import ImageIO
import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import RebornZuneCore

/// Opt-in integrated release acceptance for issue #27. The deterministic data
/// set is validation input, never Demo Library content shown by the product.
///
/// REBORN_ZUNE_RELEASE_SCALE=1 REBORN_ZUNE_RELEASE_REPORT=/tmp/report.json \
///   swift test -c release --filter ReleaseScaleValidationTests
@MainActor
final class ReleaseScaleValidationTests: XCTestCase {
    private static let trackCount = 50_000
    private static let removedSourceTrackCount = 5_000
    private static let tracksPerAlbum = 20

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

    func testIntegratedLibraryAt50000Tracks() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["REBORN_ZUNE_RELEASE_SCALE"] == "1",
            "Set REBORN_ZUNE_RELEASE_SCALE=1 to run integrated release validation"
        )

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("issue27-release-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("library.store")
        let container = try RebornZunePersistence.makePersistentContainer(at: storeURL)
        let retainedSource = ReleaseScaleSource("/release/Retained")
        let removedSource = ReleaseScaleSource("/release/Removed")
        try seed(container, retainedSource: retainedSource, removedSource: removedSource)

        let memoryBefore = Self.physicalFootprint()
        let monitor = MainThreadStallMonitor()
        defer { monitor.stop() }
        let clock = ContinuousClock()
        let coordinator = LibraryCoordinator(
            container: container,
            sources: [retainedSource, removedSource],
            bookmarkAccess: NoLibraryBookmarkAccess()
        )

        let launchStart = clock.now
        await coordinator.start()
        let launchMilliseconds = Self.milliseconds(clock.now - launchStart)
        XCTAssertEqual(coordinator.phase, .ready)
        XCTAssertEqual(coordinator.totalTrackCount, Self.trackCount)
        XCTAssertEqual(coordinator.tracks.count, 100)
        XCTAssertTrue(coordinator.hasMoreTracks)
        let sourceCounts = Dictionary(uniqueKeysWithValues: coordinator.sources.map {
            ($0.path, $0.committedTrackCount)
        })
        XCTAssertEqual(sourceCounts[retainedSource.sourcePath], 45_000)
        XCTAssertEqual(sourceCounts[removedSource.sourcePath], 5_000)
        XCTAssertEqual(retainedSource.extractionCount, 0)
        XCTAssertEqual(removedSource.extractionCount, 0)
        XCTAssertEqual(coordinator.tracks.filter { $0.artworkData != nil }.count, 100)
        let artwork = try XCTUnwrap(coordinator.tracks.first?.artworkData)
        let decodedArtwork = try Self.decodeImage(artwork)
        XCTAssertEqual(decodedArtwork.width, 256)
        XCTAssertEqual(decodedArtwork.height, 256)

        let manualScanStart = clock.now
        await coordinator.refresh()
        let manualScanMilliseconds = Self.milliseconds(clock.now - manualScanStart)
        XCTAssertNil(coordinator.scanError)
        XCTAssertEqual(coordinator.discoveredTrackCount, Self.trackCount)
        XCTAssertEqual(coordinator.totalTrackCount, Self.trackCount)
        XCTAssertEqual(coordinator.tracks.count, 100)
        XCTAssertEqual(retainedSource.extractionCount, 0)
        XCTAssertEqual(removedSource.extractionCount, 0)

        await coordinator.browse(matching: LibraryTrackQuery(sort: .albumTitle))
        await coordinator.loadNextPage()
        let browsedTrackCount = coordinator.tracks.count
        XCTAssertEqual(browsedTrackCount, 200)
        XCTAssertEqual(coordinator.totalTrackCount, Self.trackCount)

        // Build the normalized SQLite records and lazy actor-local index before
        // measuring queries, matching the established Search release benchmark.
        _ = try await coordinator.search(matching: "Release Song 49999")
        var commonMilliseconds: [Double] = []
        for index in 0..<20 {
            let query = index.isMultiple(of: 4)
                ? "No Such Track \(index)"
                : "Release Artist \(index % 500)"
            let start = clock.now
            _ = try await coordinator.search(matching: query)
            commonMilliseconds.append(Self.milliseconds(clock.now - start))
        }
        commonMilliseconds.sort()
        let commonP95 = commonMilliseconds[Int(ceil(Double(commonMilliseconds.count) * 0.95)) - 1]

        var unicodeMilliseconds: [Double] = []
        for query in ["cafe", "東京"] {
            let start = clock.now
            let result = try await coordinator.search(matching: query)
            unicodeMilliseconds.append(Self.milliseconds(clock.now - start))
            XCTAssertEqual(result.songs.count, 1)
        }

        let highStart = clock.now
        let highMatch = try await coordinator.search(matching: "1")
        let highMatchMilliseconds = Self.milliseconds(clock.now - highStart)
        XCTAssertFalse(highMatch.songs.isEmpty)

        let fullStart = clock.now
        let fullLibrary = try await coordinator.search(matching: "release")
        let fullLibraryMilliseconds = Self.milliseconds(clock.now - fullStart)
        XCTAssertEqual(fullLibrary.songs.count, Self.trackCount)
        XCTAssertEqual(fullLibrary.artists.count, 500)
        XCTAssertEqual(fullLibrary.albums.count, 2_500)

        let visibleArtworkIDs = fullLibrary.albums.prefix(5).compactMap(\.artworkTrackID)
        let visibleArtwork = await coordinator.searchArtwork(for: visibleArtworkIDs)
        XCTAssertEqual(visibleArtwork.count, 5)
        for data in visibleArtwork.values {
            XCTAssertEqual(try Self.decodeImage(data).width, 256)
        }

        let conversionStart = clock.now
        let queue = await coordinator.searchMusic(from: fullLibrary.songs)
        let conversionMilliseconds = Self.milliseconds(clock.now - conversionStart)
        XCTAssertEqual(queue.count, Self.trackCount)
        XCTAssertTrue(queue.allSatisfy { $0.artworkData == nil })

        let player = ReleaseScaleQueuePlayer()
        let engine = PlaybackEngine(
            playerFactory: { player },
            nowPlaying: ReleaseScaleNowPlaying()
        )
        let playbackStart = clock.now
        engine.setQueue(queue)
        engine.play()
        let playbackMilliseconds = Self.milliseconds(clock.now - playbackStart)
        XCTAssertEqual(engine.queue.count, Self.trackCount)
        XCTAssertEqual(player.itemURLs.count, 3)

        let controller = LibrarySearchController(search: { _ in fullLibrary })
        controller.updateQuery("release")
        let searchDeadline = clock.now + .seconds(5)
        while controller.results.songs.count != Self.trackCount, clock.now < searchDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(controller.phase, .ready)
        XCTAssertEqual(controller.results.songs.count, Self.trackCount)
        let showAllStart = clock.now
        controller.showAll(.songs)
        let showAllMilliseconds = Self.milliseconds(clock.now - showAllStart)
        XCTAssertEqual(controller.mode, .songs)
        XCTAssertEqual(controller.results.songs.count, Self.trackCount)

        // The 50 ms criterion applies to Search, Show All, and playback start.
        // Source cleanup has no such numeric target and is measured separately.
        let maximumStall = Self.milliseconds(monitor.maximumStall)
        monitor.stop()

        let removedID = UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", 49_999))!
        let retainedID = UUID(uuidString: "00000000-0000-4000-8000-000000000000")!
        let cleanupStart = clock.now
        try await coordinator.removeSource(removedSource.sourcePath)
        let cleanupMilliseconds = Self.milliseconds(clock.now - cleanupStart)
        XCTAssertEqual(coordinator.totalTrackCount, 45_000)
        XCTAssertEqual(coordinator.sources.map(\.committedTrackCount), [45_000])
        XCTAssertEqual(coordinator.tracks.count, 100)
        let existing = await coordinator.existingTrackIDs(among: [
            removedID.uuidString, retainedID.uuidString,
        ])
        XCTAssertEqual(existing, Set([retainedID.uuidString]))
        let removedResult = try await coordinator.search(matching: "Release Song 49999")
        XCTAssertTrue(removedResult.isEmpty)
        let remaining = try await coordinator.search(matching: "release")
        XCTAssertEqual(remaining.songs.count, 45_000)
        XCTAssertEqual(remaining.artists.count, 450)
        XCTAssertEqual(remaining.albums.count, 2_250)

        let memoryAfter = Self.physicalFootprint()
        let report = ReleaseScaleReport(
            trackCount: Self.trackCount,
            albumCount: Self.trackCount / Self.tracksPerAlbum,
            artistCount: 500,
            hardware: Self.hardware(),
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            launchIncludingIncrementalScanMilliseconds: launchMilliseconds,
            manualIncrementalScanMilliseconds: manualScanMilliseconds,
            publishedTrackCountAfterLaunch: 100,
            browsedTrackCountAfterPagination: browsedTrackCount,
            decodedArtworkWidth: decodedArtwork.width,
            decodedArtworkHeight: decodedArtwork.height,
            commonSearchP95Milliseconds: commonP95,
            unicodeSearchMilliseconds: unicodeMilliseconds,
            highMatchSearchMilliseconds: highMatchMilliseconds,
            highMatchSongCount: highMatch.songs.count,
            fullLibrarySearchMilliseconds: fullLibraryMilliseconds,
            searchDTOConversionMilliseconds: conversionMilliseconds,
            showAllMainThreadMilliseconds: showAllMilliseconds,
            largeQueuePlaybackStartMilliseconds: playbackMilliseconds,
            logicalQueueCount: engine.queue.count,
            materializedPlayerItemCount: player.itemURLs.count,
            sourceCleanupMilliseconds: cleanupMilliseconds,
            remainingTrackCountAfterCleanup: coordinator.totalTrackCount,
            maximumMainThreadSchedulingGapMilliseconds: maximumStall,
            physicalFootprintBeforeLaunchBytes: memoryBefore,
            physicalFootprintAfterValidationBytes: memoryAfter
        )
        try Self.write(report)
        print("RELEASE_SCALE_REPORT \(String(data: try JSONEncoder().encode(report), encoding: .utf8)!)")

        XCTAssertLessThanOrEqual(commonP95, 300)
        XCTAssertLessThanOrEqual(unicodeMilliseconds.max() ?? 0, 300)
        XCTAssertLessThanOrEqual(highMatchMilliseconds, 750)
        XCTAssertLessThanOrEqual(fullLibraryMilliseconds, 750)
        XCTAssertLessThanOrEqual(showAllMilliseconds, 50)
        XCTAssertLessThanOrEqual(playbackMilliseconds, 50)
        XCTAssertLessThanOrEqual(maximumStall, 50)
    }

    private func seed(
        _ container: ModelContainer,
        retainedSource: ReleaseScaleSource,
        removedSource: ReleaseScaleSource
    ) throws {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let modificationDate = Date(timeIntervalSince1970: 1_700_000_000)
        let genres = ["Ambient", "Jazz", "Rock", "Electronic", "Classical", "Soul", "Folk", "Pop"]
        let artwork = (0..<8).map(Self.makeArtwork)

        for index in 0..<Self.trackCount {
            let albumIndex = index / Self.tracksPerAlbum
            let artistIndex = albumIndex / 5
            let source = index < 45_000 ? retainedSource : removedSource
            let path = "\(source.sourcePath)/Artist \(artistIndex)/Album \(albumIndex)/Track \(index).m4a"
            let id = UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index))!
            let hasArtwork = index % Self.tracksPerAlbum == 0
            let track = StoredTrack(
                id: id,
                path: path,
                sourcePath: source.sourcePath,
                modificationDate: modificationDate,
                fileSize: 1_048_576,
                volumeID: Data("release-volume".utf8),
                fileID: Data(String(index).utf8),
                title: index == 0
                    ? "Café 東京 Release Song 00000"
                    : "Release Song \(String(format: "%05d", index))",
                artist: "Release Artist \(artistIndex)",
                albumArtist: "Release Artist \(artistIndex)",
                albumTitle: "Release Album \(albumIndex)",
                year: 1990 + albumIndex % 35,
                trackNumber: index % Self.tracksPerAlbum + 1,
                discNumber: 1,
                genre: genres[albumIndex % genres.count],
                duration: 150 + Double(index % 180),
                hasArtwork: hasArtwork,
                metadataVersion: currentMetadataVersion
            )
            context.insert(track)
            if hasArtwork { track.artwork = StoredTrackArtwork(data: artwork[albumIndex % 8]) }
            source.append(DiscoveredFile(
                path: path,
                modificationDate: modificationDate,
                fileSize: 1_048_576,
                volumeID: Data("release-volume".utf8),
                fileID: Data(String(index).utf8)
            ))
            if (index + 1) % 1000 == 0 { try context.save() }
        }
        try context.save()
    }

    private static func makeArtwork(_ index: Int) -> Data {
        let width = 256
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: width, height: width, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let hue = Double(index) / 8
        context.setFillColor(CGColor(
            red: 0.45 + hue * 0.4, green: 0.25 + hue * 0.3, blue: 0.75 - hue * 0.4, alpha: 1
        ))
        context.fill(CGRect(x: 0, y: 0, width: width, height: width))
        context.setFillColor(CGColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 0.8))
        context.fill(CGRect(x: 24, y: 24, width: 112 + index * 8, height: 208))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        )!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        _ = CGImageDestinationFinalize(destination)
        return data as Data
    }

    private static func decodeImage(_ data: Data) throws -> CGImage {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }

    private static func physicalFootprint() -> UInt64 {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rawPointer in
                proc_pid_rusage(getpid(), RUSAGE_INFO_V4, rawPointer)
            }
        }
        return result == 0 ? info.ri_lifetime_max_phys_footprint : 0
    }

    private static func hardware() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var value = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &value, &size, nil, 0)
        return String(
            decoding: value.map { UInt8(bitPattern: $0) }.prefix(while: { $0 != 0 }),
            as: UTF8.self
        )
    }

    private static func write(_ report: ReleaseScaleReport) throws {
        guard let path = ProcessInfo.processInfo.environment["REBORN_ZUNE_RELEASE_REPORT"] else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: URL(fileURLWithPath: path))
    }
}

private final class ReleaseScaleSource: LibraryFileSource, @unchecked Sendable {
    let sourcePath: String
    private let lock = NSLock()
    private var files: [DiscoveredFile] = []
    private var extractions = 0

    init(_ sourcePath: String) { self.sourcePath = sourcePath }

    var extractionCount: Int { lock.withLock { extractions } }

    func append(_ file: DiscoveredFile) {
        lock.withLock { files.append(file) }
    }

    func discover() async throws -> [DiscoveredFile] { lock.withLock { files } }

    func extract(_ file: DiscoveredFile) async throws -> ExtractedMetadata {
        lock.withLock { extractions += 1 }
        throw CancellationError()
    }
}

private struct ReleaseScaleReport: Codable {
    let trackCount: Int
    let albumCount: Int
    let artistCount: Int
    let hardware: String
    let operatingSystem: String
    let launchIncludingIncrementalScanMilliseconds: Double
    let manualIncrementalScanMilliseconds: Double
    let publishedTrackCountAfterLaunch: Int
    let browsedTrackCountAfterPagination: Int
    let decodedArtworkWidth: Int
    let decodedArtworkHeight: Int
    let commonSearchP95Milliseconds: Double
    let unicodeSearchMilliseconds: [Double]
    let highMatchSearchMilliseconds: Double
    let highMatchSongCount: Int
    let fullLibrarySearchMilliseconds: Double
    let searchDTOConversionMilliseconds: Double
    let showAllMainThreadMilliseconds: Double
    let largeQueuePlaybackStartMilliseconds: Double
    let logicalQueueCount: Int
    let materializedPlayerItemCount: Int
    let sourceCleanupMilliseconds: Double
    let remainingTrackCountAfterCleanup: Int
    let maximumMainThreadSchedulingGapMilliseconds: Double
    let physicalFootprintBeforeLaunchBytes: UInt64
    let physicalFootprintAfterValidationBytes: UInt64
}

@MainActor
private final class ReleaseScaleQueuePlayer: QueuePlayer {
    var itemURLs: [URL] = []
    var volume = 1.0
    var currentTime = 0.0
    var onTimeUpdate: ((TimeInterval, TimeInterval?) -> Void)?
    var onPlaybackStatusChange: ((QueuePlaybackStatus) -> Void)?
    var onItemEnd: (() -> Void)?
    func replaceItems(with urls: [URL]) { itemURLs = urls }
    func play() {}
    func pause() {}
    func seek(to seconds: TimeInterval) { currentTime = seconds }
    func invalidate() { itemURLs = [] }
}

private final class ReleaseScaleNowPlaying: NowPlayingCentering {
    func registerCommands(_ handlers: RemoteCommandHandlers) {}
    func update(item: Music?, currentTime: TimeInterval, duration: TimeInterval, rate: Double) {}
}
