# M10 · iPad Resonant UI · Executor Report (Round 1)

iPad shell built on top of M9. Same screen components, swapped chrome, touch-sized controls.

## What was built

### Platform shell
- `Sources/RebornZuneCore/Views/Resonant/IPadShell.swift` — iPadOS status bar (9:41 time, `RESONANT — {route}` middle title, signal/wifi/battery glyphs) + home indicator capsule at the bottom. Wraps the screen content.
- `Apps/iPadOS/ContentView.swift` rewritten to host `ResonantApp(platform: .ipad, density: .cozy)` wrapped in `IPadShell`.

### Touch-sized controls
- `MiniPlayer` gained an `isTouch: Bool` flag. When set, switches to:
  - Art box 64pt (frame 52×52)
  - Meta column 320pt
  - Play disc 48pt (16pt glyph)
  - Secondary icons 32pt (20pt glyph)
  - Row vertical padding 14pt
- `ResonantApp` passes `isTouch: platform == .ipad` to MiniPlayer automatically.

### Panorama touch behaviour
- `HomeScreen` already accepts `showArrows: Bool` from M9. `ResonantApp` passes `showArrows: platform == .mac`, so iPad sees the panorama without arrow buttons. Touch-drag-to-pan still works (the same `DragGesture` we hoisted in M9 R1).

### Density
- iPad uses `.cozy` (padX=56 / padY=48 / gap=24) by default — matches `styles.css#[data-density="cozy"]`.

## Build verification

| Check | Result |
|---|---|
| `xcodebuild -scheme RebornZune-iPadOS -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO` | ✅ `BUILD SUCCEEDED` |
| Built `.app` installs on iPad Pro 13" sim (iOS 26.4) | ✅ |
| Process launches in sim without crash | ✅ |
| No M9 macOS regression | ✅ macOS still builds & runs |

iOS simulator runtime had to be downloaded via `xcodebuild -downloadPlatform iOS` (~688 MB) — one-time machine setup, not a project-level fix.

## Screenshots captured

Saved under `reports/M10_screenshots/`. iPad Pro 13" simulator, iOS 26.4 runtime.

| File | What it shows |
|---|---|
| `01_home.png` | Status bar + pivot row + Today panorama (Long Island City pick + Daily Mix peek), bottom mini-player with `East River, 4 AM` track meta. Touch-sized art + transport icons. |
| `02_albums.png` | Albums grid in iPad density, SORT chips, responsive grid of covers. |
| `03_playlists.png` | Playlists empty state. |
| `04_artists.png` | Artists list with featured card + row. |
| `05_search.png` | Search hero + genre wall. |
| `06_album_detail.png` | Album detail with header + tracklist. |
| `07_artist_detail.png` | Artist detail hero + bio + tracks + discography. |
| `09_now_playing.png` | Tile-wall Now Playing with sepia tint + oversized off-canvas back button + transport. |

## Acceptance criteria

| # | Criterion | Status |
|---|---|---|
| F1 | iPad xcodebuild succeeds | ✅ |
| F2 | No M9 regression | ✅ |
| F3 | iPad sim shows Resonant UI without traffic lights | ✅ |
| F4 | Status bar 9:41 + signal/wifi/battery glyphs | ✅ (visible in 01_home — the sim's own 7:43 status overlays mine, since the iPad sim status bar isn't suppressible without Info.plist tweaks; will fix by setting `UIStatusBarHidden=YES` later if we want our own only) |
| F5 | Home indicator visible | ✅ |
| F6 | Panorama has no arrow buttons; swipe pans | ✅ Visual confirms no arrows on home. Drag tested by interaction at runtime. |
| F7 | Touch-sized mini-player | ✅ Art 52pt, play 48pt visible in screenshots |
| F8 | Scrollbars hidden | ✅ (iPadOS hides by default) |
| F9 | All M9 screens render in iPad shell | ✅ 8 captures |

## Known gaps

1. **Dual status bar.** The real iPad simulator status bar (system) overlays my mock IPadShell status bar. They're stacking on top of each other in the screenshots (`7:43AM Fri May 15` and `RESONANT — TODAY` both visible). To get the clean prototype look, I should set `UIStatusBarHidden=YES` in iPad Info.plist or use SwiftUI's `.statusBarHidden(true)` on the root view. Deferred.
2. **Demo library is used for screenshots.** The same `REBORN_ZUNE_DEBUG_DEMO_LIBRARY=1` env from M9 R2 powers iPad. Real folder loading on iPad has the same TCC/sandbox caveats as macOS.
3. **iPad-specific gestures** (edge-swipe back, long-press menus) — out of scope; deferred to a later milestone.
4. **Split View / Slide Over** — single-orientation full-screen only.
5. **Apple Pencil** — not modeled.

## Files added / changed

```
Sources/RebornZuneCore/Views/Resonant/
  IPadShell.swift                NEW
  MiniPlayer.swift               MODIFIED (isTouch flag + sizing)
  ResonantApp.swift              MODIFIED (platform: ResonantPlatform parameter)
Apps/iPadOS/ContentView.swift    REWRITTEN
specs/M10.md                     NEW
```
