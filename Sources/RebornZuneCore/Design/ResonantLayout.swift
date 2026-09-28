import SwiftUI

/// Captures the surface the app is being rendered into so spacing /
/// typography can adapt without every view re-checking `UIScreen` or
/// `horizontalSizeClass`. Published as an `@Environment` value by the
/// app root: bucketed (`from(size:)`) on iPad, screen-fixed
/// (`mac(screen:)`) on macOS, an explicit `.expanded .landscape`
/// injection on tvOS.
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
    /// stay bit-identical; on macOS it is fixed per hardware screen
    /// (see `mac(screen:)`) — M15.1: window resizes reflow layout,
    /// they never rescale sizes.
    public let windowScale: CGFloat

    /// true only on macOS (M15.1): size tokens are screen-fixed and
    /// views must respond to `\.resonantWindowSize` by reflowing
    /// arrangement (column counts, panel stacking, internal scrolling)
    /// instead of scaling sizes. false on bucketed iPad/tvOS surfaces,
    /// which keep their legacy proportional behavior bit-identically.
    public let arrangementDriven: Bool

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
        arrangementDriven = false
    }

    private init(deviceClass: DeviceClass, orientation: Orientation,
                 textScale: CGFloat, displayFontScale: CGFloat,
                 windowScale: CGFloat, arrangementDriven: Bool = false) {
        self.deviceClass = deviceClass
        self.orientation = orientation
        self.textScale = textScale
        self.displayFontScale = displayFontScale
        self.windowScale = windowScale
        self.arrangementDriven = arrangementDriven
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

    /// Screen-fixed macOS scale (M15.1), derived **once** from the
    /// hardware screen the window is on:
    ///   scale            = clamp(screenWidth / 1440, 0.9, 1.15)
    ///   displayFontScale = scale
    ///   windowScale      = scale
    ///   textScale        = min(scale, 1.1)
    /// A 1512-pt screen yields 1.05. Window resizes must NOT change
    /// these tokens — they reflow arrangement instead (callers read
    /// `\.resonantWindowSize` for discrete layout decisions). Re-invoke
    /// only when the window moves to a different screen.
    public static func mac(screen: CGSize) -> ResonantLayout {
        let scale = min(max(screen.width / 1440, 0.9), 1.15)
        return ResonantLayout(
            // `deviceClass` is an iPad concept; nothing consumes it on
            // macOS. `.regular` matches the historical Mac default.
            deviceClass: .regular,
            orientation: screen.width > screen.height ? .landscape : .portrait,
            textScale: min(scale, 1.1),
            displayFontScale: scale,
            windowScale: scale,
            arrangementDriven: true
        )
    }
}

private struct ResonantLayoutKey: EnvironmentKey {
    static let defaultValue = ResonantLayout(deviceClass: .regular, orientation: .landscape)
}

private struct ResonantWindowSizeKey: EnvironmentKey {
    static let defaultValue = CGSize(width: 1440, height: 900)
}

/// Hardware screen size. Injected at the macOS app root (re-derived only
/// when the window moves to another screen); nil elsewhere. M16.1: the
/// tile wall reads it to size its frozen arrangement so any window size
/// up to full-screen stays covered.
private struct ResonantScreenSizeKey: EnvironmentKey {
    static let defaultValue: CGSize? = nil
}

private struct ResonantWindowOriginKey: EnvironmentKey {
    static let defaultValue: CGPoint = .zero
}

public extension EnvironmentValues {
    var resonantLayout: ResonantLayout {
        get { self[ResonantLayoutKey.self] }
        set { self[ResonantLayoutKey.self] = newValue }
    }

    /// Live window/content size, published by the root GeometryReader.
    /// macOS views use it for discrete reflow decisions (column counts,
    /// panel visibility) — never as a size multiplier (M15.1).
    var resonantWindowSize: CGSize {
        get { self[ResonantWindowSizeKey.self] }
        set { self[ResonantWindowSizeKey.self] = newValue }
    }

    /// Hardware screen size (macOS root injects; nil on iPad/tvOS where
    /// window == screen anyway).
    var resonantScreenSize: CGSize? {
        get { self[ResonantScreenSizeKey.self] }
        set { self[ResonantScreenSizeKey.self] = newValue }
    }

    /// The window's top-left corner in screen-local points (origin at the
    /// screen's top-left). Injected live at the macOS root (M16.3) so the
    /// frozen tile wall can counter-offset itself and stay anchored to the
    /// hardware screen while the window moves over it. Zero elsewhere.
    var resonantWindowOrigin: CGPoint {
        get { self[ResonantWindowOriginKey.self] }
        set { self[ResonantWindowOriginKey.self] = newValue }
    }
}
