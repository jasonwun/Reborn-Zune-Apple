# M4 — Evaluator R1

Independent verification of the executor's M4 work against
`specs/M4.md` and the cross-cutting acceptance bar.

## Per-criterion verification

| # | Criterion | Status | Evidence |
| --- | --- | :---: | --- |
| D1 | All §1–§5 files exist with the spec'd public API | PASS | `Sources/RebornZuneCore/Views/LightingShader.metal`, `LightingParameters.swift`, `LightingKeyframes.swift`, `LightingAnimator.swift`, `LightingModifier.swift` all present. Each public signature checked against the spec — see "Signature audit" below. |
| D2 | `swift build` succeeds, no warnings | PASS | `swift package clean && swift build` exited 0; `grep -i 'warning'` on the rebuilt output returns no lines. |
| D3 | `swift test` passes with ≥ 45 tests, 0 failures | PASS | "Executed 55 tests, with 0 failures (0 unexpected) in 0.043s". 35 from M1–M3 + 11 (LightKeyframes) + 8 (LightingAnimator) + 1 (LightingShaderCompilation) = 55. Compilation test ran in 0.024s — was NOT skipped. |
| D4 | All 3 xcodebuild commands succeed | PASS | macOS, iPadOS Simulator (`CODE_SIGNING_ALLOWED=NO`), tvOS Simulator (`CODE_SIGNING_ALLOWED=NO`) — all `** BUILD SUCCEEDED **`. |
| D5 | Metal shader compiles into the module bundle | PASS | `default.metallib` present in: `.build/arm64-apple-macosx/debug/RebornZuneCore_RebornZuneCore.bundle/`, `~/Library/Developer/Xcode/DerivedData/.../Debug/RebornZuneCore_RebornZuneCore.bundle/Contents/Resources/`, `Debug-iphonesimulator/RebornZuneCore_RebornZuneCore.bundle/`, `Debug-appletvsimulator/RebornZuneCore_RebornZuneCore.bundle/`. The compilation test loads it and asserts `zuneLighting` is in `library.functionNames` — passed. |
| D6 | Warm/cool palettes contain exact UWP colors | PASS | All 10 hex values (5 warm + 5 cool) recomputed from `component / 255` and matched against `LightingPalette.warm.colors` / `cool.colors`. Differences ≤ 0.001 (well under the 0.01 tolerance). See "Palette numeric audit" below. |
| D7 | Keyframe interpolation correct at boundaries and midpoints | PASS | `testKeyframeProgressBoundaries` (0/1), `testInterpolationMidpoint` (0.5 of two-key set), `testColorInterpolation` (mid color), `testInterpolationClampsOutOfRange` (-0.5/+1.5 clamp), `testWarmPalettePositionAtSecondKeyframe` (exact key hit at 0.16) — all pass. |
| D8 | Animator handles `warmDelay` clamp (no negative-progress overshoot) | PASS | `LightingAnimator.swift:58–65` `clampedProgress` returns `0` for `time <= 0`. `testWarmDelayHoldsAtStart` (t = warmDelay/2), `testWarmDelayBoundary` (t = 0.6 still clamped, t = 1.6 moves), and `testProgressClampHelper` (t=-1 → 0) all assert this exactly. The cool light uses `cyclicProgress` and starts moving immediately. |
| D9 | `zuneLighting` View extension exists and compiles in a SwiftUI tree | PASS | `LightingModifier.swift:74–80` `_DebugLightingHost` applies `.zuneLighting()` to `Color.gray.frame(...)`. `swift build` and all 3 `xcodebuild` runs compile this view as part of the module. The View extension itself is on lines 61–67. |
| D10 | No external SwiftPM deps; no `print()` in `Sources/`; no M1–M3 regression | PASS | `Package.swift` declares only the in-repo `MetalCompilerPlugin` plugin target — no `dependencies:` block on the package. `grep -rn 'print(' Sources/` returns nothing. All 35 M1–M3 tests (BitMatrix, BundleLibrarySource, FolderLibrarySource, LibraryGrouping, Music, RebornZuneCore, TileSpan, VariableSpanLayout) still pass within the 55-test run. |

## Signature audit

| Spec | File:line | Match |
| --- | --- | :---: |
| `LightingParameters` 9 stored properties + memberwise init with defaults `light1Intensity=1.3`, `light2Intensity=1.3`, `ambientColor=SIMD3<Float>(0.211, 0.211, 0.211)`, `attenuationScale=1.0e-6` | `LightingParameters.swift:15–47` | ✓ |
| `LightKeyframes` with `PositionKey {progress: Double; position: SIMD3<Float>}`, `ColorKey {progress: Double; color: SIMD3<Float>}`, `positions: [PositionKey]`, `colors: [ColorKey]` | `LightingKeyframes.swift:10–42` | ✓ |
| `func position(at:)`, `func color(at:)` extensions | `LightingKeyframes.swift:44–57` | ✓ |
| `LightingPalette.warm`, `LightingPalette.cool` (and convenience `LightKeyframes.warm`/`.cool`) | `LightingKeyframes.swift:118, 149, 178–180` | ✓ |
| `LightingAnimator(warm:cool:cycleDuration:warmDelay:)` defaults `(warm:.warm, cool:.cool, 120, 0.6)` | `LightingAnimator.swift:14–30` | ✓ |
| `func parameters(at:panelSize:) -> LightingParameters` | `LightingAnimator.swift:36–53` | ✓ |
| `LightingModifier(animator:)`, `func zuneLighting(animator:) -> some View` | `LightingModifier.swift:14–19, 65–67` | ✓ |
| Metal `[[stitchable]] half4 zuneLighting(...)` in spec arg order | `LightingShader.metal:16–29` | ✓ |

## Shader sanity audit

The shader is NOT a stub — `LightingShader.metal:30–54` does:

1. Build `pixelPos = (position.x, position.y, 0)`.
2. For each of two lights, compute `dSq = dot(toLight, toLight)` and
   `falloff = 1 / (1 + dSq * attenuationScale)`.
3. `contrib = lightColor * intensity * falloff`.
4. `totalLight = ambientColor + contrib1 + contrib2`.
5. `output.rgb = currentColor.rgb * totalLight; output.a = currentColor.a`.

This is the spec's behavior verbatim. Distance-based attenuation is real
(uses the squared distance dot product, divides by `1 + d² * scale`),
and the two lights' contributions are summed with the ambient term.

## Palette numeric audit

Hex → RGB recomputed independently from `component / 255`:

Warm:
- `#865c2a` → (0.5255, 0.3608, 0.1647) vs declared (0.525, 0.361, 0.165) — Δ ≤ 0.001
- `#955a21` → (0.5843, 0.3529, 0.1294) vs declared (0.584, 0.353, 0.129) — Δ ≤ 0.001
- `#6c891b` → (0.4235, 0.5373, 0.1059) vs declared (0.424, 0.537, 0.106) — Δ ≤ 0.001
- `#62962c` → (0.3843, 0.5882, 0.1725) vs declared (0.384, 0.588, 0.173) — Δ ≤ 0.001
- `#6c401b` → (0.4235, 0.2510, 0.1059) vs declared (0.424, 0.251, 0.106) — Δ ≤ 0.001

Cool:
- `#81268b` → (0.5059, 0.1490, 0.5451) vs declared (0.506, 0.149, 0.545) — Δ ≤ 0.001
- `#68446c` → (0.4078, 0.2667, 0.4235) vs declared (0.408, 0.267, 0.424) — Δ ≤ 0.001
- `#368843` → (0.2118, 0.5333, 0.2627) vs declared (0.212, 0.533, 0.263) — Δ ≤ 0.001
- `#315b8a` → (0.1922, 0.3569, 0.5412) vs declared (0.192, 0.357, 0.541) — Δ ≤ 0.001
- `#7d2185` → (0.4902, 0.1294, 0.5216) vs declared (0.490, 0.129, 0.522) — Δ ≤ 0.001

All within the 0.01 tolerance the spec calls for.

UWP keyframe positions (with `lightDepth = 200`) cross-checked against
`/Users/yjd/Documents/Reborn-Zune/Reborn-Zune/TilePage.xaml.cs:107–113` (warm)
and `:137–143` (cool) — every (x, y, 200) tuple matches.

## warmDelay clamp behavior

`LightingAnimator.swift:58–65`:

```
static func clampedProgress(time: TimeInterval, cycle: TimeInterval) -> Double {
    if cycle <= 0 { return 0 }
    if time <= 0 { return 0 }
    let wrapped = time.truncatingRemainder(dividingBy: cycle)
    return wrapped / cycle
}
```

The `time` argument is `time - warmDelay`, so for `time < warmDelay` the
helper sees a negative input and returns 0 — i.e. the warm light reads its
`progress=0` keyframe. This matches the spec ("negative progress → clamp
to 0, not wrap"). At `t == warmDelay` the input is exactly 0, still
returns 0; first non-zero progress kicks in for any `t > warmDelay`.
Test `testWarmDelayBoundary` asserts both halves of this behaviour.

## warmDelay spec-vs-source ruling

I re-read `TilePage.xaml.cs:104–162` myself. Both the warm light
(line 114) and the cool / second light (line 145, line 157) set
`DelayTime = TimeSpan.FromMilliseconds(animationDelay)`. So the UWP
original applies the 600 ms delay to both lights — the M4 spec is
slightly inconsistent with the source on this point.

The executor faithfully implemented the **spec's stated semantics**
(warm-only delay, cool starts immediately). M4 §4 is unambiguous about
this — it even names the field `warmDelay` and says "Cool light has no
delay; starts animating immediately." The executor flagged the
discrepancy honestly in the report's "Spec-silent decisions" section.

**Ruling: the executor is correct.** The spec is what was given; the
spec-vs-source disagreement is a mediator/spec-author issue. This is
not rejection grounds for M4.

(For the record, if a future milestone needs the "both lights delayed"
behaviour, it's a one-line change: route both progresses through
`clampedProgress(time: time - delay, ...)`.)

## Independently re-run build/test outputs

### `swift package clean && swift build` (last lines)

```
[1/1] Compiling plugin MetalCompilerPlugin
Building for debugging...
[1/7] Write sources
[2/7] Metal compile LightingShader.metal (macosx)
[3/7] Copying LightingShader.air
[4/7] Metal link default.metallib (macosx)
[5/7] Copying default.metallib
[6/7] Write swift-version--58304C5D6DBC2206.txt
[8/27] Compiling RebornZuneCore LightingModifier.swift
[9/27] Compiling RebornZuneCore LightingParameters.swift
[10/27] Compiling RebornZuneCore TileSpan.swift
... (27 sources total, all compile clean) ...
[28/28] Compiling RebornZuneCore resource_bundle_accessor.swift
Build complete! (5.91s)
```

`grep -i warning` on the full output: zero matches.

### `swift test` (tail)

```
Test Suite 'LightingShaderCompilationTest' started at 2026-05-02 16:19:20.444.
Test Case '-[RebornZuneCoreTests.LightingShaderCompilationTest testZuneLightingFunctionExistsInModuleMetalLibrary]' started.
Test Case '-[RebornZuneCoreTests.LightingShaderCompilationTest testZuneLightingFunctionExistsInModuleMetalLibrary]' passed (0.024 seconds).
Test Suite 'LightingShaderCompilationTest' passed at 2026-05-02 16:19:20.469.
	 Executed 1 test, with 0 failures (0 unexpected) in 0.024 (0.025) seconds
...
Test Suite 'RebornZuneCorePackageTests.xctest' passed at 2026-05-02 16:19:20.476.
	 Executed 55 tests, with 0 failures (0 unexpected) in 0.043 (0.047) seconds
Test Suite 'All tests' passed at 2026-05-02 16:19:20.476.
	 Executed 55 tests, with 0 failures (0 unexpected) in 0.043 (0.048) seconds
```

The shader-compilation test passed in 0.024s — Metal device available, NOT skipped.

### `xcodegen generate`

```
⚙️  Generating plists...
⚙️  Generating project...
⚙️  Writing project...
Created project at /Users/yjd/Documents/Reborn-Zune-Apple/RebornZune.xcodeproj
```

### `xcodebuild RebornZune-macOS -destination 'platform=macOS'` (tail)

```
note: Disabling hardened runtime with ad-hoc codesigning. (in target 'RebornZune-macOS' from project 'RebornZune')
... (CopySwiftLibs, ProcessInfoPlistFile, etc.) ...
** BUILD SUCCEEDED **
```

### `xcodebuild RebornZune-iPadOS -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO` (tail)

```
... (CopyResource RebornZuneCore_RebornZuneCore.bundle into Reborn Zune.app) ...
** BUILD SUCCEEDED **
```

### `xcodebuild RebornZune-tvOS -destination 'generic/platform=tvOS Simulator' CODE_SIGNING_ALLOWED=NO` (tail)

```
... (builtin-swiftStdLibTool ... appletvsimulator ...) ...
** BUILD SUCCEEDED **
```

### `default.metallib` placement after xcodebuild runs

```
.../Build/Products/Debug-appletvsimulator/RebornZuneCore_RebornZuneCore.bundle/default.metallib
.../Build/Products/Debug-iphonesimulator/RebornZuneCore_RebornZuneCore.bundle/default.metallib
.../Build/Products/Debug/RebornZuneCore_RebornZuneCore.bundle/Contents/Resources/default.metallib
.../Build/Products/Debug-appletvsimulator/Reborn Zune.app/RebornZuneCore_RebornZuneCore.bundle/default.metallib
.../Build/Products/Debug-iphonesimulator/Reborn Zune.app/RebornZuneCore_RebornZuneCore.bundle/default.metallib
.../Build/Products/Debug/Reborn Zune.app/Contents/Resources/RebornZuneCore_RebornZuneCore.bundle/Contents/Resources/default.metallib
```

The metallib lands both in the standalone bundle directory (where
`Bundle.module` resolves it for unit tests / tvOS / iOS) and inside each
`.app`'s embedded core bundle (where the apps will pick it up at runtime).

### Plugin escape hatch sanity-check

`Plugins/MetalCompilerPlugin/MetalCompilerPlugin.swift` exists, declares
`@main struct MetalCompilerPlugin: BuildToolPlugin`, walks the target's
source directory for `.metal` files, runs `xcrun metal -c` per file and
`xcrun metallib` once at the end, and selects the SDK from `SDKROOT`
(falling back to `macosx` on plain `swift build`). This is the
documented build-tool plugin pattern, and the produced `default.metallib`
demonstrably appears in the build output for all three platforms — so
the plugin is doing its job.

The decision to use a build-tool plugin is sensible: SwiftPM 6.x as
shipped with Xcode 26.4 does not auto-compile `.metal` source files,
and `process` resource would only copy the .metal source rather than a
metallib. The spec anticipated and authorised this kind of edit
(M4 §6).

## macOS smoke test (visual)

The user requested a launch screenshot of the macOS app. I ran:

1. `xcodebuild ... -showBuildSettings` to locate the build product
   (`~/Library/Developer/Xcode/DerivedData/RebornZune-hiuswkghvbzkeqdhhflynoxuacdz/Build/Products/Debug/Reborn Zune.app`).
2. `open <path>.app` — the app launched. PID 61066 was running for
   2:30 minutes when I sampled with `ps -ax -o pid,etime,command`.
3. `/usr/bin/log show --predicate 'process == "Reborn Zune"' --last 5m`
   returned 149 log lines covering AppKit, SkyLight (window server),
   CoreSpotlight, RunningBoardServices, distributed_notifications, and
   pasteboard XPC connections — i.e. a normal app cold start, no
   sandbox or signing rejection. The app reached "front-process"
   status (`processmanager:front-35286506 CHECKEDIN: pid=61066
   foreground=1 asn=0x0,0xa5fa5f`).
4. **`screencapture` and `osascript "tell System Events"` are blocked
   in this CLI's TCC scope** (Privacy & Security has not granted
   Screen Recording or Accessibility permission to the harness shell).
   Both `screencapture -x out.png` and the window-id approach return
   `could not create image from display` and System Events times out
   with AppleEvent error -1712. This is an environment limitation,
   not an app problem. The screenshots directory at
   `/Users/yjd/Documents/Reborn-Zune-Apple/reports/M4_screenshots/`
   was created but is empty — I'd rather honestly leave it empty than
   fake a screenshot.
5. `kill 61066` cleanly terminated the app.

**Smoke conclusion**: the macOS app *does* launch and reach foreground
on this toolchain — the 149 log lines and 2:30+ minute uptime under
normal AppKit / SkyLight activity are conclusive on that point. The
binding on the visual capture is a host-environment permission gap,
not a milestone failure. M5 visual verification will need to be done
in a less-restricted shell (or by the user manually granting Screen
Recording to whatever runs the evaluator).

EVALUATOR.md says the smoke test exists to confirm "the macOS app
target actually launches on this toolchain" — that has been confirmed
through OS-level logs and process state. M4 itself does not yet
integrate the shader into any app target, so a screenshot would only
show the placeholder "Reborn Zune / macOS — core v0.1.0" label
anyway.

## Regression check (M1–M3)

All 35 pre-existing tests (BitMatrix, BundleLibrarySource,
FolderLibrarySource, LibraryGrouping, Music, RebornZuneCore, TileSpan,
VariableSpanLayout) still pass in the 55-test run. `Package.swift`
remains at `swift-tools-version: 6.0` (no bump). The three xcodebuild
commands still succeed, including the `CODE_SIGNING_ALLOWED=NO` flag
on iPadOS / tvOS Simulator. No M1–M3 source files were modified —
only `Package.swift`, plus new files under `Sources/RebornZuneCore/Views/`,
`Plugins/`, and `Tests/RebornZuneCoreTests/`.

## Issues found

None blocking. One observation:

- **`SwiftPM "unhandled file"` warning suppressed via `exclude:`.**
  This is a fine technique and the executor explained the rationale
  clearly. The downside is that `LightingShader.metal` no longer shows
  up in the SwiftPM-reported source list — but the build-tool plugin
  walks the filesystem directly to find it, so the file is still
  compiled and the metallib still ends up in the bundle. Acceptable.

## Verdict

VERDICT: APPROVED

All 10 acceptance criteria pass. Build is clean, 55 tests pass with
the shader-compilation test running on real Metal (not skipped), all
three xcodebuild targets succeed, the metallib lands in every platform
bundle, the warm/cool palette values match the UWP source within
0.001 of the spec's listed conversions, the warmDelay clamp behaves as
the spec demands, and the macOS app launches successfully on this
toolchain (screen-capture itself was blocked by a TCC permission gap
in the harness, but PID/log evidence is conclusive on launch).

The executor's spec-vs-source flag on the cool light's delay is
correct; they implemented the spec's stated semantics, which is what
was asked. The discrepancy is a spec-author issue and not rejection
grounds.
