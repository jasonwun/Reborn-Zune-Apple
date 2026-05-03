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
/// Defaults match the UWP `TilePage.xaml.cs` source, with M5.7/M5.8 tweaks:
/// - `light1Intensity` / `light2Intensity` = 1.8 (raised from 1.3 in M5.7
///   to broaden the visible wash; UWP source is 1.3 but Lambertian falloff
///   produces a tighter pool than the UWP composition lighting).
/// - `ambientColor` = (0.05, 0.05, 0.05) — M5.8 lowered from (0.165,
///   0.165, 0.165) so the majority of the wall reads as DARK with only
///   the moving light pool visibly bright. The UWP recording's
///   `overview_011.png` shows ~70% of the wall near-black; the previous
///   ambient bled the whole wall to a uniform mid-grey wash.
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
        light1Intensity: Float = 1.5,
        light2Position: SIMD3<Float>,
        light2Color: SIMD3<Float>,
        light2Intensity: Float = 1.5,
        ambientColor: SIMD3<Float> = SIMD3<Float>(0.01, 0.01, 0.01)
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
