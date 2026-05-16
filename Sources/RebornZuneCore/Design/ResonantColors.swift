import SwiftUI

public enum ResonantColors {
    // OLED touch platforms (iPad / tvOS) want true #000000 paper so the
    // panel meets the device bezel cleanly. macOS keeps the warmer
    // near-black that reads better behind the traffic-light gutter and
    // window chrome. Per design CSS:
    //   [data-platform="ipad"][data-theme="dark"],
    //   [data-platform="tv"][data-theme="dark"] { --paper: #000000; ... }
    #if os(macOS)
    public static let paper       = Color(light: 0xF4F1EC, dark: 0x0E0D0A)
    public static let paper2      = Color(light: 0xEAE5DD, dark: 0x161512)
    public static let paper3      = Color(light: 0xDED7CB, dark: 0x1F1D19)
    #else
    public static let paper       = Color(light: 0xF4F1EC, dark: 0x000000)
    public static let paper2      = Color(light: 0xEAE5DD, dark: 0x0A0A0A)
    public static let paper3      = Color(light: 0xDED7CB, dark: 0x141414)
    #endif
    public static let ink         = Color(light: 0x15140F, dark: 0xF4F1EC)
    public static let ink2        = Color(light: 0x7A736B, dark: 0x8A847B)
    public static let ink3        = Color(light: 0xB9B2A8, dark: 0x4A463F)
    public static let ink4        = Color(light: 0xDED7CB, dark: 0x2A2722)
    public static let magenta     = Color(rgb: 0xFF0080)
    public static let magentaSoft = Color(rgb: 0xFFD3E6)
    public static let artBorder   = Color(rgb: 0xC5C0B8)
}

extension Color {
    init(rgb: UInt32) {
        self.init(
            .sRGB,
            red:   Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >>  8) & 0xFF) / 255,
            blue:  Double( rgb        & 0xFF) / 255,
            opacity: 1
        )
    }

    init(light: UInt32, dark: UInt32) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(rgb: dark)
                : UIColor(rgb: light)
        })
        #elseif canImport(AppKit)
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
            return isDark ? NSColor(rgb: dark) : NSColor(rgb: light)
        })
        #else
        self.init(rgb: light)
        #endif
    }
}

#if canImport(UIKit)
import UIKit
extension UIColor {
    fileprivate convenience init(rgb: UInt32) {
        self.init(
            red:   CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >>  8) & 0xFF) / 255,
            blue:  CGFloat( rgb        & 0xFF) / 255,
            alpha: 1
        )
    }
}
#endif

#if canImport(AppKit)
import AppKit
extension NSColor {
    fileprivate convenience init(rgb: UInt32) {
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green:   CGFloat((rgb >>  8) & 0xFF) / 255,
            blue:    CGFloat( rgb        & 0xFF) / 255,
            alpha: 1
        )
    }
}
#endif
