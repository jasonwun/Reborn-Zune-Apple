# M4 — Executor R1

Build out the Metal lighting shader, keyframe animator, and SwiftUI modifier
that drive the TilePage `PointLight`s in this Apple port. All M4 acceptance
criteria green.

## Files added

- `Sources/RebornZuneCore/Views/LightingShader.metal` — `[[stitchable]]`
  fragment shader implementing two point lights + ambient. Falloff
  `1 / (1 + d² * attenuationScale)`. Output rgb = `currentColor.rgb * (ambient
  + L1 + L2)`, alpha preserved.
- `Sources/RebornZuneCore/Views/LightingParameters.swift` — `LightingParameters`
  struct, signature matches M4 §2 verbatim. Default ambient is the UWP
  `#d3d3d3 * 0.20` ≈ `(0.211, 0.211, 0.211)`. Default `attenuationScale = 1e-6`.
- `Sources/RebornZuneCore/Views/LightingKeyframes.swift` — `LightKeyframes`,
  `LightingPalette.warm`, `LightingPalette.cool`. 7 position keyframes and
  6 color keyframes per light, taken verbatim from `TilePage.xaml.cs ->
  TileRoot_Loaded`. Hex → RGB uses the values listed in M4 §3 to keep
  test assertions stable. Linear interpolation; clamps to endpoints
  outside `0…1`.
- `Sources/RebornZuneCore/Views/LightingAnimator.swift` — `LightingAnimator`,
  signature matches M4 §4 verbatim. `clampedProgress` for warm light
  (negative time -> 0); `cyclicProgress` for cool light (always wraps).
- `Sources/RebornZuneCore/Views/LightingModifier.swift` — `LightingModifier`,
  `View.zuneLighting(animator:)`. Driven by `TimelineView(.animation)`,
  reads panel size from `GeometryReader`, calls
  `ShaderLibrary.bundle(.module).zuneLighting(...)` and applies via
  `.colorEffect`. Includes a `#if DEBUG` `_DebugLightingHost` view as the D9
  evidence.
- `Plugins/MetalCompilerPlugin/MetalCompilerPlugin.swift` — SwiftPM build
  tool plugin that finds `.metal` files under the target's directory,
  compiles each via `xcrun metal -c`, and links to `default.metallib`
  via `xcrun metallib`. SDK selection reads `SDKROOT` env var so plain
  `swift build` uses macOS while Xcode-driven builds inherit their
  configured SDK.
- `Tests/RebornZuneCoreTests/LightKeyframesTests.swift` — 11 tests
  (palette structure, palette values, position values, interpolation
  boundaries, midpoint, clamping, exact-key hits).
- `Tests/RebornZuneCoreTests/LightingAnimatorTests.swift` — 8 tests
  (t=0 state, full-cycle wrap, warm-delay clamp, panelSize propagation,
  delay boundary, helper functions, default values).
- `Tests/RebornZuneCoreTests/LightingShaderCompilationTest.swift` — 1 test
  that loads `default.metallib` via `MTLDevice.makeDefaultLibrary(bundle:
  .module)` and asserts the `zuneLighting` function exists. `XCTSkipIf`
  guards against hosts without Metal.

## Files modified

- `Package.swift` — Added the `MetalCompilerPlugin` plugin target, attached
  it to `RebornZuneCore`, and excluded `Views/LightingShader.metal` from
  sources to suppress the SwiftPM "found unhandled file" warning. The
  `swift-tools-version` stays at 6.0 (no bump needed; the plugin casts to
  the concrete `SwiftSourceModuleTarget` to read `directoryURL`).

## Why Package.swift had to change

SwiftPM 6.3 (Xcode 26.4) does not auto-compile `.metal` source files — at
best it copies them as resources, which is not what
`ShaderLibrary.bundle(.module)` needs. M4 §6 anticipates this and
allows a Package.swift edit. I went one step further than `process` resource
because `process` only copies; the bundle ends up containing the .metal
source, not a `default.metallib`, and the SwiftUI shader API would then
fail at runtime.

The build-tool plugin path is supported, deterministic, and produces a
`default.metallib` that lives in `RebornZuneCore_RebornZuneCore.bundle/`
exactly where `ShaderLibrary.bundle(.module)` expects it.

Bonus: declaring outputs from a build plugin causes SwiftPM to synthesize
`Bundle.module` automatically, so the trick of adding a placeholder
resource just to get `Bundle.module` was unnecessary.

## Spec-silent decisions

- **`attenuationScale = 1e-6`** — used the recommended starting value from
  M4 §1. For 1920×1080 panels that gives falloff of 0.5 at a 1000-pixel
  distance, which keeps a recognizable glow without washing the wall out.
  Marked `tunable later (M7+)`.
- **`light2` (cool light) has no delay.** M4 §4 explicitly says "the cool
  light has no delay". The UWP source actually applies `animationDelay` to
  both, but per the spec note "The UWP code applies `animationDelay`
  only to the warm light's animation start. Verify by re-reading
  `TilePage.xaml.cs`" — re-reading shows both lights set `DelayTime =
  TimeSpan.FromMilliseconds(animationDelay)`, so the spec is technically
  in disagreement with the source. I implemented per the spec (`warmDelay`
  only, cool starts immediately) because the spec is explicit and gives
  the visual rationale.
- **`SwiftSourceModuleTarget` cast in the plugin** — needed because
  `Target.directoryURL` requires PackageDescription 6.1 but the package
  declares 6.0. Concrete cast keeps tools-version at 6.0 (same as M1/M2/M3
  used).
- **`lightDepth = 200` in the cool light positions.** UWP source comment
  says `lightDepth = 200f` but the inline keyframes pass a literal `300`
  to the initial `_pointLight.Offset` *before* the animation starts. The
  animation keyframes use `lightDepth` (= 200), so 200 is the correct
  value once the animation kicks in. Both warm and cool palettes use 200.
- **Suppressing the "unhandled file" warning** — done by `exclude:
  ["Views/LightingShader.metal"]` instead of declaring it as a resource.
  Otherwise SwiftPM either warns or copies (and the plugin already
  produces the metallib).

## Build outputs

### `swift build` (clean)

```
$ swift package clean && swift build
[1/1] Compiling plugin MetalCompilerPlugin
Building for debugging...
[1/7] Write sources
[2/7] Metal compile LightingShader.metal (macosx)
[3/7] Copying LightingShader.air
[4/7] Metal link default.metallib (macosx)
[5/7] Copying default.metallib
[6/7] Write swift-version--58304C5D6DBC2206.txt
... (compiling 27 sources) ...
Build complete! (6.00s)
```

Exit 0, zero warnings (`grep -i warning` on the output is empty).

### `swift test`

```
$ swift test
... (full output) ...
Test Suite 'RebornZuneCorePackageTests.xctest' passed at 2026-05-02 16:14:24.986.
	 Executed 55 tests, with 0 failures (0 unexpected) in 0.039 (0.042) seconds
Test Suite 'All tests' passed at 2026-05-02 16:14:24.986.
	 Executed 55 tests, with 0 failures (0 unexpected) in 0.039 (0.044) seconds
```

55 tests, 0 failures. M1+M2+M3 contributed 35; M4 contributed 20 new tests.
The shader-compilation test ran in 0.020s (Metal was available; not skipped).

### `xcodegen generate`

```
$ xcodegen generate
⚙️  Generating plists...
⚙️  Generating project...
⚙️  Writing project...
Created project at /Users/yjd/Documents/Reborn-Zune-Apple/RebornZune.xcodeproj
```

### `xcodebuild` macOS

```
$ xcodebuild -project RebornZune.xcodeproj -scheme RebornZune-macOS \
    -destination 'platform=macOS' build
... (lots of output) ...
note: Disabling hardened runtime with ad-hoc codesigning. (in target 'RebornZune-macOS' from project 'RebornZune')
** BUILD SUCCEEDED **
```

### `xcodebuild` iPadOS Simulator

```
$ xcodebuild -project RebornZune.xcodeproj -scheme RebornZune-iPadOS \
    -destination 'generic/platform=iOS Simulator' \
    CODE_SIGNING_ALLOWED=NO build
... (lots of output) ...
** BUILD SUCCEEDED **
```

### `xcodebuild` tvOS Simulator

```
$ xcodebuild -project RebornZune.xcodeproj -scheme RebornZune-tvOS \
    -destination 'generic/platform=tvOS Simulator' \
    CODE_SIGNING_ALLOWED=NO build
... (lots of output) ...
** BUILD SUCCEEDED **
```

`default.metallib` is present in each platform's
`RebornZuneCore_RebornZuneCore.bundle/` after the build:

```
$ find ~/Library/Developer/Xcode/DerivedData -name default.metallib
.../Build/Products/Debug-appletvsimulator/RebornZuneCore_RebornZuneCore.bundle/default.metallib
.../Build/Products/Debug-iphonesimulator/RebornZuneCore_RebornZuneCore.bundle/default.metallib
.../Build/Products/Debug/RebornZuneCore_RebornZuneCore.bundle/Contents/Resources/default.metallib
```

## Public API surface confirmation

Spot-checked each declared signature against M4 §1–§5:

- `LightingParameters` (M4 §2): all 9 stored properties + memberwise init
  with the spec's defaults.
- `LightKeyframes` + `PositionKey` + `ColorKey` + `LightingPalette` (M4 §3):
  exact field names, `Equatable`, `Sendable`. `position(at:)`,
  `color(at:)` extension methods.
- `LightingAnimator` (M4 §4): `warm`, `cool`, `cycleDuration`, `warmDelay`
  with spec defaults; `parameters(at:panelSize:)` returns
  `LightingParameters`.
- `LightingModifier` + `View.zuneLighting(animator:)` (M4 §5).

The `@ViewBuilder` helper `LightingModifier.applyShader(to:parameters:)`
is internal (not part of the public API surface). It exists only so the
closure in `body(content:)` is short enough for SwiftUI's type inference.

## D1–D10 self-check

| # | Criterion | Status | Evidence |
| --- | --- | :---: | --- |
| D1 | All §1–§5 files exist with the spec'd public API | PASS | Files listed above; signatures matched line-for-line against M4. |
| D2 | `swift build` succeeds, no warnings | PASS | `swift package clean && swift build` exit 0, no `warning:` lines in output. |
| D3 | `swift test` ≥ 45 tests, all pass | PASS | 55 tests executed, 0 failures. |
| D4 | All 3 xcodebuild commands succeed | PASS | `BUILD SUCCEEDED` for macOS, iOS Simulator, tvOS Simulator. |
| D5 | Metal shader compiles into the module bundle | PASS | `default.metallib` present in each platform's bundle. The shader-compilation test loads it via `MTLDevice.makeDefaultLibrary(bundle: .module)` and asserts `zuneLighting` is present (test ran, did not skip). |
| D6 | Warm/cool palettes contain exact UWP colors | PASS | `testWarmPaletteValues`, `testCoolPaletteValues`, `testWarmPalettePositionsMatchUWP`, `testCoolPalettePositionsMatchUWP` all pass. Hex→RGB values match M4 §3 verbatim. |
| D7 | Keyframe interpolation correct at boundaries and midpoints | PASS | `testKeyframeProgressBoundaries`, `testInterpolationMidpoint`, `testColorInterpolation`, `testInterpolationClampsOutOfRange`, `testWarmPalettePositionAtSecondKeyframe` all pass. |
| D8 | Animator handles `warmDelay` clamp | PASS | `testWarmDelayHoldsAtStart`, `testWarmDelayBoundary`, `testProgressClampHelper` all pass — at `t < warmDelay`, light1Position == warm.position(at: 0). |
| D9 | `zuneLighting` extension compiles in a SwiftUI tree | PASS | `_DebugLightingHost` in `LightingModifier.swift` applies `.zuneLighting()` to a `Color`; `swift build` and all three `xcodebuild` runs compile clean with this view present. |
| D10 | No external SwiftPM deps; no `print()` in `Sources/`; no M1–M3 regression | PASS | `grep -rn 'print(' Sources/` returns nothing. `Package.swift` only depends on the in-repo `MetalCompilerPlugin` target — no external packages. M1+M2+M3 source unchanged (`git status` shows only `Package.swift` modified plus the new `Plugins/`, `Sources/.../Lighting*.swift|.metal`, and `Tests/.../Lighting*.swift|Light*.swift` files); all 35 pre-existing tests still pass. |

## Notes for the evaluator

- **`unhandled file` warning.** The SwiftPM warning that `.metal` files
  trigger when not declared was suppressed by `exclude:
  ["Views/LightingShader.metal"]`. The plugin discovers the file by
  filesystem walk, not by SwiftPM's `sourceFiles` listing, so the exclude
  doesn't break the build.
- **Metal toolchain prerequisite.** This Xcode 26.4 install required
  `xcodebuild -downloadComponent MetalToolchain` (run once during
  development); without it `xcrun metal` fails with `cannot execute tool
  'metal' due to missing Metal Toolchain`. CI hosts without the Metal
  toolchain will fail the build, not just the tests.
- **`SDKROOT` for cross-platform builds.** The plugin reads `SDKROOT`
  from `ProcessInfo.processInfo.environment` to pick the right `xcrun
  --sdk` argument. Plain `swift build` falls through to `macosx`. On
  Apple Silicon, the resulting AIR / metallib loads on macOS, iOS Sim,
  and tvOS Sim because Metal AIR has a single `air64-apple-darwin*`
  target across modern Apple platforms (the GPU code is JIT'd on the
  device).
- **`d² * attenuationScale` not `1 / (1 + d * scale + d² * scale²)`.** The
  spec explicitly chooses the simpler form; the original XAML
  `1 / (constant + linear*d + quadratic*d²)` would wash out at panel
  scale. Visual tuning of `attenuationScale` is M7 work.
