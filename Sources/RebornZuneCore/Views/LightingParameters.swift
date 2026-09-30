import CoreGraphics
import simd

/// Per-frame uniform values consumed by the `zuneLighting` Metal shader.
///
/// The shader applies two animated point lights and a single ambient color
/// to a pre-desaturated (via SwiftUI `.saturation(0)`) tile-wall pixel.
///
/// M5.6 update: switched the shader to Lambertian diffuse against a
/// surface normal of (0, 0, 1). The light's Z-component (200, baked into
/// the keyframe positions) provides the natural pool falloff, so a
/// separate `attenuationScale` parameter is no longer needed and has been
/// removed from this type and the shader signature.
///
/// Defaults match the UWP `TilePage.xaml.cs` source, tuned against the
/// user's screen recording of the real client (M16.6) and the user's
/// direct feedback on the calibrated build (M16.8):
/// - `light1Intensity` / `light2Intensity` = 1.8 — M16.6's 0.9 matched the
///   recording's measured quadrant ratio (~1.5–2.7x) but read too dim on
///   the user's display; doubled at their request. (History: 1.3 UWP
///   source → 1.5 in M5.7 → 2.2 in M16.4 under squared falloff → 0.9 in
///   M16.6 with linear falloff.)
/// - `ambientColor` = (0.06, 0.06, 0.06) — the recording keeps every tile
///   readable at all times; M5.8's near-zero ambient (0.01) blacked out
///   everything outside the pools, which the recording contradicts.
///
/// `ambientColor` is the ambient RGB **already multiplied by the ambient
/// intensity** — the shader does not re-scale it.
public struct LightingParameters: Equatable, Sendable {
    public var panelSize: CGSize
    public var light1Position: SIMD3<Float>
    public var light1Color: SIMD3<Float>
    public var light1Intensity: Float
    public var light2Position: SIMD3<Float>
    public var light2Color: SIMD3<Float>
    public var light2Intensity: Float
    public var ambientColor: SIMD3<Float>

    public init(
        panelSize: CGSize,
        light1Position: SIMD3<Float>,
        light1Color: SIMD3<Float>,
        light1Intensity: Float = 1.8,
        light2Position: SIMD3<Float>,
        light2Color: SIMD3<Float>,
        light2Intensity: Float = 1.8,
        ambientColor: SIMD3<Float> = SIMD3<Float>(0.06, 0.06, 0.06)
    ) {
        self.panelSize = panelSize
        self.light1Position = light1Position
        self.light1Color = light1Color
        self.light1Intensity = light1Intensity
        self.light2Position = light2Position
        self.light2Color = light2Color
        self.light2Intensity = light2Intensity
        self.ambientColor = ambientColor
    }
}
