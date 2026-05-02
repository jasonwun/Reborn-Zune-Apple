# Milestones

Each milestone has its own spec file (`specs/M{N}.md`) with deliverables and
acceptance criteria. Each runs through the executor → evaluator loop until
approved before the next one starts.

| # | Title | Outcome |
| --- | --- | --- |
| M1 | Project scaffolding | `swift build` + `xcodebuild` for all 3 app targets succeeds. Each app shows "Reborn Zune – {platform}". |
| M2 | Library sources | `LibrarySource` protocol; Spotlight impl (macOS/iPad) + Bundle impl (tvOS); domain types `Music`/`Album`/`Artist`; thumbnail cache. Unit tests pass. |
| M3 | VariableSpanLayout + TileView | SwiftUI `Layout` placing 1×1, 3×3, 4×4 tiles in a wrap grid with no overlaps. Layout snapshot tests. |
| M4 | Metal lighting shader | `.layerEffect` shader with 2 animated point lights + ambient, parameter-driven from SwiftUI. Visual parity check vs the UWP reference screenshots. |
| M5 | Tile flip + staggered entry | Per-tile periodic flip every 5s; staggered fade-in waves on first load. Animation behavior matches reference. |
| M6 | Audio + Now Playing | `PlaybackEngine` (AVQueuePlayer) with shuffle, queue management. `MPNowPlayingInfoCenter` populated; remote commands wired. |
| M7 | App shells | macOS/iPad β shells with folder picker + Now Playing strip; tvOS α shell directly on the tile wall. All three apps actually play music. |
| M8 | Persistence | SwiftData models for playlists/settings on macOS/iPad. Playlists survive relaunches. |

## Stop conditions per milestone

A milestone is **approved** by the evaluator only when:

1. All build commands in `PROJECT_SPEC.md` exit 0 (where applicable for the milestone).
2. All acceptance criteria in `M{N}.md` are individually verified.
3. No regressions in earlier milestones' acceptance criteria.
4. The executor's report describes what was actually built (not what was intended).

A milestone is **rejected** if any acceptance criterion is unmet, builds fail, tests fail,
or the executor's report contains unverified claims.
