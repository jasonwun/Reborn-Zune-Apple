import Foundation

public enum UpNextSurface: Equatable, Sendable {
    case rail
    case overlay
}

/// Open state is independent of width so rail/overlay crossings never close the editor.
public struct UpNextInteractionState: Equatable, Sendable {
    public private(set) var isOpen = false

    public init() {}

    public func surface(for width: Double) -> UpNextSurface {
        width >= 1000 ? .rail : .overlay
    }

    public mutating func toggle() {
        isOpen.toggle()
    }

    public mutating func dismissOverlay(at width: Double) {
        guard surface(for: width) == .overlay else { return }
        isOpen = false
    }
}
