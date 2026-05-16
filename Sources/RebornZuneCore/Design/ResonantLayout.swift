import SwiftUI

/// Captures the surface the app is being rendered into so spacing /
/// typography can adapt without every view re-checking `UIScreen` or
/// `horizontalSizeClass`. Published as an `@Environment` value by a
/// `GeometryReader` at the iPad app root. Mac and tvOS hit the
/// default and don't vary.
public struct ResonantLayout: Equatable, Sendable {
    /// Coarse iPad bucket. `compact` covers multitasking + mini;
    /// `regular` covers iPad 10/11 and Air 11; `expanded` covers
    /// Air 13 and Pro 13. Bucketed on min(width, height) so the
    /// bucket survives rotation.
    public enum DeviceClass: Equatable, Sendable {
        case compact   // iPad mini, split-view, slide-over
        case regular   // iPad 10/11", iPad Air 11"
        case expanded  // iPad Air 13", iPad Pro 13"
    }

    public enum Orientation: Equatable, Sendable {
        case portrait, landscape
    }

    public let deviceClass: DeviceClass
    public let orientation: Orientation

    public init(deviceClass: DeviceClass, orientation: Orientation) {
        self.deviceClass = deviceClass
        self.orientation = orientation
    }

    /// Build a layout from a measured window size.
    public static func from(size: CGSize) -> ResonantLayout {
        let minDim = min(size.width, size.height)
        let deviceClass: DeviceClass =
            minDim < 800  ? .compact
          : minDim < 950  ? .regular
          : .expanded
        let orientation: Orientation = size.width > size.height ? .landscape : .portrait
        return ResonantLayout(deviceClass: deviceClass, orientation: orientation)
    }

    /// Multiplier for non-display text (body, mono tags, meta lines,
    /// rail copy, eyebrows). Display type (HUGE TITLE, pivot row,
    /// large ResonantFont.display sizes) ignores this — those are
    /// already calibrated per-platform.
    public var textScale: CGFloat {
        switch deviceClass {
        case .compact:  return 1.0
        case .regular:  return 1.15
        case .expanded: return 1.25
        }
    }
}

private struct ResonantLayoutKey: EnvironmentKey {
    static let defaultValue = ResonantLayout(deviceClass: .regular, orientation: .landscape)
}

public extension EnvironmentValues {
    var resonantLayout: ResonantLayout {
        get { self[ResonantLayoutKey.self] }
        set { self[ResonantLayoutKey.self] = newValue }
    }
}
