import SwiftUI
import CoreText

/// Resonant's three families:
///   display — Barlow Condensed (200 / 300) at 130–240pt
///   body    — Inter (300 / 400 / 500 / 600) variable
///   mono    — JetBrains Mono (400 / 500 / 600) variable
///
/// The .ttfs ship in `Resources/Fonts/` and are registered with
/// `CTFontManagerRegisterFontsForURL` on first access. If registration
/// fails (e.g., the SPM bundle is missing in some surface), helpers
/// fall back to the closest system font so the UI still renders.
public enum ResonantFont {
    public static func display(_ size: CGFloat, weight: Font.Weight = .ultraLight) -> Font {
        ResonantFontRegistrar.ensureRegistered()
        let psName: String
        switch weight {
        case .ultraLight, .thin:  psName = "BarlowCondensed-ExtraLight"
        case .light:              psName = "BarlowCondensed-Light"
        case .regular:            psName = "BarlowCondensed-Regular"
        case .medium:             psName = "BarlowCondensed-Medium"
        default:                  psName = "BarlowCondensed-SemiBold"
        }
        return .custom(psName, size: size)
    }

    public static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        ResonantFontRegistrar.ensureRegistered()
        return Font.custom("Inter-Regular", size: size).weight(weight)
    }

    public static func mono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        ResonantFontRegistrar.ensureRegistered()
        return Font.custom("JetBrainsMono-Regular", size: size).weight(weight)
    }
}

extension Text {
    /// Apply the canonical mono "tag" style — uppercase letterspacing for the
    /// eyebrow / catalog labels that appear on every screen.
    public func resonantTag(size: CGFloat = 10, tracking: CGFloat = 1.6,
                            color: Color = ResonantColors.ink2,
                            weight: Font.Weight = .medium) -> Text {
        self
            .font(ResonantFont.mono(size, weight: weight))
            .tracking(tracking)
            .foregroundColor(color)
    }
}

/// Registers the bundled .ttfs with CoreText once per process so SwiftUI
/// `Font.custom("BarlowCondensed-ExtraLight", …)` can resolve them.
enum ResonantFontRegistrar {
    private static let registered: Bool = {
        let names = [
            "BarlowCondensed-ExtraLight",
            "BarlowCondensed-Light",
            "BarlowCondensed-Regular",
            "BarlowCondensed-Medium",
            "BarlowCondensed-SemiBold",
            "Inter-VariableFont_opsz,wght",
            "JetBrainsMono-VariableFont_wght",
        ]
        var ok = true
        for name in names {
            guard let url = Bundle.module.url(forResource: name, withExtension: "ttf") else {
                ok = false
                continue
            }
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                // Already-registered is non-fatal (happens during SwiftUI
                // previews / hot reloads).
                _ = error?.takeRetainedValue()
            }
        }
        return ok
    }()

    static func ensureRegistered() {
        _ = registered
    }
}
