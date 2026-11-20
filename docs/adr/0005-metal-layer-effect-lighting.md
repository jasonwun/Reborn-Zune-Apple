# Metal `.layerEffect` shader for composition lighting parity

The defining feature of the original app is a tile wall lit by two animated
`PointLight`s that orbit and color-shift over a long loop. Pixel-perfect parity
with that effect is the point of this port, and a Metal shader driven through
SwiftUI's `.layerEffect` is the only path to true parity with XAML's
`PointLight` — parameter-driven from SwiftUI so the UI can modulate it. This is
why the OS floors are pinned at macOS 27 / iPadOS 17 / tvOS 17 (ADR-0001).

## Considered options

- Approximating the lighting with SwiftUI gradients/overlays: rejected, cannot
  match the XAML `PointLight` falloff and orbit behavior.
