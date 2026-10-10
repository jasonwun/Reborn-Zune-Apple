# Shared Swift package core with three thin app targets

All library code lives in a single Swift package, `RebornZuneCore`; the macOS,
iPadOS, and tvOS apps are thin shells over it, with the Xcode project generated
from `project.yml` via xcodegen. This keeps per-platform code minimal and lets
the core be built and tested on the host with plain `swift build` / `swift test`
independent of any simulator.
