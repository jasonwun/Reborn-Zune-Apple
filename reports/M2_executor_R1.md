# M2 — Executor Report (R1)

Milestone: library/data layer (`Music`, `Album`, `Artist`, `LibraryGrouping`,
`LibrarySource`, `MetadataExtractor`, `FolderLibrarySource`, `BundleLibrarySource`).
Toolchain: same as M1 (Xcode 26.4.1, Swift 6.3.1).

## Files added

Domain types (`Sources/RebornZuneCore/Models/`):
- `/Users/yjd/Documents/Reborn-Zune-Apple/Sources/RebornZuneCore/Models/Music.swift`
- `/Users/yjd/Documents/Reborn-Zune-Apple/Sources/RebornZuneCore/Models/Album.swift`
- `/Users/yjd/Documents/Reborn-Zune-Apple/Sources/RebornZuneCore/Models/Artist.swift`
- `/Users/yjd/Documents/Reborn-Zune-Apple/Sources/RebornZuneCore/Models/LibraryGrouping.swift`

Library layer (`Sources/RebornZuneCore/Library/`):
- `/Users/yjd/Documents/Reborn-Zune-Apple/Sources/RebornZuneCore/Library/LibrarySource.swift`
- `/Users/yjd/Documents/Reborn-Zune-Apple/Sources/RebornZuneCore/Library/MetadataExtractor.swift`
- `/Users/yjd/Documents/Reborn-Zune-Apple/Sources/RebornZuneCore/Library/FolderLibrarySource.swift`
- `/Users/yjd/Documents/Reborn-Zune-Apple/Sources/RebornZuneCore/Library/BundleLibrarySource.swift`

Folder skeleton (empty `.keep` files):
- `/Users/yjd/Documents/Reborn-Zune-Apple/Sources/RebornZuneCore/Audio/.keep`
- `/Users/yjd/Documents/Reborn-Zune-Apple/Sources/RebornZuneCore/Views/.keep`
- `/Users/yjd/Documents/Reborn-Zune-Apple/Sources/RebornZuneCore/Persistence/.keep`

Tests (`Tests/RebornZuneCoreTests/`):
- `/Users/yjd/Documents/Reborn-Zune-Apple/Tests/RebornZuneCoreTests/MusicTests.swift`
- `/Users/yjd/Documents/Reborn-Zune-Apple/Tests/RebornZuneCoreTests/LibraryGroupingTests.swift`
- `/Users/yjd/Documents/Reborn-Zune-Apple/Tests/RebornZuneCoreTests/BundleLibrarySourceTests.swift`
- `/Users/yjd/Documents/Reborn-Zune-Apple/Tests/RebornZuneCoreTests/FolderLibrarySourceTests.swift`

No files outside `Sources/RebornZuneCore/` and `Tests/RebornZuneCoreTests/` were touched.
`Package.swift`, `project.yml`, and `Apps/` are unchanged.

## Public API surface — confirmation against spec

All public types/signatures match the spec verbatim.

- `public struct Music: Identifiable, Hashable, Sendable` — fields `id`, `url`,
  `title`, `artist`, `albumArtist`, `albumTitle`, `year`, `duration`, `artworkData`;
  designated initializer matches spec parameter list and types. CONFIRMED.
- `public static func Music.makeID(for:) -> String` — SHA-256 of `url.path`
  (deterministic per the spec note). CONFIRMED. (Spec gives latitude: "use the
  path itself or its SHA-256.")
- `public struct Album: Identifiable, Hashable, Sendable` — fields `id`, `title`,
  `albumArtist`, `year`, `tracks`; computed `artworkData` returning
  `tracks.first?.artworkData`. CONFIRMED.
- `public struct Artist: Identifiable, Hashable, Sendable` — fields `id`, `name`,
  `albums`. CONFIRMED.
- `public enum LibraryGrouping` with
  `public static func albums(from tracks: [Music]) -> [Album]` and
  `public static func artists(from albums: [Album]) -> [Artist]`. CONFIRMED.
- `public protocol LibrarySource: Sendable { func load() async throws -> [Music] }`. CONFIRMED.
- `struct MetadataExtractor` (file-internal access — no `public`) with
  `static func extract(from url: URL) async throws -> Music`. Uses
  `try await asset.load(.metadata)` and `asset.load(.duration)`. CONFIRMED.
- `public final class FolderLibrarySource: LibrarySource` —
  `public init(folder: URL)` and `public func load() async throws -> [Music]`.
  Recursive scan of `.mp3 / .m4a / .mp4 / .aac`, bounded concurrency at 8,
  per-file failure tolerated, results sorted by title ascending. CONFIRMED.
- `public final class BundleLibrarySource: LibrarySource` —
  `public init(bundle: Bundle = .main, subdirectory: String? = nil)` and
  `public func load() async throws -> [Music]`. Uses
  `bundle.urls(forResourcesWithExtension:subdirectory:)` for each supported
  extension; same metadata pipeline as `FolderLibrarySource`. CONFIRMED.

## Build outputs

### `swift build` (last 30 lines)
```
Building for debugging...
[0/2] Write sources
[1/2] Write swift-version--58304C5D6DBC2206.txt
[3/4] Emitting module RebornZuneCore
[4/4] Compiling RebornZuneCore MetadataExtractor.swift
[5/6] Compiling RebornZuneCore BundleLibrarySource.swift
[6/6] Compiling RebornZuneCore FolderLibrarySource.swift
Build complete! (0.53s)
```
Exit 0. No warnings.

(An earlier compile produced AVFoundation deprecation warnings on the synchronous
`stringValue`/`dataValue`/`numberValue` accessors. Per the spec rule "if a warning
is real, fix the code", I rewrote `MetadataExtractor` to use the async
`item.load(.stringValue)` / `.load(.dataValue)` / `.load(.numberValue)` accessors.
The current build is warning-free.)

### `swift test` summary
```
Test Suite 'All tests' passed at 2026-05-02 15:27:43.457.
     Executed 15 tests, with 0 failures (0 unexpected) in 0.007 (0.008) seconds
```

Per-suite breakdown (from full output):
- `BundleLibrarySourceTests`: 2 tests passed
- `FolderLibrarySourceTests`: 3 tests passed
- `LibraryGroupingTests`: 7 tests passed
- `MusicTests`: 2 tests passed
- `RebornZuneCoreTests` (M1 carryover): 1 test passed

15 tests total, 0 failures.

### `xcodegen generate`
```
⚙️  Generating plists...
⚙️  Generating project...
⚙️  Writing project...
Created project at /Users/yjd/Documents/Reborn-Zune-Apple/RebornZune.xcodeproj
```
Exit 0.

### `xcodebuild RebornZune-macOS platform=macOS build` (last lines)
```
note: Disabling hardened runtime with ad-hoc codesigning. (in target 'RebornZune-macOS' from project 'RebornZune')
** BUILD SUCCEEDED **
```

### `xcodebuild RebornZune-iPadOS generic/platform=iOS Simulator build CODE_SIGNING_ALLOWED=NO`
```
Ignoring --strip-bitcode because --sign was not passed
** BUILD SUCCEEDED **
```

### `xcodebuild RebornZune-tvOS generic/platform=tvOS Simulator build CODE_SIGNING_ALLOWED=NO`
```
ProcessInfoPlistFile ... Reborn\ Zune.app/Info.plist (in target 'RebornZune-tvOS' from project 'RebornZune')
** BUILD SUCCEEDED **
```

All three app targets `BUILD SUCCEEDED` with no regression versus M1.

## Acceptance criteria self-check

| # | Criterion | Status | Evidence |
| --- | --- | --- | --- |
| B1 | All §1–§6 files exist with spec'd types/signatures | PASS | See "Files added" and "Public API surface" sections above. Each spec'd public type/method enumerated and confirmed. |
| B2 | `swift build` exit 0 | PASS | "Build complete! (0.53s)" — no warnings. |
| B3 | `swift test` exit 0 with ≥10 tests | PASS | "Executed 15 tests, with 0 failures". 15 ≥ 10. |
| B4 | All three xcodebuild commands still succeed | PASS | macOS, iPadOS, tvOS all `** BUILD SUCCEEDED **` (outputs above). |
| B5 | `Music.id` deterministic for the same URL | PASS | `MusicTests.testIDIsDerivedFromURL` asserts `Music.makeID(for: urlA) == Music.makeID(for: urlB)` for two URLs with the same path, and `!=` for different paths. |
| B6 | `LibraryGrouping.albums` collapses by `(title, privilegedArtist)` correctly | PASS | `LibraryGroupingTests`: `testAlbumGroupingByAlbumAndArtist` (same-title-different-albumArtist splits), `testPrivilegedArtistRule` (all four sub-cases including `"Unknown Artist"`-as-nil), `testEarliestYearWins`, `testTrackOrdering`, `testEmptyInput`, plus extras `testMissingAlbumTitleBecomesUnknownAlbum` and `testArtistsGroupAlbumsByAlbumArtist`. All pass. |
| B7 | `FolderLibrarySource` and `BundleLibrarySource` conform to `LibrarySource` | PASS | Both declared `: LibrarySource`; compiler-enforced. `BundleLibrarySourceTests.testConformsToLibrarySource` additionally binds an instance to `any LibrarySource`. |
| B8 | `MetadataExtractor` is internal | PASS | Declared `struct MetadataExtractor { ... }` — no `public` modifier. The `extract(from:)` method is also internal (default access). Verified by reading source. |
| B9 | No external SwiftPM dependencies in `Package.swift` | PASS | `Package.swift` unmodified from M1 — no top-level `dependencies:` array, only `dependencies: ["RebornZuneCore"]` on the test target (referencing a sibling target, not an external package). `CryptoKit` and `AVFoundation` are system frameworks. |
| B10 | No `print()` debug noise in `Sources/` | PASS | `grep -rn 'print(' Sources/` returns no matches. |

## Decisions where the spec was silent

1. **`Music.makeID` formula.** The spec offered "use the path itself or its
   SHA-256". I went with SHA-256 hex of `url.path` so the ID is filesystem-safe,
   length-bounded, and free of path separators (useful when the ID later becomes
   a SwiftData key or a cache filename). Functionally equivalent to using the
   path; the test asserts determinism and inequality, which holds either way.
2. **`Album.makeID` and `Artist.makeID`.** Spec says `Album.id` is "hash of
   (albumTitle, privilegedArtist)" and `Artist.id` is "hash of name". I made
   these `static func makeID(...)` helpers (internal, not `public`) on each type
   and called them from `LibraryGrouping`. The grouping logic is the canonical
   construction site, so users don't need to call these helpers themselves.
3. **Insertion order vs. alphabetical for albums/artists.** Spec specifies
   ordering only inside an album ("sort by `title` ascending"); it is silent on
   the order of albums returned by `albums(from:)` or artists returned by
   `artists(from:)`. I preserved the insertion order of the first-seen track per
   `(albumTitle, privilegedArtist)`. Stable and predictable for tests; if a
   later milestone wants alphabetical, that's a one-line change.
4. **`SupportedAudioExtension` enum.** Internal enum factored out to share the
   `.mp3 / .m4a / .mp4 / .aac` list between `FolderLibrarySource` and
   `BundleLibrarySource`. Single source of truth. Not part of the public API.
5. **`FolderLibrarySource` non-existent folder error type.** Spec says "throws
   on permission failures, missing folder, etc." I throw a `CocoaError` with
   `.fileReadNoSuchFile`. Tests just assert that `try await source.load()`
   throws; the specific error type is unobservable at the public API.
6. **Title-sort uses `localizedCaseInsensitiveCompare`.** Spec says "sort by
   `title` ascending" without specifying case sensitivity or locale. Localized
   case-insensitive sort is the conventional Apple library-app behavior.
7. **Bounded concurrency implementation.** Spec says
   "`withTaskGroup` or `async let` — bounded concurrency, max 8 in-flight". I
   used `withTaskGroup` with a prime/drain pattern that keeps at most 8 tasks
   in flight at any moment.
8. **AVFoundation async accessors.** The spec mandates the modern
   `asset.load(.metadata)` / `.load(.duration)` APIs. The synchronous
   `AVMetadataItem.stringValue` / `.dataValue` / `.numberValue` are also
   deprecated in macOS 13+ and produced warnings on the first build. To honor
   the spec rule "if a warning is real, fix the code", I switched the per-item
   value reads to the async `item.load(.stringValue)` / `.load(.dataValue)` /
   `.load(.numberValue)` variants. This is consistent with the spec's stated
   preference for the modern async APIs.

## Anything the spec got wrong

Nothing. The spec was buildable as written; the only real-world wrinkle was the
deprecation of the sync `stringValue`/`dataValue`/`numberValue` accessors in
macOS 13+, which I fixed by adopting the async equivalents (note above).

## Scope discipline check

Did not add any UI code, did not add a `ThumbnailCache`, did not introduce
SwiftData persistence types, did not add `NSMetadataQuery` integration, did not
add bookmark management, did not add real audio test fixtures, did not modify
`Package.swift`, `project.yml`, `Apps/`, or M1 source files. All of those are
explicitly out of scope per `M2.md → Out of scope`.
