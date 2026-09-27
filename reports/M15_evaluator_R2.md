# M15 Evaluator R2 — macOS Responsive Layout: APPROVED

Date: 2026-09-27 · Evaluator: Kimi (orchestrator) · Executor: subagent (R1+R2)

## Verdict

**M15 approved.** All 7 acceptance criteria from `specs/M15.md` pass on the
restored toolchain, including live-window behavioral checks that were
impossible in R1/R2 (broken Xcode license / missing Metal toolchain).

## Build & test evidence (canonical commands, all exit 0)

| Command | Result |
| --- | --- |
| `swift build` | OK (Metal Toolchain component downloaded first — Xcode 27 on-demand component) |
| `swift test` | **113 tests, 0 failures** (incl. 10 new `ResonantLayoutTests`) |
| `xcodegen generate` | OK (needs `USER` env set; also requires the gitignored empty dir `Apps/tvOS/Resources/UserMusic` to exist) |
| `xcodebuild -scheme RebornZune-macOS build` | OK |
| `xcodebuild -scheme RebornZune-iPadOS -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build` | OK |
| `xcodebuild -scheme RebornZune-tvOS -destination 'generic/platform=tvOS Simulator' CODE_SIGNING_ALLOWED=NO build` | OK |

## Live-window acceptance (real app, real NSWindow)

Drove the actual app (`Reborn Zune.app`, Debug) via
`REBORN_ZUNE_DEBUG_WINDOW_SIZE` and measured the window **in-process through
AppKit** (ground truth):

| Check | Result |
| --- | --- |
| First launch, no saved frame | `window.frame = 1440×900` exactly (`.defaultSize`) ✓ |
| Floor probe: force 800×500 | clamps to content minimum — frame `900×632` (content 900×600 + 32pt chrome) ✓ |
| Force 1100×700 | exact 1100×700 ✓ |
| Quit at 1100×700, relaunch without env | restores 1100×700 — user's saved frame wins over the default ✓ |

### Measurement-evidence deviation (important for future screenshot sweeps)

`CGWindowListCopyWindowInfo` (external probe) reports all window sizes ×0.9
on this host (1440→1296, 1100→990, 900→810), while AppKit in-process reports
exact values. The external probe's coordinate space does not match AppKit's
on this machine/session; **AppKit is authoritative** (it drives
`GeometryReader` → `ResonantLayout.mac(windowSize:)`). Early in this
acceptance round the ×0.9 artifact was misread as a sizing bug; it is not one.
Screen Recording / Accessibility permissions are not granted to the CLI, so
live-window pixel captures were not possible — layout visuals below come from
the R2 NSWindow-hosted renders, which remain valid (no `Sources/` change
since they were rendered).

## Defect found & fixed during this acceptance round

**First launch opened at the 900×600 floor instead of the spec's 1440×900
default.** Root cause: R1/R2 set `idealWidth/idealHeight` on the content
frame, which `WindowGroup` initial sizing ignores — the window falls back to
the content minimum. Fixed in `Apps/macOS/RebornZuneMacApp.swift` with
`.defaultSize(width:height:)` (verified exact 1440×900 in-process). The DEBUG
env hook was moved into `ContentView.swift` (`WindowSizeAccessor` +
`setContentSize`) so the sweep works even over a restored frame; production
returns nil and never touches the user's window.

## R1 visual defects — all verified fixed (R2 renders)

1. Home @900×600: cover no longer cuts the "Long Island City" title line ✓
2. Home meta line wraps to two lines instead of truncating to "H…" ✓
3. Artist @900×600: content no longer sliced by MiniPlayer at rest ✓
4. NowPlaying @900×600: back-button ring fully on-canvas ✓

1440×900 renders are pixel-identical to R1 (verified in R2 report §diffs).

## Spec notes

- `specs/M15.md` lists an "ArtistsScreen adaptive grid" change; no such grid
  exists (executor flagged this in R1). Harmless spec drift — fix the spec
  text next time it is touched.
- `textScale` curve `clamp(0.5 + 0.5·w/1440, 0.85, 1.1)` was executor-chosen
  per spec latitude and is now locked by tests.

## Residual risks

- Live-drag continuity (60fps re-layout) is code-path-verified
  (`GeometryReader` → environment) but not pixel-verified per-frame; the
  resize sweep covered 5 sizes × 5+ screens instead.
- iPad/tvOS: bit-identical bucket table + simulator builds green; no sim
  runtime re-run this round (simulators were reinstalled with Xcode 27).
