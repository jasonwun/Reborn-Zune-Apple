import SwiftUI

/// A focusable tvOS card pairing artwork with a caption. Lifts on focus
/// and flips the title to magenta. Matches `styles.css#.tv-card`.
public struct TvCard<Art: View>: View {
    let title: String
    let subtitle: String
    let art: Art
    let action: () -> Void

    @FocusState private var focused: Bool

    public init(title: String, subtitle: String,
                @ViewBuilder art: () -> Art,
                action: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.art = art()
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                art
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 26, weight: .light).width(.condensed))
                        .tracking(-0.26)
                        .foregroundColor(focused ? ResonantColors.magenta : ResonantColors.ink)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .tracking(1.8)
                        .textCase(.uppercase)
                        .foregroundColor(ResonantColors.ink2)
                        .lineLimit(1)
                    if focused {
                        Text("▶ OPEN")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .tracking(2.2)
                            .foregroundColor(ResonantColors.magenta)
                            .padding(.top, 2)
                    }
                }
            }
            .offset(y: focused ? -8 : 0)
        }
        .focused($focused)
        // Suppress the system focus pill; the magenta title + `▶ OPEN`
        // hint + 8pt lift IS the focused appearance.
        .buttonStyle(TvFlatButtonStyle())
        .animation(.easeInOut(duration: 0.24), value: focused)
    }
}
