# M1 — Evaluator Report (R1)

Milestone: project scaffolding.
Toolchain (verified by re-running): Xcode 26.4.1, Swift 6, xcodegen 2.45.4 producing
`RebornZune.xcodeproj` against macOS SDK 26.4 / iPhoneSimulator SDK 26.4 / AppleTVSimulator SDK 26.4.

All commands re-run by the evaluator from `/Users/yjd/Documents/Reborn-Zune-Apple/`.
The xcodeproj was deleted and regenerated from scratch before the xcodebuild runs to
ensure no stale state.

## Per-criterion verification

| # | Criterion | Status | Evidence |
| --- | --- | --- | --- |
| A1 | Repo layout matches `PROJECT_SPEC.md → Project layout` | verified | `ls -la` shows `Package.swift`, `project.yml`, `README.md`, `.gitignore`, `Apps/{macOS,iPadOS,tvOS}/`, `Sources/RebornZuneCore/{Models,Library,Audio,Views,Persistence,Resources}/` (six empty subdirs as scaffold) plus `RebornZuneCore.swift`, `Tests/RebornZuneCoreTests/RebornZuneCoreTests.swift`, `specs/`, `agents/`, `reports/`. |
| A2 | `swift build` succeeds, "Build complete!" | verified | Re-ran `swift build`; output: `Building for debugging... [0/2] Write swift-version-... Build complete! (0.11s)`. Exit 0. |
| A3 | `swift test` exit 0 with ≥1 test | verified | Re-ran `swift test`. Output includes `Test Case '-[RebornZuneCoreTests.RebornZuneCoreTests testVersionStringIsNonEmpty]' passed (0.000 seconds).` and `Test Suite 'All tests' passed ... Executed 1 test, with 0 failures`. Source `Tests/RebornZuneCoreTests/RebornZuneCoreTests.swift` actually asserts `XCTAssertFalse(RebornZuneCore.version.isEmpty)` against the production `version = "0.1.0"` constant — a real (if minimal) assertion, not a trivial no-op. |
| A4 | `xcodegen generate` succeeds, `RebornZune.xcodeproj` produced | verified | Deleted the existing xcodeproj, ran `xcodegen generate` fresh. Output: `Generating plists / Generating project / Writing project / Created project at /Users/yjd/Documents/Reborn-Zune-Apple/RebornZune.xcodeproj`. `xcodebuild -list` confirms the four schemes: `RebornZune-iPadOS`, `RebornZune-macOS`, `RebornZune-tvOS`, `RebornZuneCore`. |
| A5 | macOS xcodebuild succeeds | verified | Ran the canonical command. Tail: `note: Disabling hardened runtime with ad-hoc codesigning. (in target 'RebornZune-macOS' from project 'RebornZune')` then `** BUILD SUCCEEDED **`. Note: the project disables `ENABLE_HARDENED_RUNTIME` warning is informational; build still succeeds and the target is ad-hoc signed (`CODE_SIGN_IDENTITY = "-"`). |
| A6 | iPadOS xcodebuild (`generic/platform=iOS Simulator` + `CODE_SIGNING_ALLOWED=NO`) succeeds | verified | Tail: `** BUILD SUCCEEDED **`. SDK used: `iPhoneSimulator26.4.sdk`. |
| A7 | tvOS xcodebuild (`generic/platform=tvOS Simulator` + `CODE_SIGNING_ALLOWED=NO`) succeeds | verified | Tail: `** BUILD SUCCEEDED **`. SDK used: `AppleTVSimulator26.4.sdk`. |
| A8 | All three apps `import RebornZuneCore` and use `RebornZuneCore.version` | verified | Read all three `ContentView.swift` files. All contain `import RebornZuneCore` (line 2) and `Text("{platform} — core v\(RebornZuneCore.version)")` (line 9), with `{platform}` correctly being `macOS`, `iPadOS`, and `tvOS` respectively. SwiftPM dependency wired via `packages: RebornZuneCore: path: .` and per-target `dependencies: - package: RebornZuneCore product: RebornZuneCore` in `project.yml`. |
| A9 | iPadOS `TARGETED_DEVICE_FAMILY = 2` | verified | `project.yml` line 76: `TARGETED_DEVICE_FAMILY: "2"`. Generated `RebornZune.xcodeproj/project.pbxproj` shows `TARGETED_DEVICE_FAMILY = 2;` in BOTH the iPadOS Debug and Release configs (lines 371 and 463). tvOS shows `= 3` (Apple TV family — correct). macOS has none (correct, macOS does not use the family code). |
| A10 | All three bundle IDs match the spec table | verified | `grep PRODUCT_BUNDLE_IDENTIFIER RebornZune.xcodeproj/project.pbxproj` returns exactly `dev.yjd.rebornzune.macos`, `dev.yjd.rebornzune.ipados`, `dev.yjd.rebornzune.tvos`, each in both Debug and Release configs, matching the spec table verbatim. |

## Independently-run command outputs (last lines)

### `swift build`
```
[0/1] Planning build
Building for debugging...
[0/1] Write swift-version--58304C5D6DBC2206.txt
Build complete! (0.11s)
```

### `swift test`
```
Test Suite 'RebornZuneCoreTests' started at 2026-05-02 15:21:26.717.
Test Case '-[RebornZuneCoreTests.RebornZuneCoreTests testVersionStringIsNonEmpty]' started.
Test Case '-[RebornZuneCoreTests.RebornZuneCoreTests testVersionStringIsNonEmpty]' passed (0.000 seconds).
Test Suite 'RebornZuneCoreTests' passed at 2026-05-02 15:21:26.717.
     Executed 1 test, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
Test Suite 'RebornZuneCorePackageTests.xctest' passed at 2026-05-02 15:21:26.717.
     Executed 1 test, with 0 failures (0 unexpected) in 0.000 (0.001) seconds
Test Suite 'All tests' passed at 2026-05-02 15:21:26.717.
     Executed 1 test, with 0 failures (0 unexpected) in 0.000 (0.001) seconds
```

### `xcodegen generate` (after deleting the existing project)
```
⚙️  Generating plists...
⚙️  Generating project...
⚙️  Writing project...
Created project at /Users/yjd/Documents/Reborn-Zune-Apple/RebornZune.xcodeproj
```

### macOS xcodebuild
```
note: Disabling hardened runtime with ad-hoc codesigning. (in target 'RebornZune-macOS' from project 'RebornZune')
** BUILD SUCCEEDED **
```

### iPadOS xcodebuild
```
** BUILD SUCCEEDED **
```

### tvOS xcodebuild
```
** BUILD SUCCEEDED **
```

## Spec scrutiny / executor-decision review

1. **macOS `CODE_SIGNING_ALLOWED = YES` override.** The spec gives the executor a
   choice between Manual sign-to-run-locally and `CODE_SIGNING_ALLOWED=NO`. The
   executor's hybrid (project-base `NO`, macOS-target override `YES` + ad-hoc `-`
   identity, iPadOS/tvOS keep base `NO`) is consistent with the M1 build commands:
   the canonical macOS command has no `CODE_SIGNING_ALLOWED=NO` flag and macOS
   apps must be at least ad-hoc signed to launch. iPadOS and tvOS commands pass
   `CODE_SIGNING_ALLOWED=NO`. All three commands succeed. Decision is within spec.
2. **iPadOS `TARGETED_DEVICE_FAMILY = "2"` propagation.** Confirmed in both
   `project.yml` and the regenerated `pbxproj` (Debug + Release).
   `SUPPORTS_MACCATALYST = NO` is also set, which is defensible insurance for
   "iPad-only family".
3. **Info.plist files.** xcodegen writes them into `Apps/{platform}/Info.plist`
   from `info.properties`. They are not gitignored. Spec did not say either way;
   the executor flagged this. Acceptable for M1 since they currently contain
   only spec-relevant keys (`CFBundleDisplayName`, `CFBundleName`, iPad orientations).
   No action required for M1; revisit if/when M2 introduces hand-authored plist keys.
4. **`Package.resolved` added to `.gitignore`.** Outside the spec's listed entries
   but harmless. All required entries from the spec are present.
5. **App `struct` names** (`RebornZuneMacApp`, `RebornZuneIPadApp`, `RebornZuneTVApp`)
   match the spec's `RebornZune{Suffix}App` template with `{Suffix} = Mac, IPad, TV`.
6. **Test substance.** `XCTAssertFalse(RebornZuneCore.version.isEmpty)` is the
   single assertion the spec mandates. It is not a tautology — it would fail if
   the version constant were ever set to `""`.

## Regressions

None. M1 is the first milestone; there are no prior acceptance criteria to preserve.

## Findings outside the per-criterion table

- `.build/` exists in the repo but is correctly listed in `.gitignore`.
- `RebornZune.xcodeproj/` was present before the evaluator started; it was deleted
  and regenerated cleanly. Both runs produced identical schemes.
- `xcodebuild -list` reports the package scheme `RebornZuneCore` alongside the
  three app schemes — expected, since xcodegen attaches the local SwiftPM package.
- All six scaffold subdirs under `Sources/RebornZuneCore/` (`Models`, `Library`,
  `Audio`, `Views`, `Persistence`, `Resources`) are present and empty, matching
  M1's "empty subfolders are fine" exemption.
- No .swiftpm/, .build/, *.xcodeproj/, or DerivedData/ artifacts will be committed
  thanks to the `.gitignore` (which the evaluator confirmed contains every required
  entry from the spec).

VERDICT: APPROVED
