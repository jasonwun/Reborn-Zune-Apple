# M5 — Evaluator R1

## Summary

Independently re-ran every build/test command and re-captured all three
screenshots from a clean DerivedData/sim-launch sequence. Every spec deliverable
§1–§7 is present with the documented public API, the warm-delay fix correctly
applies the 600 ms `startDelay` to BOTH lights (verified by both code reading
and tests), all three platform builds succeed, the swift test suite runs 68
tests with 0 failures, and the live iPadOS + tvOS sim screenshots show the
tile wall WITH the lighting wash visible (multi-color tinting drifting across
the wall). Multiple tiles caught mid-flip in both sim screenshots confirms
the periodic flip animation runs in the live app. macOS `ImageRenderer`
snapshot output shows the tile wall correctly but without the lighting wash —
this is the documented `ImageRenderer` `.colorEffect` limitation, called out
in the spec as acceptable.

## Per-criterion verification (E1–E10)

| # | Criterion | Status | Evidence |
| --- | --- | :---: | --- |
| E1 | All §1–§7 deliverables exist with the spec'd public API | verified | All listed files present in `Sources/RebornZuneCore/Views/`. Read each file: `LightingAnimator.swift` exposes `startDelay: TimeInterval` default 0.6 (signatures match §1); `TileView.swift` exposes `init(images:span:flipPeriod:flipDuration:initialDelay:)` with defaults `(5, 1.2, 0)` (matches §2); `TileEntryAnimation.swift` exposes the struct with defaults `(14, 0.08, 0.45, 0.6)` and `parameters(forWave:)` returning the 3-tuple (matches §3); `TileWallView.swift` exposes the struct with defaults `(70, LightingAnimator(), TileEntryAnimation(), 0)` plus `TileWallEntry` and `staticSnapshot(...)` (matches §4); `SnapshotHarness.swift` exposes `requestedOutputPath`, `requestedSnapshotTime`, and `render(_:size:outputPath:) -> Bool` under `#if DEBUG` (matches §5); `Apps/{macOS,iPadOS,tvOS}/ContentView.swift` all use the SnapshotView/DefaultContent split (matches §6); `SyntheticTiles.swift` exposes `sample(seed:count:)` with defaults `(0, 64)` (matches §7). |
| E2 | Warm-delay fix: `LightingAnimator.startDelay` applies to both lights | verified | Read `LightingAnimator.swift:36–43`: BOTH `warmProgress` and `coolProgress` are computed via `clampedProgress(time: time - startDelay, ...)`. The `clampedProgress` helper (lines 57–64) returns 0 for any `time <= 0`, so before `startDelay` both lights freeze at progress 0. `LightingAnimatorTests.testStartDelayHoldsBothLights` (lines 40–48) asserts at `t = startDelay/2` that BOTH `light1Position`/`light1Color` (warm) AND `light2Position`/`light2Color` (cool) match their progress=0 keyframes — the test passes. `testParametersAtStartDelayBoundary` (lines 52–67) further verifies behavior at exactly `t = startDelay` and `t = startDelay + 1`. |
| E3 | `swift build` succeeds with no warnings | verified | `swift build` exits 0 (`Build complete! (0.69s)`); also re-ran `swift build -Xswiftc -warnings-as-errors` to a clean exit 0. Compilation log shows 27/27 sources compiled with no diagnostics. |
| E4 | `swift test` passes ≥ 60 tests, 0 failures | verified | Final summary line: `Executed 68 tests, with 0 failures (0 unexpected) in 1.977 (1.981) seconds`. New M5 tests include `TileEntryAnimationTests` (7 tests) and `SyntheticTilesTests` (6 tests); modified `LightingAnimatorTests` includes both `testStartDelayHoldsBothLights` and `testParametersAtStartDelayBoundary`. |
| E5 | `xcodebuild` for all 3 app targets succeeds | verified | `xcodebuild -scheme RebornZune-macOS -destination 'platform=macOS' build` → `** BUILD SUCCEEDED **`. `xcodebuild -scheme RebornZune-iPadOS -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build` → `** BUILD SUCCEEDED **`. `xcodebuild -scheme RebornZune-tvOS -destination 'generic/platform=tvOS Simulator' CODE_SIGNING_ALLOWED=NO build` → `** BUILD SUCCEEDED **`. |
| E6 | App targets compile with the SnapshotView/DefaultContent split | verified | All three `Apps/<plat>/ContentView.swift` files use the `#if DEBUG` SnapshotView/DefaultContent gate with verbatim `SnapshotHarness.requestedOutputPath` check. All three apps build (E5) and the macOS app correctly switches to SnapshotView under env vars (see E7). |
| E7 | Snapshot harness produces a non-empty PNG when run with `REBORN_ZUNE_SNAPSHOT_PATH` set | verified | Removed `/tmp/m5_eval_macos.png`, ran the macOS app with `REBORN_ZUNE_SNAPSHOT_PATH=/tmp/m5_eval_macos.png REBORN_ZUNE_SNAPSHOT_TIME=30`, app exited on its own (verified by `ps -p $APP_PID` returning nothing 5 s later — no zombie). `file` reports `PNG image data, 2560 x 1440, 8-bit/color RGBA, non-interlaced`. Size `1,432,230 bytes` (≫ 10 KB threshold). The `requestedSnapshotTime` env var is wired through `SnapshotHarness.swift:33–39` and consumed by `Apps/{macOS,iPadOS,tvOS}/ContentView.swift:27,36` as `frozenTime:`. |
| E8 | Visual verification: rendered tile wall is plausible (≥ 50 distinct color regions, not all-black, lighting wash visible) | verified (lighting via simctl path) | macOS snapshot shows ~80 distinct gradient tiles spanning multiple hues with clear 1×1/3×3/4×4 span variety; lighting wash absent (documented `ImageRenderer` limitation). iPadOS sim screenshot shows lighting wash AND mid-flip rotated tiles. tvOS sim screenshot shows lighting wash AND mid-flip rotated tiles. Detailed visual descriptions in the section below. |
| E9 | iPadOS Simulator + tvOS Simulator can launch the app and screenshot via `xcrun simctl io <UDID> screenshot` | verified | Booted `iPad Pro 13-inch (M5)` (iOS 26.4, UDID `9D050E4A-C62B-4FBD-B435-8B5AD778317F`) and `Apple TV 4K (3rd gen) at 1080p` (tvOS 26.4, UDID `E4350367-19C7-4842-9F50-AF7EFE1FC9DA`); installed and launched both apps in DefaultContent mode (no env vars); both screenshots written successfully. PIDs returned by `simctl launch`: iPad 70929, tvOS 70935. |
| E10 | No regression: M1–M4 acceptance criteria still pass | verified | All 35 M1–M3 tests still pass (BitMatrix×8, Bundle/FolderLibrarySource×5, LibraryGrouping×7, Music×2, RebornZuneCore×1, TileSpan×3, VariableSpanLayout×9). M4's lighting tests still pass (LightingAnimator×8, LightKeyframes×11, LightingShaderCompilation×1 = 20). The `warmDelay` → `startDelay` rename is a M4-spec-correction, not a regression — the M4 spec explicitly conceded the warm-only model was an error. The Metal plugin platform-dispatch fix in `Plugins/MetalCompilerPlugin/MetalCompilerPlugin.swift` is strictly additive: macOS host builds (the only platform M4 actually exercised) still produce the same metallib, and iOS/tvOS sim builds are now correctly handled. |

## Independent build/test outputs (last lines)

### `swift build -Xswiftc -warnings-as-errors`

```
[22/27] Compiling RebornZuneCore Album.swift
[23/27] Compiling RebornZuneCore Artist.swift
[24/27] Compiling RebornZuneCore BundleLibrarySource.swift
[25/27] Compiling RebornZuneCore FolderLibrarySource.swift
[26/27] Compiling RebornZuneCore TileWallView.swift
[27/27] Compiling RebornZuneCore resource_bundle_accessor.swift
Build complete! (0.69s)
```

### `swift test`

```
Test Suite 'RebornZuneCorePackageTests.xctest' passed at 2026-05-02 17:09:29.351.
	 Executed 68 tests, with 0 failures (0 unexpected) in 1.977 (1.981) seconds
Test Suite 'All tests' passed at 2026-05-02 17:09:29.351.
	 Executed 68 tests, with 0 failures (0 unexpected) in 1.977 (1.981) seconds
```

### `xcodegen generate`

```
⚙️  Generating plists...
⚙️  Generating project...
⚙️  Writing project...
Created project at /Users/yjd/Documents/Reborn-Zune-Apple/RebornZune.xcodeproj
```

### `xcodebuild` for all 3 app targets

- `xcodebuild -scheme RebornZune-macOS -destination 'platform=macOS' build` → `** BUILD SUCCEEDED **`
- `xcodebuild -scheme RebornZune-iPadOS -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build` → `** BUILD SUCCEEDED **`
- `xcodebuild -scheme RebornZune-tvOS -destination 'generic/platform=tvOS Simulator' CODE_SIGNING_ALLOWED=NO build` → `** BUILD SUCCEEDED **`

## Re-captured screenshot paths and visual descriptions

Saved to `/Users/yjd/Documents/Reborn-Zune-Apple/reports/M5_eval_screenshots/`:

### `macos_snapshot.png` (1,432,230 bytes, 2560×1440)

Source: `REBORN_ZUNE_SNAPSHOT_PATH=/tmp/m5_eval_macos.png REBORN_ZUNE_SNAPSHOT_TIME=30 "Reborn Zune.app/Contents/MacOS/Reborn Zune"`.

Visual: The tile wall renders correctly with full variable-span variety on a black backdrop. I count many 1×1 unit tiles arranged in rows, two clearly visible 3×3 medium tiles (one teal-blue on the left, one orange/red on the right), one large 4×4 tile (orange/red, lower right), and a green medium tile in the lower-center. Each tile shows its underlying gradient image with a unique hue derived from its index — the wall has dozens of distinct color regions (well over the ≥50 threshold). The wall fills the upper ~half of the 2560×1440 frame (since the static panel is 1280×720). Surrounding bands above/below/right are pure black.

Lighting wash: NOT visible. Tiles render their underlying gradient hues only, with no warm/cool tinting overlaid. This matches the documented `ImageRenderer` `.colorEffect` limitation called out in M5.md (§"Notes for the executor"); the simctl path is the source of truth for lighting verification, and that path passes (see iPadOS/tvOS below).

No rendering bugs: no all-black, no banding, no missing tiles, no scaling artifacts. Tile borders are visible and crisp.

### `ipados_default.png` (1,392,345 bytes, 2064×2752)

Source: `xcrun simctl io 9D050E4A-C62B-4FBD-B435-8B5AD778317F screenshot` after launching `dev.yjd.rebornzune.ipados` in DefaultContent mode and waiting 5 s for entry animations to settle and lighting to advance from t=0 to ~5 s.

Visual: Tile wall renders at the top of the iPad portrait frame (~10% of the height since `unitSize: 70` produces a wall sized to 64 tiles roughly half-screen-wide). Variable spans clearly present: many 1×1 unit tiles, multiple 3×3 medium tiles (one bright green left of center, one warm-pink top-center, one orange-pink center, several green/teal scattered), and one large 4×4 tile (greenish, lower-left of the wall area). Status bar visible at top ("5:10 PM Sat May 2", "100%", wifi icon).

Lighting wash: VISIBLE. The wall is dominated by green/lime tinting on the left two-thirds with a clear shift to warm orange/pink on the right third. Tiles in the center mid-area show a distinctly purple/lavender wash on a few mid-flip frames where the underlying gradient is bluish — this is the cool-light component bleeding through during the flip rotation. The multi-color tinting is clearly the shader's output, not just per-tile gradient hues.

Mid-flip tiles: at least 4–5 tiles are visibly rotated in 3D (parallelogram-shaped, with one edge thinner than the other) AND partially faded — this is the periodic flip animation caught at random rotation angles. The flip animation is running.

No rendering bugs: no all-black, no banding, no missing tiles. The lower ~70% of the screen is intentionally black (TileWallView layout doesn't fill the whole iPad screen with this tile count and unit size; M5 doesn't require it to).

### `tvos_default.png` (450,382 bytes, 1920×1080)

Source: `xcrun simctl io E4350367-19C7-4842-9F50-AF7EFE1FC9DA screenshot` after launching `dev.yjd.rebornzune.tvos` in DefaultContent mode and waiting 5 s.

Visual: Tile wall renders in the upper third of the 1920×1080 frame. Same span variety: many 1×1 tiles, several 3×3 medium tiles (bright green dominating the left and center-right, dark purple/magenta in the center, orange/pink near center), one clearly visible large 4×4 tile (lime green, right of center).

Lighting wash: VISIBLE. Strong green tinting dominates the left half and center-right; the middle has a magenta/purple region (the cool light) and a warm orange/pink region between them. The lighting clearly washes across multiple tiles — adjacent tiles tinted differently because the wash gradient passes through them differently — confirming the Metal `.colorEffect` shader is running.

Mid-flip tiles: at least 3 tiles visibly rotated and partially faded (notably the dark purple/black 3×3 tile center-bottom of the wall, which appears foreshortened indicating a rotation angle around 45–60°).

No rendering bugs: no all-black, no banding, no missing tiles. Lower 2/3 of the screen is black background, expected.

## Regressions from M1–M4

None found.

- All M1–M3 tests still pass (counted in the 68-test total).
- M4 lighting tests still pass; the `warmDelay` → `startDelay` rename is a spec-correction explicitly required by M5 §1, not a regression of the M4 spec.
- The Metal compiler plugin update (per-platform shell-script dispatch in `Plugins/MetalCompilerPlugin/MetalCompilerPlugin.swift`) is strictly additive: macOS host builds use the same `xcrun --sdk macosx metal` invocation path as before; the new branches are only entered when `PLATFORM_NAME` is set to an iOS/tvOS simulator SDK at xcodebuild time.
- App-target build matrix (E5) is now green for all three platforms; previously (per the executor report) M4 only validated the macOS path because no app target actually invoked the shader. The plugin fix unblocks the iOS/tvOS app paths without altering macOS behavior.

## Spec-silent decisions noted (not rejection grounds)

The executor disclosed these in the report, all reasonable:
1. `SeededRNG` renamed to `ZuneSeededRNG` to avoid clash with a same-named test-target helper.
2. Per-tile `initialDelay = (Double(index % 8) / 8.0) * 5.0` matches the spec's suggestion in §4 verbatim.
3. `TileView` resets rotation to 0° after each flip cycle (cosmetic, not visible).
4. Independent `withAnimation` blocks for opacity and scale entry transitions match the UWP source's separate `KeyFrameAnimation`s.
5. `staticSnapshot` uses an internal `StaticTile` that doesn't run the flip Task — required for deterministic snapshot output.
6. `SnapshotHarness.render` tries `nsImage`/`uiImage` then falls back to `cgImage`.
7. Metal plugin dispatch via shell scripts because SwiftPM build plugins can't see runtime `PLATFORM_NAME`.

VERDICT: APPROVED
