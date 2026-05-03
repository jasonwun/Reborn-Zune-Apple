# M5.7 Evaluator R1 — independent verification

## Independent build/test verification

All four canonical commands re-run on a fresh shell session.

| Command | Exit | Tail evidence |
| --- | --- | --- |
| `swift build` | 0 | `Build complete! (0.17s)` — no warning lines emitted (verified by re-running with `grep -i warning\|error`, returned no matches) |
| `xcodegen generate` | 0 | `Created project at .../RebornZune.xcodeproj` |
| `swift test` | 0 | `Executed 91 tests, with 0 failures (0 unexpected) in 4.024 (4.029) seconds` |
| `xcodebuild -scheme RebornZune-macOS -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build` | 0 | `** BUILD SUCCEEDED **` |
| `xcodebuild -scheme RebornZune-iPadOS -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build` | 0 | `** BUILD SUCCEEDED **` |
| `xcodebuild -scheme RebornZune-tvOS -destination 'generic/platform=tvOS Simulator' CODE_SIGNING_ALLOWED=NO build` | 0 | `** BUILD SUCCEEDED **` |

Test count: 91 (≥ 70 threshold). All passing. Executor's report claim of 91
matches my reproduction.

The only emitted "warning" line during xcodebuild was a benign
`appintentsmetadataprocessor`: `Metadata extraction skipped. No
AppIntents.framework dependency found.` This is a system-tool warning, not
a Swift compiler warning, and is unrelated to the codebase.

## Source-code parameter checks (read directly)

| File | Line | Verified |
| --- | --- | --- |
| `Sources/RebornZuneCore/Views/LightingAnimator.swift` | 100 | `static let referencePanelSize: CGSize = CGSize(width: 2300, height: 1300)` exposed via `public extension LightingAnimator` |
| `Sources/RebornZuneCore/Views/LightingAnimator.swift` | 55–59 | `scaleX = Float(panelSize.width / Self.referencePanelSize.width)` and `scaleY = ... height / referencePanelSize.height`. Scaled vectors are `SIMD3<Float>(warmPos.x * scaleX, warmPos.y * scaleY, warmPos.z)` — Z passes through **unscaled**, exactly per spec. |
| `Sources/RebornZuneCore/Views/LightingParameters.swift` | 38, 41 | `light1Intensity: Float = 1.8`, `light2Intensity: Float = 1.8` — bumped from 1.3 |
| `Sources/RebornZuneCore/Views/LightingParameters.swift` | 42 | `ambientColor: SIMD3<Float> = SIMD3<Float>(0.165, 0.165, 0.165)` — unchanged from M5.6 |

Test coverage of these invariants:
- `LightingAnimatorTests.testReferencePanelSizeConstant` — asserts the exact
  `CGSize(2300, 1300)` literal.
- `LightingAnimatorTests.testKeyframesScaleWithPanelSize` — at t=25, halving
  the panel halves both lights' XY (accuracy 0.001) and leaves Z and color
  untouched.
- `LightingAnimatorTests.testDefaultIntensityAndAmbient` — asserts intensity
  1.8 and ambient (0.165, 0.165, 0.165).
- `LightingShaderTests.testParametersDefaultsMatchM56Spec` — also asserts
  intensity 1.8 and ambient 0.165.

All four tests pass in my run.

## Independent screenshot capture

I rebuilt for the concrete sim ids (`9D050E4A-…` iPad Pro 13-inch (M5),
`E0AAFDA7-…` Apple TV 4K (3rd gen)), booted both, installed, launched
both apps simultaneously, recorded the launch unix timestamp
(1777784330), waited until launch+15 s and launch+45 s, and captured PNGs
via `xcrun simctl io … screenshot`. Both sims were shut down post-capture.

Files (saved under `reports/M5_7_evaluator_screenshots/`):
- `/Users/yjd/Documents/Reborn-Zune-Apple/reports/M5_7_evaluator_screenshots/eval_ipados_t15.png`
- `/Users/yjd/Documents/Reborn-Zune-Apple/reports/M5_7_evaluator_screenshots/eval_ipados_t45.png`
- `/Users/yjd/Documents/Reborn-Zune-Apple/reports/M5_7_evaluator_screenshots/eval_tvos_t15.png`
- `/Users/yjd/Documents/Reborn-Zune-Apple/reports/M5_7_evaluator_screenshots/eval_tvos_t45.png`

I read all four myself with vision, and I read the executor's four captures
plus the M5.6 baselines and the three UWP reference frames, for direct
side-by-side comparison.

## Visual comparison paragraphs

### 1. Wash breadth and saturation vs M5.6

The M5.6 iPad baseline (`reports/M5_6_screenshots/ipados_default.png`) is a
predominantly **black wall** with scattered low-saturation dark
maroon/burgundy tiles — no broad colored wash, no clear pool focal point,
roughly 15–20% of the wall carries any visible chroma and that chroma is
muddy. The tvOS M5.6 baseline is similar: dark with isolated dim warm
tiles, no broad lit region. Both **M5.7 evaluator captures** (mine) and
the **executor's M5.7 captures** show a dramatically broader colored
wash spanning a clear majority of the wall — at least 50% of the panel
shows visible warm or olive or magenta light contribution rather than
sitting in near-black. Saturation per tile is also visibly higher: the
amber/olive/magenta colors read as recognisable hues rather than the
muddy desaturated burgundy of M5.6. **PASS**.

### 2. Two distinct colored regions in the warm-phase capture

In the executor's `ipados_t15.png`, the upper-left quadrant is dominated
by a clear **rust-orange/amber warm wash** (warm light at progress ≈
0.12, transitioning toward keyframe-1 amber peak), while the lower-right
shows clear **deep purple/magenta** (cool light contribution) — two
distinct, simultaneously-visible colored regions. In my own
`eval_ipados_t15.png` (captured a few seconds further into the orbit,
since the simctl launch takes a couple of seconds before the first
frame), the warm wash is shifted toward the upper-middle (an amber tile
cluster around the upper-third) while the lower portion shows the cool
light's olive/teal contribution — again two distinct regions. The tvOS
captures show the same two-region pattern at an aspect ratio of 16:9.
Both lights are clearly in-frame and contributing. **PASS**.

### 3. Coverage and saturation vs UWP `overview_002.png` and `overview_011.png`

UWP `overview_002.png` shows a warm-orange wash covering roughly the
**left half** of the wall, fading toward dark on the right. UWP
`overview_011.png` shows a saturated **magenta/purple pool covering the
right half**, fading to dark on the left. UWP `overview_005.png` shows a
subtle olive over the centre. In each UWP frame the lit pool covers
roughly 40–55% of the wall and the colour is recognisable but not
oversaturated — tiles still have visible internal structure.

The M5.7 captures (both executor's and mine) match this character: the
warm pool covers roughly the upper-left to centre region (~40–50% of
the wall), the cool pool is visible elsewhere (~25–30% of the wall),
and tiles retain visible internal grayscale structure under the light.
Coverage and saturation are now in the same range as the UWP
recording. There is one observable difference: the UWP composition
lighting produces a softer, more diffuse falloff than our Lambertian
`dot(N,L)` shader does, so M5.7 pools have slightly harder edges. This
is an architectural trait of Lambertian (per spec, "still using
`dot(N,L)`") and is not a regression — the *coverage and saturation*
levers, which are what M5.7 was changing, now match the reference. **PASS**.

### 4. Color shift between t=15 and t=45 (orbit is animating)

The two iPad captures from the executor's run show an unambiguous shift:
`ipados_t15.png` is **rust-orange dominant with magenta accents**;
`ipados_t45.png` is **olive/yellow-green dominant** with rust-red
patches retreating to the lower left. My own iPad pair shows the same
phenomenon at a slightly later phase: `eval_ipados_t15.png` has olive
already taking over the right side with a warm pocket in the
upper-middle, while `eval_ipados_t45.png` shows a deep red/maroon and
teal mixture as the warm light reaches its later orbit position. The
tvOS pair from both runs shows analogous shifts. Critically: in BOTH
captures of BOTH sims, light contribution is visible across most of the
panel, confirming the panel-size scaling is keeping both lights inside
the visible region throughout the orbit phases sampled. **PASS**.

### 5. Tiles still grayscale (`.saturation(0)` still working)

In every capture, examining the unlit corners (top edges, dark gaps
between bright pools, the bottom corners on iPad, the screen edges on
tvOS) shows tiles fading to **near-black with a faint neutral-grey
ambient** — no rainbow chroma from the synthetic DefaultContent palette
bleeding through. If `.saturation(0)` were broken, the
DefaultContent palette's intentionally varied hues (deep teals, deep
maroons, deep purples, blues) would appear in the unlit regions, but
they read as monotone dark. Where tiles do show colour, the colour is
consistent across neighbouring tiles in a single pool — i.e. it's the
*light* that's colored, not the tile. M5.6's
LightingModifier `.saturation(0)` overlay is intact. **PASS**.

## Per-criterion verification

| # | Criterion | Status | Evidence |
| --- | --- | --- | --- |
| I1 | `LightingAnimator.referencePanelSize == CGSize(2300, 1300)` | verified | `LightingAnimator.swift:100`; `testReferencePanelSizeConstant` passes |
| I2 | `parameters(at:panelSize:)` scales XY by `panelSize / referencePanelSize` | verified | `LightingAnimator.swift:55–59`: scaleX = `Float(panelSize.width / Self.referencePanelSize.width)`, applied to both warm and cool XY. `testKeyframesScaleWithPanelSize` asserts `half == full/2` at half-panel, accuracy 0.001 |
| I3 | Z component is NOT scaled by panelSize | verified | `LightingAnimator.swift:58–59`: `SIMD3<Float>(warmPos.x * scaleX, warmPos.y * scaleY, warmPos.z)` — Z passed through unchanged. Test asserts `half.z == full.z`. |
| I4 | `LightingParameters.init` defaults: intensity 1.8, ambient unchanged | verified | `LightingParameters.swift:38, 41` (`light1Intensity: Float = 1.8`, `light2Intensity: Float = 1.8`); ambient still `(0.165, 0.165, 0.165)` at line 42. Two tests assert these values. |
| I5 | `swift build` clean, no warnings | verified | exit 0; grep for warning/error in build output returned no matches |
| I6 | `swift test` passes, ≥ 70 tests, 0 failures | verified | exit 0; `Executed 91 tests, with 0 failures (0 unexpected)` (91 ≥ 70) |
| I7 | All 3 xcodebuild commands succeed | verified | macOS, iPadOS-generic, tvOS-generic all `** BUILD SUCCEEDED **` (and the two concrete-sim builds for screenshots also succeeded) |
| I8 | iPad sim screenshot at t≥12 s shows visibly broader and more saturated wash than M5.6 | verified | Both my `eval_ipados_t15.png` and the executor's `ipados_t15.png` show wash covering ~half the wall with warm + cool both visible, vs M5.6's mostly-black wall with isolated dim tiles. See visual paragraphs 1–3. |
| I9 | Two screenshots ~30 s apart show clearly different colored regions | verified | Executor pair: rust-orange dominant → olive-green dominant. My pair: warm-pocket-with-emerging-olive → deep red/maroon mixture. Both show unambiguous orbit progression. See visual paragraph 4. |
| I10 | tvOS sim screenshot shows similar improvement | verified | Both my `eval_tvos_t15.png` and the executor's `tvos_t15.png` show broad wash covering most of the 16:9 wall, in contrast to M5.6 tvOS's narrow centre-right pool. The 30 s shift to olive-dominated is also visible on tvOS. |

## Regressions check

- M5.6 `.saturation(0)` overlay: intact (visual paragraph 5).
- `LightingPalette.warm` and `LightingPalette.cool` keyframes: not modified
  (executor confirms; spot-checked source).
- `LightingParameters` field count: `testParametersStoredFieldCount` still
  asserts `mirror.children.count == 8`, and that test passes — no fields
  added or removed.
- `attenuationScale` removal from M5.6: still removed (no field, no shader
  parameter).
- 600 ms start delay applied to both lights (M5 fix): preserved; existing
  `testStartDelayHoldsBothLights` and `testParametersAtStartDelayBoundary`
  pass.
- All earlier milestones' tests (TileEntryAnimator, TileFlipAnimator,
  TileLighting, VariableSpanLayout, etc.) still pass within the 91-test run.

No regressions found.

## Notes

- The executor's report is honest about all the spec-silent decisions
  (test fixture switched to `referencePanelSize`, two distinct
  test names, screenshot timing). All are reasonable; I would have
  made the same calls.
- My own captured screenshots show a slightly different phase than the
  executor's for a given `t`. This is expected: the launch-to-first-frame
  latency varies by a few seconds across runs, putting us at slightly
  different points on the 120 s cycle. The behaviour shown — broad
  wash, two-light coverage, color shifting between captures, grayscale
  tiles — is consistent across both runs.

## Verdict

VERDICT: APPROVED
