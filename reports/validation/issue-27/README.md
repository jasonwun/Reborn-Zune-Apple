# Issue #27 integrated validation evidence

## Result

**Pass — the integrated macOS player meets the issue #27 acceptance criteria.**
The 50,000-track release scenario, Search correctness regression, every build
command of record, and the complete native macOS journey pass, including Control
Center transport/seek and all three Repeat menu states.

The host was unlocked and required foreground interaction was explicitly
authorized. The product, ADR-0001, ADR-0005, `Package.swift`, `project.yml`, and
parent specification #17 now target **macOS 27+**; the former macOS 14 runtime
blocker is removed by that explicit product decision.

Validation date: 2026-11-19. Environment details: `environment.txt`.

## Search defect fixed with red → green public-seam tests

The integrated scenario exposed a two-source, multi-batch Search defect: a full
Library query returned only 7,000 of 50,000 Songs. A minimized 3,000-track public
`LibrarySearchStore.search` regression reproduced 2,000 Songs, 400 of 600
Artists, and 1,000 of 3,000 Albums.

- RED: `search-batches-red.log` and `release-scale-red.log`
- GREEN: `search-batches-green.log` and `release-scale-final.log`

The keyset-paginated fetches could return limited batches in context-registration
order rather than the requested path order. `LibrarySearchStore` now uses fresh
`ModelContext` instances with SQLite offset/limit batches, preserving bounded
reads, cancellation checks, matching, ranking, DTO conversion, and the existing
lazy-memory-index fallback. No FTS engine or new numeric target was introduced.

## Reproducible integrated 50,000-track release scenario

Run from the repository root:

```sh
REBORN_ZUNE_RELEASE_SCALE=1 \
REBORN_ZUNE_RELEASE_REPORT="$PWD/reports/validation/issue-27/release-scale.json" \
swift test -c release \
  --filter ReleaseScaleValidationTests.testIntegratedLibraryAt50000Tracks
```

Final result on the macOS 27 deliverable: one test passed in 81.736 seconds.
Complete output: `release-scale-final.log`; machine-readable output:
`release-scale.json`.

The deterministic dataset contains 50,000 persisted Tracks, 2,500 Albums, 500
Artists, eight genre strings, disc/track numbers, durations, and separate
256×256 decodable PNG artwork. Two non-overlapping fake file sources own 45,000
and 5,000 rows. Unchanged incremental scans perform zero metadata extractions.
These are test records, not Demo Library content or 50,000 real audio decodes.

The scenario covers paged launch, incremental and manual scans, a second browse
page, actual ImageIO artwork decoding, common/zero-result/diacritic/CJK/high-
match/full-Library Search, Show All, a 50,000-track logical Queue, and removal
of the 5,000-track source followed by Search rebuilding.

| Measurement | Actual result | Required threshold |
| --- | ---: | ---: |
| Launch call including incremental scan | 8,289.048 ms | Record only |
| Manual incremental scan | 8,289.528 ms | Record only |
| Tracks published at launch | 100 of 50,000 | Paged, not full Library |
| Tracks after one additional page | 200 | 200 expected |
| Decoded artwork dimensions | 256×256 | Must decode |
| Common Search p95 | 238.581 ms | ≤300 ms |
| `cafe` / `東京` Search | 100.656 / 177.994 ms | ≤300 ms |
| High-match Search | 114.590 ms | ≤750 ms |
| Full-Library Search | 40.932 ms | ≤750 ms |
| Full-Library results | 50,000 Songs / 500 Artists / 2,500 Albums | Complete |
| Search DTO conversion | 54.899 ms | Record only; off main actor |
| Show All main-thread apply | 0.043 ms | ≤50 ms |
| Large-Queue playback start | 10.047 ms | ≤50 ms |
| Logical / materialized player items | 50,000 / 3 | Current + two |
| Search/Show All/playback maximum main-thread gap | 22.600 ms | ≤50 ms |
| Source cleanup | 843.006 ms | Record only |
| Results after removing 5,000-track source | 45,000 Songs / 450 Artists / 2,250 Albums | Complete |
| Lifetime physical footprint before / after | 45,187,960 / 255,198,312 bytes | Record only |

The separate launch/browse probe (`library-scale.log`) passed with 100 published
Tracks, an 18.564 ms launch scheduling gap, and a 0.112 ms maximum synchronous
browse apply. The established Search benchmark (`search-scale-final.log`) also
passed: common p95 112.349 ms, high-match 71.988 ms, full-Library 72.509 ms,
Show All 0.011 ms, playback start 9.376 ms, and maximum gap 1.509 ms.

## Native macOS journey

Isolated apps used container-local Stores and test-only real MP3/ID3,
M4A/iTunes ALAC, FLAC/Vorbis, WAV, AIFF, and AAC fixtures. No Demo Library
records were injected. `native-output.txt` records read-back output, including
menu contents, Dock recents, Queue order, and shortcut state.

Verified with native interactions and read-back:

- Fresh-profile access failure and Grant Access flow; persisted authorization.
- Two non-overlapping sources, recursive import, full paths, availability and
  committed counts; a manual scan changed Additional from 3 to 4 Tracks.
- Real Home/Album/Artist metadata, multi-disc headings, genres and artwork;
  no fabricated biographies, listener counts, or Demo artists.
- Playlist creation with `Issue 27 Listening` preserving both spaces, searchable
  multi-select picker, added confirmation, populated Playlist and real playback.
- Global Search empty genres, grouped Song results, Show All, Down selection and
  Return playback through the complete snapshot.
- Play Later, two-row Up Next, drag reorder, hover removal and Clear. Actual
  playback followed the displayed reordered Queue.
- Queue restoration after relaunch: `Next Listening` at exactly 0:16 paused,
  with `Fixture Title` still upcoming.
- Wide rail and narrow overlay, Escape close, and open-state preservation across
  both width-threshold crossings. Opening/settled captures differ visibly.
- Dock transport and Recently Played (`Next Listening`, `Fixture Title`), plus
  click-to-play from the Dock recent submenu.
- Space, next/previous, ±15 seconds, volume ±5%, all five pivot shortcuts,
  Cmd-F, Cmd-L and Cmd-[. Controls/View menu contents and Controls transport,
  skip, volume and Shuffle check state.
- Source-removal confirmation, linked Library cleanup with audio files retained,
  scanning spinner with `Discovered 5,003 tracks` and Cancel, no-source and empty
  Home states.

A final macOS 27 deployment-target build independently repeated authorization,
Global Search and real `Next Listening` playback/Now Playing. The other native
captures are from the identical product code before the deployment-target-only
follow-up.

### Final system-control verification and repair

Control Center published the real Track and drove remote Pause, Resume, Next,
Previous and a 25%-slider seek to exactly 0:30 while paused. Repeated paused
reads showed no drift. Remote Shuffle/Repeat remain enabled through
MPRemoteCommandCenter and are covered by command-registration/engine tests; the
Control Center UI exposes no separate Shuffle/Repeat buttons.

The original Repeat Picker did not reliably accept every native selection. It is
replaced by one Repeat Menu with independent Off/All/One Toggles. Native
read-back confirmed each checkmark: All, then One, then Off.

Per the user's scope clarification, this is a macOS-only acceptance effort.
Native iPadOS/tvOS sweeps are not blockers; shared tests and both simulator
builds pass.

## Acceptance criteria status

| Criterion | Status | Evidence / reason |
| --- | --- | --- |
| Fresh-profile, multi-source, metadata, Playlist, Queue, Search, history and system-control journey | **Pass** | Native read-back includes Dock and Control Center transport/seek. |
| Realistic 50,000-track launch, scans, browse, Search, Show All, large Queue, artwork and cleanup | **Pass (automated release seam)** | `release-scale-final.log` and `release-scale.json`. |
| Search thresholds and no full-Library/full-Queue materialization | **Pass (automated release seam)** | All numeric assertions passed; launch publishes 100 rows and playback materializes three items. |
| Fallback order and unchanged semantics | **Pass** | Existing lazy-memory-index fallback retained; no FTS or new target added. |
| Native visual verification on every affected surface | **Pass** | 39 native captures individually inspected below, including Control Center and Repeat. |
| Demo-only fabrication and iPadOS/tvOS non-regression | **Pass** | Real macOS data, shared tests and simulator builds pass; no native sweep is required by the clarified scope. |
| All build commands of record | **Pass** | Final macOS 27 logs below; all commands exited zero. |
| Defects fixed or explicitly blocking completion | **Pass** | Search result loss and Repeat menu selection were fixed and revalidated. |

## Final command output

All commands ran sequentially on the final macOS 27 code and exited zero.

| Command | Actual output / log |
| --- | --- |
| `xcodegen generate` | `xcodegen.log`: project created |
| `swift build` | `swift-build.log`: `Build complete! (0.20 sec)` |
| `swift test` | `swift-test.log`: 320 tests, 3 skipped, 0 failures in 22.623 s |
| macOS app build | `macos-build.log`: `** BUILD SUCCEEDED **` |
| iPadOS simulator build | `ipados-build.log`: `** BUILD SUCCEEDED **` |
| tvOS simulator build | `tvos-build.log`: `** BUILD SUCCEEDED **` |

The three ordinary-suite skips are the opt-in scale tests. They were run
explicitly with the actual outputs linked above.

## Native captures and inspection

All images are native ScreenCaptureKit/`screencapture` output under
`reports/screenshots/issue-27/`, not `ImageRenderer`. Every image was opened and
inspected. Two transition-only invalid captures were discarded or recaptured;
the list below describes the retained files.

1. `01-fresh-profile-access.png` — honest access failure with full isolated path,
   Retry and Grant Access; no fabricated Library content.
2. `02-home-real-metadata.png` — real Fixture album/artist, track count, year,
   genre and working playback/source chrome.
3. `03-settings-first-source.png` — authorized Default source with full path and
   `Available · 3 tracks`.
4. `04-settings-two-sources.png` — non-overlapping Additional/Default sources,
   each available with three committed Tracks.
5. `05-albums-multi-source.png` — five real album cards from both sources with
   real artist/year metadata and no Demo artist names.
6. `06-album-real-metadata.png` — Fixture Album detail with Disc 1/Disc 2,
   real track numbers, genre and embedded artwork.
7. `07-artists-real-library.png` — real Artists with genre/album counts and no
   fabricated monthly listeners or locations.
8. `08-artist-real-metadata.png` — Artist detail with real genre, Top Tracks,
   discography and Shuffle Artist; no biography/follow module.
9. `09-search-empty-real-genres.png` — exact empty-query copy and three real
   genre tiles with correct counts.
10. `10-search-grouped-song.png` — `Title` returns `SONGS · 1`, real metadata,
    duration, artwork and Show All.
11. `11-search-show-all.png` — complete Song Show All with Back to Results and
    the same ordered result.
12. `12-search-keyboard-selection.png` — selected Song has a magenta title and
    visible selected-row background after Down.
13. `13-search-playback-miniplayer.png` — Enter started the selected real Track;
    MiniPlayer shows real metadata, progress and Pause.
14. `14-playlist-empty-spaces.png` — empty Playlist named `Issue 27 Listening`
    with spaces intact, disabled playback and working Add Tracks.
15. `15-playlist-track-picker.png` — searchable multi-select picker showing all
    seven real Tracks with title/artist/album fields.
16. `16-playlist-populated.png` — two Tracks in picker order and transient
    `Added to Issue 27 Listening` confirmation.
17. `17-playlist-playing.png` — populated Playlist playing `Next Listening`
    with Pause and real duration.
18. `18-now-playing-wide-closed.png` — final macOS 27 Now Playing with real
    `Next Listening`, 0:13 elapsed, Pause and Up Next closed.
19. `19-up-next-opening.png` — opening rail is visibly translucent at the right
    during the fade/slide transition.
20. `20-up-next-wide-open.png` — settled wide rail is darker and more opaque,
    showing the empty-Up Next state; it differs from the opening frame.
21. `21-up-next-wide-with-track.png` — wide editable rail with `Next Listening`,
    duration and Clear.
22. `22-before-relaunch-queue.png` — pre-relaunch `Next Listening` at 0:16
    paused with `Fixture Title` in the transitioning rail.
23. `23-narrow-up-next-overlay.png` — 900-point narrow right-side overlay with
    backdrop, `Fixture Title` and Clear; no read-only summary.
24. `24-narrow-overlay-escape-closed.png` — Escape removed the narrow overlay;
    player chrome and current Track remain unchanged.
25. `25-wide-open-preserved-from-narrow.png` — wide rail is open again after
    direct narrow-to-wide crossing with `Fixture Title` intact.
26. `26-after-relaunch-queue.png` — restored `Next Listening` at 0:16 paused,
    with `Fixture Title` in Up Next.
27. `27-dock-recently-played.png` — real Dock menu and Recently Played submenu
    with `Next Listening` above `Fixture Title`, both enabled.
28. `28-controls-menu.png` — Controls menu with transport, ±15-second skip,
    volume, Shuffle, Repeat and Now Playing shortcuts.
29. `29-view-menu.png` — View menu with five pivots, Focus Search, Back and
    standard window items.
30. `30-remove-source-confirmation.png` — confirmation explicitly says linked
    app data is removed but audio files on disk are not deleted.
31. `31-source-cleanup-complete.png` — only Default remains with three Tracks;
    the four Additional audio files remained on disk.
32. `32-scanning-discovered-tracks.png` — scanning spinner, `Discovered 5,003
    tracks`, disabled actions and Cancel.
33. `33-no-library-sources.png` — honest no-source state and promise not to
    recreate a removed source automatically.
34. `34-empty-library-home.png` — empty Home with `Pick a folder` and Choose
    Folder, not fabricated demo content.
35. `35-control-center-playing.png` — system Control Center shows the real
    `Next Listening` / Queue Artist with Pause and working transport.
37. `37-control-center-seek-paused.png` — expanded system media surface shows
    the remote seek result at exactly 00:30 with Play while paused.
38. `38-controls-repeat-one.png` — original Repeat submenu after selecting One;
    this is the before-menu-repair capture.
39. `39-repeat-toggles-verified.png` — final Repeat Menu shows Off checked after
    native Off→All→One→Off read-back, with real player state behind it.
40. `40-control-center-paused-final.png` — final system Now Playing surface at
    00:00 with Play, Previous and Next; repeated reads showed no paused drift.
