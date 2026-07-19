import SwiftUI

/// `ButtonStyle` that hands ALL visuals to the label. Use on tvOS to
/// suppress the default system focus chrome (the translucent "liquid
/// glass" pill UIKit lays under any standard focusable button), so the
/// design's own focus visuals — magenta fill, outline, or
/// `translateY(-3)` lift — are the only thing the user sees.
///
/// Buttons that opt in still need `@FocusState` to drive their own
/// focused look; this style just stops the system from drawing on top.
struct TvFlatButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}
