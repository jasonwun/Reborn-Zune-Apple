import SwiftUI

/// Resonant uses three families:
///   display — Barlow Condensed (200 / 300) at 130–240pt
///   body    — Inter (300/400/500/600)
///   mono    — JetBrains Mono (400/500/600) — eyebrows, catalog tags, time
///
/// We don't bundle the binary font files in this milestone — we route through
/// SwiftUI's system fonts with `.width(.condensed)` for display and
/// `.monospaced()` for mono. The visual rhythm (weight contrast, condensed
/// proportion, monospace metadata) carries through; pixel-perfect glyph match
/// can be added later by dropping the .otf files into `Resources/Fonts/` and
/// registering them.
public enum ResonantFont {
    public static func display(_ size: CGFloat, weight: Font.Weight = .ultraLight) -> Font {
        .system(size: size, weight: weight, design: .default)
            .width(.condensed)
    }

    public static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    public static func mono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
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
