import SwiftUI

// tvOS lacks `.onHover` and `DragGesture`. Most of the shared M9 screens
// only ever run on macOS / iPadOS, but the Swift package compiles every
// file for every platform target. These tiny no-op shims let the shared
// screens compile against tvOS without sprinkling `#if !os(tvOS)` over
// every call site.

#if os(tvOS)
extension View {
    /// tvOS no-op shim for the macOS / iOS `.onHover` modifier.
    @ViewBuilder
    func onHover(perform action: @escaping (Bool) -> Void) -> some View {
        self
    }
}
#endif
