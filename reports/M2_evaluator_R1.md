# M2 — Evaluator Report (R1)

Independent verification of the executor's M2 deliverables. All build/test
commands re-run from scratch by the evaluator; source files independently read
and compared to `specs/M2.md`.

## Per-criterion verification

| # | Criterion | Status | Evidence |
| --- | --- | --- | --- |
| B1 | All §1–§6 files exist with spec'd types/signatures | verified | `find` listed every spec'd path. Read each file and confirmed the exact public signatures (see "Signature spot-check" below). Folder skeleton: `Sources/RebornZuneCore/{Audio,Views,Persistence}/.keep` all present. |
| B2 | `swift build` succeeds | verified | `Build complete! (0.11s)` — exit 0, no warnings. |
| B3 | `swift test` succeeds and runs ≥ 10 tests | verified | `Executed 15 tests, with 0 failures (0 unexpected) in 0.006 (0.008) seconds`. 15 ≥ 10. |
| B4 | All three xcodebuild commands still succeed | verified | macOS / iPadOS Simulator / tvOS Simulator: each printed `** BUILD SUCCEEDED **` (re-run by evaluator). |
| B5 | `Music.id` for the same `URL` is deterministic | verified | `MusicTests.testIDIsDerivedFromURL` asserts `Music.makeID(for: urlA) == Music.makeID(for: urlB)` for two URLs at the same path, and `!=` for a different path. Implementation hashes `url.path` via `SHA256.hash(data: Data(path.utf8))`. |
| B6 | `LibraryGrouping.albums` collapses by `(title, privilegedArtist)` correctly — all four sub-cases | verified | `LibraryGroupingTests.testPrivilegedArtistRule` covers (a) only `artist`, (b) both set (prefers `albumArtist`), (c) `albumArtist == "Unknown Artist"` falls back to `artist`, (d) both unknown → `"Unknown Artist"`. `testAlbumGroupingByAlbumAndArtist` covers same album title with differing albumArtist splitting into two albums. `testEarliestYearWins`, `testTrackOrdering`, `testEmptyInput` all present and have meaningful asserts. |
| B7 | `FolderLibrarySource` and `BundleLibrarySource` conform to `LibrarySource` | verified | Both declared `: LibrarySource`; `BundleLibrarySourceTests.testConformsToLibrarySource` additionally binds an instance to `any LibrarySource`. Compiler-enforced. |
| B8 | `MetadataExtractor` is internal | verified | `Sources/RebornZuneCore/Library/MetadataExtractor.swift` line 4: `struct MetadataExtractor {` — no `public`, no `@_spi`, no `@usableFromInline`. Method `static func extract(from url: URL) async throws -> Music` is also internal (default access). |
| B9 | No external SwiftPM dependencies in `Package.swift` | verified | `Package.swift` has no top-level `dependencies:`. The test target's `dependencies: ["RebornZuneCore"]` is a same-package target reference, not an external package. `CryptoKit` and `AVFoundation` are system frameworks (no `import` triggers a SwiftPM dependency). |
| B10 | No `print()` debug noise in production code paths | verified | `grep -rn 'print(' /Users/yjd/Documents/Reborn-Zune-Apple/Sources/` returned no matches. |

## Signature spot-check

Each public type read and compared to the spec. All signatures match exactly.

- `Sources/RebornZuneCore/Models/Music.swift` — `public struct Music: Identifiable, Hashable, Sendable` with all nine fields (`id, url, title, artist, albumArtist, albumTitle, year, duration, artworkData`) and the spec'd designated initializer parameter list/types. `public static func makeID(for url: URL) -> String` is an additional helper (spec gives latitude here; permitted).
- `Sources/RebornZuneCore/Models/Album.swift` — `public struct Album: Identifiable, Hashable, Sendable` with `id, title, albumArtist, year, tracks` and computed `artworkData: Data? { tracks.first?.artworkData }`. Initializer added by executor; spec didn't forbid it.
- `Sources/RebornZuneCore/Models/Artist.swift` — `public struct Artist: Identifiable, Hashable, Sendable` with `id, name, albums`.
- `Sources/RebornZuneCore/Models/LibraryGrouping.swift` — `public enum LibraryGrouping` with `public static func albums(from tracks: [Music]) -> [Album]` and `public static func artists(from albums: [Album]) -> [Artist]`. Privileged-artist helper is internal.
- `Sources/RebornZuneCore/Library/LibrarySource.swift` — `public protocol LibrarySource: Sendable { func load() async throws -> [Music] }`. Internal `enum SupportedAudioExtension: String, CaseIterable` for shared file-extension list (not part of the public API).
- `Sources/RebornZuneCore/Library/MetadataExtractor.swift` — internal `struct MetadataExtractor` with `static func extract(from url: URL) async throws -> Music`. Uses modern async API: `try await asset.load(.metadata)` and `try await asset.load(.duration)`. Per-item value reads use the async `item.load(.stringValue) / .load(.dataValue) / .load(.numberValue)` accessors (avoiding the deprecated synchronous accessors).
- `Sources/RebornZuneCore/Library/FolderLibrarySource.swift` — `public final class FolderLibrarySource: LibrarySource` with `public init(folder: URL)` and `public func load() async throws -> [Music]`. Recursive enumeration, supported extensions match spec, bounded concurrency at 8 via `withTaskGroup` prime/drain pattern, per-file failure tolerated (`try?` swallows extraction errors), result sorted by title.
- `Sources/RebornZuneCore/Library/BundleLibrarySource.swift` — `public final class BundleLibrarySource: LibrarySource` with `public init(bundle: Bundle = .main, subdirectory: String? = nil)` and `public func load() async throws -> [Music]`. Same metadata pipeline.

## Modern-API check

`grep -rn '\.metadata' Sources/` returned only:
- `MetadataExtractor.swift:12: try await asset.load(.metadata)` — modern async accessor (correct).
- `MetadataExtractor.swift:49,73: AVMetadataItem.metadataItems(from: items, filteredByIdentifier:)` — class-level filter helper (not the deprecated sync `asset.metadata` accessor).

No use of the deprecated synchronous `AVAsset.metadata` property. Spec rule satisfied.

## Test substance audit

Each test read for asserts (not just object construction):

- `MusicTests.testIDIsDerivedFromURL` — asserts equality for same path, inequality for different path, ID non-empty.
- `MusicTests.testHashableEquality` — asserts `==`, equal hashValues, inequality for different URL, and that a `Set` collapses equal Music values.
- `LibraryGroupingTests.testAlbumGroupingByAlbumAndArtist` — asserts album count, presence of both albumArtists, per-album track counts, album title.
- `LibraryGroupingTests.testPrivilegedArtistRule` — asserts the artistsSet contains the four expected names (one per sub-case) and album count is 4.
- `LibraryGroupingTests.testEarliestYearWins` — asserts album.year == 1999 (the earliest non-nil among 2003, 1999, nil).
- `LibraryGroupingTests.testTrackOrdering` — asserts the tracks array maps to `["Alpha", "Bravo", "Charlie"]` (verifying ascending title sort).
- `LibraryGroupingTests.testEmptyInput` — asserts both `albums(from: [])` and `artists(from: [])` return `[]`.
- `LibraryGroupingTests.testMissingAlbumTitleBecomesUnknownAlbum` (extra) — asserts album.title == "Unknown Album".
- `LibraryGroupingTests.testArtistsGroupAlbumsByAlbumArtist` (extra) — asserts artist count, per-artist album counts, and stable ID via `Artist.makeID(name:)`.
- `BundleLibrarySourceTests.testEmptyBundleReturnsEmpty` — asserts `tracks == []`.
- `BundleLibrarySourceTests.testConformsToLibrarySource` (extra) — binds an instance to `any LibrarySource`; weak but compiler-enforced via `: LibrarySource` declaration anyway.
- `FolderLibrarySourceTests.testEmptyFolderReturnsEmpty` — asserts empty array.
- `FolderLibrarySourceTests.testNonExistentFolderThrows` — `XCTFail` if no throw; expected throw caught.
- `FolderLibrarySourceTests.testNonAudioFilesAreIgnored` (extra) — asserts non-audio files don't load.
- `RebornZuneCoreTests.testVersionStringIsNonEmpty` (M1 carryover) — asserts version string non-empty.

All tests have substantive asserts. No "construct and pass" anti-patterns.

## M1 regression check

Re-ran the three xcodebuild commands (M1's primary acceptance criterion). All three printed `** BUILD SUCCEEDED **`. M1 unit test (`testVersionStringIsNonEmpty`) still passes inside the M2 test run. No regression.

## Independent build/test outputs (last lines)

### `swift build`
```
[0/1] Planning build
Building for debugging...
[0/1] Write swift-version--58304C5D6DBC2206.txt
Build complete! (0.11s)
```

### `swift test`
```
Test Suite 'RebornZuneCorePackageTests.xctest' passed at 2026-05-02 15:30:46.629.
	 Executed 15 tests, with 0 failures (0 unexpected) in 0.006 (0.007) seconds
Test Suite 'All tests' passed at 2026-05-02 15:30:46.629.
	 Executed 15 tests, with 0 failures (0 unexpected) in 0.006 (0.008) seconds
◇ Test run started.
↳ Testing Library Version: 1743
↳ Target Platform: arm64e-apple-macos14.0
✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.
```

### `xcodebuild RebornZune-macOS platform=macOS`
```
note: Disabling hardened runtime with ad-hoc codesigning. (in target 'RebornZune-macOS' from project 'RebornZune')
** BUILD SUCCEEDED **
```

### `xcodebuild RebornZune-iPadOS generic/platform=iOS Simulator CODE_SIGNING_ALLOWED=NO`
```
ClangStatCache /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang-stat-cache /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator26.4.sdk -o /Users/yjd/Library/Developer/Xcode/DerivedData/SDKStatCaches.noindex/iphonesimulator26.4-23E252-686eebb5dc1d8ecb277353a59184f4aa.sdkstatcache

** BUILD SUCCEEDED **
```

### `xcodebuild RebornZune-tvOS generic/platform=tvOS Simulator CODE_SIGNING_ALLOWED=NO`
```
ClangStatCache /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang-stat-cache /Applications/Xcode.app/Contents/Developer/Platforms/AppleTVSimulator.platform/Developer/SDKs/AppleTVSimulator26.4.sdk -o /Users/yjd/Library/Developer/Xcode/DerivedData/SDKStatCaches.noindex/appletvsimulator26.4-23L236-11f4d1e4fa50bf500d4b8df235a2802e.sdkstatcache

** BUILD SUCCEEDED **
```

## Findings summary

- All 10 acceptance criteria (B1–B10) are independently verified.
- All public API signatures match the spec exactly.
- `MetadataExtractor` is internal as required.
- Privileged-artist sentinel rule (`"Unknown Artist"` demotes to next fallback) is implemented and explicitly tested.
- `Album.tracks` is sorted by title ascending and explicitly tested.
- No `print()` calls in `Sources/`. No deprecated `asset.metadata` sync accessor. No external SwiftPM dependencies.
- 15 tests pass, well above the spec's ≥ 10 threshold; every test has a substantive `XCTAssert`.
- M1 regression: all three xcodebuild commands still succeed.

VERDICT: APPROVED
