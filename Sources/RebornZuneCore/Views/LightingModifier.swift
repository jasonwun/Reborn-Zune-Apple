import SwiftUI
import simd

/// A `ViewModifier` that applies the Zune-style two-point-light + ambient
/// composition lighting effect. Frames are driven by
/// `TimelineView(.animation)`; per-frame uniforms come from
/// `LightingAnimator`.
///
/// The modifier normally reads the panel size via `GeometryReader` so the
/// shader's keyframe positions (authored in panel-pixel space in the UWP
/// original) stay anchored regardless of the actual display size. Callers
/// with a frozen panel (the tile wall) pass `panelSize:` explicitly —
/// see the property doc for why the GeometryReader value is wrong there.
/// Frame timing comes from `WallTime` so the cycle remains continuous
/// across view re-creations AND across macOS window-drag suspensions
/// (M17.2 — the raw clock jumped forward by the drag duration on resume).
public struct LightingModifier: ViewModifier {
    public let animator: LightingAnimator

    /// M16.4: explicit light-field size override. The modifier's internal
    /// `GeometryReader` measures the size *proposed by the parent* — which,
    /// in `TileWallView`, is the live window size, NOT the frozen wall
    /// panel. Using it scaled the light positions with every window
    /// resize. `TileWallView` now passes the light-field size (hardware
    /// screen) here so the light field stays anchored to the screen.
    /// When nil (standalone `.zuneLighting()` usage) the GeometryReader
    /// fallback keeps the old behavior.
    public let fieldSize: CGSize?

    /// M16: cap the lighting frame rate. The light cycle is 120 s — far
    /// too slow for the eye to distinguish 15 fps from the display's
    /// native 60/120 Hz — while every `TimelineView(.animation)` tick
    /// re-applies a full-screen Metal `colorEffect` over the whole tile
    /// wall (measured: 22.6% idle CPU at native rate, ~13% at 30 fps,
    /// ~9% at 20 fps; see `reports/M16_baseline.md`).
    public static let frameInterval: TimeInterval = 1.0 / 15

    public init(animator: LightingAnimator = LightingAnimator(), fieldSize: CGSize? = nil) {
        self.animator = animator
        self.fieldSize = fieldSize
    }

    public func body(content: Content) -> some View {
        // M16.9: suspend the animation clock while the window is being
        // dragged/resized (macOS). The screen-anchored wall is static
        // relative to the screen during a drag, so the frozen light frame
        // is visually correct — and skipping the 15 fps full-wall Metal
        // re-render leaves WindowServer/GPU headroom for move compositing.
        #if os(macOS)
        let suspended = WindowActivityMonitor.shared.isActive
        #else
        let suspended = false
        #endif
        if let fieldSize {
            TimelineView(.animation(minimumInterval: Self.frameInterval, paused: suspended)) { _ in
                let parameters = animator.parameters(
                    at: WallTime.now,
                    panelSize: fieldSize
                )
                LightingModifier.applyShader(to: content, parameters: parameters)
            }
        } else {
            GeometryReader { geo in
                TimelineView(.animation(minimumInterval: Self.frameInterval, paused: suspended)) { _ in
                    let parameters = animator.parameters(
                        at: WallTime.now,
                        panelSize: geo.size
                    )
                    LightingModifier.applyShader(to: content, parameters: parameters)
                }
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
