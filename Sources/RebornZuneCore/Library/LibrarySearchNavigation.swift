import Foundation

public enum LibrarySearchDirection: Sendable, Equatable {
    case up
    case down
    case left
    case right
}

public struct LibrarySearchNavigationItem: Sendable, Equatable {
    public enum Group: Sendable, Equatable {
        case songs
        case artists
        case albums
    }

    public let id: String
    public let group: Group
    public let index: Int
    public let columns: Int

    public init(id: String, group: Group, index: Int, columns: Int) {
        self.id = id
        self.group = group
        self.index = index
        self.columns = max(1, columns)
    }
}

/// Pure visual-order keyboard navigation shared by grouped and Show All Search.
public enum LibrarySearchNavigation {
    public static func move(
        from currentID: String?,
        direction: LibrarySearchDirection,
        in items: [LibrarySearchNavigationItem]
    ) -> String? {
        guard !items.isEmpty else { return nil }
        guard let currentID, let position = items.firstIndex(where: { $0.id == currentID }) else {
            return direction == .down ? items[0].id : nil
        }
        let current = items[position]
        if position == 0 && direction == .up { return nil }

        switch direction {
        case .left, .right:
            guard current.columns > 1 else { return current.id }
            let delta = direction == .left ? -1 : 1
            let target = current.index + delta
            let sameGroup = items.filter { $0.group == current.group }
            guard sameGroup.contains(where: { $0.index == target }) else { return current.id }
            return sameGroup.first { $0.index == target }?.id
        case .up, .down:
            let delta = direction == .up ? -current.columns : current.columns
            let target = current.index + delta
            let groups = items.reduce(into: [LibrarySearchNavigationItem.Group]()) { result, item in
                if result.last != item.group { result.append(item.group) }
            }
            let sameGroup = items.filter { $0.group == current.group }
            if let item = sameGroup.first(where: { $0.index == target }) { return item.id }
            guard let groupPosition = groups.firstIndex(of: current.group) else { return current.id }
            let nextGroupPosition = groupPosition + (direction == .up ? -1 : 1)
            guard groups.indices.contains(nextGroupPosition) else { return current.id }
            let adjacent = items.filter { $0.group == groups[nextGroupPosition] }
            let column = current.index % current.columns
            if direction == .down {
                return adjacent.first(where: { $0.index == column })?.id ?? adjacent.last?.id
            }
            let previousColumns = adjacent.first?.columns ?? 1
            let previousColumn = min(column, previousColumns - 1)
            return adjacent.last(where: { $0.index % previousColumns == previousColumn })?.id
                ?? adjacent.last?.id
        }
    }
}
