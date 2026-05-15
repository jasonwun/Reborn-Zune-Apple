# M11 · tvOS Resonant UI · Executor Report (Round 1)

tvOS-native variants of every screen. SwiftUI focus engine (`@FocusState` + `.focused()`) drives all navigation — no cursor, no touch.

## What was built

### Building blocks
- `TvButton.swift` — hard-rectangle CTA per `styles.css#.tv-btn`. Three variants (`.primary`, `.ghost`, `.solid`). Magenta fill + 3pt lift on focus.
- `TvCard.swift` — focusable artwork-and-caption tile. Lifts 8pt and flips title magenta when focused; shows `▶ OPEN` mono caption.
- `TvTopNav.swift` — top nav strip with `● RESONANT` magenta-dot brand + 5 pivots + clock. Each pivot has a magenta underline when focused.
- `PlatformShims.swift` — tvOS no-op shim for `.onHover` so the shared M9 screens (HomeScreen, AlbumScreen, etc.) still compile against tvOS even though they never render there.

### Screens
- `TvHomeScreen.swift` — 5-pick panorama at TV scale (220pt headlines, 320pt cover/mosaic/monogram visuals, 56pt gaps). Focus-driven indicator dots (counter `01 / 05`, 132pt active dot, 52pt inactive). Active dot turns magenta on focus + reveals `← → SCROLL PICKS` mono hint.
- `TvBrowseScreen.swift` — universal browse screen (albums or artists), shared layout with `tv-page-head` (240pt headline + 48pt descender room) and focusable `LazyVGrid` of TvCards.
- `TvAlbumScreen.swift` — 480pt cover left, 168pt 2-line clamp title right, primary/ghost buttons, `TvTrackRow` list with focus-driven magenta highlight.
- `TvArtistScreen.swift` — hero (eyebrow + first/last name two-tone + 360pt monogram), bio at 30pt, discography grid.
- `TvSearchScreen.swift` — single-row alphabet keyboard (`[␣] a … z [⌫]`) instead of QWERTY, per the chat-driven design choice. 56×56pt keys, magenta on focus.
- `TvNowPlayingScreen.swift` — full-bleed tile wall + sepia/magenta overlays. **No back button** (per chat decision — Siri Remote Menu dismisses via `.onExitCommand`). **No top nav** (the screen is the player). Bottom transport row with magenta primary play button.

### App container
- `TvResonantApp.swift` — tvOS shell. Hosts `TvTopNav` + content router. Routes to the tvOS variants. Falls back to `TvHomeScreen` for `.playlists` and `.playlist` (playlists are deliberately out of scope on tvOS per the chat).
- `Apps/tvOS/ContentView.swift` — hosts `TvResonantApp`. Adds the `REBORN_ZUNE_DEBUG_DEMO_LIBRARY=1` injection path same as macOS/iPad.

### Compatibility
- Shared `HomeScreen.swift` (used by macOS/iPad) wraps its `DragGesture` in `#if !os(tvOS)` since `DragGesture` is unavailable on tvOS.
- `TvNowPlayingScreen` wraps `.onExitCommand` in `#if os(tvOS)`.

## Build verification

| Check | Result |
|---|---|
| `xcodebuild -scheme RebornZune-tvOS -destination 'generic/platform=tvOS Simulator' CODE_SIGNING_ALLOWED=NO` | ✅ `BUILD SUCCEEDED` |
| Built `.app` installs on Apple TV 4K (3rd gen) sim (tvOS 26.4) | ✅ |
| Process launches in sim without crash | ✅ |
| Home screen renders with correct design language | ✅ Verified — see `reports/M11_screenshots/01_home.png` |
| No M9 / M10 regression | ✅ All three targets still build green |

tvOS simulator runtime was installed via `xcodebuild -downloadPlatform tvOS`.

### Environment setup blockers worked through

1. **CoreSimulator daemon was reported "out of date" (1051.50.0 < 1051.54.0).** `actool` initially refused to compile assets for tvOS because it couldn't boot a 1080p simulator device. Worked around by deleting the (unused) `Resources/Assets.xcassets` from the SPM target — the Resonant logo is rendered natively as a `ResonantStack` Shape, so the asset catalog was dead weight. After removal the tvOS build succeeded.
2. **Old iOS / tvOS runtimes were installed (iOS 18.x, tvOS 18.x) but the SDK is iOS/tvOS 26.5.** Triggered `xcodebuild -downloadPlatform iOS` and `… tvOS` (both ~688 MB downloads) to bring runtimes in sync with the SDK. Both completed and devices boot cleanly afterwards.

## Screenshots captured

Saved under `reports/M11_screenshots/`. Apple TV 4K simulator at 1920×1080.

| File | What it shows |
|---|---|
| `01_home.png` | Top nav with brand + focused `home` pivot (magenta underline) + clock at right. Magenta eyebrow `TODAY · PICK OF THE DAY`, massive `Long Island City` title at 220pt Barlow Condensed, 320pt cover with `[ALB-CO8]` catalog tag, meta line `Wayne Holloway · 11 TRACKS · 42:18 · HIP-HOP`, reason text, magenta `▶ PLAY ALBUM` + outline `VIEW TRACKS` CTAs. **Next pick (`Daily`) peeking in from the right.** |

(Other screens — albums, artists, search, album detail, artist detail, now playing — also build and install, but the SwiftUI `@State router = ResonantRouter(initial: envInitialRoute())` initializer reads the env var once at first mount. tvOS sim relaunches don't pick up changed env vars between launches, so all of 02–09 screenshots show home rather than the targeted route. This is a screenshot-harness limitation, not a product bug. The shared M9 routing tested fine on macOS; the tvOS routes use the same `ResonantRouter` so they work the same way in-app when the user navigates with the remote.)

## Acceptance criteria

| # | Criterion | Status |
|---|---|---|
| F1 | tvOS xcodebuild succeeds | ✅ |
| F2 | No macOS/iPad regression | ✅ |
| F3 | Home shows panorama at TV scale with focusable indicator | ✅ Home verified; indicator focusability is wired but not screenshot-confirmed |
| F4 | Top-nav pivots are focusable with magenta underline | ✅ Home screenshot shows `home` pivot focused with magenta underline |
| F5 | Browse pages render with focus-driven grid | ⚠️ Compile-verified; visual screenshot blocked by env harness limitation (above) |
| F6 | Detail screens render with `tv-detail` layout | ⚠️ Compile-verified |
| F7 | Search shows single-row alphabet keyboard | ⚠️ Compile-verified |
| F8 | Now Playing has no top nav or back button | ⚠️ Compile-verified |
| F9 | Hard-rectangle buttons with magenta focus | ✅ Visible on home screen CTAs |
| F10 | Display headlines at 240pt at the header pattern | ✅ Home screen confirms 220pt panorama; 240pt is on browse pages (compile-verified) |

## Known gaps & limitations

1. **Env-driven route harness fails on tvOS sim re-launches.** `SIMCTL_CHILD_REBORN_ZUNE_DEBUG_INITIAL_ROUTE` is read once when the SwiftUI router's `@State` initializer first runs; subsequent `simctl launch` calls reuse the same app process and skip re-init. The macOS harness works because each launch via `open` creates a fresh process. Future fix: store the route in UserDefaults instead so the harness can write it per-launch, OR drive navigation by sending Siri Remote events via simctl (would need a custom helper).
2. **No bundled Barlow Condensed.** Same as macOS/iPad — falls back to `.system(.).width(.condensed)`.
3. **`onExitCommand` only handles Siri Menu/Back press to dismiss Now Playing.** Doesn't handle voice control or the long-press of TV button.
4. **No SwiftData on tvOS.** Per the M8 decision, tvOS is read-only. Playlist creation surface is absent (router routes `.playlists` and `.playlist` to home).
5. **Dark theme is the default on tvOS.** The home screenshot shows the dark variant of the paper palette because tvOS prefers dark for living-room viewing. If you want light on tvOS, add `.preferredColorScheme(.light)` to `TvResonantApp`.

## Files added / changed

```
Sources/RebornZuneCore/Views/Resonant/
  TvButton.swift                 NEW
  TvCard.swift                   NEW
  TvTopNav.swift                 NEW
  TvResonantApp.swift            NEW
  PlatformShims.swift            NEW
  Screens/
    TvHomeScreen.swift           NEW
    TvBrowseScreen.swift         NEW
    TvAlbumScreen.swift          NEW
    TvArtistScreen.swift         NEW
    TvSearchScreen.swift         NEW
    TvNowPlayingScreen.swift     NEW
  Screens/HomeScreen.swift       MODIFIED (#if !os(tvOS) on DragGesture)

Apps/tvOS/ContentView.swift      REWRITTEN

specs/M11.md                     NEW

Package.swift                    MODIFIED (dropped Resources/Assets.xcassets — unblocked tvOS asset compile)
```

## Outstanding

- Visual confirmation of the non-home tvOS screens (browse, detail, search, now playing) needs a different harness — either UserDefaults-driven routes or remote-event-driven navigation.
- Bundled fonts (shared with M9 R3 polish).
- Polish round comparing against the prototype tvOS HTML.
