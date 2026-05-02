# M3 Evaluator Report — R1

Independent verification of the M3 executor's R1 submission. Every build/test
command was re-run from a clean state in
`/Users/yjd/Documents/Reborn-Zune-Apple/`. Source files were read directly to
confirm signatures and behavioral claims.

## Per-criterion verification

| # | Criterion | Status | Evidence |
|---|---|---|---|
| C1 | Files in §1–§5 exist with spec'd public API signatures | verified | All six source files present in `Sources/RebornZuneCore/Views/`. Signatures verified line-by-line: `TileSpan` is `public enum TileSpan: Int, Sendable, Hashable` with cases `unit=1, medium=3, large=4` (TileSpan.swift:8–12). Both `static func random<G: RandomNumberGenerator>(using rng: inout G) -> TileSpan` and `static func random() -> TileSpan` are declared as `public extension TileSpan` (TileSpan.swift:14–38). `TileSpanLayoutKey` is internal with `static let defaultValue: TileSpan = .unit` (TileSpanLayoutKey.swift:6–8). `func tileSpan(_ span: TileSpan) -> some View` is in a `public extension View` (TileSpanLayoutKey.swift:10–15). `BitMatrix` is declared `struct BitMatrix` (no access modifier → internal) with the three required members (BitMatrix.swift:11–82). `VariableSpanLayout` is `public struct VariableSpanLayout: Layout`, `init(unitSize: CGFloat, spacing: CGFloat = 0)`, `public typealias Cache = LayoutCache` (VariableSpanLayout.swift:27–38). `TileView` is `public struct TileView: View` with `public init(image: CGImage?, span: TileSpan)` (TileView.swift:13–20). |
| C2 | `swift build` succeeds with no warnings | verified | `rm -rf .build && swift build` exits 0 with `Build complete! (5.98s)`. `swift build 2>&1 \| grep -i "warning:"` produces no output. |
| C3 | `swift test` passes ≥ 20 tests total | verified | `swift test` exits 0; final lines: `Executed 35 tests, with 0 failures (0 unexpected) in 0.017 (0.020) seconds`. Per-suite counts confirmed: BitMatrixTests (8), TileSpanTests (3), VariableSpanLayoutTests (9), plus 15 carry-over tests from M1+M2 = 35 total. |
| C4 | All 3 xcodebuild commands still pass | verified | Re-ran `xcodegen generate` (project regenerated cleanly), then all three xcodebuild invocations finish with `** BUILD SUCCEEDED **`: macOS (`platform=macOS`), iPadOS (`generic/platform=iOS Simulator` + `CODE_SIGNING_ALLOWED=NO`), tvOS (`generic/platform=tvOS Simulator` + `CODE_SIGNING_ALLOWED=NO`). |
| C5 | `BitMatrix` packing matches UWP `FluidBitMatrix` semantics | verified | All six spec cases present in `BitMatrixTests.swift` and pass: `testEmptyMatrixFindsTopLeft`, `testSequentialUnitsFillRow`, `testWrapToNextRow`, `testMediumPushesFollowingUnits` (asserts (0,0), (0,1), (0,4), (0,5) and verifies medium occupies rows 0–2, cols 1–3), `testLargeOverflowsWidth` (4×4 in 3-wide returns nil), `testFilledRowCountAfterMixedPlacement`. Two extra guard tests included. |
| C6 | `TileSpan.random` distribution matches UWP probabilities | verified | `testDistributionWithSeededRNG` draws 10 000 with `SeededRNG(state: 0xC0FFEE_C0FFEE)` and asserts each fraction within ±2% of 87.5/10/2.5 (TileSpanTests.swift:17–35). The implementation thresholds at `< 5` → large, `< 25` → medium, else unit on `Int.random(in: 0..<200)` (TileSpan.swift:23–30) — a faithful port of the UWP `Random.Next(200)` cutoffs. |
| C7 | `VariableSpanLayout` is `public` and conforms to `Layout` | verified | `public struct VariableSpanLayout: Layout` (VariableSpanLayout.swift:27); compile-checked, plus runtime smoke `let layout: any Layout = VariableSpanLayout(unitSize: 70)` in `testLayoutTypeIsPublicAndConformsToLayoutProtocol`. |
| C8 | `BitMatrix` is `internal` (not `public`) | verified | `grep -n "public" Sources/RebornZuneCore/Views/BitMatrix.swift` returns no matches. The struct, init, methods, and computed property all use the default access (internal). |
| C9 | `_DebugTileWall` is `#if DEBUG`-only and absent from release | verified | File is wrapped from line 1 (`#if DEBUG`) to line 84 (`#endif`); the entire body, including the type declaration and the private RNG helper, sits inside the directive. After `swift build -c release`, scanning every release `.o` with `nm ... \| grep -i "debugtilewall"` produces zero matches across all 15 emitted object files. The `_DebugTileWall.swift.o` artifact exists (SwiftPM cannot exclude files per-config) but contains no symbols for the type. |
| C10 | No `print()` in `Sources/` | verified | `grep -rn "print(" Sources/` returns no matches. |

## Spec-silent decisions — verdict

1. **`[[Bool]]` storage in BitMatrix** — explicitly permitted by the spec; reasonable choice. Approved.
2. **Matrix sizing** (`max(estimatedRows, sumOfSpanSides)`) — produces a provably sufficient upper bound; sensible. Approved.
3. **Oversize-span fallback (degrade to unit).** This is the most consequential deviation. The UWP code throws `InvalidOperationException`; the executor instead silently rewrites the offending span to `.unit` inside the `effectiveSpans` mapping in `pack()` (VariableSpanLayout.swift:160–162). Ruling: **acceptable**. Reasoning:
   - SwiftUI's `Layout` protocol is non-throwing and runs inside the renderer's update loop; throwing or asserting would crash the app at layout time. The UWP exception was effectively a "this should never occur" guard that a desktop-class renderer could afford; a SwiftUI port cannot.
   - The behavior is **documented in code** (VariableSpanLayout.swift:158–162: "shrink any tile whose side exceeds the row width back down to a unit so packing always succeeds. Mirrors the spec's 'tiles never overflow the wall' guarantee.") and **pinned by a test** (`testPackOversizeSpanFallsBackToUnit`) so the policy is intentional, not an accident.
   - The realistic failure mode (a `medium` or `large` tile dropped into a 1- or 2-cell-wide window during a tight resize) is benign visually — the tile becomes a unit cell — and recovers automatically when the window widens, since `pack()` is re-run on resize. There is no mechanism by which a 5×5 tile could be added without already failing the type checker (the enum has only `unit`/`medium`/`large`).
   - The decision is documented prominently in the executor report (Spec-silent decisions §3).
   I would have preferred a single `assertionFailure` in DEBUG to flag accidental misuse, but that's a style preference, not a spec violation.
4. **Extra cache-validity fields on `LayoutCache`** — `lastResolvedWidth`, `lastSubviewCount`, `cellsPerRow` are package-private (no access modifier). They don't change the spec'd public surface (`placements`, `totalRows`) — the spec didn't say "exactly these fields", it said the cache must contain them. Approved.
5. **`pack` static helper actually drives the real `placeSubviews`.** Verified in VariableSpanLayout.swift:139 — `repackIfNeeded` calls `Self.pack(spans:cellsPerRow:)` and stores the result in `cache.placements`, which `placeSubviews` then iterates (lines 92–104). The tests exercise the same code path the renderer does. Not a duplicated test-only routine.
6. **Tile border via `Rectangle().stroke(...)` overlay** — visually equivalent to `.border` at 0.8pt; spec said "exact pixel border isn't critical." Approved.
7. **Spacing semantics** — shrinks tile by `spacing` and offsets by `spacing/2`; produces uniform gap inside the cell rectangle without changing `cellsPerRow`. Reasonable interpretation of the spec's "insets between tiles by spacing." With `spacing == 0` the tile fills its cell. Approved.

## Regressions

- M1 carryover: package builds, single `RebornZuneCoreTests.testVersionStringIsNonEmpty` still passes. `Package.swift` retains zero external dependencies (verified by Read — only the standard `PackageDescription` import).
- M2 carryover: `BundleLibrarySourceTests` (1), `FolderLibrarySourceTests` (4), `LibraryGroupingTests` (7), `MusicTests` (2) all pass — 14 M2 tests + 1 M1 test = 15 carryover, matching expectations.
- No animations, `withAnimation`, `import Metal`, `MTL`, `.layerEffect`, or `.colorEffect` introduced (M4/M5 territory) — `grep -rEn` across `Sources/` returns no matches.
- No `print()` in `Sources/`.

## Independently-run command outputs (last lines)

### `swift build` (clean)
```
[14/18] Compiling RebornZuneCore _DebugTileWall.swift
[15/18] Compiling RebornZuneCore TileSpan.swift
[16/18] Compiling RebornZuneCore RebornZuneCore.swift
[17/18] Compiling RebornZuneCore VariableSpanLayout.swift
[18/18] Emitting module RebornZuneCore
Build complete! (5.98s)
```

### `swift test`
```
Test Suite 'VariableSpanLayoutTests' passed at 2026-05-02 15:42:23.670.
	 Executed 9 tests, with 0 failures (0 unexpected) in 0.001 (0.001) seconds
Test Suite 'RebornZuneCorePackageTests.xctest' passed at 2026-05-02 15:42:23.670.
	 Executed 35 tests, with 0 failures (0 unexpected) in 0.017 (0.019) seconds
Test Suite 'All tests' passed at 2026-05-02 15:42:23.670.
	 Executed 35 tests, with 0 failures (0 unexpected) in 0.017 (0.020) seconds
◇ Test run started.
↳ Testing Library Version: 1743
↳ Target Platform: arm64e-apple-macos14.0
✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.
```

### `xcodegen generate`
```
⚙️  Generating plists...
⚙️  Generating project...
⚙️  Writing project...
Created project at /Users/yjd/Documents/Reborn-Zune-Apple/RebornZune.xcodeproj
```

### `xcodebuild` — macOS
```
note: Disabling hardened runtime with ad-hoc codesigning. (in target 'RebornZune-macOS' from project 'RebornZune')
** BUILD SUCCEEDED **
```

### `xcodebuild` — iPadOS Simulator (CODE_SIGNING_ALLOWED=NO)
```
** BUILD SUCCEEDED **
```

### `xcodebuild` — tvOS Simulator (CODE_SIGNING_ALLOWED=NO)
```
** BUILD SUCCEEDED **
```

### Release build symbol audit
```
$ swift build -c release
Build complete! (4.96s)
$ for o in .build/arm64-apple-macosx/release/RebornZuneCore.build/*.o; do
    nm "$o" 2>/dev/null | grep -i "debugtilewall"
  done
(no output — zero DebugTileWall symbols in any release object)
```

## Verdict

VERDICT: APPROVED

All ten acceptance criteria verified independently. Public API signatures match
the spec exactly; both `swift build` (debug + release) and the three
`xcodebuild` invocations succeed cleanly; 35 tests pass with zero failures
(spec floor was 20). The `_DebugTileWall` debug fixture is correctly excluded
from release builds. The single deviation worth flagging — degrading
oversize tile spans to unit instead of throwing — is documented in code,
pinned by test, sensible for the SwiftUI render-loop context, and reflects an
intentional adaptation of UWP's "should never happen" assertion rather than
silent error eating.
