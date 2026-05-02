# M3 Executor Report — R1

VariableSpanLayout + TileView ported from the UWP `VariableSizedWrapPanel` /
`FluidBitMatrix`. No animations, no Metal, no rounded tiles — strictly the
geometric layout and a placeholder visual, per the M3 spec.

## Files added

All paths are absolute under `/Users/yjd/Documents/Reborn-Zune-Apple/`.

### Sources (`Sources/RebornZuneCore/Views/`)

- `TileSpan.swift` — `public enum TileSpan: Int` + `random(using:)`/`random()`.
- `TileSpanLayoutKey.swift` — internal `LayoutValueKey` + public
  `View.tileSpan(_:)` modifier.
- `BitMatrix.swift` — internal `struct BitMatrix` with `findRegion`,
  `setRegion`, `filledRowCount`. `[[Bool]]` storage (the spec allowed either
  `[UInt64]` packing or `[[Bool]]`; chose the simpler form because at
  ~200 tiles the speed difference is irrelevant).
- `VariableSpanLayout.swift` — public `struct VariableSpanLayout: Layout`,
  public `struct LayoutCache`, plus internal/static helpers
  `cellsPerRow(forWidth:unitSize:)`, `resolvedWidth(proposal:unitSize:)`,
  and `pack(spans:cellsPerRow:)` exposed to enable testing.
- `TileView.swift` — public `struct TileView: View` with `image: CGImage?`
  and `span: TileSpan`. Self-applies `.tileSpan(span)`.
- `_DebugTileWall.swift` — internal `#if DEBUG` fixture (gradient images,
  seeded spans).

### Tests (`Tests/RebornZuneCoreTests/`)

- `BitMatrixTests.swift` — all 6 cases listed in the spec, plus 2 extra
  guard-rail tests (8 tests).
- `TileSpanTests.swift` — distribution + raw values + RNG determinism
  (3 tests). Includes the `SeededRNG` LCG helper from the spec note.
- `VariableSpanLayoutTests.swift` — 9 tests covering `cellsPerRow`,
  `resolvedWidth`, and the internal `pack` packer (which the layout
  delegates to).

No M1 or M2 source/test files were touched.

## Public API surface — confirmation against the M3 spec

| § | Symbol | Signature | Match |
|---|---|---|---|
| 1 | `TileSpan` | `public enum TileSpan: Int, Sendable, Hashable` with `unit=1, medium=3, large=4` | yes |
| 1 | `TileSpan.random(using:)` | `static func random<G: RandomNumberGenerator>(using rng: inout G) -> TileSpan` | yes |
| 1 | `TileSpan.random()` | `static func random() -> TileSpan` | yes |
| 2 | `TileSpanLayoutKey` | `struct TileSpanLayoutKey: LayoutValueKey` (internal); `static let defaultValue: TileSpan = .unit` | yes |
| 2 | `View.tileSpan(_:)` | `func tileSpan(_ span: TileSpan) -> some View` (public) | yes |
| 3 | `BitMatrix` | internal `struct`; `init(rows: Int, columns: Int)`; `findRegion(startingAt:width:height:)`; `setRegion(row:col:width:height:)`; `var filledRowCount: Int` | yes |
| 4 | `VariableSpanLayout` | `public struct VariableSpanLayout: Layout`; `unitSize`, `spacing`; `init(unitSize:spacing:)`; `sizeThatFits`; `placeSubviews`; `Cache = LayoutCache` | yes |
| 4 | `LayoutCache` | `public struct LayoutCache` with `placements: [(row, col, span)]` and `totalRows: Int` | yes (plus three additional internal cache-validity fields) |
| 5 | `TileView` | `public struct TileView: View`; `image: CGImage?`; `span: TileSpan`; `init(image:span:)`; `body` | yes |
| 6 | `_DebugTileWall` | internal, `#if DEBUG`-gated; `tileCount`, `unitSize`, `seed`; `body` | yes |

Spec-silent decisions noted later in this report.

## Build outputs

### `swift build` (debug, clean)

```
$ rm -rf .build && swift build
Building for debugging...
[0/2] Write sources
[1/2] Write swift-version--58304C5D6DBC2206.txt
[3/18] Compiling RebornZuneCore _DebugTileWall.swift
... (18 source files)
[18/18] Compiling RebornZuneCore VariableSpanLayout.swift
Build complete! (5.97s)
```

`swift build 2>&1 | grep -i "warning:"` → no output. **No warnings.**

### `swift test`

```
Test Suite 'All tests' passed at 2026-05-02 15:39:38.196.
	 Executed 35 tests, with 0 failures (0 unexpected) in 0.017 (0.020) seconds
```

Exit 0. **35 tests, 0 failures.** (Spec floor was 20 across M1+M2+M3.)

Per-suite breakdown observed in the run log:

| Suite | Tests |
|---|---|
| BundleLibrarySourceTests | 1 |
| FolderLibrarySourceTests | 4 |
| LibraryGroupingTests | 7 |
| MusicTests | 2 |
| RebornZuneCoreTests | 1 |
| **BitMatrixTests** | **8** |
| **TileSpanTests** | **3** |
| **VariableSpanLayoutTests** | **9** |
| Total | 35 |

### `xcodebuild` — macOS

```
xcodebuild -project RebornZune.xcodeproj -scheme RebornZune-macOS -destination 'platform=macOS' build
... (last lines)
note: Disabling hardened runtime with ad-hoc codesigning. (in target 'RebornZune-macOS' from project 'RebornZune')
** BUILD SUCCEEDED **
```

### `xcodebuild` — iPadOS

```
xcodebuild -project RebornZune.xcodeproj -scheme RebornZune-iPadOS -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
...
Ignoring --strip-bitcode because --sign was not passed
** BUILD SUCCEEDED **
```

### `xcodebuild` — tvOS

```
xcodebuild -project RebornZune.xcodeproj -scheme RebornZune-tvOS -destination 'generic/platform=tvOS Simulator' CODE_SIGNING_ALLOWED=NO build
...
ProcessInfoPlistFile ... Reborn\ Zune.app/Info.plist ... Apps/tvOS/Info.plist ...
** BUILD SUCCEEDED **
```

## Acceptance criteria self-check

| # | Criterion | Status | Evidence |
|---|---|---|---|
| C1 | All §1–§5 files exist with spec'd public API signatures | PASS | API table above; `swift build` succeeds, which compiler-validates the signatures |
| C2 | `swift build` succeeds with no warnings | PASS | `swift build 2>&1 \| grep "warning:"` returns nothing; "Build complete!" |
| C3 | `swift test` passes ≥ 20 tests total | PASS | 35 tests, 0 failures, exit 0 |
| C4 | All 3 xcodebuild commands still pass | PASS | All three end with `** BUILD SUCCEEDED **` |
| C5 | `BitMatrix` packing matches UWP `FluidBitMatrix` semantics | PASS | All 6 spec cases covered in `BitMatrixTests` plus 2 guard tests; medium-pushes-units verified at exact positions (0,0), (0,1)-(2,3), (0,4), (0,5) |
| C6 | `TileSpan.random` distribution matches UWP probabilities | PASS | `testDistributionWithSeededRNG` asserts within ±2% of 87.5/10/2.5 over 10 000 draws |
| C7 | `VariableSpanLayout` is `public` and conforms to `Layout` | PASS | `public struct VariableSpanLayout: Layout`; smoke-tested via `let layout: any Layout = VariableSpanLayout(...)` |
| C8 | `BitMatrix` is `internal` (not `public`) | PASS | `struct BitMatrix` declared without an access modifier; default is internal |
| C9 | `_DebugTileWall` is `#if DEBUG`-only and absent from release | PASS | File entirely wrapped in `#if DEBUG ... #endif`; release build of the package produces zero `_DebugTileWall` symbols (`nm` on the release `.o` returned no matches) |
| C10 | No `print()` in `Sources/` | PASS | `grep -rn "print(" Sources/` returns nothing |

## Spec-silent decisions

1. **`BitMatrix` storage is `[[Bool]]`, not `[UInt64]` packing.** The spec
   explicitly allows either; I chose the simpler form. The packing algorithm
   is otherwise a faithful port of the UWP `TryFindRegion` /
   `AnyBitsSetInRegion` flow (top-to-bottom row scan, left-to-right within
   each row, return first fitting cell).

2. **Matrix sizing inside `pack`.** The spec says the layout uses a bit
   matrix of `cellsPerRow` columns, but doesn't pin down how many rows to
   allocate. I size it to
   `max(estimatedRows, sumOfSpanSides)` where
   `estimatedRows = ceil(totalCells / cellsPerRow) + 4`. The
   `sumOfSpanSides` upper bound is provably sufficient (every tile in its
   own band). This matches the UWP intent (the C# version uses a sum-of-
   heights estimate too).

3. **Oversize-span fallback.** If a caller asks the layout to place a
   `medium` (3×3) into a 2-cell-wide row, the UWP code throws
   `InvalidOperationException`. SwiftUI layouts cannot meaningfully throw, so
   I downgrade the offending tile to `.unit`. `testPackOversizeSpanFallsBackToUnit`
   pins the behavior.

4. **`LayoutCache` extra fields.** The spec lists `placements` and
   `totalRows`. I added three more `var` fields used purely to detect when
   the cache must be rebuilt (`lastResolvedWidth`, `lastSubviewCount`,
   `cellsPerRow`). They are package-private (no access modifier on the
   property) and don't change the public surface beyond what the spec
   listed. `LayoutCache` itself remains a `public struct` because
   `Layout.Cache` must be visible at the `VariableSpanLayout` access level.

5. **Static helpers exposed for testing.** The spec note says "test
   `VariableSpanLayout.cellsPerRow(for:)` if we expose a helper." I exposed
   two `public static` helpers — `cellsPerRow(forWidth:unitSize:)` and
   `resolvedWidth(proposal:unitSize:)` — and a file-internal
   `static func pack(spans:cellsPerRow:)`. The first two are named slightly
   differently than the spec's parenthetical hint (`for:`) because they take
   two arguments, not one; I picked labels that read naturally at the call
   site. The internal `pack` is the actual packing routine the layout
   delegates to.

6. **Tile border rendering.** Spec said "0.8 px border, exact pixel border
   isn't critical." I used `Rectangle().stroke(Color.black, lineWidth: 0.8)`
   in an overlay so the stroke is centered on the bounds — visually
   indistinguishable from `.border` at this width, but it doesn't get
   double-drawn against the `.clipped()` background.

7. **Spacing semantics.** Spec said "insets between tiles by `spacing`."
   I implemented this by shrinking each tile by `spacing` and offsetting by
   `spacing/2`, so a `spacing > 0` produces a uniform gap inside the
   tile-cell box without changing how many cells fit per row. With
   `spacing == 0` (the default) the tile fills the entire cell rectangle —
   matching the UWP original.

## Layout-level test coverage notes

The spec offers an out: "If layout-level tests prove infeasible to write
without rendering, that's fine — note it in the report and ensure
`BitMatrixTests` exhaustively covers the packing logic."

`Subviews` cannot be constructed outside a SwiftUI render pass, so calling
`sizeThatFits(proposal:subviews:cache:)` directly in XCTest is not
practical. To keep coverage strong, I **(a)** factored the packing math out
of `placeSubviews`/`sizeThatFits` into the static `pack(spans:cellsPerRow:)`
function, **(b)** wrote 9 `VariableSpanLayoutTests` that exercise that
function and the supporting helpers, and **(c)** went beyond the 6 cases the
spec listed in `BitMatrixTests` with two extra cases (invalid arguments,
empty matrix).

Net: the spec listed 3 layout-level tests; I provided 9 layout-tier tests
(against the same packing logic the layout uses) plus 8 BitMatrix tests
(against the underlying algorithm). Combined with the 3 TileSpan tests,
that's 20 new M3 tests on top of the 15 from M1+M2.

## Notes for the evaluator

- `swift build -c release` produces zero `_DebugTileWall` symbols (verified
  via `nm`). The file is in the source list because Swift Package Manager
  doesn't support per-configuration excludes, but its contents are entirely
  inside `#if DEBUG`.
- All commands above were run from `/Users/yjd/Documents/Reborn-Zune-Apple`
  with the repo's default toolchain. Exit codes: `swift build` 0,
  `swift test` 0, all three `xcodebuild` 0.
