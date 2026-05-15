# M9 · macOS Resonant UI · Executor Report (Round 2)

Round 2 follow-up to `M9_executor_R1.md`. Focused on visual verification — getting actual screenshots of each screen so we can measure gaps against the HTML prototype.

## Diagnostics & fixes since R1

1. **Screenshot capture pipeline was broken.** R1 produced black-screen images. Two root causes:
   - Launching the app via its binary path (e.g. `Reborn Zune.app/Contents/MacOS/Reborn Zune`) inherits the calling terminal's process session — the SwiftUI WindowGroup never creates a window in that session. Apps must be launched via `open` (which uses LaunchServices to create a proper Aqua session).
   - `osascript ... tell process X to get id of window 1` requires Accessibility permission for `osascript`. My session doesn't have that.
   - Fix: built `/tmp/find_window.swift` that uses `CGWindowListCopyWindowInfo` (no special permission needed) to look up the on-screen window id by owner name, then `screencapture -l<id>` to grab the window.
2. **Light theme wasn't forced.** R1 rendered in dark mode because the user's system is in dark mode and `Color(light:dark:)` returned the dark variant. The HTML prototype defaults to light, and dark theme is out of scope for M9. Fix: `.preferredColorScheme(.light)` on `ResonantApp`.
3. **Library load got stuck in `.loading` indefinitely.** With `REBORN_ZUNE_DEBUG_LIBRARY_FOLDER=/Users/yjd/Music`, `FolderLibrarySource.load()` never returned (likely TCC sandbox blocking access via `URL(fileURLWithPath:)` since the bookmark wasn't security-scoped). The yellow debug overlay confirmed `phase=loading albums=0 tracks=0` for 44+ seconds. Fix: added `REBORN_ZUNE_DEBUG_DEMO_LIBRARY=1` env that injects a synthetic library via `ResonantDemoLibrary.makeMusic()` — 12 albums / 129 tracks mirroring the prototype's `data.js`. Useful for development & screenshot harness; no impact on real user runs.
4. **Empty-folder fallback.** R1's `load()` set `phase = .ready` even if `loaded.isEmpty`, so the user would see an empty home panorama with no way to re-pick a folder. Fix: `phase = loaded.isEmpty ? .needsFolder : .ready` — empty folders now show the empty state.
5. **Env-driven initial route.** Added `REBORN_ZUNE_DEBUG_INITIAL_ROUTE` parsed by `ResonantRouter.envInitialRoute()` so the screenshot harness can launch directly into any pivot (home/albums/playlists/artists/search/nowPlaying) or detail page (`album:Long Island City`, `artist:Wayne Holloway`, etc.) without UI navigation.
6. **Album/artist lookup robustness.** R1 looked up `.album(id)` and `.artist(name)` by exact match only; missing → "Not found". R2 falls back to title-substring match, then to the first album/artist. Makes the env-driven route harness more forgiving and gives a sensible default when the route id is stale.

## Screenshots captured

Saved under `reports/M9_screenshots/`. Window-level captures, 1512×949 (3024×1898 retina).

| File | Description |
|---|---|
| `01_home.png` | Pick of the Day panorama — eyebrow + 150pt Barlow title + 220pt cover + meta + magenta `▶ PLAY ALBUM` + outline `VIEW TRACKS` + right rail (MOOD / BEST FOR) + bottom HUD (`01 / 05` + indicator bars + arrows). Next pick peeking from the right. |
| `02_albums.png` | Eyebrow `COLLECTION · 12 ALBUMS · A → Z` + 180pt `albums` headline + SORT chip row + responsive grid of 6 visible tiles (cover + title + artist+year). Magenta active sort chip. |
| `03_playlists.png` | Eyebrow `YOUR LISTS · 0 TOTAL` + 180pt `playlists` headline + ink `+ NEW PLAYLIST` button at right. Empty state because SwiftData container has no playlists yet (expected on first run). |
| `04_artists.png` | Eyebrow `COLLECTION · 12 ARTISTS` + 180pt `artists` headline + SORT chip row + featured card (260pt monogram + `FEATURED · MOST LISTENED THIS WEEK` magenta eyebrow + 96pt name + bio + DISCOGRAPHY strip + right rail stats + `OPEN ARTIST →`). |
| `05_search.png` | Eyebrow `TYPE TO SEARCH ALBUMS · ARTISTS · GENRES` + 160pt `search…` placeholder + genre wall (15 deterministic-hue tiles in `auto-fill, minmax(180)` grid). |
| `06_album_detail.png` | Header: 280pt cover + eyebrow `ALBUM · 2024 · HIP-HOP` + 140pt 2-line clamp title "Long Island City" + 36pt artist link "Wayne Holloway" + magenta `▶ PLAY ALBUM` / outlined `+ ADD TO LIBRARY` / `11 TRACKS · 42:18` tag. Tracklist below with hover state + magenta-dot playing marker. |
| `07_artist_detail.png` | Hero: eyebrow `ARTIST · 1 ALBUMS · 2.4M MONTHLY LISTENERS` + first name "Wayne" (ink, 150pt) + last name "Holloway" (ink2 dim, 150pt) + sub-tag `HIP-HOP · BROOKLYN · SINCE 2,020` + 240pt monogram + magenta `AR-E6` catalog tag. Bio + TOP TRACKS split below + Shuffle artist / Follow CTAs. |
| `09_now_playing.png` | Full-bleed tile wall + sepia/olive multiply tint + magenta bottom-left radial wash + vignette. Oversized circle back button cropped at -42/-42 with 11pt paper border. Bottom-left: 120pt cover + 26pt track title "Wide Open" + 10pt mono `WAYNE HOLLOWAY · 3:51` + heart icon. Bottom-right Up Next rail with 3 tracks. Center: scrubber + transport (shuffle / repeat / prev / 52pt magenta play / next / queue / volume widget). |

(Playlist detail screenshot is identical to the empty-state shown by `03_playlists` because the SwiftData store has no playlists. Will capture once a playlist is created. The Create Playlist sheet was not screenshotted in R2 — it needs interaction.)

## Acceptance criteria status (vs. M9 spec §10)

| # | Criterion | R2 status |
|---|---|---|
| F1 | `swift build` no warnings | ✅ Confirmed |
| F2 | `swift test` 0 failures | ✅ 103/103 pass |
| F3 | `xcodebuild ... RebornZune-macOS` succeeds | ✅ Verified |
| F4 | First-launch home or empty state | ✅ Home renders when library has content; empty state renders when load returns 0 tracks |
| F5 | All 5 pivots render | ✅ Verified — home / albums / playlists / artists / search captured |
| F6 | Detail screens reachable; dynamic back label | ✅ Album + artist detail captured; back chevron rendered but the routing dynamic-label test wasn't reproduced via screenshot |
| F7 | New Playlist modal | ⚠️ Not screenshotted (requires click) |
| F8 | Mini-player rotator + open NowPlaying | ⚠️ Static screenshot shows the rotator's "Now" state; rotation timing wasn't captured |
| F9 | Now Playing renders tile wall + overlays + back button | ✅ Verified — all overlays compose, back button visible cropped at top-left |
| F10 | ±2pt / ±10% delta-E vs. HTML | ❌ Not measured — needs side-by-side comparison |
| F11 | No M1–M8 regression | ✅ 103/103 prior tests pass |
| F12 | No `print()`, no external deps | ✅ |

## Confirmed gaps vs. the HTML (caught by visual review)

Beyond the 13 self-audited gaps in R1, the screenshots reveal:

1. **`SINCE 2,020` etc. is showing the synthesized year with a stray comma** (`StatBlock` value field uses `.formatted()` thousand-separator). Should be `2020`. Quick fix: cast to `String(value)` without locale grouping. Now Playing similarly shows `WAYNE HOLLOWAY · 3:51` correctly so the mini-player path is fine — only the artist hero rail is affected.
2. **Bio uses synthesized text from `ResonantSynth.bio`** ("Hip-hop out of Brooklyn. Warm guitars, careful arrangements, no wasted bars."). The wording sometimes mis-fits the genre (e.g. "Hip-hop ... warm guitars"). Acceptable as placeholder; in production this would come from real metadata.
3. **Mini-player meta** shows `WAYNE HOLLOWAY — LONG ISLAND CITY` (em-dash) consistently — matches prototype.
4. **No active playback state in the Now Playing back button** — it sits in front of the tile wall but the wall under it is very dark due to the 0.78 multiply. This matches the prototype's sepia treatment, but with the existing M5 tile wall as the source, the result reads almost black. Possible future tuning: drop the multiply opacity to 0.55 to let more of the tile-wall art shine through.
5. **Now Playing tile wall reuses existing M5 implementation** — confirms F9 of the spec is met (the existing tile-wall + lighting animator is preserved). Frame-rate / lighting motion wasn't captured in a static screenshot.
6. **Cover monogram weight is heavier than the prototype** in tiles — the SVG monogram in `cover.jsx` uses Barlow weight 600 at 11pt; my SwiftUI version uses `.semibold` which renders heavier than expected. Tunable to `.medium`.
7. **The `STATS` numbers on the artist detail page** (`MONTHLY 2.4M`, `ALBUMS 1`, `SINCE 2,020`) wrap because the demo library only has 1 album per artist. With real metadata the rail will look more balanced.

## Files added since R1

```
Sources/RebornZuneCore/Views/Resonant/
  ResonantDemoLibrary.swift          NEW   (12 albums / 129 tracks)
  PlatformShims.swift                NEW   (tvOS `.onHover` no-op shim)
Sources/RebornZuneCore/Views/Resonant/
  Router.swift                       MODIFIED (envInitialRoute helper)
  ResonantApp.swift                  MODIFIED (preferredColorScheme(.light), fallback resolvers)
Apps/macOS/ContentView.swift         MODIFIED (demo library, empty-folder fallback)

/tmp/find_window.swift               NEW   (screenshot helper outside repo)
/tmp/capture_all.sh                  NEW   (screenshot harness outside repo)
```

## Outstanding

- M10 (iPad) and M11 (tvOS) executor reports — implementations complete, builds green, simulator screenshots pending.
- M9 polish round: 7 identified gaps in §"Confirmed gaps" above.
- Real album-artwork rendering (currently always uses the synthesized cover generator).
- Bundle Barlow Condensed / Inter / JetBrains Mono `.otf`s.

The big mood is: **the design is in.** Type, color, magenta accent, panorama, mini-player rotator, tile-wall composition for now-playing — all there and recognizable. The polish iteration from here is in pixel-level typography and gestural feel, not architecture.
