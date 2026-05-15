import SwiftUI

/// Hard-rectangle CTA button matching `styles.css#.tv-btn`. Three variants:
/// - `.primary` — magenta fill on focus
/// - `.ghost` — outlined, flips to magenta fill on focus
/// - `.solid` — ink fill, flips to magenta on focus
public struct TvButton: View {
    public enum Variant { case primary, ghost, solid }

    let label: String
    let variant: Variant
    let action: () -> Void

    @FocusState private var focused: Bool

    public init(_ label: String, variant: Variant = .primary, action: @escaping () -> Void) {
        self.label = label
        self.variant = variant
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .tracking(2.2)
                .textCase(.uppercase)
                .foregroundColor(foreground)
                .padding(.horizontal, 30)
                .padding(.vertical, 18)
                .frame(minHeight: 56)
        }
        .background(background)
        .overlay(Rectangle().strokeBorder(border, lineWidth: 1))
        .offset(y: focused ? -3 : 0)
        .focused($focused)
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.22), value: focused)
    }

    private var foreground: Color {
        switch variant {
        case .primary, .solid: return ResonantColors.paper
        case .ghost:           return focused ? ResonantColors.paper : ResonantColors.ink
        }
    }

    private var background: Color {
        if focused { return ResonantColors.magenta }
        switch variant {
        case .primary: return ResonantColors.magenta
        case .ghost:   return .clear
        case .solid:   return ResonantColors.ink
        }
    }

    private var border: Color {
        if focused { return ResonantColors.magenta }
        switch variant {
        case .primary: return ResonantColors.magenta
        case .ghost:   return ResonantColors.ink4
        case .solid:   return ResonantColors.ink
        }
    }
}
