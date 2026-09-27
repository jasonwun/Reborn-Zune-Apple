# M15 Evaluator R1 — REJECTED

Evaluator inspected the executor's R1 diff (12 files, +185/−71), the new
`ResonantLayoutTests.swift` (10 tests), and the 25-image resize sweep in
`reports/M15_screenshots/` at first hand.

## Verified good

- `ResonantLayout` refactor is clean: scales are now stored values, the
  bucketed init keeps the M13 table bit-identical (test pinned), and
  `mac(windowSize:)` matches the locked spec formula
  (`clamp(w/1440, 0.75, 1.15)`; anchor 1.0 @ 1440; clamps exact at
  1080/1656). The `windowScale` token is a tidy way to keep iPad
  visuals untouched by construction.
- macOS injection (`Apps/macOS/ContentView.swift` GeometryReader +
  `.mac(windowSize:)`) and window floor/default
  (`windowResizability(.contentMinSize)` + 900×600 / 1440×900) are
  correctly implemented at the code level.
- Dead `canvasWidth` removed; zero remaining references.
- Sweep evidence at 1100 / 1440 / 1512 / 1920: Home, Albums, Artist,
  Album all lay out cleanly; type scales monotonically. Albums at
  900×600 is fine (4-col grid, no overflow).

## Failures (acceptance #4 — "no overlap, no mid-glyph clipping")

1. **Home @ 900×600 — title/cover collision.** The panorama bottom
   strip is absolutely anchored (`geo.height − 80 − coverSize`), and at
   the window floor the scaled title block (eyebrow + two ~97pt lines)
   extends below the strip's top edge: the cover image cuts through
   the "City" sub-line mid-glyph. See `mac_home_900x600.png`.
2. **Home @ 900×600 — meta truncation.** The meta line ellipsizes to
   "…· 42:18 · H…" — genre unreadable. Spec allowed `lineLimit(1)`
   truncation on *rail* lines, not the primary meta.
3. **Artist @ 900×600 — bottom content clipped mid-glyph** at the
   MiniPlayer boundary (visible cut text line bottom-left and a
   partially-shown "TOP TRACKS"-area label bottom-right). Either the
   scroll content lacks bottom padding equal to the MiniPlayer height,
   or a fixed frame extends past the viewport.
4. **Now Playing @ 900×600 — back-button ring clipped** by the
   window's top-left corner (circle visibly cut at both edges). Padding
   scaled below the control's radius.

## Blocked (not the executor's fault, but acceptance #1 unmet)

Canonical build commands cannot run on this host: the App Store
reinstalled Xcode 27.0 on 2026-09-26 and the license was never
accepted (`swift build` → metal plugin fails; `xcodebuild` → exit 69).
Evaluator independently confirmed with
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`
→ "You have not agreed to the Xcode license agreements."
Resolution requires the owner: `sudo xcodebuild -license accept`,
`sudo xcodebuild -runFirstLaunch`, and the Metal toolchain component.
The executor's substitute evidence (swiftc typecheck ×3 SDKs,
hand-linked XCTest runner 10/10) is accepted as interim only.

## Direction for R2

- Fix the Home panel vertical budget at the floor: the title block and
  bottom strip must be layout-aware of each other (e.g. strip flows
  below the title with a minimum gap, or the sub-line/anchor constants
  collapse gracefully under scale), not two absolutely-anchored blocks
  that collide.
- Give the meta line room at the floor (allow two lines or widen the
  column before truncating).
- Audit every screen at 900×600 for edge-clipped chrome (Now Playing
  back button) and MiniPlayer-boundary clipping (Artist).
- Re-render the sweep at 900×600 (and re-check 1100×700) after fixes.
- Re-run the canonical builds once the owner clears the Xcode license;
  paste exit codes into `M15_executor_R2.md`.
