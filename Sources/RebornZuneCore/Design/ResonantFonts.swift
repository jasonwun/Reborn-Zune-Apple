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
    ///
    /// Returns `some View` rather than `Text` because the underlying
    /// modifier reads `@Environment(\.resonantLayout)` to scale the
    /// font size per device class (1.0× on compact / Mac default,
    /// 1.15× on regular iPad, 1.25× on expanded iPad Pro 13).
    /// Tracking is multiplied too so the optical letterspacing
    /// stays balanced at the new size.
    public func resonantTag(size: CGFloat = 10, tracking: CGFloat = 1.6,
                            color: Color = ResonantColors.ink2,
                            weight: Font.Weight = .medium) -> some View {
        self.modifier(ResonantTagModifier(
            size: size, tracking: tracking, color: color, weight: weight
        ))
    }
}

private struct ResonantTagModifier: ViewModifier {
    let size: CGFloat
    let tracking: CGFloat
    let color: Color
    let weight: Font.Weight

    @Environment(\.resonantLayout) private var layout

    func body(content: Content) -> some View {
        let scale = layout.textScale
        return content
            .font(ResonantFont.mono(size * scale, weight: weight))
            .tracking(tracking * scale)
            .foregroundColor(color)
    }
}

extension View {
    /// Chainable replacement for `.font(.system(size:weight:design:))`
    /// on small/secondary text. Reads `\.resonantLayout` and scales
    /// the size so 10–12pt text feels right on iPad Pro 13 the same
    /// way it does on a Mac window.
    public func resonantScaledFont(_ size: CGFloat,
                                   weight: Font.Weight = .regular,
                                   design: Font.Design = .default,
                                   tracking: CGFloat = 0) -> some View {
        self.modifier(ResonantScaledFontModifier(
            size: size, weight: weight, design: design, tracking: tracking
        ))
    }
}

private struct ResonantScaledFontModifier: ViewModifier {
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    let tracking: CGFloat

    @Environment(\.resonantLayout) private var layout

    func body(content: Content) -> some View {
        let scale = layout.textScale
        return content
            .font(.system(size: size * scale, weight: weight, design: design))
            .tracking(tracking * scale)
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
