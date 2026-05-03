import SwiftUI
import simd

/// A `ViewModifier` that applies the Zune-style two-point-light + ambient
/// composition lighting effect. Frames are driven by
/// `TimelineView(.animation)`; per-frame uniforms come from
/// `LightingAnimator`.
///
/// The modifier reads the panel size via `GeometryReader` so the shader's
/// keyframe positions (authored in panel-pixel space in the UWP original)
/// stay anchored regardless of the actual display size. Frame timing comes
/// from `Date.timeIntervalSinceReferenceDate` so the cycle remains
/// continuous across view re-creations.
public struct LightingModifier: ViewModifier {
    public let animator: LightingAnimator

    public init(animator: LightingAnimator = LightingAnimator()) {
        self.animator = animator
    }

    public func body(content: Content) -> some View {
        GeometryReader { geo in
            TimelineView(.animation) { context in
                let parameters = animator.parameters(
                    at: context.date.timeIntervalSinceReferenceDate,
                    panelSize: geo.size
                )
                LightingModifier.applyShader(to: content, parameters: parameters)
            }
        }
    }

    /// Apply the lighting shader to a content view using the given
    /// parameters. Factored out so the closure body in `body(content:)` is
    /// short enough for SwiftUI's `@ViewBuilder` type inference.
    @ViewBuilder
    static func applyShader<V: View>(to content: V, parameters: LightingParameters) -> some View {
        let l1p = parameters.light1Position
        let l1c = parameters.light1Color
        let l2p = parameters.light2Position
        let l2c = parameters.light2Color
        let amb = parameters.ambientColor
        let shader = ShaderLibrary.bundle(.module).zuneLighting(
            .float2(
                Float(parameters.panelSize.width),
                Float(parameters.panelSize.height)
            ),
            .float3(l1p.x, l1p.y, l1p.z),
            .float3(l1c.x, l1c.y, l1c.z),
            .float3(l2p.x, l2p.y, l2p.z),
            .float3(l2c.x, l2c.y, l2c.z),
            .float3(amb.x, amb.y, amb.z),
            .float(parameters.light1Intensity),
            .float(parameters.light2Intensity)
        )
        content.colorEffect(shader)
    }
}

public extension View {
    /// Apply the Zune-style two-light + ambient composition lighting effect
    /// to this view. The effect animates over the configured cycle (default
    /// 120 seconds), driven by `TimelineView(.animation)`.
    func zuneLighting(animator: LightingAnimator = LightingAnimator()) -> some View {
        modifier(LightingModifier(animator: animator))
    }
}

#if DEBUG
/// A debug-only host view that exercises the `.zuneLighting` modifier in a
/// SwiftUI tree. Existence of this view (and its successful compilation as
/// part of `swift build`) is the M4 D9 evidence — no UI snapshot needed.
struct _DebugLightingHost: View {
    var body: some View {
        Color.gray
            .frame(width: 1920, height: 1080)
            .zuneLighting()
    }
}
#endif
