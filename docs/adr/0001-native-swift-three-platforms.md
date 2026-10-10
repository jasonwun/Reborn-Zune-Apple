# Native Swift/SwiftUI across macOS 14+, iPadOS 17+, tvOS 17+

The app is a port of the UWP "Reborn-Zune" music player. We build it in native
Swift/SwiftUI with OS floors of macOS 14 / iPadOS 17 / tvOS 17, because tvOS
support rules out cross-platform .NET (no code is reused from the C# original),
and these OS versions unlock SwiftUI Metal shaders (`.layerEffect`), which the
lighting parity goal depends on (see ADR-0005).
