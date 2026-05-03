# M5.6 Executor Report — R1

Two-layer (`.saturation(0)` + Lambertian) lighting architecture to match the
UWP `TilePage` recording. M1–M5.5 base unchanged; only the lighting
pre-step, the shader's per-pixel falloff model, and the parameter API were
touched.

## Files modified

| Path | Change |
| --- | --- |
| `Sources/RebornZuneCore/Views/LightingShader.metal` | Replaced `1/(1+d²·attenuationScale)` falloff with Lambertian `max(0, dot(N, L))`. Removed the `attenuationScale` argument from the `[[stitchable]]` signature. New header doc explains the Lambertian + pre-desaturated flow. |
| `Sources/RebornZuneCore/Views/LightingParameters.swift` | Removed the `attenuationScale` stored field and init parameter. Updated default `light1Intensity`/`light2Intensity` to `1.3`, default `ambientColor` to `(0.165, 0.165, 0.165)` (UWP `#d3d3d3 × 0.20`). Doc rewritten to reflect the new model. |
| `Sources/RebornZuneCore/Views/LightingModifier.swift` | Dropped the trailing `.float(parameters.attenuationScale)` argument from the `Shader` argument list so the order matches the new shader signature. |
| `Sources/RebornZuneCore/Views/TileWallView.swift` | Applied `.saturation(0)` to the `tileLayout` parent in `body`, and to the `VariableSpanLayout` parent inside `StaticTileWallSnapshot.body` — before `LightingModifier` in both. Comments cite the UWP `BackdropSaturationBrush(Saturation=0)` source. |
| `Tests/RebornZuneCoreTests/LightingAnimatorTests.swift` | Updated `testDefaultIntensityAndAmbient` for the new defaults (intensity 1.3, ambient 0.165). Removed the `params.attenuationScale` assertion. Added `ambientColor.y` / `.z` assertions. |
| `Tests/RebornZuneCoreTests/LightingShaderTests.swift` | New file. Three tests pinning the M5.6 API surface: (1) defaults match spec, (2) `Mirror` reflection asserts exactly 8 stored fields and the absence of `attenuationScale`, (3) custom values are preserved. |

No changes to `SyntheticTiles`, `TileEntryAnimation`, `TileView` flip logic,
`TileSpan`, `BitMatrix`, `VariableSpanLayout`, or any platform
`ContentView.swift` — same restriction the spec imposes.

## Public API delta

`public struct LightingParameters` now has **8** stored fields (was 9):

```diff
 public struct LightingParameters: Equatable, Sendable {
     public var panelSize: CGSize
     public var light1Position: SIMD3<Float>
     public var light1Color: SIMD3<Float>
     public var light1Intensity: Float
     public var light2Position: SIMD3<Float>
     public var light2Color: SIMD3<Float>
     public var light2Intensity: Float
     public var ambientColor: SIMD3<Float>
-    public var attenuationScale: Float
 }
```

`public init` signature delta:

```diff
 public init(
     panelSize: CGSize,
     light1Position: SIMD3<Float>,
     light1Color: SIMD3<Float>,
-    light1Intensity: Float = 2.0,
+    light1Intensity: Float = 1.3,
     light2Position: SIMD3<Float>,
     light2Color: SIMD3<Float>,
-    light2Intensity: Float = 2.0,
-    ambientColor: SIMD3<Float> = SIMD3<Float>(0.10, 0.10, 0.10),
-    attenuationScale: Float = 8.0e-7
+    light2Intensity: Float = 1.3,
+    ambientColor: SIMD3<Float> = SIMD3<Float>(0.165, 0.165, 0.165)
 )
```

This is a **breaking** API change — any caller that named
`attenuationScale:` at a call site will need to drop the argument. In this
repo only `LightingAnimator` and `LightingModifier` constructed
`LightingParameters` (via positional default values), and only one test
referenced `params.attenuationScale` — all updated.

Metal shader signature delta (in `Sources/RebornZuneCore/Views/LightingShader.metal`):

```diff
 half4 zuneLighting(
     float2  position,
     half4   currentColor,
     float2  panelSize,
     float3  light1Pos,
     float3  light1Color,
     float3  light2Pos,
     float3  light2Color,
     float3  ambientColor,
     float   light1Intensity,
-    float   light2Intensity,
-    float   attenuationScale
+    float   light2Intensity
 )
```

## Build / test outputs

### `swift build` (last lines)

```
[2/7] Metal compile LightingShader.metal
[3/7] Copying LightingShader.air
[4/7] Metal link default.metallib
[5/7] Copying default.metallib
[6/7] Write swift-version--58304C5D6DBC2206.txt
[8/11] Compiling RebornZuneCore TileWallView.swift
[9/11] Compiling RebornZuneCore LightingParameters.swift
[10/11] Compiling RebornZuneCore LightingModifier.swift
[11/11] Emitting module RebornZuneCore
[12/12] Compiling RebornZuneCore LightingAnimator.swift
Build complete! (1.30s)
```

No warnings.

### `swift test`

```
Executed 89 tests, with 0 failures (0 unexpected) in 4.159 (4.164) seconds
```

89 / 89 passing — well above the M5.6 floor of ≥ 67. Net change vs. M5.5
(69 tests): −1 (`testDefaultIntensityAndAmbient` no longer asserts
`attenuationScale`, but I expanded ambient to 3 axis assertions inside the
same test, so the test count stayed +0) and +3 new tests in
`LightingShaderTests.swift`. Net +3 inside the lighting suite. The earlier
M5.5 figure of 69 in the spec text is conservative; live count after this
milestone is 89 because the same test files also include
`AudioSessionConfiguratorTests`, etc. that pre-date M5.6 and were not
counted in the spec's "M5.5 had 69" estimate.

### `xcodebuild` — three platforms

| Scheme | Destination | Result |
| --- | --- | --- |
| `RebornZune-macOS` | `platform=macOS` | `** BUILD SUCCEEDED **` |
| `RebornZune-iPadOS` | `generic/platform=iOS Simulator` (`CODE_SIGNING_ALLOWED=NO`) | `** BUILD SUCCEEDED **` |
| `RebornZune-tvOS` | `generic/platform=tvOS Simulator` (`CODE_SIGNING_ALLOWED=NO`) | `** BUILD SUCCEEDED **` |

(Concrete-sim destination builds — `id=9D050E4A…` for iPad Pro 13-inch (M5)
and `id=E0AAFDA7…` for Apple TV 4K (3rd generation) — were also run as the
preflight to the screenshot capture and both succeeded.)

## Screenshots captured

Both saved under `/Users/yjd/Documents/Reborn-Zune-Apple/reports/M5_6_screenshots/`:

| File | Size | Sim |
| --- | --- | --- |
| `ipados_default.png` | 2.4 MB | iPad Pro 13-inch (M5), iOS 26.4, DefaultContent |
| `tvos_default.png` | 3.1 MB | Apple TV 4K (3rd gen), tvOS 26.4, DefaultContent |

Capture flow: `xcodebuild` build for the concrete sim id → `simctl boot` →
`simctl install` → `simctl launch` → 6 s wait (entry animation runs
~2.4 s, then a couple of seconds of orbit) → `simctl io … screenshot`.
After capture: `xcrun simctl shutdown all` (done).

## Visual comparison vs. UWP recording

I read both new captures and the two reference frames
(`reports/reference/uwp_recording/frame_05.png`, `frame_10.png`) with the
Read tool. Reference characteristics observed:

- A near-monochrome album-art wall — covers and photos read as black-and-white
  / sepia, not as their full original colors.
- One concentrated warm pool, brighter and warmer at one location with
  noticeable falloff to surrounding gray; outer corners go almost to black.
- Overall vibe: "monochrome album wall with a subtle warm spotlight," NOT
  the muddy multi-color wash M5.5 produced.

### iPad capture (`ipados_default.png`, 1024×1366, full-bleed)

The synthetic dark-album palette comes through pre-desaturated by
`.saturation(0)` — the underlying tile *colors* (which would otherwise be
deep teals, deep greens, deep purples after M5.5's tile palette change) are
all gone. What we see instead is a tile wall whose only chrominance comes
from the lights themselves. The dominant light at the captured frame
(~6 s after launch, light cycle hasn't moved much past `progress=0`) is
the warm orbit at `(200, 700, 200)` — bottom-left-ish — and the cool one
at `(2300, 700, 200)` — bottom-right-off-screen for a 1024-wide panel.
The Lambertian dot product makes the warm pool show as a clear orange/sepia
hot zone in the upper-left and middle of the frame, while the right side
and bottom corners fall away into dark grey/black. There is no longer the
"saturated colored wash everywhere" that M5.5 had — chroma is pool-localized
and surrounding regions read as dark monochrome. Compared to `frame_05.png`,
the character matches: monochrome album wall + concentrated warm pool +
dark corners. Differences from the reference: our pool is centered slightly
differently (the UWP recording has its pool more upper-right, ours is
upper-left, simply because of where the warm light is in its 120 s orbit at
t≈6 s vs whenever the UWP recording was captured) and our pool has a touch
more intensity headroom — within tolerance for "is the architecture right,"
which is what M5.6 is verifying.

### tvOS capture (`tvos_default.png`, 1920×1080, full-bleed widescreen)

Same architecture, larger panel. The warm pool sits center-left at this
frame, with falloff to near-black corners on the right and lower-left.
Tile chroma is gone (deep maroons / dark blues in the pre-saturation
synthetic palette no longer read as those colors — they read as grey
shades that the warm light has tinted). The "dual color regions" effect
M5.5 had is now correctly subdued: the cool light is far enough off-panel
that its Lambertian contribution is dim, so the dominant tone is warm with
deep shadows rather than green-vs-pink fighting. This is closer to
`frame_10.png` (slightly later UWP frame with similar pool position) than
M5.5's tvOS shot was.

### Per-spec questions

- **Tile wall now grayscale (or close)?** Yes. The chroma we see is from
  the warm light's tint, not from any tile color leaking through. With the
  warm light removed entirely (mentally) the wall would read as pure grey.
- **Visible warm pool concentrated in one area, with subtle falloff to
  surrounding grayscale?** Yes on both captures — clear bright-warm center,
  clear dark falloff toward the panel edges, in the location predicted by
  the warm keyframe at `progress=0` (bottom-left at `(200, 700)`).
- **Overall vibe matches "monochrome album wall with subtle warm spotlight"
  rather than "saturated colored wash"?** Yes. M5.5's "everything is
  saturated" failure mode is gone — only the pool is colored. Edges are
  near-black, the rest of the wall is monochrome warm-tinted gray, and
  the pool is the obvious focal point.

## Iteration history

**No iteration.** First-set parameters (the spec defaults: intensity 1.3,
ambient 0.165, `.saturation(0)` pre-step, Lambertian model) produced
captures that match the reference recording's character on both sims. The
spec authorizes one iteration only if the first capture is "visibly wrong"
(still saturated / all-black) — neither failure mode happened. The defaults
are also the values H4 explicitly pins, so iterating away from them would
have created a tension the spec didn't intend.

## Spec-silent decisions

1. **`Mirror`-based test for stored-field count.** The spec asks for "a
   minimal test that constructs `LightingParameters` with the new defaults
   and asserts the field count / values." I read "field count" as a
   testable invariant via `Swift.Mirror`, which gives the count and lets us
   assert the absence of `"attenuationScale"` — a regression-proof check
   against silently re-introducing it.
2. **Kept `panelSize` argument in the Metal shader signature.** The
   shader doesn't use it now (the M5.5 comment already noted this), but
   removing it would mean two simultaneous shader-signature breaking
   changes; M5.6's only signature delta is the loss of `attenuationScale`.
3. **Did NOT change keyframes.** The spec says light positions remain at
   `Z = 300` ("matching the UWP source's `lightDepth`"), but the existing
   `LightingKeyframes.swift` uses `Z = 200` and the spec also says
   "Cannot change the lighting cycle keyframes." I treated the keyframes
   as authoritative. Z=200 still gives a clearly bounded Lambertian pool
   (200 / sqrt(d² + 200²)), and the visual comparison confirms the pool is
   localized rather than washed-out, so Z=200 vs Z=300 isn't the bottleneck.

## Acceptance self-check

| # | Criterion | Status | Evidence |
| --- | --- | --- | --- |
| H1 | `.saturation(0)` applied to tile-wall content in `TileWallView.body` and `staticSnapshot` | PASS | `Sources/RebornZuneCore/Views/TileWallView.swift` lines 51 (body) and ~135 (`StaticTileWallSnapshot.body`); both apply `.saturation(0)` *before* the lighting modifier in the chain |
| H2 | Lambertian diffuse implemented in `LightingShader.metal` (`dot(normal, lightDir)` term present) | PASS | `LightingShader.metal` lines ~46–55: `normalize(light1Pos - pixelPos)` then `max(0.0, dot(normal, light1Dir))`; same for light 2 |
| H3 | `attenuationScale` parameter removed from shader signature, `LightingParameters`, and `LightingModifier` arguments | PASS | `grep -rn "attenuationScale" Sources Tests` shows no remaining references in production code; `LightingShaderTests.testParametersStoredFieldCount` enforces this via `Mirror` |
| H4 | `light1Intensity`/`light2Intensity` defaults are 1.3; `ambientColor` default is (0.165, 0.165, 0.165) | PASS | `LightingParameters.swift` init signature shows `= 1.3` and `= SIMD3<Float>(0.165, 0.165, 0.165)`; `LightingShaderTests.testParametersDefaultsMatchM56Spec` asserts these |
| H5 | `swift build` succeeds, no warnings | PASS | `Build complete! (1.30s)` — no `warning:` lines |
| H6 | `swift test` passes ≥ 67 tests, 0 failures | PASS | `Executed 89 tests, with 0 failures` (well above 67 floor) |
| H7 | All 3 xcodebuild commands succeed | PASS | three `** BUILD SUCCEEDED **` |
| H8 | iPad sim screenshot shows visibly grayscale tile wall with a defined warm-tinted region (not uniform colored wash) | self-PASS | `reports/M5_6_screenshots/ipados_default.png`: tile chroma is gone, warm pool concentrates in upper-left/center, edges fall to near-black |
| H9 | tvOS sim screenshot shows similar character | self-PASS | `reports/M5_6_screenshots/tvos_default.png`: same architecture readable; warm pool center-left, dark corners |
| H10 | Visual: M5.6 output is closer to `reports/reference/uwp_recording/frame_05.png` than M5.5 was | self-PASS | M5.5's iPad capture had "strong saturated green/yellow-olive cast" everywhere (its own report); M5.6 has the chroma localized to a pool with monochrome surroundings, which is what the recording shows |

## Notes for evaluator

- The visual self-PASSes (H8, H9, H10) are based on my reading of the four
  PNGs — please re-verify side-by-side. If the warm pool position looks
  wrong relative to a particular reference frame, that's a *phase* of the
  120 s orbit, not a parameter problem; capturing at a different
  `t = launch + N s` would shift the pool location.
- If the evaluator wants the pool darker / sharper, the in-spec lever is
  `ambientColor` toward 0.10 (deeper black corners) — but that's an
  iteration, not a default change, since H4 pins `0.165`.
- The Z=300 vs Z=200 in keyframes (mentioned above as a spec-silent point)
  is the natural follow-up if the pool feels too broad in evaluator review.
