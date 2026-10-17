// Typed models for map.json. These are static data: they never change during a game.
// Mutable per-game facts (who owns what) live in GameState.

public typealias TerritoryID = String
public typealias SeaZoneID = String
public typealias ChokepointID = String
public typealias CivilizationID = String

public enum Terrain: String, Codable, Sendable, CaseIterable {
    case plains, hills, mountains, forest, desert
}

/// Raw resources a territory can yield. Bronze is derived (copper + tin) and is not listed here.
public enum Resource: String, Codable, Sendable, CaseIterable, CodingKeyRepresentable {
    case grain, copper, tin, horses, timber, gold
}

public enum Crossing: String, Codable, Sendable {
    case river, strait
}

public enum Government: String, Codable, Sendable {
    case monarchy, republic
}

public struct Territory: Codable, Sendable, Identifiable, Hashable {
    public let id: TerritoryID
    public let name: String
    public let terrain: Terrain
    /// Base grain yield. Every territory produces at least 1.
    public let grain: Int
    /// Non-grain resource yields.
    public let resources: [Resource: Int]
    /// Sea zones this territory borders (coastline).
    public let seas: [SeaZoneID]

    public var isCoastal: Bool { !seas.isEmpty }
}

/// An undirected land border, optionally across a river or strait.
/// Encoded in JSON as `["a", "b"]` or `["a", "b", "river"]`.
public struct LandLink: Codable, Sendable, Hashable {
    public let a: TerritoryID
    public let b: TerritoryID
    public let crossing: Crossing?

    public init(a: TerritoryID, b: TerritoryID, crossing: Crossing? = nil) {
        self.a = a
        self.b = b
        self.crossing = crossing
    }

    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        a = try c.decode(TerritoryID.self)
        b = try c.decode(TerritoryID.self)
        crossing = c.isAtEnd ? nil : try c.decode(Crossing.self)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(a)
        try c.encode(b)
        if let crossing { try c.encode(crossing) }
    }
}

public struct SeaZone: Codable, Sendable, Identifiable, Hashable {
    public let id: SeaZoneID
    public let name: String
}

public struct Chokepoint: Codable, Sendable, Identifiable, Hashable {
    public let id: ChokepointID
    public let name: String
    /// Territories that must all be held to control the chokepoint.
    public let heldBy: [TerritoryID]
    /// For sea chokepoints, the pair of sea zones whose link this chokepoint gates.
    /// Nil for land passes.
    public let gatesSeaLink: [SeaZoneID]?
}

public struct Civilization: Codable, Sendable, Identifiable, Hashable {
    public let id: CivilizationID
    public let name: String
    public let capital: TerritoryID
    public let government: Government
}
