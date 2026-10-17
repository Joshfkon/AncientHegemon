/// A count of each unit type. Used for army stacks, move orders and starting armies.
public struct UnitCounts: Codable, Sendable, Hashable {
    public var infantry: Int
    public var archers: Int
    public var cavalry: Int

    public init(infantry: Int = 0, archers: Int = 0, cavalry: Int = 0) {
        self.infantry = infantry
        self.archers = archers
        self.cavalry = cavalry
    }

    public static let zero = UnitCounts()

    public subscript(type: UnitType) -> Int {
        get {
            switch type {
            case .infantry: infantry
            case .archers: archers
            case .cavalry: cavalry
            }
        }
        set {
            switch type {
            case .infantry: infantry = newValue
            case .archers: archers = newValue
            case .cavalry: cavalry = newValue
            }
        }
    }

    public var total: Int { infantry + archers + cavalry }
    public var isEmpty: Bool { total == 0 }
    public var isNonNegative: Bool { infantry >= 0 && archers >= 0 && cavalry >= 0 }

    /// True if every count in `self` is at most the matching count in `other`.
    public func fits(in other: UnitCounts) -> Bool {
        UnitType.allCases.allSatisfy { self[$0] <= other[$0] }
    }

    public static func + (a: UnitCounts, b: UnitCounts) -> UnitCounts {
        UnitCounts(infantry: a.infantry + b.infantry, archers: a.archers + b.archers,
                   cavalry: a.cavalry + b.cavalry)
    }

    public static func - (a: UnitCounts, b: UnitCounts) -> UnitCounts {
        UnitCounts(infantry: a.infantry - b.infantry, archers: a.archers - b.archers,
                   cavalry: a.cavalry - b.cavalry)
    }

    public static func += (a: inout UnitCounts, b: UnitCounts) { a = a + b }
    public static func -= (a: inout UnitCounts, b: UnitCounts) { a = a - b }
}
