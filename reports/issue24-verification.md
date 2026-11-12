# Issue #24 Verification

## Automated builds and tests

Commands run on the final worktree unless noted otherwise:

- `swift test`: **314 tests executed, 2 opt-in scale tests skipped, 0 failures**.
- `xcodebuild -project RebornZune.xcodeproj -scheme RebornZune-macOS -destination 'platform=macOS' build`: **BUILD SUCCEEDED**.
- `xcodebuild -project RebornZune.xcodeproj -scheme RebornZune-iPadOS -destination 'generic/platform=iOS Simulator' build`: **BUILD SUCCEEDED**.
- `xcodebuild -project RebornZune.xcodeproj -scheme RebornZune-tvOS -destination 'generic/platform=tvOS Simulator' build`: **BUILD SUCCEEDED**.

## 50,000-Track release benchmark

Hardware: `arm64`. OS: `Version 27.0.1 (Build 26A434)`. This is not a macOS 14 host.

The normalized SQLite baseline was measured first and missed the required thresholds:

```text
SEARCH_BENCHMARK tracks=50000 hardware=arm64 os=Version 27.0.1 (Build 26A434)
SEARCH_BENCHMARK common_p95_ms=2517.660333 high_match_ms=1982.308291 full_library_ms=2562.238334
SEARCH_BENCHMARK playback_main_ms=10.142459 player_items=1 max_main_gap_ms=2613.604875
```

Following the spec's fallback order, the implementation evaluates a lazy actor-local in-memory index before considering FTS5. The final command was:

```sh
REBORN_ZUNE_RUN_SEARCH_BENCHMARK=1 swift test -c release --filter LibrarySearchScaleBenchmarkTests
```

Final output (one test passed in 23.391 seconds):

```text
SEARCH_BENCHMARK seeded=50000
SEARCH_BENCHMARK normalized=50000
SEARCH_BENCHMARK tracks=50000 hardware=arm64 os=Version 27.0.1 (Build 26A434)
SEARCH_BENCHMARK common_p95_ms=113.588959 high_match_ms=73.886625 full_library_ms=72.313417
SEARCH_BENCHMARK high_match_songs=37687 dto_conversion_ms=43.1215 unicode_ms=[61.973833, 112.944542]
SEARCH_BENCHMARK show_all_main_ms=0.021708 playback_main_ms=10.186625 player_items=1 max_main_gap_ms=1.253083
```

The unicode timings are for diacritic-insensitive `cafe` and CJK `東京` queries. The full-Library query returned all 50,000 Songs. Playback materialized only the current player item in this final-position case; the player window remains capped at three items.

## Native macOS verification

An isolated persistent store and a real source under `~/Music/issue24` were used. The source was granted through the application's actual Open Panel flow. It contained real MP3/M4A/FLAC/WAV/AIFF fixtures plus a ten-second WAV used to observe active playback.

Verified with accessibility interactions and keyboard events:

- Empty-query real genre tiles and exact copy.
- Grouped full counts, capped overview, and complete Show All order.
- Down selection, continuous cross-group navigation, selection highlighting, and Enter activation.
- Playback from the complete ranked snapshot with real current-track metadata in MiniPlayer.
- Show All/query/mode/scroll preservation across pivot navigation and Album detail Back.
- Exact No Results copy and Escape clearing query/mode/selection.

Screenshots were captured from the native window and personally inspected:

- `screenshots/issue24-empty.png`: five real genre tiles are readable on a fixed dark background; no fabricated genre appears.
- `screenshots/issue24-grouped.png`: Songs show full count, artwork/monograms, real metadata, duration, and hover Play/menu affordances without clipping.
- `screenshots/issue24-show-all.png`: all 16 matching Songs at capture time share the grouped order, with Back to Results visible.
- `screenshots/issue24-selection.png`: the first Song has a clear magenta title and selected-row background after Down.
- `screenshots/issue24-scroll.png`: repeated Down in Show All moves to the 12th Song and scrolls it into the visible center.
- `screenshots/issue24-playback.png`: Enter has started the selected real track; MiniPlayer shows its title/artist and Pause state.
