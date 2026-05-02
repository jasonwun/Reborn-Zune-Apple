import SwiftUI

/// Layout value key that carries a `TileSpan` from a tagged subview up to
/// `VariableSpanLayout`. Internal — callers tag views via the `tileSpan(_:)`
/// modifier instead of touching the key directly.
struct TileSpanLayoutKey: LayoutValueKey {
    static let defaultValue: TileSpan = .unit
}

public extension View {
    /// Tags this view with a tile span for use inside `VariableSpanLayout`.
    func tileSpan(_ span: TileSpan) -> some View {
        layoutValue(key: TileSpanLayoutKey.self, value: span)
    }
}
