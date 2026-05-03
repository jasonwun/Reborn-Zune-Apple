# M5.5 Evaluator Report — R1

A focused visual-tuning pass. Independently verified against the spec criteria
G1–G10. The acceptance bar is "visually closer to the Zune references than M5
was." This evaluator independently re-ran every build/test command, re-read the
five reference / before / after PNGs, and re-captured all three platform
screenshots from the current build state.

## Per-criterion verification (G1–G10)

| # | Criterion | Status | Evidence |
| --- | --- | --- | --- |
| G1 | `TileSpan.small = 2` case added; existing cases unchanged | verified | `Sources/RebornZuneCore/Views/TileSpan.swift` lines 10–15: `case unit = 1`, `case small = 2`, `case medium = 3`, `case large = 4`. Raw values unchanged for the three existing cases. |
| G2 | New 70/20/8/2 distribution; test updated and passing | verified | `random(using:)` lines 25–36 implements thresholds `<2 → large`, `<10 → medium`, `<30 → small`, else `unit` (= 2/8/20/70%). `TileSpanTests.testDistributionWithSeededRNG` and `SyntheticTilesTests.testSpanDistributionIsApproximatelyUWP` both assert 70/20/8/2 ±2% and pass. |
| G3 | `SyntheticTiles` produces dark gradients (mean luminance ≤ 0.55) | verified | `darkPalettes` (lines 58–79) — every stop has all RGB components in 0.05–0.36 range. `testTileBrightnessRangeIsAlbumArtLike` (lines 59–77) samples 200 tiles, computes Rec. 709 luminance, asserts mean ∈ [0.05, 0.55]. Test passes. Visual confirmation: the captured tiles read as dark olive / forest green / brown / teal / plum / burgundy. |
| G4 | `LightingParameters` defaults updated (2.0 / 0.10 / 8e-7) | verified | `LightingParameters.swift` lines 33, 36, 37, 38: `light1Intensity: Float = 2.0`, `light2Intensity: Float = 2.0`, `ambientColor = SIMD3<Float>(0.10, 0.10, 0.10)`, `attenuationScale: Float = 8.0e-7`. `LightingAnimatorTests.testDefaultIntensityAndAmbient` asserts these new values and passes. |
| G5 | DefaultContent uses 250 tiles in all 3 apps | verified | `Apps/macOS/ContentView.swift` line 53, `Apps/iPadOS/ContentView.swift` line 53, `Apps/tvOS/ContentView.swift` line 53 — all read `SyntheticTiles.sample(count: 250)`. The default in `SyntheticTiles.sample(seed:count:)` is also `count: 250`. |
| G6 | `swift build` succeeds, no warnings | verified | Independent run: `Build complete! (0.13s)`, `swift build 2>&1 \| grep warning` returns empty. |
| G7 | `swift test` passes; ≥ 68 tests, 0 failures | verified | Independent run: `Executed 69 tests, with 0 failures (0 unexpected) in 4.672s`. M5 had 68; M5.5 adds `testTileBrightnessRangeIsAlbumArtLike` for 69. |
| G8 | All 3 xcodebuild commands succeed | verified | Independent runs of `RebornZune-macOS` (platform=macOS), `RebornZune-iPadOS` (generic iOS Simulator, code-signing disabled), `RebornZune-tvOS` (generic tvOS Simulator, code-signing disabled) all end with `** BUILD SUCCEEDED **`. |
| G9 | iPad and tvOS shots show more saturated wash AND denser coverage than M5 | verified | Side-by-side reading below. M5 iPad: tile wall fills only top ~40% of screen; lower 60% is pure black. M5.5 iPad: full-bleed edge-to-edge tiles. M5 had crisp rainbow tiles where the wash was barely visible because tiles already saturated the channels; M5.5 tiles recede to dark olive / forest green letting the lighting wash dominate the visible color. |
| G10 | M5.5 closer to Zune references than M5 | verified | Walked through pairwise. The dense, dark, mostly-monochrome warm-cast iPad capture in particular reads very close to the warm-orange phase of `zune_pc_01` and the warm-olive phase of `zune_pc_02`. The original M5 captures don't look like Zune at all — they look like a half-empty grid of Pride flags. |

## Independently-run build / test outputs

### `swift build`

```
[1/1] Compiling plugin MetalCompilerPlugin
Building for debugging...
[1/2] Write swift-version--58304C5D6DBC2206.txt
Build complete! (0.13s)
```

`swift build 2>&1 | grep -i warning` → no warnings.

### `swift test` (last lines)

```
Test Suite 'RebornZuneCorePackageTests.xctest' passed at 2026-05-02 17:58:26.304.
	 Executed 69 tests, with 0 failures (0 unexpected) in 4.672 (4.676) seconds
Test Suite 'All tests' passed at 2026-05-02 17:58:26.304.
	 Executed 69 tests, with 0 failures (0 unexpected) in 4.672 (4.677) seconds
```

### `xcodegen generate`

```
⚙️  Generating plists...
⚙️  Generating project...
⚙️  Writing project...
Created project at /Users/yjd/Documents/Reborn-Zune-Apple/RebornZune.xcodeproj
```

### `xcodebuild` × 3

All three end with `** BUILD SUCCEEDED **`:

- `RebornZune-macOS` `-destination 'platform=macOS'` → BUILD SUCCEEDED
- `RebornZune-iPadOS` `-destination 'generic/platform=iOS Simulator'` `CODE_SIGNING_ALLOWED=NO` → BUILD SUCCEEDED
- `RebornZune-tvOS` `-destination 'generic/platform=tvOS Simulator'` `CODE_SIGNING_ALLOWED=NO` → BUILD SUCCEEDED

## Source-code parameter checks

Direct read of the changed files confirms every spec-mandated value:

- `TileSpan.small = 2`: present, between `unit = 1` and `medium = 3`. ✓
- `TileSpan.random` distribution: thresholds `<2 / <10 / <30` mapping to `large / medium / small / unit`, i.e. exactly 2/8/20/70 %. ✓
- `LightingParameters` defaults:
  - `light1Intensity = 2.0` ✓
  - `light2Intensity = 2.0` ✓
  - `ambientColor = (0.10, 0.10, 0.10)` ✓
  - `attenuationScale = 8.0e-7` ✓
- `SyntheticTiles` palette stops: all ten palettes have both stops with all RGB components ≤ 0.36 (read directly). Mean target luminance is in the 0.05–0.45 range, well inside the 0.55 ceiling the new test asserts. ✓
- `SyntheticTiles.sample(seed:count:)` default `count = 250`. ✓
- All three `ContentView.swift` files use `SyntheticTiles.sample(count: 250)` in `DefaultContent`. ✓
- New test `testTileBrightnessRangeIsAlbumArtLike` exists at `Tests/RebornZuneCoreTests/SyntheticTilesTests.swift:59` and asserts mean luminance ≤ 0.55 (and ≥ 0.05). ✓

## Visual verification — five-way side-by-side

The five PNGs read with vision:

1. `reports/reference/zune_original/zune_pc_01.jpg` — Zune PC, Stevie Ray Vaughan / *Texas Flood*. The wall is dense edge-to-edge album art, dominated by warm orange wash from a single point light pulling toward the upper-left, fading to almost-black in the lower-right. Tile distribution: ~70 % small (1×1 / 2×2), ~20 % feature (2×2 / 3×3), a handful of 4×4. Album art is largely dark with bright accents; the warm cast turns everything sepia-monochrome.
2. `reports/reference/zune_original/zune_pc_02.jpg` — Zune PC, P!nk / *Can't Take Me Home*. Two distinctly colored regions: yellow-olive warm covering the upper two-thirds, and a small but visible cool-pink hot-spot in the lower-right where the second light is. Same dense full-bleed mosaic.
3. `reports/M5_screenshots/ipados_default.png` — fewer than ~50 tiles fill only the top 1/3 of the iPad screen; the lower 2/3 is solid black. Tiles are bright HSB rainbow gradients (greens, magentas, browns); the lighting wash exists but is invisible because the tiles' own saturation drowns it. Does not look like the Zune wall at all.
4. `reports/M5_screenshots/tvos_default.png` — even worse: only the very top strip has tiles, ~75 % of screen is black. Same bright rainbow palette.
5. `reports/M5_screenshots/macos_snapshot_t30.png` — at least the snapshot frame is filled, but the tiles are again bright HSB; even though the snapshot path doesn't render the wash, the tile palette alone reads completely unlike the Zune muted album-art look.

After M5.5:

6. `reports/M5_5_screenshots/ipados_default.png` — full-bleed edge-to-edge tile mosaic. Tile sizes spread across all four spans (the new 2×2 `.small` is clearly the most common feature size). Tile palette is dark olive / forest green / dark brown / muted plum / dark teal — ie the dark album-art band the spec demands. The lighting wash is dramatically more present: the upper-left area reads as a saturated yellow-olive cast (the warm light at this orbit phase) and the bottom-right shows a slight greener / cooler tone where the cool light is approaching. This is the closest of all three captures to `zune_pc_02`'s warm-olive phase.
7. `reports/M5_5_screenshots/tvos_default.png` — full-bleed dense mosaic, all four span sizes legible. Dark album-art palette is the source content. The wash here is more subtle but in two distinguishable color bands: warmer brown / olive in the right half, cooler dark teal / dark green in the left half. This is the screenshot that makes "two distinct lights with two distinct colors" plainest.
8. `reports/M5_5_screenshots/macos_snapshot_t30.png` — snapshot harness path, no Metal wash by design. Layout is full-bleed, tiles are dark album-art toned (forest green, dark brown, muted teal, plum, burgundy). This shows the *underlying* content is now headroom-friendly even before the wash ever runs.

### Per-platform paragraph

**macOS snapshot.** Tile density is full-bleed: I count ~150 visible tiles across the 600×336 frame, with a clear mix of `.unit` 1×1, the new `.small` 2×2 (the visually dominant feature size, exactly as in Zune), several `.medium` 3×3, and a couple of `.large` 4×4 (the prominent dark green block on the left and the dark brown block center). Tile content is decisively dark album-art-like: forest greens, dark browns, muted teal, plum, ochre, burgundy. There is no lighting wash here — the snapshot harness uses `ImageRenderer` which can't run the Metal `.layerEffect` shader, a known limitation that pre-dates M5.5. So multi-light visibility is N/A on this platform. As a *content* check, this image is exactly what the spec asked for: dark, headroom-friendly source content. Reference closeness: by source-content alone it is closest to `zune_pc_02` because both are mostly muted/sepia rather than the warmer monochrome of `zune_pc_01`.

**iPad sim.** Tile density now fully fills a 1024×1366 portrait panel — visibly hundreds of tiles, edge to edge, top to bottom. Tile content is the new dark palette; you can see the source colors peeking through (a few darker browns and muted plums in the lower third). Lighting saturation is **dramatically more visible** than M5: the wash sets a clear yellow-olive cast across the upper half of the screen, transitioning subtly toward greener tones in the lower right. Multi-light visibility: only partially distinct here — both lights happen to be on the upper portion of the panel at this moment of the orbit, so the dominant cast is one tone (the warm olive). You *can* see a subtle hue shift into the lower right; that is the cool light approaching. Reference closeness: this matches `zune_pc_02` extremely well — both have a dominant warm-olive wash with hints of a second color creeping in from another corner.

**tvOS sim.** Tile density is full-bleed across a 1920×1080 frame; clear visual mix of all four span sizes. Tile content is the same dark palette. Lighting saturation is more subtly mixed than the iPad capture but it shows the most clearly *separated* two-light effect of any of the three: the right half of the wall reads warmer (olive / amber / brown) while the left half reads cooler (dark teal / muted green). This is the criterion's "two distinct colored regions (warm + cool)" requirement satisfied unambiguously. Reference closeness: not as warm-saturated as `zune_pc_01`, but conceptually the closest to `zune_pc_02` — two lights, two regions, dense mosaic, dark headroom.

## Fresh re-capture vs executor's saved screenshots

I re-captured all three independently:

- macOS: `REBORN_ZUNE_SNAPSHOT_PATH=/tmp/m5_5_eval_macos.png REBORN_ZUNE_SNAPSHOT_TIME=30 "/Users/.../Reborn Zune"` — produced `/tmp/m5_5_eval_macos.png`. **md5 byte-identical** to `reports/M5_5_screenshots/macos_snapshot_t30.png` (`c0d100bdcd4c1d810b44edc098e5385a`). Confirmed.
- iPad sim (iPad Pro 13-inch (M5), `9D050E4A-...`): installed, terminated, launched fresh, slept 5 s, screenshot to `/tmp/m5_5_eval_ipados.png`. Visual content matches the saved file's dark olive/green/brown mosaic; the precise lighting wash differs slightly because the lighting orbit advances with wall-clock time and the new launch starts the orbit at a different moment, but the tile pattern, density, and dark-palette character are identical (deterministic seed). Confirmed substantially identical.
- tvOS sim (Apple TV 4K (3rd gen), `E0AAFDA7-...`): same flow, screenshot to `/tmp/m5_5_eval_tvos.png`. Same conclusion as iPad — same tile pattern from the deterministic seed; lighting wash phase differs minorly because the orbit-time is a function of launch wall-clock. Confirmed substantially identical.

The fact that the macOS snapshot is byte-identical between executor and evaluator captures, and the simulator screenshots show the same tile mosaic from the seed, confirms the executor's saved screenshots came from the *current* code state — not a stale build.

## Final assessment

The executor implemented every M5.5 deliverable exactly as the spec demanded — no half-measures, no parameter drift. The four observed gaps from M5 are each unambiguously resolved in M5.5:

1. **Tile density** went from 64 tiles in roughly 25 % of the panel to 250 tiles edge-to-edge.
2. **Tile content** went from saturated HSB rainbow to dark muted album-art palettes (mean luminance ≤ 0.55, asserted by test).
3. **Lighting saturation** went from a barely-perceptible tint to a clearly dominant colored wash on iPad and tvOS captures.
4. **Multi-light visibility** is plainly readable in the tvOS capture (warm right half, cool left half).

M5.5 is *clearly* closer to the Zune references than M5 was. Not perfect — that would need real album art and possibly a frozenTime parameter for picking a particularly dramatic phase of the orbit — but the spec calls out perfect parity as out of scope, and the visual delta vs M5 is decisive on every one of the four spec gaps.

VERDICT: APPROVED
