# M15 Executor R2 — macOS responsive layout: acceptance-#4 fixes

R2 addresses all four acceptance-#4 failures from `M15_evaluator_R1.md`
(REJECTED). Nine files touched, all inside
`Sources/RebornZuneCore/Views/Resonant/Screens/`. No `specs/` or `agents/`
changes. iPad stays bit-identical (proven per-fix below). 1440×900 renders
**pixel-identical** to R1 (proven by byte-diff below).

Canonical builds are **still blocked** by the unaccepted Xcode 27 license
(owner action pending — see last section). All substitute evidence was
produced with the license-free `swiftc` toolchain from R1, hardened this
round with deterministic baselines (see "Harness determinism").

---

## Failure 1 — Home @ 900×600: title/cover collision

**Root cause.** `HomePickPanel` placed the title block and the bottom strip
with two independent absolute anchors: title flows down from
`y = 20 × displayFontScale`; strip top sat at
`height − 80 − 220 × displayFontScale`. Neither knew the other's extent.
Measured on the R1 pixels (2× backing): at 900×600 the panel is
H ≈ 464pt tall, so the strip top landed at panel-y 218 while the title
ZStack's *declared* frame already reached 228.5 — and the painted "City"
sub-line ran further, because the declared frame
(`subOffsetY + subOffsetY` = 258 × scale) under-reports the true line box
of a 150pt-scale display line (~1.12em). The cover cut the sub-line
mid-glyph, exactly as the evaluator saw.

**Fix** (`HomeScreen.swift`, `HomePickPanel.body`): the panel now computes
a layout-aware vertical budget before placing anything:

```
titleBudget = 20·d + 10·textScale·1.35 + 12·d + (sub ? 129·d + 150·d·1.12 : 150·d·1.12)
fit  = min(1, (H − minGap − 66) / (titleBudget + 220·d))   // 66 = HUD pad 28 + arrows 38
s    = d · max(fit, 0.6)
stripY = max(H − 80 − 220·s,  titleBudget·(s/d) + minGap)  // minGap = 12·windowScale
```

Both subviews now take `scale:` as a parameter (was: read
`displayFontScale` internally), and the title ZStack frame is honest:
`subOffsetY + 150·scale·1.12`. Two invariants hold *by construction* at
every window size: strip top ≥ painted title bottom + minGap, and
strip bottom ≤ H − 66 (never intrudes into the HUD row).

**Why 1440×900 and iPad are bit-identical.** Whenever the composition
fits, `fit == 1`, so `s == displayFontScale` and
`stripY == H − 80 − 220·d` — the exact R1 formula with the exact R1
constants. Verified arithmetically for all five sweep sizes (fit = 1.15 /
1.13 / 1.37 / 1.46 at 1440/1100/1512/1920) and for the three contractual
iPad buckets (compact 0.7 / regular 0.92 / expanded 1.0 all give fit ≥ 1.09
at their design heights, so `s == dScale` and R1 geometry results). The
fit factor only engages below the floor-fit threshold — where R1 collided.

**Evidence.** `M15_screenshots/R2/mac_home_900x600.png`: "Long Island /
City" fully painted with a clean gap above the cover (cover 151.7pt,
strip bottom lands at H−65.8, clear of the HUD). Pixel-diff table below:
home is IDENTICAL to R1 at 1100/1440/1512/1920.

## Failure 2 — Home @ 900×600: meta truncation

**Fix.** The primary meta line is now `.lineLimit(2)` (the evaluator's
sanctioned option). At 900×600 the middle column is ~283pt wide vs the
~300pt meta string, so it wraps: "… 42:18 ·" / "HIP-HOP" — genre fully
readable. At ≥1100 wide the string fits one line and a single-line render
under `lineLimit(2)` is byte-identical to `lineLimit(1)` — confirmed by
the pixel-diff (home IDENTICAL at 1100/1440/1512/1920). The two-line meta
adds ≤12pt to the strip's middle column, which still fits the
`220·s ≈ 152pt` strip frame at the floor. iPad: one line at every
contractual bucket width (meta column ≥ 420pt vs the ~300pt string),
so bit-identical.

**Evidence.** `M15_screenshots/R2/mac_home_900x600.png` (meta wraps,
nothing ellipsized).

## Failure 3 — Artist @ 900×600: content clipped at MiniPlayer boundary

**Honest diagnosis** (evaluator offered two hypotheses): neither a fixed
frame overflowing nor content trapped under an overlay. `ResonantApp`
lays out PivotNav / content / MiniPlayer in a VStack, so the MiniPlayer
takes real layout space and the ScrollView's viewport ends exactly at the
player's top edge. The R1 render shows the *scroll fold at rest* cutting
the BIO / TOP TRACKS labels mid-glyph; the content was always reachable
by scrolling. The genuine deficiency: end-of-scroll bottom padding was
only 16pt, so the last section rested hard against the player chrome.

**Fix.** End-of-scroll clearance ≈ MiniPlayer height on macOS, on every
scroll screen (the audit the evaluator asked for), each behind
`#if os(macOS)` so iPad keeps the contractual 16pt untouched:

```
Artist, Album, Albums, Artists, Search, Playlists, Playlist:
    .padding(.bottom, 68 * layout.windowScale)   // macOS; 68pt = player height at anchor
```

(PlaylistScreen gained an `@Environment(\.resonantLayout)` — read only in
the macOS branch.) Rest-position renders are unchanged: the pixel table
shows albums/album/artist IDENTICAL to R1 at all five sizes.

**Evidence.** `M15_screenshots/R2/mac_artist_900x600_scrolled.png` and
`mac_album_900x600_scrolled.png` — the harness now drives the
NSScrollView beneath SwiftUI's ScrollView to its end before a second
capture: the final TOP TRACKS rows, the full discography row, and album
track 11 all render completely, followed by a clean ~51pt
(68 × 0.75) clearance band above the MiniPlayer. Nothing clipped, nothing
trapped.

## Failure 4 — Now Playing @ 900×600: back ring clipped by the corner

**Root cause.** The off-canvas crop is a design token (42pt at the 1440
anchor) that scaled with `windowScale` with no floor: at the 900pt floor
the crop was 31.5pt against a 126pt ring — a quarter of the control
guillotined by both window edges.

**Fix** (`NowPlayingScreen.swift`): floored crop ramp —

```
crop = 42 · (s ≥ 1 ? s : max(0, (s − 0.8) / 0.2))
```

s ≥ 1 keeps the exact R1 formula (1440×900 pixel-identical — verified;
iPad windowScale == 1 → 42, untouched by construction). From s = 0.8 down
the crop ramps continuously to zero (no pop mid-drag), so at the 900pt
floor the full 126pt ring renders on-canvas. Side effect, intended:
1100×700 (s = 0.764) now shows the full ring too — R1's 32pt crop there
was the same defect at a milder dose.

**Evidence.** `M15_screenshots/R2/mac_nowplaying_900x600.png` (full ring,
both edges clear); pixel-diff localizes the change to the ring bounding
box: DIFF(0,0,252,252) @900 and DIFF(0,0,257,257) @1100, IDENTICAL @1440.

---

## Pixel verification (byte-diff, PIL ImageChops)

R1's working tree was uncommitted, so the R1 code was reconstructed by
reverting the nine R2 edits in a copy (reverse patch verified against
zero leftover R2 anchors), rebuilt, and re-rendered under identical
conditions. Both sweeps ran with `SWIFT_DETERMINISTIC_HASHING=1` (see
next section). `getbbox()` on the per-pair difference:

| screen     | 900×600        | 1100×700       | 1440×900    | 1512×945   | 1920×1200  |
|------------|----------------|----------------|-------------|------------|------------|
| home       | DIFF (the fix) | IDENTICAL      | IDENTICAL   | IDENTICAL  | IDENTICAL  |
| albums     | IDENTICAL      | IDENTICAL      | IDENTICAL   | IDENTICAL  | IDENTICAL  |
| album      | IDENTICAL      | IDENTICAL      | IDENTICAL   | IDENTICAL  | IDENTICAL  |
| artist     | IDENTICAL      | IDENTICAL      | IDENTICAL   | IDENTICAL  | IDENTICAL  |
| nowplaying | DIFF (ring)    | DIFF (ring)    | IDENTICAL   | DIFF†      | DIFF†      |

† nowplaying at 1512/1920 differs full-frame between **any two runs of
identical code** (proven: same binary re-run → DIFF(0,0,3024,1890)):
`TileWallView.expansionSeed` is `.random(in:)` per process and the
backdrop only expands on canvases larger than 1440pt wide. Pre-existing
demo randomness, unrelated to R2; the ring code path for s ≥ 1 is
unchanged and its 1440×900 render is pixel-identical.

## Harness determinism (new this round)

The first R2 render diffed against the archived R1 PNGs showed a
mysterious MiniPlayer delta at every size: R1 showed "See You at the
Bridge", R2 showed "Wanted". Root cause: **pre-existing** —
`ResonantDemoLibrary.makeMusic()` picks track titles via
`abs(seed.id.hashValue)`, and Swift string hashing is randomized per
process. R1's sweep and R2's sweep simply rolled different demo
libraries. The app code was deliberately **not** changed (fixing it would
alter demo content on every surface); instead both sweeps now run with
`SWIFT_DETERMINISTIC_HASHING=1`, making the demo library — and all future
pixel comparisons — reproducible. The delivered R2 PNGs show the
deterministic library (MiniPlayer title "Cathode"); this differs from
R1's archived PNGs in track-name strings only, never in layout.

## Tests & typechecks (license-free substitute evidence)

- `ResonantLayoutTests`: **10/10 pass, exit 0** via the hand-linked
  XCTest runner (rebuilt against the R2 library with `-enable-testing`;
  rpaths baked in for XCTest.framework + libXCTestSwiftSupport).
- Full-module compile, macOS SDK (`-emit-library -emit-module`): 0 errors.
- Full-module `-typecheck`, iPhoneSimulator SDK: **0 errors**;
  AppleTVSimulator SDK: **0 errors** (the Home/NowPlaying changes are
  shared code; the padding changes are `#if os(macOS)` with `#else`
  branches — all compile on every surface).
- Resize sweep: **25/25 renders OK** + 2 scrolled-to-end captures, via
  the NSWindow-hosted renderer (ImageRenderer leaves scroll regions
  blank).

## Still blocked — owner action required (unchanged from R1)

Canonical acceptance #1 commands cannot run on this host: the App Store
reinstalled Xcode 27.0 on 2026-09-26 and the license was never accepted.
Re-confirmed this round: `xcodebuild -license check` → "You have not
agreed to the Xcode license agreements." Once the owner runs
`sudo xcodebuild -license accept` + `sudo xcodebuild -runFirstLaunch`
(and installs the Metal toolchain component), the executor will run
`swift build` / `swift test`, `xcodebuild` for macOS/iPadOS/tvOS, and the
iPad/tvOS regression sims, and paste exit codes into an addendum.

## Where the evaluator should look first (scrutiny points)

1. **The fit-factor formula** (`HomeScreen.swift`, `HomePickPanel.body`):
   the `1.12em` painted-line-box estimate and the 66pt HUD reserve are the
   two judgement calls. Both are conservative (over-reserve), and the
   formula is constructed so `fit == 1` reproduces R1 constants exactly —
   that is what the pixel table proves.
2. **The crop ramp** (`NowPlayingScreen.swift`, `backButtonCrop`): the
   0.8–1.0 transition zone still partially crops by design-token
   proportion; only s < 0.8 floors to zero. If the evaluator wants the
   full ring at *every* sub-anchor width, the ramp is the one line to
   adjust.
3. The artist/album `_scrolled` captures are produced by driving the
   backing NSScrollView from the harness — no app-code test hooks were
   added.
