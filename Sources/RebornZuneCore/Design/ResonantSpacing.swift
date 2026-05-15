import CoreGraphics

public enum ResonantDensity {
    case cozy
    case comfortable
    case spacious
}

public struct ResonantSpacing: Sendable {
    public let padX: CGFloat
    public let padY: CGFloat
    public let gap: CGFloat
    public let displaySize: CGFloat

    public static let cozy = ResonantSpacing(
        padX: 56, padY: 48, gap: 24, displaySize: 200
    )
    public static let comfortable = ResonantSpacing(
        padX: 80, padY: 64, gap: 32, displaySize: 240
    )
    public static let spacious = ResonantSpacing(
        padX: 112, padY: 88, gap: 40, displaySize: 280
    )

    public static func `for`(_ density: ResonantDensity) -> ResonantSpacing {
        switch density {
        case .cozy:        return .cozy
        case .comfortable: return .comfortable
        case .spacious:    return .spacious
        }
    }
}
