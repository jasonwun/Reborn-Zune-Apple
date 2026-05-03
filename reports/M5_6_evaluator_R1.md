# M5.6 Evaluator Report — R1

Independent verification of the M5.6 deliverables (two-layer architecture +
Lambertian lighting). The user supplied a recording of the original UWP
`TilePage` showing the real target visual: monochrome album wall with a
subtle warm spotlight pool — a complete reframing relative to M5.5's
"saturated colored wash" target.

## Source-code parameter checks

### `LightingShader.metal` (Lambertian, no `attenuationScale`)

`Sources/RebornZuneCore/Views/LightingShader.metal` — verified by reading lines 24–60:

- `[[stitchable]] half4 zuneLighting(...)` signature now takes 10
  arguments: `position`, `currentColor`, `panelSize`, `light1Pos`,
  `light1Color`, `light2Pos`, `light2Color`, `ambientColor`,
  `light1Intensity`, `light2Intensity`. **No `attenuationScale` argument.**
- Both lights compute Lambertian diffuse:
  `dot(normal, normalize(lightPos - pixelPos))` with `normal = (0, 0, 1)`,
  clamped at `max(0.0, ...)`. Output is `currentColor.rgb * (ambient +
  contrib1 + contrib2)`. Matches the spec body verbatim.

H2 PASS, H3 PASS (shader side).

### `LightingParameters.swift`

`Sources/RebornZuneCore/Views/LightingParameters.swift` — verified:

- Struct fields: `panelSize, light1Position, light1Color, light1Intensity,
  light2Position, light2Color, light2Intensity, ambientColor` — **8
  stored fields, no `attenuationScale`**.
- `init` defaults: `light1Intensity: Float = 1.3`,
  `light2Intensity: Float = 1.3`,
  `ambientColor: SIMD3<Float> = SIMD3<Float>(0.165, 0.165, 0.165)`.

H4 PASS, H3 PASS (params side).

### `LightingModifier.swift`

`Sources/RebornZuneCore/Views/LightingModifier.swift` — `Shader.Argument`
list now passes panelSize, two `light{N}Position`s as `.float3`, two
`light{N}Color`s as `.float3`, ambient as `.float3`, two `.float`
intensities — 8 trailing arguments matching the new shader signature
order. **No `parameters.attenuationScale` reference.**

H3 PASS (modifier side).

### `TileWallView.swift` — `.saturation(0)` placement

`Sources/RebornZuneCore/Views/TileWallView.swift`:

- Live `body` (line 53–55): `tileLayout.saturation(0).modifier(OptionalLightingModifier(...))`
  — saturation is applied to the layout, then the lighting modifier
  wraps that.
- `StaticTileWallSnapshot.body` (line 136–148): `VariableSpanLayout {...}.saturation(0)`,
  then `LightingModifier.applyShader(to: layout, ...)` is invoked on the
  desaturated layout.

Both paths: saturation comes before lighting. H1 PASS.

### `attenuationScale` cleanup

`grep -rn "attenuationScale" Sources Tests` returns 6 hits — all in doc
comments (explaining its removal) or in `LightingShaderTests.swift` /
`LightingAnimatorTests.swift` lines that explicitly assert the field's
absence (regression tests). No live code references. Clean removal.

## Build/test outputs

### `swift build`

```
[0/1] Planning build
[1/1] Compiling plugin MetalCompilerPlugin
Building for debugging...
[1/2] Write swift-version--58304C5D6DBC2206.txt
Build complete! (0.18s)
```

Exit 0, no `warning:` lines. H5 PASS.

### `swift test`

```
Executed 89 tests, with 0 failures (0 unexpected) in 4.121 (4.126) seconds
Test Suite 'All tests' passed at 2026-05-02 19:09:05.674.
```

89 tests, 0 failures, well above the ≥67 floor. H6 PASS.

`LightingShaderTests` (new, 3 cases) was inspected — substantive: pins
default values, uses `Mirror` to enforce 8-stored-field invariant + assert
absence of `attenuationScale`, and checks custom-value preservation.

### `xcodegen generate`

```
⚙️  Generating plists...
⚙️  Generating project...
⚙️  Writing project...
Created project at /Users/yjd/Documents/Reborn-Zune-Apple/RebornZune.xcodeproj
```

### `xcodebuild` × 3

| Scheme | Destination | Result |
| --- | --- | --- |
| `RebornZune-macOS` | `platform=macOS` | `** BUILD SUCCEEDED **` |
| `RebornZune-iPadOS` | `generic/platform=iOS Simulator` (`CODE_SIGNING_ALLOWED=NO`) | `** BUILD SUCCEEDED **` |
| `RebornZune-tvOS` | `generic/platform=tvOS Simulator` (`CODE_SIGNING_ALLOWED=NO`) | `** BUILD SUCCEEDED **` |

All three green. H7 PASS.

## Visual verification — independent re-capture

I built the iPadOS app for `iPad Pro 13-inch (M5)` (`9D050E4A-...`) and the
tvOS app for `Apple TV 4K (3rd generation)` (`E0AAFDA7-...`), booted both,
installed, launched, waited 6 s for the entry animation to settle, and
captured. Saved to `reports/M5_6_evaluator_screenshots/ipados_eval.png`,
`ipados_eval_t2.png` (+8 s later, to confirm orbit movement), and
`tvos_eval.png`.

### iPad capture — `reports/M5_6_evaluator_screenshots/ipados_eval.png`

The wall reads as **predominantly dark monochrome**: tiles are charcoal,
near-black, with localized warm-orange and dull-red spotlight regions in
the centerish-right area, and a faint cool teal hint at the very upper-left
corner (the cool light's contribution is mostly off-panel as expected for
a light at `(2300, 700, 200)` over a 1024-wide layout). Saturation is
clearly stripped from the underlying tile palette — the M5.5 deep teals,
deep greens, and olive yellows are absent. The chroma we do see is the
warm light tinting otherwise-gray tiles, exactly the architecture the spec
mandates. Outer edges and a large fraction of the central area read as
near-black, which matches the UWP reference's dark-corner falloff.

### iPad t+8 s capture — `reports/M5_6_evaluator_screenshots/ipados_eval_t2.png`

Captured 8 s later to verify the lighting orbit. The pool position has
shifted: a small bright olive-yellow pool now sits at the lower-middle,
the cool light has crept further onto the panel and produced a subtle
teal/blue cast in some upper-area tiles, and the warm pool has dimmed.
This confirms (a) the animation is running, (b) the lights move smoothly,
(c) the desaturation is consistent across orbit phases — the wall stays
monochrome and the chroma is always pool-localized.

### tvOS capture — `reports/M5_6_evaluator_screenshots/tvos_eval.png`

Same architecture in 1920×1080 widescreen. Warm pool concentrates in the
center-left to lower-center area as a dull orange cast on near-black
tiles; the right third falls into deep black; a very subtle cool teal
tint shows in the upper-left corner from the cool light. No saturated
rainbow wash anywhere on the panel.

## Per-spec written comparison (vs UWP reference)

**1. Tile wall mostly grayscale?**
Yes. Looking at any individual tile across either capture, color comes
exclusively from the tinting light's contribution; the underlying tile
chrominance has been removed. Tiles outside the warm pool read as pure
charcoal/black. H8/H9 grayscale aspect: PASS.

**2. Defined warm pool concentrated in one region with surrounding gray/dark?**
Yes. iPad shows a warm pool in the upper-center and middle-right with
falloff to near-black at panel edges; tvOS shows a warm pool in the
center-left fading to black on the right. Compare to UWP `frame_03.png`
which has its pinkish/warm pool more on the right, `frame_05.png` with the
warm pool spread across the panel, and `frame_10.png` with a different
warm pool position — each UWP frame shows a different orbit phase, and
M5.6's captures show the same character of one warm region + dark
surroundings. The pool position differing between UWP frames and our
captures is just orbit phase, not a structural mismatch. H8/H9 pool aspect: PASS.

**3. Reads as "monochrome album wall with subtle colored spotlight" rather than "saturated rainbow wash"?**
Yes, unambiguously. M5.5's screenshots literally looked like saturated
rainbow tile sets (greens / teals / olives / maroons everywhere); M5.6's
screenshots look like a dark monochrome wall with a sepia/orange tint
zone. Identical character to the UWP reference. PASS.

**4. M5.6 visibly closer to UWP reference than M5.5 was?**
Yes — the delta is dramatic. M5.5 looked like the wrong app entirely
(saturated colored synthetic tiles dominating the frame); M5.6 looks
like a port of the UWP `TilePage`. H10 PASS.

**5. Critique — anything still off (for fast-follow tuning)?**

- The wall in M5.6 captures runs slightly darker overall than the UWP
  recording. UWP frames have a more pronounced warm pool brightness against
  the dark surroundings — a clearer focal "spotlight." M5.6's pool is
  subtler. This is most likely either (a) `Z=200` in the keyframes
  (executor flagged this in their report; spec text mentions Z=300 for
  `lightDepth`, and switching to Z=300 would broaden each light's pool);
  or (b) a touch more `light{N}Intensity` headroom. The spec hard-pins
  intensity 1.3 and ambient 0.165 (H4), and locks keyframes, so the
  authorized in-spec lever is `Z` in the keyframes — which is technically
  outside H4's intensity/ambient defaults but inside "natural pool
  falloff" tuning. Recommend a fast-follow M5.7 to evaluate Z=300 vs Z=200
  side-by-side against the UWP recording.
- The "warm pool" in our iPad capture at t≈6 s is more diffused across
  the wall than UWP's tighter pool. Same root cause likely (Z value).
- `panelSize` is still in the shader signature but unused (the executor
  noted this and kept it in to avoid a second simultaneous signature
  break). Acceptable.

These are tuning issues, not structural failures. The spec explicitly
allows for "looks fundamentally right but somewhat too dark / too bright"
to be approved with a critique note.

## Side-by-side written comparison summary

| Frame | M5.5 character | M5.6 character | UWP reference character |
| --- | --- | --- | --- |
| iPad | Saturated yellow-green / olive wall, dominant lit-from-everywhere look | Dark monochrome wall with warm pool concentrated upper-mid/right, near-black corners | Monochrome album photos with warm/sepia spotlight pool, dark corners |
| tvOS | Saturated rainbow grid (red, teal, purple, yellow, green tiles) | Dark monochrome wall with warm pool center-left, subtle cool tint upper-left, deep black right side | Same as iPad reference, widescreen aspect |

For both platforms, M5.6 matches the UWP character class (monochrome +
warm pool + dark falloff) while M5.5 was in a different class entirely
(saturated rainbow). The architectural fix (`.saturation(0)` pre-step +
Lambertian lighting + intensity/ambient retune) is correct and visible in
the output.

## Per-criterion verification table

| # | Criterion | Status | Evidence |
| --- | --- | --- | --- |
| H1 | `.saturation(0)` applied in `body` and `staticSnapshot` before lighting | PASS | `TileWallView.swift:53` (body) and `:142` (`StaticTileWallSnapshot.body`) — both apply saturation to the layout view before chaining into the lighting modifier |
| H2 | Lambertian diffuse `dot(normal, lightDir)` in shader | PASS | `LightingShader.metal:47–48` and `:52–53` — `normalize(lightPos - pixelPos)` then `max(0.0, dot(normal, lightDir))` for both lights |
| H3 | `attenuationScale` removed from shader, params, modifier | PASS | Shader signature has 10 args (no attenuation); `LightingParameters` has 8 stored fields (Mirror count test enforces); `LightingModifier` `Shader.Argument` list has no attenuation `.float`; grep over `Sources Tests` confirms no live references |
| H4 | Defaults: intensity 1.3, ambient (0.165, 0.165, 0.165) | PASS | `LightingParameters.swift:36–40` shows the default values; `LightingShaderTests.testParametersDefaultsMatchM56Spec` asserts them |
| H5 | `swift build` green, no warnings | PASS | `Build complete! (0.18s)`, no `warning:` lines |
| H6 | `swift test` ≥ 67, 0 failures | PASS | 89 tests, 0 failures |
| H7 | All 3 xcodebuild commands succeed | PASS | three `** BUILD SUCCEEDED **` (macOS, iPadOS Simulator, tvOS Simulator) |
| H8 | iPad screenshot shows grayscale wall with defined warm-tinted region | PASS | `ipados_eval.png` (independent re-capture): tile chroma stripped, warm pool concentrated mid-right, falloff to black; matches UWP `frame_03/05/10` character |
| H9 | tvOS screenshot shows similar character | PASS | `tvos_eval.png` (independent re-capture): same monochrome + warm pool + dark falloff structure on widescreen panel |
| H10 | M5.6 visually closer to UWP reference than M5.5 | PASS | M5.5 was a saturated rainbow grid (different visual class); M5.6 reads as the same class as the UWP reference. Side-by-side comparison decisive |

## Regression check

- M5/M5.5 entry animations: still run (verified by waiting 6 s post-launch
  and observing the static settled state, which means the entry animation
  ran to completion).
- Tile flips: independent re-capture at t+8 s differs from t+0, with both
  the lighting orbit AND tile content slightly varying — confirming
  per-tile flip animation is still active.
- `LightingAnimator` keyframes: untouched per spec.
- `SyntheticTiles`: untouched per spec.
- All 89 tests pass — no test regression vs M5.5's count.

## Notes for the next milestone

- The "pool a bit too diffused / wall a bit too dark" critique above
  suggests testing keyframe `Z = 300` (what the spec says lightDepth is in
  the UWP source) vs the existing `Z = 200`. This is a single-line change
  in `LightingKeyframes.swift` and would likely tighten the pool's "hot
  spot" appearance closer to the UWP recording. Could be a fast-follow.
- `panelSize` is still passed to the shader but unused. Future cleanup
  (one-line shader signature change) when there's another reason to
  recompile the shader.

## Final verdict

The M5.6 deliverables are all in place and verified. The visual change
relative to M5.5 is exactly the right direction — from "saturated
multi-color wash" to "monochrome album wall with subtle warm spotlight,"
matching the UWP recording's character on both platforms. Build, test,
and xcodebuild commands are all green. There are minor tuning notes
(slightly too dark / pool slightly too diffuse) which the spec explicitly
authorizes as approve-with-critique material.

VERDICT: APPROVED — character match achieved on iPad and tvOS; minor
darkness/pool-tightness tuning recommended as fast-follow (try Z=300 in
`LightingKeyframes.swift`).
