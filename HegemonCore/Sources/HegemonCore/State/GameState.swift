/// Per-territory facts that change during a game.
public struct TerritoryState: Codable, Sendable, Equatable {
    public var owner: CivilizationID?
    public var population: Int
}

/// Per-civilization facts that change during a game.
public struct CivState: Codable, Sendable, Equatable {
    public var gold: Int
    /// Stored grain, drawn on when consumption exceeds production.
    public var granary: Int
    public var eliminated: Bool = false
    /// Stockpiled bronze, made each turn from copper and tin.
    public var bronze: Int = 0
    /// Recruits of resource-limited units this turn, by resource (e.g. cavalry against horses).
    public var resourceUsedThisTurn: [Resource: Int] = [:]
}

/// An unordered pair of civilizations, for relations.
public struct CivPair: Codable, Sendable, Hashable {
    public let a: CivilizationID
    public let b: CivilizationID

    public init(_ x: CivilizationID, _ y: CivilizationID) {
        (a, b) = x < y ? (x, y) : (y, x)
    }
}

public struct PeaceOffer: Codable, Sendable, Hashable {
    public let from: CivilizationID
    public let to: CivilizationID
}

/// An army stack in a territory. At most one civilization has an army in a territory;
/// moving into a territory held by another civilization's army is a battle (build step 4).
public struct Army: Codable, Sendable, Equatable {
    public var owner: CivilizationID
    public var units: UnitCounts
}

/// Everything that changes during a game. Fully Codable so a game can be saved, reloaded,
/// or attached to a bug report as JSON. Static map data and rules are not stored here;
/// `mapVersion` and `rulesVersion` record which ones the state was built against.
///
/// Dictionaries here have no stable iteration order. Engine code must sort keys before
/// iterating whenever order affects the result.
public struct GameState: Codable, Sendable, Equatable {
    public var mapVersion: Int
    public var rulesVersion: Int
    public var seed: UInt64
    public var turn: Int
    public var rng: SeededRNG
    /// Civilizations in play, in turn order.
    public var players: [CivilizationID]
    public var activePlayerIndex: Int
    public var winner: CivilizationID?
    public var land: [TerritoryID: TerritoryState]
    public var civs: [CivilizationID: CivState]
    public var armies: [TerritoryID: Army]
    /// Units that have already moved this turn, by the territory they moved into.
    public var moved: [TerritoryID: UnitCounts]
    /// Pairs of civilizations at peace. Everyone else is at war.
    public var peace: Set<CivPair>
    /// Outstanding peace offers, accepted by the recipient on their turn.
    public var peaceOffers: Set<PeaceOffer>

    /// Starts a new game. Each participating civilization begins holding only its capital,
    /// with the starting army there; everything else is unowned. Everyone starts at war.
    public init(map: GameMap, rules: Rules, seed: UInt64, civilizations: [CivilizationID]? = nil) throws {
        let ids = civilizations ?? map.civilizations.map(\.id)
        guard !ids.isEmpty else { throw MapError.invalid("a game needs at least one civilization") }
        guard Set(ids).count == ids.count else { throw MapError.invalid("duplicate civilization in game setup") }

        var land: [TerritoryID: TerritoryState] = [:]
        for t in map.territories {
            land[t.id] = TerritoryState(owner: nil, population: rules.startingPopulation(grain: t.grain))
        }
        var civs: [CivilizationID: CivState] = [:]
        var armies: [TerritoryID: Army] = [:]
        for id in ids {
            guard let civ = map.civilization(id) else {
                throw MapError.invalid("unknown civilization '\(id)'")
            }
            land[civ.capital]!.owner = civ.id
            civs[civ.id] = CivState(gold: rules.start.gold, granary: rules.start.granary)
            if !rules.start.army.isEmpty {
                armies[civ.capital] = Army(owner: civ.id, units: rules.start.army)
            }
        }

        self.mapVersion = map.version
        self.rulesVersion = rules.version
        self.seed = seed
        self.turn = 1
        self.rng = SeededRNG(seed: seed)
        self.players = ids
        self.activePlayerIndex = 0
        self.winner = nil
        self.land = land
        self.civs = civs
        self.armies = armies
        self.moved = [:]
        self.peace = []
        self.peaceOffers = []
    }

    public var activePlayer: CivilizationID { players[activePlayerIndex] }

    public func atPeace(_ a: CivilizationID, _ b: CivilizationID) -> Bool {
        peace.contains(CivPair(a, b))
    }

    /// Distinct civilizations are at war unless they have made peace.
    public func atWar(_ a: CivilizationID, _ b: CivilizationID) -> Bool {
        a != b && !atPeace(a, b)
    }

    public func owner(of territory: TerritoryID) -> CivilizationID? {
        land[territory]?.owner
    }

    public func population(of territory: TerritoryID) -> Int {
        land[territory]?.population ?? 0
    }

    /// Territories held by a civilization, sorted for deterministic iteration.
    public func territories(of civ: CivilizationID) -> [TerritoryID] {
        land.filter { $0.value.owner == civ }.map(\.key).sorted()
    }

    /// Army stacks owned by a civilization, by territory, sorted for deterministic iteration.
    public func armies(of civ: CivilizationID) -> [(territory: TerritoryID, units: UnitCounts)] {
        armies.filter { $0.value.owner == civ }.map { ($0.key, $0.value.units) }.sorted { $0.0 < $1.0 }
    }

    public func totalUnits(of civ: CivilizationID) -> UnitCounts {
        armies(of: civ).reduce(.zero) { $0 + $1.units }
    }

    public func totalPopulation(of civ: CivilizationID) -> Int {
        territories(of: civ).reduce(0) { $0 + population(of: $1) }
    }
}
