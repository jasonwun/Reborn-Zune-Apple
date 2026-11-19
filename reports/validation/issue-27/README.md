# Issue #27 integrated validation evidence

## Result

**Blocked — keep issue #27 open.** The integrated 50,000-track release scenario,
its Search correctness regression, and every build command of record pass. The
final native macOS journey could not be exercised because the host remained
locked (`screen_locked`), and this host cannot supply the specified macOS 14
runtime check. No visual or platform-runtime acceptance is claimed without
actual evidence.

Validation date: 2026-11-19. Starting revision: `c8bb937`.

## Environment

- MacBook Pro (`Mac15,8`), Apple M3 Max, 128 GiB RAM, arm64
- macOS 27.0.1 (26A434)
- Xcode 27.2 (27B52)
- Scale validation: release Swift tests with temporary on-disk SwiftData stores
- Native host available: macOS 27.0.1 only; no macOS 14 runtime result

See `environment.txt` for the captured environment output.

## Search defect fixed with red → green public-seam tests

The new integrated scenario exposed a correctness defect that the existing
single-source benchmark did not catch. A two-source, multi-batch Library query
for `release` returned only 7,000 of 50,000 Songs. After source cleanup it
returned 2,000 of the remaining 45,000.

A minimized `LibrarySearchStore.search` regression using 3,000 Tracks across two
sources then reproduced 2,000 Songs, 400 of 600 Artists, and 1,000 of 3,000
Albums. The complete ordered result must contain every row without repeats.

- RED: `search-batches-red.log` and `release-scale-red.log`
- GREEN: `search-batches-green.log` and `release-scale-final.log`

The keyset-paginated fetches could return limited batches in context-registration
order rather than the requested path order. Advancing a cursor past an unordered
batch skipped unread Tracks and their aggregate search records.

`LibrarySearchStore` now uses a fresh `ModelContext` with SQLite offset/limit
pagination for each 1,000-row batch. Search-key writes are saved per batch while
the Library's normalization version is marked current only after the complete
rebuild. The lazy actor-local memory index, matching, ranking, DTO conversion,
and cancellation checks remain in place. No FTS engine or new numeric target was
introduced.

## Reproducible integrated 50,000-track release scenario

Run from the repository root:

```sh
REBORN_ZUNE_RELEASE_SCALE=1 \
REBORN_ZUNE_RELEASE_REPORT="$PWD/reports/validation/issue-27/release-scale.json" \
swift test -c release \
  --filter ReleaseScaleValidationTests.testIntegratedLibraryAt50000Tracks
```

Actual final result: one test passed in 79.005 seconds. Complete output is in
`release-scale-final.log`; machine-readable output is in `release-scale.json`.

The deterministic validation dataset contains 50,000 persisted Tracks, 2,500
Albums, 500 Artists, eight genre strings, disc/track numbers, durations, and
separate 256×256 decodable PNG artwork records. Two non-overlapping fake file
sources own 45,000 and 5,000 rows. Unchanged incremental scans perform zero
metadata extractions. These are test records, not Demo Library content shown by
the product and not 50,000 real audio-file decodes.

The scenario exercises, in order:

1. Paged launch publication and the first incremental scan.
2. A manual incremental scan of all 50,000 discovered Tracks.
3. Store browsing and a second 100-Track page.
4. Actual ImageIO decoding of loaded and Search-visible artwork.
5. Common, zero-result, diacritic-insensitive, CJK, high-match, and full-Library
   Global Search queries.
6. Complete Show All state and a 50,000-Track logical Queue playback start.
7. Removal of the 5,000-Track source, linked identity cleanup, and a rebuilt
   Search snapshot.

| Measurement | Actual result | Required threshold |
| --- | ---: | ---: |
| Launch call including incremental scan | 8,080.079 ms | Record only |
| Manual incremental scan | 8,041.338 ms | Record only |
| Tracks published at launch | 100 of 50,000 | Paged, not full Library |
| Tracks after one additional page | 200 | 200 expected |
| Decoded artwork dimensions | 256×256 | Must decode |
| Common Search p95 | 235.578 ms | ≤300 ms |
| `cafe` / `東京` Search | 93.973 / 168.262 ms | ≤300 ms |
| High-match Search | 110.871 ms | ≤750 ms |
| Full-Library Search | 39.100 ms | ≤750 ms |
| Full-Library results | 50,000 Songs / 500 Artists / 2,500 Albums | Complete |
| Search DTO conversion | 54.308 ms | Record only; off main actor |
| Show All main-thread apply | 0.034 ms | ≤50 ms |
| Large-Queue playback start | 9.565 ms | ≤50 ms |
| Logical / materialized player items | 50,000 / 3 | Current + two |
| Search/Show All/playback maximum main-thread gap | 22.674 ms | ≤50 ms |
| Source cleanup | 801.899 ms | Record only |
| Results after removing 5,000-Track source | 45,000 Songs / 450 Artists / 2,250 Albums | Complete |
| Lifetime physical footprint before / after | 45,532,000 / 246,137,960 bytes | Record only |

The main-thread gap assertion is scoped to Search, Show All, and playback start;
source cleanup has no numeric target. The separate launch/browse release probe
(`library-scale.log`) also passed: 31.520 ms to the first browsable page, 100
published Tracks, an 18.564 ms launch scheduling gap, and a 0.112 ms maximum
synchronous browse apply.

The established Search release benchmark was rerun after the fix
(`search-scale-final.log`): one test passed in 28.252 seconds; common p95 was
112.349 ms, high-match 71.988 ms, full-Library 72.509 ms, Show All 0.011 ms,
playback start 9.376 ms, and maximum main-thread gap 1.509 ms.

## Native and cross-platform verification status

An isolated app copy, test-only real MP3/M4A/FLAC/WAV/AIFF/AAC fixtures, and a
container-local debug Store were prepared. However, every Orca accessibility
read returned `screen_locked` before any interaction. Consequently this run does
**not** establish the fresh-profile/multi-source/Playlist/Queue/Search/history/
menu/Dock/remote journey, native animation states, or final iPadOS/tvOS native
behavior sweeps. No new screenshots are presented as evidence.

The earlier per-slice native captures remain historical evidence only; they are
not substituted for final integrated visual acceptance. A macOS 14 runtime is
also unavailable on this Mac, so the parent specification's requested macOS 14
format/metadata check remains open.

## Acceptance criteria status

| Criterion | Status | Evidence / reason |
| --- | --- | --- |
| Fresh-profile, multi-source, metadata, Playlist, Queue, Search, history and system-control journey | **Blocked** | Final native UI could not be read or driven while the host was locked. |
| Realistic 50,000-track launch, scans, browse, Search, Show All, large Queue, artwork and cleanup | **Pass (automated release seam)** | `release-scale-final.log` and `release-scale.json`. |
| Search thresholds and no full-Library/full-Queue materialization | **Pass (automated release seam)** | All numeric assertions passed; launch publishes 100 rows and playback materializes three items. |
| Fallback order and unchanged semantics | **Pass** | Existing lazy-memory-index fallback retained; no FTS or new target added. |
| Native visual verification on every affected surface | **Blocked** | No final native captures or animation inspection due to `screen_locked`. |
| Demo-only fabrication and iPadOS/tvOS non-regression | **Partial** | Real-data regression suite and all builds pass; final native platform sweeps were not run. |
| All build commands of record | **Pass** | Final logs below; all commands exited zero. |
| Defects fixed or explicitly blocking completion | **Blocked, explicitly reported** | Search result loss fixed; native and macOS 14 acceptance gaps remain. |

## Final command output

All commands ran sequentially on the final code and exited zero.

| Command | Actual output / log |
| --- | --- |
| `xcodegen generate` | `xcodegen.log`: project created |
| `swift build` | `swift-build.log`: `Build complete! (2.25 sec)` |
| `swift test` | `swift-test.log`: 320 tests, 3 skipped, 0 failures in 23.567 s |
| macOS app build | `macos-build.log`: `** BUILD SUCCEEDED **` |
| iPadOS simulator build | `ipados-build.log`: `** BUILD SUCCEEDED **` |
| tvOS simulator build | `tvos-build.log`: `** BUILD SUCCEEDED **` |

The three ordinary-suite skips are the opt-in Library scale, Search scale, and
integrated release validations. The first two and the integrated scenario were
run explicitly with the actual outputs linked above.
