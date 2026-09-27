import SwiftUI

/// Captures the surface the app is being rendered into so spacing /
/// typography can adapt without every view re-checking `UIScreen` or
/// `horizontalSizeClass`. Published as an `@Environment` value by a
/// `GeometryReader` at the app root: bucketed (`from(size:)`) on iPad,
/// continuous (`mac(windowSize:)`) on macOS, an explicit
/// `.expanded .landscape` injection on tvOS.
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

    /// Multiplier for non-display text (body, mono tags, meta lines,
    /// rail copy, eyebrows). Display type (HUGE TITLE, pivot row,
    /// large ResonantFont.display sizes) uses `displayFontScale`
    /// instead.
    public let textScale: CGFloat

    /// Multiplier for display type — the panorama HUGE TITLE (150pt),
    /// pivot row labels (42pt), and the big "albums" / "playlists" /
    /// "artists" page titles (180pt). Those numbers are calibrated
    /// for 1366pt+ Mac / iPad Pro surfaces and overwhelm the smaller
    /// 1133pt iPad mini, so the compact bucket scales them down.
    public let displayFontScale: CGFloat

    /// Elastic multiplier for fixed point sizes inherited from the
    /// 1440pt design canvas (panorama peek strip, rail columns, cover
    /// frames, grid minimums, chrome paddings). **1.0 on bucketed
    /// surfaces** (iPad / tvOS / unwired default) so M13/M14 visuals
    /// stay bit-identical; on macOS it tracks the continuous
    /// `displayFontScale` so these fossils flex with the window width.
    public let windowScale: CGFloat

    public init(deviceClass: DeviceClass, orientation: Orientation) {
        self.deviceClass = deviceClass
        self.orientation = orientation
        // Bucketed lookup tables — values are contractual (M13) and
        // must stay bit-identical for the iPad regression guard.
        switch deviceClass {
        case .compact:  textScale = 1.0;  displayFontScale = 0.7
        case .regular:  textScale = 1.15; displayFontScale = 0.92
        case .expanded: textScale = 1.25; displayFontScale = 1.0
        }
        windowScale = 1.0
    }

    private init(deviceClass: DeviceClass, orientation: Orientation,
                 textScale: CGFloat, displayFontScale: CGFloat,
                 windowScale: CGFloat) {
        self.deviceClass = deviceClass
        self.orientation = orientation
        self.textScale = textScale
        self.displayFontScale = displayFontScale
        self.windowScale = windowScale
    }

    /// Build a layout from a measured window size (iPad bucketing).
    public static func from(size: CGSize) -> ResonantLayout {
        let minDim = min(size.width, size.height)
        let deviceClass: DeviceClass =
            minDim < 800  ? .compact
          : minDim < 950  ? .regular
          : .expanded
        let orientation: Orientation = size.width > size.height ? .landscape : .portrait
        return ResonantLayout(deviceClass: deviceClass, orientation: orientation)
    }

    /// Continuous macOS scale, anchored at the 1440pt design width.
    ///
    /// Mac windows resize continuously, so discrete iPad-style buckets
    /// would visibly jump at bucket boundaries mid-drag. Instead:
    ///   displayFontScale = clamp(width / 1440, 0.75, 1.15)
    ///   textScale        = clamp(0.5 + 0.5 · width / 1440, 0.85, 1.1)
    /// Both anchor at exactly 1.0 @ 1440pt and are monotonic
    /// non-decreasing in window width. `textScale` ramps at half the
    /// rate of `displayFontScale` so body text stays readable while
    /// display type carries the visual scaling. `windowScale` follows
    /// `displayFontScale` so 1440pt-canvas fossils flex too.
    public static func mac(windowSize: CGSize) -> ResonantLayout {
        let ratio = windowSize.width / 1440
        let display = min(max(ratio, 0.75), 1.15)
        let text = min(max(0.5 + 0.5 * ratio, 0.85), 1.1)
        return ResonantLayout(
            // `deviceClass` is an iPad concept; nothing consumes it on
            // macOS. `.regular` matches the historical Mac default.
            deviceClass: .regular,
            orientation: windowSize.width > windowSize.height ? .landscape : .portrait,
            textScale: text,
            displayFontScale: display,
            windowScale: display
        )
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
