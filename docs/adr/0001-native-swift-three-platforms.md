# Native Swift/SwiftUI across macOS 27+, iPadOS 17+, tvOS 17+

The app is a port of the UWP "Reborn-Zune" music player. We build it in native
Swift/SwiftUI with OS floors of macOS 27 / iPadOS 17 / tvOS 17, because tvOS
support rules out cross-platform .NET (no code is reused from the C# original).
SwiftUI Metal shaders (`.layerEffect`) remain available on all supported systems;
the macOS 27 floor is the current product-support policy (see ADR-0005).
