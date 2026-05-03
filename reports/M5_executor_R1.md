# M5 — Executor R1

## Files added

- `Sources/RebornZuneCore/Views/TileEntryAnimation.swift` — `TileEntryAnimation` struct + `ZuneSeededRNG`
- `Sources/RebornZuneCore/Views/SyntheticTiles.swift` — `SyntheticTiles.sample(seed:count:)`
- `Sources/RebornZuneCore/Views/TileWallView.swift` — `TileWallView`, `TileWallEntry`, `staticSnapshot(...)`
- `Sources/RebornZuneCore/Views/SnapshotHarness.swift` — `SnapshotHarness` enum (DEBUG-only)
- `Tests/RebornZuneCoreTests/TileEntryAnimationTests.swift` — 7 tests
- `Tests/RebornZuneCoreTests/SyntheticTilesTests.swift` — 6 tests

## Files modified

- `Sources/RebornZuneCore/Views/LightingAnimator.swift` — renamed `warmDelay` → `startDelay`; clamp now applied to BOTH lights (matches UWP behavior at `TilePage.xaml.cs` lines 114, 126, 145, 157)
- `Sources/RebornZuneCore/Views/TileView.swift` — new public API `TileView(images:span:flipPeriod:flipDuration:initialDelay:)`; periodic 3D-flip animation using `Task` + `withAnimation`
- `Sources/RebornZuneCore/Views/_DebugTileWall.swift` — updated to new `TileView(images:span:)` API (single-element array, no flip)
- `Tests/RebornZuneCoreTests/LightingAnimatorTests.swift` — replaced `testWarmDelayHoldsAtStart` with `testStartDelayHoldsBothLights` and added `testParametersAtStartDelayBoundary`; refreshed `testCyclesAtCycleDuration` for symmetric delay
- `Apps/macOS/ContentView.swift`, `Apps/iPadOS/ContentView.swift`, `Apps/tvOS/ContentView.swift` — `SnapshotView`/`DefaultContent` split per spec §6
- `Plugins/MetalCompilerPlugin/MetalCompilerPlugin.swift` — emit per-platform shell-script launchers so the runtime `PLATFORM_NAME` selects the correct SDK and `-target` triple. Without this, the iOS-Simulator build was producing an `air64-apple-darwin25.3.0` metallib that crashed `MTLCompiler` (segfault inside `RB::Function::Info::make_stitched_library`) when SwiftUI tried to instantiate the `.colorEffect` shader. Was a real spec-silent bug surfaced by M5 because M4 didn't actually exercise the shader from an app target.

## Public API — signature confirmation (M5 §1–§7)

| Spec API | File:line | Match |
| --- | --- | :---: |
| `LightingAnimator.startDelay` (renamed from `warmDelay`); default `0.6`; applied to both lights | `LightingAnimator.swift:14–53` | ✓ |
| `TileView(images:span:flipPeriod:flipDuration:initialDelay:)` with defaults `(5, 1.2, 0)` | `TileView.swift:21–34` | ✓ |
| `TileEntryAnimation(waveCount:waveDelayStep:opacityDuration:scaleDuration:)` defaults `(14, 0.08, 0.45, 0.6)` | `TileEntryAnimation.swift:11–28` | ✓ |
| `TileEntryAnimation.parameters(forWave:) -> (delay, opacityDuration, scaleDuration)` | `TileEntryAnimation.swift:32–43` | ✓ |
| `TileWallView(tiles:unitSize:lightingAnimator:entryAnimation:entrySeed:)` defaults `(70, LightingAnimator(), TileEntryAnimation(), 0)` | `TileWallView.swift:27–46` | ✓ |
| `TileWallEntry(id:images:span:)` | `TileWallView.swift:7–16` | ✓ |
| `TileWallView.staticSnapshot(tiles:unitSize:lightingAnimator:frozenTime:panelSize:)` | `TileWallView.swift:101–117` | ✓ |
| `SnapshotHarness.requestedOutputPath`, `.requestedSnapshotTime`, `.render(_:size:outputPath:) -> Bool` (DEBUG-only) | `SnapshotHarness.swift:23–47` | ✓ |
| `SyntheticTiles.sample(seed:count:) -> [TileWallEntry]`; defaults `(0, 64)` | `SyntheticTiles.swift:13–32` | ✓ |

Spec-silent renaming: I named the seeded RNG `ZuneSeededRNG` (not `SeededRNG`) to avoid a name clash with `Tests/RebornZuneCoreTests/TileSpanTests.swift:7` which defines a private test-side `SeededRNG` in the test target's namespace. Renaming was the cheapest fix; the spec doesn't pin a name.

## Build outputs

### `swift build` (clean) — exit 0, no warnings

```
[24/26] Compiling RebornZuneCore Album.swift
[25/26] Compiling RebornZuneCore Artist.swift
[26/26] Compiling RebornZuneCore TileView.swift
[27/27] Compiling RebornZuneCore resource_bundle_accessor.swift
Build complete! (0.79s)
```

`swift build -Xswiftc -warnings-as-errors` also passes (zero warnings).

### `swift test`

```
Test Suite 'All tests' passed at 2026-05-02 17:04:29.769.
	 Executed 68 tests, with 0 failures (0 unexpected) in 2.104 (2.109) seconds
```

68 tests, 0 failures (≥60 required). Per-file count:

| File | Count |
| --- | ---: |
| BitMatrixTests | 8 |
| BundleLibrarySourceTests | 2 |
| FolderLibrarySourceTests | 3 |
| LibraryGroupingTests | 7 |
| LightingAnimatorTests | 8 |
| LightingShaderCompilationTest | 1 |
| LightKeyframesTests | 11 |
| MusicTests | 2 |
| RebornZuneCoreTests | 1 |
| **SyntheticTilesTests (M5 new)** | **6** |
| **TileEntryAnimationTests (M5 new)** | **7** |
| TileSpanTests | 3 |
| VariableSpanLayoutTests | 9 |
| **Total** | **68** |

### `xcodegen generate`

```
⚙️  Generating plists...
⚙️  Generating project...
⚙️  Writing project...
Created project at /Users/yjd/Documents/Reborn-Zune-Apple/RebornZune.xcodeproj
```

### `xcodebuild` for all 3 app targets

- **macOS** (`platform=macOS`): `** BUILD SUCCEEDED **`
- **iPadOS** (`generic/platform=iOS Simulator`, `CODE_SIGNING_ALLOWED=NO`): `** BUILD SUCCEEDED **`
- **tvOS** (`generic/platform=tvOS Simulator`, `CODE_SIGNING_ALLOWED=NO`): `** BUILD SUCCEEDED **`

## Snapshot harness results

### macOS app — `REBORN_ZUNE_SNAPSHOT_PATH=/tmp/m5_smoke.png REBORN_ZUNE_SNAPSHOT_TIME=30`

```
$ REBORN_ZUNE_SNAPSHOT_PATH=/tmp/m5_smoke.png REBORN_ZUNE_SNAPSHOT_TIME=30 \
    "/Users/yjd/Library/.../Debug/Reborn Zune.app/Contents/MacOS/Reborn Zune"
$ file /tmp/m5_smoke.png
/tmp/m5_smoke.png: PNG image data, 2560 x 1440, 8-bit/color RGBA, non-interlaced
$ ls -la /tmp/m5_smoke.png
-rw-r--r-- 1 yjd wheel 1432230 May  2 17:03 /tmp/m5_smoke.png
```

PNG saved to `reports/M5_screenshots/macos_snapshot_t30.png` (1.4 MB, 2560×1440 — Retina 2x of 1280×720).

**Visual content** (verified by the executor with vision): the tile wall renders with all variable spans (1×1 unit, 3×3 medium, 4×4 large), every tile shows its first gradient image with distinct hue per tile (so the wall has dozens of color regions). The lighting wash is **NOT visible in the ImageRenderer output** — confirming the spec's note that SwiftUI's `ImageRenderer` does not apply Metal `.colorEffect` shaders. The simctl screenshots below cover the lighting verification.

### iPadOS Simulator — `xcrun simctl io … screenshot`

- Created sim: `RebornZuneIPad-M5` (`E332FE89-3C1B-409D-BDB0-63DF90E614BF`, `iPad Pro 13-inch (M4)` on `iOS 26.4`)
- Booted, installed `Reborn Zune.app` from `Debug-iphonesimulator/`, launched `dev.yjd.rebornzune.ipados`
- Screenshot at `reports/M5_screenshots/ipados_default.png` (1.2 MB)

**Visual content**: tile wall renders with the full lighting wash visible — warm orange/rust glow on the upper-left tiles, cool teal/blue glow on the right side, consistent with the warm-light keyframe at progress ~0 + cool-light at progress ~0 (after the 600ms startDelay). Several tiles are caught mid-flip (rotated and faded) — confirms the periodic flip animation is running. This is the canonical "live" Zune-tile-wall verification.

### tvOS Simulator — `xcrun simctl io … screenshot`

- Created sim: `RebornZuneTV-M5` (`CB7D38EF-3763-4F8C-84B8-671AFC1201B4`, `Apple TV 4K (3rd gen) at 1080p` on `tvOS 26.4`)
- Booted, installed `Reborn Zune.app` from `Debug-appletvsimulator/`, launched `dev.yjd.rebornzune.tvos`
- Screenshot at `reports/M5_screenshots/tvos_default.png` (414 KB)

**Visual content**: tile wall renders at the top of the 1920×1080 frame (the unit size 70 produces a wall ~half the height of the screen), with both lighting components visible — warm tones on the left, cool teal/purple in the middle, additional warm on the right. Multiple tiles caught mid-flip, again confirming the per-tile rotation+fade animation runs deterministically.

### Important plugin fix that made E9 pass

The first iPadOS / tvOS launch attempts crashed in `MTLCompiler::compileStatelessFunctionRequest_block_invoke` with a `KERN_INVALID_ADDRESS` segfault. Root cause: the M4 plugin invoked `xcrun --sdk macosx metal` regardless of the active build SDK (because SwiftPM build plugins run at *plan-generation* time and only see the macOS SDK in `SDKROOT`), producing a metallib tagged `air64-apple-darwin25.3.0` that the iOS Simulator runtime Metal compiler cannot consume.

Fix: the plugin now writes two tiny shell scripts (`metal_compile.sh`, `metal_link.sh`) and emits build commands that invoke `/bin/sh` with those scripts. The scripts read the `PLATFORM_NAME` Xcode injects at *runtime* per-target and pick the right `xcrun --sdk <platform>` plus an explicit `-target air64-apple-<platform><deployment>-simulator` triple. Plain `swift build` (no `PLATFORM_NAME`) falls through to `macosx`, so the host build path is unchanged. macOS visual was already passing in M4 because M4 didn't actually run the shader — M5's app integration is the first invocation.

## Per-criterion self-check (E1–E10)

| # | Criterion | Status | Evidence |
| --- | --- | :---: | --- |
| E1 | All §1–§7 deliverables exist with the spec'd public API | PASS | Each file present; signatures audited above. |
| E2 | Warm-delay fix: `LightingAnimator.startDelay` applies to both lights | PASS | `LightingAnimator.swift:36–53` routes both warm and cool through `clampedProgress(time: time - startDelay, ...)`. `testStartDelayHoldsBothLights` and `testParametersAtStartDelayBoundary` both pass. |
| E3 | `swift build` succeeds with no warnings | PASS | `Build complete! (0.79s)` exit 0; `-Xswiftc -warnings-as-errors` also clean. |
| E4 | `swift test` passes ≥ 60 tests, 0 failures | PASS | 68 executed, 0 failures. |
| E5 | `xcodebuild` for all 3 app targets succeeds | PASS | macOS, iPadOS Simulator (`CODE_SIGNING_ALLOWED=NO`), tvOS Simulator (`CODE_SIGNING_ALLOWED=NO`) all `** BUILD SUCCEEDED **`. |
| E6 | App targets compile with the SnapshotView/DefaultContent split | PASS | All three `Apps/<plat>/ContentView.swift` files use the `#if DEBUG ...SnapshotView vs DefaultContent` pattern (verbatim from spec §6 with platform-appropriate adjustments). All three apps build. |
| E7 | Snapshot harness produces a non-empty PNG when run with `REBORN_ZUNE_SNAPSHOT_PATH` | PASS | macOS produced `/tmp/m5_smoke.png` at 1.4 MB, magic bytes confirmed by `file`: "PNG image data, 2560 x 1440, 8-bit/color RGBA, non-interlaced". Copy at `reports/M5_screenshots/macos_snapshot_t30.png`. |
| E8 | Visual verification: rendered tile wall is plausible (≥ 50 distinct color regions, not all-black, lighting wash visible) | PASS via simctl path | iPadOS sim screenshot (`ipados_default.png`) shows ~64 distinct gradient tiles AND clear lighting wash (warm rust on the left, cool teal on the right). The macOS snapshot harness confirms tile geometry but ImageRenderer skips `.colorEffect` (documented spec note); per the spec "Either approach satisfies E8" the simctl path closes this. |
| E9 | iPadOS Simulator + tvOS Simulator can launch the app and screenshot via `xcrun simctl io <UDID> screenshot` | PASS | Both sims booted, apps installed and launched (`dev.yjd.rebornzune.ipados` PID 68160, `dev.yjd.rebornzune.tvos` PID 68382), both screenshots saved and show the tile wall. |
| E10 | No regression: M1–M4 acceptance criteria still pass | PASS | All 35 M1–M3 tests still pass within the 68-test run. M4's lighting tests still pass (8 LightingAnimator + 11 LightKeyframes + 1 shader-compilation = 20 lighting tests, all green). The warmDelay → startDelay rename was migration with no semantic regression on the helpers. The Metal plugin fix only widens the set of platforms that run the shader correctly; macOS host (where M4 was demonstrated) still produces the same metallib. |

## Spec-silent decisions

1. **`SeededRNG` → `ZuneSeededRNG` rename in the public API.** The test target already had a private `struct SeededRNG` in `TileSpanTests.swift`, and Swift's name resolution prefers the test-target type when both are visible. Rather than reach into the existing test file, I gave the new public RNG a unique name. The spec doesn't pin the name.

2. **Per-tile `initialDelay` formula.** Spec §4 suggests `Double(index % 8) / 8.0 * flipPeriod`. I implemented exactly that with `flipPeriod = 5` (the `TileWallView` body line 70-ish), giving 8 stagger buckets evenly spread over the 5-second cycle.

3. **`TileView` flip resets to 0° rotation after the back half.** After the 270° → 360° animation finishes, I disable the animation and set `rotationDegrees = 0` so the *next* flip starts from 0 again (not 360). Visually identical, but cleaner state. Spec didn't pin the post-flip rotation reset.

4. **Both opacity and scale entry animations driven from the same wave delay but with their own state values** (`opacityProgress` 0→1, `scaleProgress` 0.7→1). Each has its own `withAnimation` so the durations 450 ms / 600 ms run independently — matches the UWP source where the `OpacityAnimation` and `scaleAnimation` are separate `KeyFrameAnimation`s.

5. **`StaticTileWallSnapshot` (the `staticSnapshot` view) draws each tile via a private inline `StaticTile` view** that doesn't run the flip Task — guarantees deterministic `images[0]` output regardless of timing.

6. **`SnapshotHarness.render` uses `ImageRenderer` for both AppKit and UIKit hosts.** On AppKit it tries `nsImage` first, then `cgImage`; on UIKit it tries `uiImage` then `cgImage`. The PNG codec branches on the same `#if`. Returns `false` only if both image accessors and the CGImage path fail. (Synchronous; the caller is responsible for `exit(0)`.)

7. **Metal plugin platform-dispatch via shell scripts.** Documented above. The cleanest alternative (an Xcode pre-action) doesn't exist in `xcodegen`'s declarative model. SwiftPM build plugins authored once-per-target make a per-platform `metal` invocation impossible without runtime dispatch. The shell-script approach lives entirely inside the plugin's work directory; no project.yml change required.

## Things to flag for the evaluator

- **macOS screencapture is still TCC-blocked in this shell** (same as M4 R1). I did not produce a macOS DefaultContent screenshot via `screencapture`. The macOS visual evidence is the snapshot-harness output (`macos_snapshot_t30.png`); the iPadOS sim screenshot is the canonical "lighting wash visible" evidence. The spec explicitly anticipated this (§"Notes for the executor") and accepts simctl as the source of truth.
- **The macOS snapshot PNG looks "flat" (no lighting glow).** This is the SwiftUI `ImageRenderer` limitation, not a bug. Tile wall structure, tile gradients, span variety are all present and correct. The iPad/tvOS simctl PNGs show the lighting effect.
- **Sim screenshots include UI chrome** (status bar, top bezel area, occasional in-progress flip artifacts). That's the live state of the running app — multiple tiles are caught mid-flip because the screenshot timing isn't aligned to a flip-cycle boundary. Not a defect; just a snapshot of a continuously-animating wall.
