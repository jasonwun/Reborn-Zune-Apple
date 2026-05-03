# M5.7 Executor R1 — panel-size scaling + intensity 1.3 → 1.8

A small follow-up tuning pass after a second UWP recording revealed M5.6's
wash was too narrow and too dim. Two surgical fixes per spec:

1. Scale the UWP keyframe X/Y values from their reference 2300×1300 panel
   to the actual render panel size, so the orbit stays inside the visible
   region on iPad (~1180 px wide) and tvOS (1920 px).
2. Bump default `light1Intensity` / `light2Intensity` from 1.3 to 1.8 so
   the Lambertian-falloff pool covers more of the wall, matching the
   ~50% coverage observed in `overview_002.png`.

No other files touched. Shader, saturation overlay, keyframe values, and
all app targets unchanged.

## Files modified

| Path | Change |
| --- | --- |
| `Sources/RebornZuneCore/Views/LightingAnimator.swift` | Added `static let referencePanelSize = CGSize(width: 2300, height: 1300)` extension. `parameters(at:panelSize:)` now multiplies the interpolated warm/cool XY by `panelSize / referencePanelSize`; Z is left alone. Added doc comment explaining the rationale. |
| `Sources/RebornZuneCore/Views/LightingParameters.swift` | `light1Intensity` / `light2Intensity` defaults: `1.3` → `1.8`. Doc comment updated to call out the deviation from UWP source and the reason. |
| `Tests/RebornZuneCoreTests/LightingAnimatorTests.swift` | Changed test fixture `panel` from `1920×1080` to `LightingAnimator.referencePanelSize` (2300×1300) so existing absolute-XY assertions still hold (scale = 1.0). Added `testReferencePanelSizeConstant` and `testKeyframesScaleWithPanelSize`. Updated `testDefaultIntensityAndAmbient` to assert `1.8` not `1.3`. |
| `Tests/RebornZuneCoreTests/LightingShaderTests.swift` | Updated `testParametersDefaultsMatchM56Spec` to assert intensity `1.8`. |

## Public API delta (vs M5.6)

| Symbol | Before | After |
| --- | --- | --- |
| `LightingAnimator.referencePanelSize` | (did not exist) | `static let CGSize = CGSize(width: 2300, height: 1300)` |
| `LightingParameters.init(...).light1Intensity` default | `1.3` | `1.8` |
| `LightingParameters.init(...).light2Intensity` default | `1.3` | `1.8` |
| `LightingAnimator.parameters(at:panelSize:)` signature | unchanged | unchanged |
| `LightingAnimator.parameters(at:panelSize:)` semantics | returns raw keyframe XY at the reference scale | returns keyframe XY scaled by `panelSize / referencePanelSize`; Z unscaled |

`ambientColor` default unchanged. `attenuationScale` still removed (M5.6).
`LightingParameters` still has 8 stored properties (`testParametersStoredFieldCount` still passes).

## Build commands of record

All four canonical commands ran clean. `CODE_SIGNING_ALLOWED=NO` was
applied to the three sim builds as the spec dictates.

| Command | Exit | Tail-line evidence |
| --- | --- | --- |
| `swift build` | 0 | `Build complete! (0.79s)` |
| `swift test` | 0 | `Executed 91 tests, with 0 failures (0 unexpected) in 3.908 (3.912) seconds` |
| `xcodebuild … -scheme RebornZune-macOS -destination 'platform=macOS' build` | 0 | `** BUILD SUCCEEDED **` |
| `xcodebuild … -scheme RebornZune-iPadOS -destination 'generic/platform=iOS Simulator' build` | 0 | `** BUILD SUCCEEDED **` |
| `xcodebuild … -scheme RebornZune-tvOS -destination 'generic/platform=tvOS Simulator' build` | 0 | `** BUILD SUCCEEDED **` |

The two concrete-sim builds for the screenshot pass (`id=9D050E4A…` for
iPad Pro 13-inch (M5), `id=E0AAFDA7…` for Apple TV 4K (3rd generation))
also exited with `** BUILD SUCCEEDED **`.

Test count: 91 (was 90 before M5.7; spec required ≥ 67, on the way to 90).
The `testKeyframesScaleWithPanelSize` test added one; no tests were
removed. Existing tests that previously hard-coded XY values continue to
pass because the test fixture's `panel` is now `referencePanelSize`,
keeping the scale at 1.0.

## Screenshots

Saved under `/Users/yjd/Documents/Reborn-Zune-Apple/reports/M5_7_screenshots/`:

| File | Sim | Capture time |
| --- | --- | --- |
| `ipados_t15.png` | iPad Pro 13-inch (M5), iOS 26.4, DefaultContent | t ≈ 15 s after launch |
| `ipados_t45.png` | iPad Pro 13-inch (M5), iOS 26.4, DefaultContent | t ≈ 45 s after launch |
| `tvos_t15.png` | Apple TV 4K (3rd generation), tvOS 26.4, DefaultContent | t ≈ 15 s after launch |
| `tvos_t45.png` | Apple TV 4K (3rd generation), tvOS 26.4, DefaultContent | t ≈ 45 s after launch |

Capture flow: build for the concrete sim id → `simctl boot` →
`simctl install` → `simctl launch` (launch-time recorded as a unix
timestamp) → wait until `launch + 15s` → `simctl io … screenshot` for
both sims → wait until `launch + 45s` → second pair of screenshots →
`xcrun simctl shutdown all`. Both sims are now shut down.

The 30-second gap between the two captures intentionally probes a
different point in the 120 s warm/cool orbit to confirm the orbit (and
the new scaling) actually moves the visible pool.

## Visual comparison

I read all four M5.7 captures along with `overview_002.png` (warm peak),
`overview_011.png` (purple peak), and the M5.6 captures
(`reports/M5_6_screenshots/{ipados,tvos}_default.png`).

### iPad t≈15s (`ipados_t15.png`) vs M5.6 iPad and `overview_002.png`

The M5.6 iPad capture was uniformly dim — small isolated tiles with
muddy red-orange/maroon chroma scattered across a mostly-black wall, no
obvious "pool" focal point. M5.7's iPad t=15s shows a clearly focused
warm-rust-orange wash spanning roughly the upper-left quadrant and
bleeding into the middle column, with deeper magenta/purple tones in
the centre-right and dark green/teal hints encroaching on the right
edge — i.e. *both* lights are now in-frame and producing visible
contributions. Compared to UWP `overview_002.png`, the warm orange
spread covers a similar fraction of the wall (the UWP frame's wash is
also roughly the left-to-centre half) and the tile-level colour is in
the same warm-rust family rather than the murky red M5.6 produced. The
right edge of M5.7's frame shows the cool light's purple/green starting
to bleed in, which is consistent with the UWP recording's longer
sequence (where the cool light's hue cycles between magenta and olive
across the orbit). Tile chroma is no longer fighting the lighting —
because `.saturation(0)` is still applied (M5.6 architecture preserved),
the visible color is *almost entirely from the lights*, exactly as in
the UWP reference. The "tiles look colored" only because grey × warm
light = warm, which is the intended output.

### iPad t≈45s (`ipados_t45.png`) — orbit + scaling proof

30 seconds later (~37.5% through the 120 s cycle, well past the warm
peak at progress 0.16), the wall is dominated by an olive/yellow-green
wash that fills nearly the entire panel, with small remaining patches
of rust-red on the lower left and a magenta-pink presence in the
mid-right. This is the warm light's progress≈0.4 keyframe
(`color = (0.424, 0.537, 0.106)` — olive green) reaching its visible
peak, with the cool light contributing a small magenta accent. The
shift is dramatic and unambiguous: a different colour clearly dominates
than at t=15 s, proving that (a) the orbit is animating and (b) the
new scaling is keeping both lights in-frame at this phase. This
matches `overview_017.png`'s "olive-green wash dominating" character.

### tvOS t≈15s and t≈45s

Same architecture, wider 16:9 aspect. At t=15 s the warm-rust pool
spreads across the upper-middle of the wall with deeper red-purple in
the right half — broader coverage than M5.6 tvOS, where the wash was
constrained to the centre-right quadrant. At t=45 s the entire frame
turns olive/yellow-green with the warm-amber pocket retreating to the
bottom-left, matching the iPad t=45 s phase. The 2.13× tvOS-vs-iPad
scaleX ratio (1920/2300 vs 1180/2300) means the tvOS pool is
proportionally larger in absolute pixel terms but covers a similar
*fraction* of the wall — exactly the geometric intent of the
panel-size scaling.

### Saturation overlay still working

In all four captures, examining individual tiles in the unlit corners
(top-right of iPad t=15 s, lower-left of iPad t=45 s, etc.) shows
near-black with a faint ambient grey (0.165) — no original tile chroma
bleeds through. If `.saturation(0)` were broken, the synthetic
DefaultContent palette (deep teals, deep maroons, deep purples) would
appear in the unlit corners, but they read as monochrome dark. This
confirms the M5.6 architecture (LightingModifier wrapping a
`.saturation(0)`-treated tile) is intact and the M5.7 visual change is
purely a function of the two intended levers (panel scaling + intensity).

### Verdict

Visibly closer to the UWP reference. The wash is broader and more
saturated than M5.6, the orbit is plainly animating across the panel,
and the saturation overlay remains correct. Not over-tuned: the corners
still go to near-black (the `dot(N,L)` falloff is still doing its job),
and at neither t=15 s nor t=45 s does the panel look uniformly lit.

## Acceptance criteria self-check

| # | Criterion | Status | Evidence |
| --- | --- | --- | --- |
| I1 | `LightingAnimator.referencePanelSize == CGSize(2300, 1300)` | PASS | `Sources/RebornZuneCore/Views/LightingAnimator.swift:97-98`; `testReferencePanelSizeConstant` asserts the literal value |
| I2 | `parameters(at:panelSize:)` scales XY by `panelSize / referencePanelSize` | PASS | `LightingAnimator.swift:53-58` (`scaleX`/`scaleY` from `Float(panelSize.width / Self.referencePanelSize.width)`); `testKeyframesScaleWithPanelSize` asserts `half == full / 2` for both lights' X and Y, accuracy 0.001 |
| I3 | Z component is NOT scaled by panelSize | PASS | `LightingAnimator.swift:57-58` constructs `SIMD3<Float>(warmPos.x * scaleX, warmPos.y * scaleY, warmPos.z)` — Z passes through unchanged. `testKeyframesScaleWithPanelSize` asserts `half.z == full.z` for both lights |
| I4 | `LightingParameters.init` defaults: intensity 1.8 (was 1.3), ambient unchanged | PASS | `LightingParameters.swift:38, 41` (both `Float = 1.8`); `ambientColor` default unchanged at `SIMD3<Float>(0.165, 0.165, 0.165)`; `testDefaultIntensityAndAmbient` and `testParametersDefaultsMatchM56Spec` both assert 1.8 + 0.165 |
| I5 | `swift build` clean, no warnings | PASS | exit 0; `Build complete! (0.79s)` — no warnings emitted |
| I6 | `swift test` passes, ≥ 70 tests, 0 failures | PASS | exit 0; `Executed 91 tests, with 0 failures (0 unexpected)` (well above the ≥ 70 / ≥ 67 threshold) |
| I7 | All 3 xcodebuild commands succeed | PASS | macOS, iPadOS-generic, tvOS-generic all `** BUILD SUCCEEDED **` (and the two concrete-sim builds also succeeded as the screenshot preflight) |
| I8 | iPad sim screenshot at t≥12 s shows visibly broader and more saturated wash than M5.6 | PASS (self) | `ipados_t15.png` — see comparison paragraph above. Wash spans most of the upper-left to centre region instead of M5.6's scattered chroma |
| I9 | Two screenshots ~30 s apart show clearly different colored regions | PASS (self) | `ipados_t15.png` (rust-orange + magenta peaks) vs `ipados_t45.png` (olive-green dominant) — different keyframe phases of the warm light, scaling keeps both lights in-frame at both phases. tvOS pair shows the same shift. |
| I10 | tvOS sim screenshot shows similar improvement | PASS (self) | `tvos_t15.png` and `tvos_t45.png` — broader coverage than M5.6 tvOS (which had a narrow centre-right pool), and the 30 s shift is equally visible |

Note: I8/I9/I10 are self-PASS based on my reading of the four PNGs. Please
re-verify the visual deltas against `overview_002.png` and the M5.6
captures side-by-side. If the warm pool position looks "off" relative to
a particular UWP frame, that's the 120 s orbit's *phase*, not a parameter
issue — at t=15 s the warm light is at progress ≈ 0.12 (transitioning
toward the keyframe-1 amber peak at progress 0.16), which is what
appears in the iPad capture.

## Spec-silent decisions

1. **Test fixture panel size.** Spec §3 instructs "either pass the
   reference panel size (2300×1300) explicitly or assert ratios rather
   than absolutes" for any test that hard-codes XY. I picked the
   former: changed the file-level `private let panel = CGSize(width:
   1920, height: 1080)` to `private let panel =
   LightingAnimator.referencePanelSize`. This keeps every existing
   absolute-XY assertion valid without rewriting them, and it
   centralises the convention so a future reader can grep for
   `referencePanelSize` to find every test that depends on the 1.0-scale
   path.

2. **Test naming.** Spec §3 says "Add `testKeyframesScaleWithPanelSize`"
   — done verbatim. I added a separate `testReferencePanelSizeConstant`
   for I1 specifically, since "the constant has the right value" is a
   distinct invariant from "scaling math behaves correctly" and a
   future regression in either should fail loudly on its own line.

3. **Screenshot timing.** Spec §4 says "Wait at least 12 seconds before
   capturing." I picked t=15 s (well past the 12 s minimum, with the
   warm light close to its progress-0.16 keyframe-1 amber peak) and t=45
   s (well past the warm peak, in the green/olive segment). This is
   inside spec — "two captures showing different cycle phases" — and
   maximises the visible delta.

4. **No spec-disagreements found.** The spec values landed where the
   spec said they would: the wash is broader, saturation overlay still
   works, orbit phase is visible, no over-saturation. Shipping these
   defaults.

## Notes for evaluator

- All sims shut down (`xcrun simctl shutdown all` ran cleanly post-capture).
- `Sources/RebornZuneCore/Resources/zuneLighting.metal` was not touched.
- `Sources/RebornZuneCore/Views/LightingModifier.swift` (`.saturation(0)`
  application) was not touched.
- `LightingPalette.warm` and `LightingPalette.cool` keyframe values were
  not touched — they're still UWP-source verbatim (`200, 700, 200` etc.),
  the new behaviour is purely runtime scaling on top.
- The unrelated `LightingShaderTests.testParametersStoredFieldCount`
  still asserts `mirror.children.count == 8`, which still holds — no
  fields were added to `LightingParameters`.
- If the evaluator needs the wash even broader, the in-spec lever is
  intensity → 2.0 (still inside reasonable range), but the M5.7 spec
  explicitly tells us 1.8 is what we're trying first. I did not iterate
  further since the captures look "visibly closer to the reference"
  per the user's bar in the executor brief.
