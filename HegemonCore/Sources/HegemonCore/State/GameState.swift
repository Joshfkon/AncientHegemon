/// The owner of native garrisons. Not a player: natives never act, trade or make peace.
public let nativesID: CivilizationID = "natives"
/// The owner of barbarian hordes, which raid when a migration event strikes. Not a player.
public let barbariansID: CivilizationID = "barbarians"

/// The ways to win.
public enum VictoryKind: String, Codable, Sendable {
    /// Held the required share of the map.
    case domination
    /// Held every sea chokepoint while trading with every rival, for long enough.
    case trade
    /// Highest prestige when the round limit ran out.
    case legacy
    /// Every rival was destroyed.
    case lastStanding
}

/// How convincing a win was.
public enum VictoryGrade: String, Codable, Sendable, Comparable {
    case minor, major, decisive

    public static func < (a: Self, b: Self) -> Bool {
        let order: [Self] = [.minor, .major, .decisive]
        return order.firstIndex(of: a)! < order.firstIndex(of: b)!
    }
}

public struct Victory: Codable, Sendable, Equatable {
    public let kind: VictoryKind
    public let grade: VictoryGrade
    public let round: Int
    /// Every civilization, best first: survivors by prestige, then the fallen, last to fall first.
    public let standings: [CivilizationID]
}

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
    /// The round this civ fell, for the final standings.
    public var eliminatedOnRound: Int?
    /// Stockpiled bronze, made each turn from copper and tin.
    public var bronze: Int = 0
    /// Recruits of resource-limited units this turn, by resource (e.g. cavalry against horses).
    public var resourceUsedThisTurn: [Resource: Int] = [:]
    public var government: Government = .monarchy
    public var ruler = Ruler(name: "", age: 30, trait: .ableAdministrator)
    /// The monarchy's heir. Republics have none.
    public var heir: Heir?
    /// The ruler's standing, 0–100.
    public var legitimacy = 50
    /// A bad omen this turn: no attacks.
    public var omen = false
    /// Plague arriving along a trade route: strikes at the start of this civ's next turn.
    public var plagueIncoming = false
    /// For civilizations born in a civil war: the realm they split from and their name.
    public var rebelledFrom: CivilizationID?
    public var displayName: String?
}

public struct Ruler: Codable, Sendable, Equatable {
    public var name: String
    public var age: Int
    public var trait: RulerTrait
}

public struct Heir: Codable, Sendable, Equatable {
    public var name: String
    public var age: Int
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
    /// The formation this army fights in, attacking or defending. Nil means the rules' default.
    public var formation: FormationID?

    public init(owner: CivilizationID, units: UnitCounts, formation: FormationID? = nil) {
        self.owner = owner
        self.units = units
        self.formation = formation
    }
}

/// A civilization's ships in a sea zone, with the land units they carry. Civilizations at peace
/// can share a sea; civilizations at war fight when one sails into the other.
public struct Fleet: Codable, Sendable, Equatable {
    public var sea: SeaZoneID
    public var owner: CivilizationID
    public var ships: Int
    /// Ships that have already sailed or been built this turn.
    public var movedShips: Int = 0
    public var cargo: UnitCounts = .zero
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
    /// How the game was won, once it is.
    public var victory: Victory?
    /// Consecutive rounds each civ has held the conditions for a trade victory.
    public var tradeHold: [CivilizationID: Int]
    public var land: [TerritoryID: TerritoryState]
    public var civs: [CivilizationID: CivState]
    public var armies: [TerritoryID: Army]
    /// Units that have already moved this turn, by the territory they moved into.
    public var moved: [TerritoryID: UnitCounts]
    public var generals: [GeneralID: General]
    public var fleets: [Fleet]
    /// Generals who have already moved this turn.
    public var generalsMoved: Set<GeneralID>
    /// Pairs of civilizations at peace. Everyone else is at war.
    public var peace: Set<CivPair>
    /// Outstanding peace offers, accepted by the recipient on their turn.
    public var peaceOffers: Set<PeaceOffer>
    /// Harvest multipliers (percent) from this turn's events, used and cleared by the next harvest.
    public var harvestPercent: [TerritoryID: Int]
    /// Gold yields found by events, on top of the map's.
    public var bonusGold: [TerritoryID: Int]
    /// Civil wars so far; numbers the rebel factions.
    public var rebellions: Int

    /// Starts a new game. Each participating civilization begins holding its capital and
    /// heartland, with the starting army in the capital; everything else is unowned and held
    /// by native garrisons.
    /// Everyone starts at war.
    public init(map: GameMap, rules: Rules, seed: UInt64, civilizations: [CivilizationID]? = nil) throws {
        let ids = civilizations ?? map.civilizations.map(\.id)
        guard !ids.isEmpty else { throw MapError.invalid("a game needs at least one civilization") }
        guard Set(ids).count == ids.count else { throw MapError.invalid("duplicate civilization in game setup") }

        var land: [TerritoryID: TerritoryState] = [:]
        for t in map.territories {
            land[t.id] = TerritoryState(owner: nil, population: rules.startingPopulation(grain: t.grain))
        }
        var civs: [CivilizationID: CivState] = [:]
        var rng = SeededRNG(seed: seed)
        var armies: [TerritoryID: Army] = [:]
        var generals: [GeneralID: General] = [:]
        for id in ids {
            guard let civ = map.civilization(id) else {
                throw MapError.invalid("unknown civilization '\(id)'")
            }
            land[civ.capital]!.owner = civ.id
            for t in rules.start.realms[civ.id] ?? [] {
                guard land[t] != nil else { throw MapError.unknownTerritory(t, context: "start realm of '\(civ.id)'") }
                land[t]!.owner = civ.id
            }
            var cs = CivState(gold: rules.start.gold, granary: rules.start.granary)
            let g = rules.government
            cs.government = civ.government
            cs.legitimacy = g.startLegitimacy
            cs.ruler = Ruler(name: Self.pickName(rules.names[civ.id]?.rulers, &rng),
                             age: Self.roll(g.rulerStartAge, &rng), trait: RulerTrait.allCases.randomElement(using: &rng)!)
            if civ.government == .monarchy {
                cs.heir = Heir(name: Self.pickName(rules.names[civ.id]?.rulers, &rng),
                               age: max(0, cs.ruler.age - Self.roll(g.heirAgeGap, &rng)))
            }
            civs[civ.id] = cs
            if !rules.start.army.isEmpty {
                armies[civ.capital] = Army(owner: civ.id, units: rules.start.army)
            }
            if let g = rules.start.generals[civ.id] {
                let gid = "\(civ.id)-1"
                generals[gid] = General(id: gid, name: g.name, owner: civ.id, trait: g.trait,
                                        renown: 0, location: civ.capital, loyalty: rules.government.startLoyalty)
            }
        }

        let natives = rules.start.natives
        for t in map.territories where land[t.id]!.owner == nil {
            let count = natives.base + t.grain / max(1, natives.grainPerUnit)
            if count > 0 { armies[t.id] = Army(owner: nativesID, units: UnitCounts(infantry: count)) }
        }

        self.mapVersion = map.version
        self.rulesVersion = rules.version
        self.seed = seed
        self.turn = 1
        self.rng = rng
        self.players = ids
        self.activePlayerIndex = 0
        self.winner = nil
        self.victory = nil
        self.tradeHold = [:]
        self.land = land
        self.civs = civs
        self.armies = armies
        self.moved = [:]
        self.generals = generals
        self.fleets = []
        self.generalsMoved = []
        self.peace = []
        self.harvestPercent = [:]
        self.bonusGold = [:]
        self.rebellions = 0
        self.peaceOffers = []
    }

    public var activePlayer: CivilizationID { players[activePlayerIndex] }

    /// A uniform pick from an inclusive `[low, high]` range.
    static func roll(_ range: [Int], _ rng: inout SeededRNG) -> Int {
        let low = range.first ?? 0, high = max(low, range.last ?? low)
        return low + Int(rng.next() % UInt64(high - low + 1))
    }

    static func pickName(_ names: [String]?, _ rng: inout SeededRNG) -> String {
        guard let names, !names.isEmpty else { return "Unnamed" }
        return names[Int(rng.next() % UInt64(names.count))]
    }

    /// Players are civilizations with a `CivState`; natives and barbarians are not.
    public func isPlayer(_ civ: CivilizationID?) -> Bool {
        civ.map { civs[$0] != nil } ?? false
    }

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

    /// Units in a civilization's armies on land (not counting cargo at sea).
    public func totalUnits(of civ: CivilizationID) -> UnitCounts {
        armies(of: civ).reduce(.zero) { $0 + $1.units }
    }

    public func fleet(of civ: CivilizationID, in sea: SeaZoneID) -> Fleet? {
        fleets.first { $0.owner == civ && $0.sea == sea }
    }

    public func fleets(of civ: CivilizationID) -> [Fleet] {
        fleets.filter { $0.owner == civ }
    }

    /// The living general of a civilization standing in a territory, if any.
    public func general(of civ: CivilizationID, at territory: TerritoryID) -> General? {
        generals.values.filter { $0.owner == civ && $0.location == territory }.min { $0.id < $1.id }
    }

    public func totalPopulation(of civ: CivilizationID) -> Int {
        territories(of: civ).reduce(0) { $0 + population(of: $1) }
    }
}
