import CoreGraphics
import simd

/// Per-frame uniform values consumed by the `zuneLighting` Metal shader.
///
/// The shader applies two animated point lights and a single ambient color
/// to a sampled pixel. `attenuationScale` tunes the distance falloff —
/// `1 / (1 + d² * attenuationScale)`. The default `1e-6` gives a falloff of
/// `0.5` at a 1000-pixel distance, matching the visual softness of the UWP
/// reference at typical 1920×1080 panel sizes.
///
/// `ambientColor` is the ambient RGB **already multiplied by the ambient
/// intensity** — the shader does not re-scale it. The default value
/// `(0.211, 0.211, 0.211)` is `#d3d3d3 * 0.20`, matching the UWP setup.
public struct LightingParameters: Equatable, Sendable {
    public var panelSize: CGSize
    public var light1Position: SIMD3<Float>
    public var light1Color: SIMD3<Float>
    public var light1Intensity: Float
    public var light2Position: SIMD3<Float>
    public var light2Color: SIMD3<Float>
    public var light2Intensity: Float
    public var ambientColor: SIMD3<Float>
    public var attenuationScale: Float

    public init(
        panelSize: CGSize,
        light1Position: SIMD3<Float>,
        light1Color: SIMD3<Float>,
        light1Intensity: Float = 1.3,
        light2Position: SIMD3<Float>,
        light2Color: SIMD3<Float>,
        light2Intensity: Float = 1.3,
        ambientColor: SIMD3<Float> = SIMD3<Float>(0.211, 0.211, 0.211),
        attenuationScale: Float = 1.0e-6
    ) {
        self.panelSize = panelSize
        self.light1Position = light1Position
        self.light1Color = light1Color
        self.light1Intensity = light1Intensity
        self.light2Position = light2Position
        self.light2Color = light2Color
        self.light2Intensity = light2Intensity
        self.ambientColor = ambientColor
        self.attenuationScale = attenuationScale
    }
}
