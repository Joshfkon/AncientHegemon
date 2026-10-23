import Foundation

public enum MapError: Error, Equatable, CustomStringConvertible {
    case resourceMissing(String)
    case duplicateID(String)
    case unknownTerritory(String, context: String)
    case unknownSea(String, context: String)
    case invalid(String)

    public var description: String {
        switch self {
        case .resourceMissing(let name): "map resource '\(name)' not found in bundle"
        case .duplicateID(let id): "duplicate id '\(id)'"
        case .unknownTerritory(let id, let ctx): "unknown territory '\(id)' in \(ctx)"
        case .unknownSea(let id, let ctx): "unknown sea zone '\(id)' in \(ctx)"
        case .invalid(let msg): msg
        }
    }
}

/// The static map: territories, seas, links, chokepoints and civilizations, with adjacency indexes.
/// Built once from JSON and validated on load; queries never fail for ids that came from the map.
public struct GameMap: Sendable, Codable {
    public let version: Int
    public let territories: [Territory]
    public let landLinks: [LandLink]
    public let seas: [SeaZone]
    public let seaLinks: [[SeaZoneID]]
    public let chokepoints: [Chokepoint]
    public let civilizations: [Civilization]
    /// The empires of a game nobody asked otherwise for: every civilization not from an expansion.
    public var baseCivilizations: [Civilization] { civilizations.filter { $0.expansion == nil } }
    /// The named peoples of a generated world, by homeland (the classic map's are in the rules).
    public let peoples: [TerritoryID: People]?
    /// How a generated world is drawn (the classic board's art ships with the app).
    public let art: MapArt?
    /// The seed a generated world was made from; nil for the classic map.
    public let worldSeed: UInt64?

    private let territoryIndex: [TerritoryID: Territory]
    private let seaIndex: [SeaZoneID: SeaZone]
    private let landNeighborIndex: [TerritoryID: [TerritoryID: Crossing?]]
    private let seaNeighborIndex: [SeaZoneID: Set<SeaZoneID>]
    private let coastIndex: [SeaZoneID: [TerritoryID]]

    // MARK: Loading

    private struct File: Codable {
        let version: Int
        let territories: [Territory]
        let landLinks: [LandLink]
        let seas: [SeaZone]
        let seaLinks: [[SeaZoneID]]
        let chokepoints: [Chokepoint]
        let civilizations: [Civilization]
        var peoples: [TerritoryID: People]?
        var art: MapArt?
        var worldSeed: UInt64?
    }

    /// Loads the bundled `map.json`.
    public static func bundled() throws -> GameMap {
        guard let url = Bundle.module.url(forResource: "map", withExtension: "json") else {
            throw MapError.resourceMissing("map.json")
        }
        return try GameMap(json: Data(contentsOf: url))
    }

    public init(json: Data) throws {
        try self.init(file: JSONDecoder().decode(File.self, from: json))
    }

    public init(from decoder: Decoder) throws {
        try self.init(file: File(from: decoder))
    }

    public func encode(to encoder: Encoder) throws {
        try File(version: version, territories: territories, landLinks: landLinks, seas: seas, seaLinks: seaLinks,
                 chokepoints: chokepoints, civilizations: civilizations, peoples: peoples, art: art,
                 worldSeed: worldSeed).encode(to: encoder)
    }

    /// A map from its parts, validated as a loaded one is.
    public init(version: Int, territories: [Territory], landLinks: [LandLink], seas: [SeaZone],
                seaLinks: [[SeaZoneID]], chokepoints: [Chokepoint], civilizations: [Civilization],
                peoples: [TerritoryID: People]? = nil, art: MapArt? = nil, worldSeed: UInt64? = nil) throws {
        try self.init(file: File(version: version, territories: territories, landLinks: landLinks, seas: seas,
                                 seaLinks: seaLinks, chokepoints: chokepoints, civilizations: civilizations,
                                 peoples: peoples, art: art, worldSeed: worldSeed))
    }

    private init(file f: File) throws {
        version = f.version
        territories = f.territories
        landLinks = f.landLinks
        seas = f.seas
        seaLinks = f.seaLinks
        chokepoints = f.chokepoints
        civilizations = f.civilizations
        peoples = f.peoples
        art = f.art
        worldSeed = f.worldSeed

        var tIndex: [TerritoryID: Territory] = [:]
        for t in f.territories {
            guard tIndex.updateValue(t, forKey: t.id) == nil else { throw MapError.duplicateID(t.id) }
            if t.grain < 1 { throw MapError.invalid("territory '\(t.id)' produces less than 1 grain") }
        }
        var sIndex: [SeaZoneID: SeaZone] = [:]
        for s in f.seas {
            guard sIndex.updateValue(s, forKey: s.id) == nil else { throw MapError.duplicateID(s.id) }
        }
        territoryIndex = tIndex
        seaIndex = sIndex

        func checkT(_ id: TerritoryID, _ ctx: String) throws {
            if tIndex[id] == nil { throw MapError.unknownTerritory(id, context: ctx) }
        }
        func checkS(_ id: SeaZoneID, _ ctx: String) throws {
            if sIndex[id] == nil { throw MapError.unknownSea(id, context: ctx) }
        }

        var land: [TerritoryID: [TerritoryID: Crossing?]] = [:]
        for link in f.landLinks {
            try checkT(link.a, "landLinks")
            try checkT(link.b, "landLinks")
            if link.a == link.b { throw MapError.invalid("territory '\(link.a)' linked to itself") }
            if land[link.a]?[link.b] != nil { throw MapError.invalid("duplicate land link \(link.a)-\(link.b)") }
            land[link.a, default: [:]][link.b] = .some(link.crossing)
            land[link.b, default: [:]][link.a] = .some(link.crossing)
        }
        landNeighborIndex = land

        var seaNeighbors: [SeaZoneID: Set<SeaZoneID>] = [:]
        for pair in f.seaLinks {
            guard pair.count == 2 else { throw MapError.invalid("sea link must have 2 entries: \(pair)") }
            try checkS(pair[0], "seaLinks")
            try checkS(pair[1], "seaLinks")
            seaNeighbors[pair[0], default: []].insert(pair[1])
            seaNeighbors[pair[1], default: []].insert(pair[0])
        }
        seaNeighborIndex = seaNeighbors

        var coast: [SeaZoneID: [TerritoryID]] = [:]
        for t in f.territories {
            for s in t.seas {
                try checkS(s, "territory '\(t.id)'")
                coast[s, default: []].append(t.id)
            }
        }
        coastIndex = coast

        for c in f.chokepoints {
            for t in c.heldBy { try checkT(t, "chokepoint '\(c.id)'") }
            if let gate = c.gatesSeaLink {
                guard gate.count == 2, seaNeighbors[gate[0]]?.contains(gate[1]) == true else {
                    throw MapError.invalid("chokepoint '\(c.id)' gates a sea link that doesn't exist")
                }
            }
        }
        for civ in f.civilizations { try checkT(civ.capital, "civilization '\(civ.id)'") }
        if Set(f.civilizations.map(\.capital)).count != f.civilizations.count {
            throw MapError.invalid("two civilizations share a capital")
        }
        for t in (f.peoples ?? [:]).keys { try checkT(t, "peoples") }
        for t in (f.art?.territories ?? [:]).keys { try checkT(t, "art") }
    }

    // MARK: Queries

    public func territory(_ id: TerritoryID) -> Territory? { territoryIndex[id] }
    public func sea(_ id: SeaZoneID) -> SeaZone? { seaIndex[id] }
    public func civilization(_ id: CivilizationID) -> Civilization? {
        civilizations.first { $0.id == id }
    }

    /// Territories sharing a land border with `id`, sorted for deterministic iteration.
    public func landNeighbors(of id: TerritoryID) -> [TerritoryID] {
        (landNeighborIndex[id]?.keys).map { $0.sorted() } ?? []
    }

    public func areLandAdjacent(_ a: TerritoryID, _ b: TerritoryID) -> Bool {
        landNeighborIndex[a]?[b] != nil
    }

    /// The crossing on the border between two adjacent territories, or nil if there is none
    /// (or they aren't adjacent; check `areLandAdjacent` to tell the two apart).
    public func crossing(between a: TerritoryID, and b: TerritoryID) -> Crossing? {
        landNeighborIndex[a]?[b] ?? nil
    }

    /// Sea zones bordering a territory.
    public func seas(bordering id: TerritoryID) -> [SeaZoneID] {
        territoryIndex[id]?.seas ?? []
    }

    /// Territories with a coastline on the given sea zone.
    public func coastalTerritories(of sea: SeaZoneID) -> [TerritoryID] {
        coastIndex[sea] ?? []
    }

    /// Sea zones directly connected to `sea`, sorted for deterministic iteration.
    public func seaNeighbors(of sea: SeaZoneID) -> [SeaZoneID] {
        (seaNeighborIndex[sea]).map { $0.sorted() } ?? []
    }

    /// The chokepoint that gates movement between two sea zones, if any.
    public func chokepoint(gating a: SeaZoneID, _ b: SeaZoneID) -> Chokepoint? {
        chokepoints.first { c in
            guard let g = c.gatesSeaLink else { return false }
            return Set(g) == [a, b]
        }
    }

    /// Territories with no land neighbors; reachable only by sea.
    public var islands: [TerritoryID] {
        territories.map(\.id).filter { landNeighborIndex[$0]?.isEmpty ?? true }
    }
}
