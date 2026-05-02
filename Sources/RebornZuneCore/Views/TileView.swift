import SwiftUI

/// A single album-art tile.
///
/// Renders the supplied `CGImage` with `aspectFill` semantics (the image
/// fills the tile bounds and crops as necessary). A `nil` image produces a
/// solid black placeholder. The tile applies its own `.tileSpan(span)`
/// modifier so callers can drop a `TileView` into `VariableSpanLayout`
/// without having to remember the modifier separately.
///
/// M3 keeps this view intentionally minimal — no rounded corners, no
/// animations, no flip transitions. Those arrive in M4/M5.
public struct TileView: View {
    public let image: CGImage?
    public let span: TileSpan

    public init(image: CGImage?, span: TileSpan) {
        self.image = image
        self.span = span
    }

    public var body: some View {
        ZStack {
            Color.black
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
        .clipped()
        .overlay(
            Rectangle()
                .stroke(Color.black, lineWidth: 0.8)
        )
        .tileSpan(span)
    }
}
