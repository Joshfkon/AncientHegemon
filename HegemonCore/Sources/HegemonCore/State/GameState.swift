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
    /// Finished projects. They stay when the land changes hands.
    public var improvements: Set<ProjectKind> = []
    /// A project under way, lost if the land changes hands.
    public var construction: Construction?
    /// The round it last changed hands by conquest or submission (it is restless for a while).
    public var takenOnRound: Int?
    /// Projects to start, in order, as the one under way finishes (paid for when each starts).
    public var queue: [ProjectKind] = []
}

public struct Construction: Codable, Sendable, Equatable {
    public let kind: ProjectKind
    public var turnsLeft: Int

    public init(kind: ProjectKind, turnsLeft: Int) {
        self.kind = kind
        self.turnsLeft = turnsLeft
    }
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
    /// Played by a person: succession crises wait for their decision instead of resolving.
    public var isHuman = false
    /// Percent of the people's wealth taken in taxes.
    public var taxRate = 40
    /// Stockpiled stone, timber and iron.
    public var stock: [Resource: Int] = [:]
    /// Progress in each field of knowledge.
    public var knowledge: [KnowledgeField: Int] = [:]
    /// Recent practice in each field, which steers where new knowledge goes.
    public var experience: [KnowledgeField: Int] = [:]
    /// A contested succession awaiting the human ruler's decision. Nothing else can be ordered
    /// until it is resolved.
    public var crisis: SuccessionCrisis?
    /// The throne room: decorations bought and trophies won.
    public var decorations: Set<DecorationID> = []
    public var trophies: [Trophy] = []
    /// The field of learning the court pays for, if any.
    public var patronage: KnowledgeField?
    /// A dilemma waiting for a person's answer this turn.
    public var decision: DecisionKind?
    /// Rounds left in an age of splendour, and rounds before another can begin.
    public var splendour = 0
    public var splendourRest = 0
    /// Rivals' capitals this civ has sacked.
    public var sacked = 0
}

/// Rival claimants to a contested throne, and what buying them off would cost.
public struct SuccessionCrisis: Codable, Sendable, Equatable {
    /// Generals pressing a claim, strongest first.
    public let claimants: [GeneralID]
    public let bribeCost: Int
    /// The new ruler (the heir or regent) if the crisis is weathered.
    public let ruler: String

    public init(claimants: [GeneralID], bribeCost: Int, ruler: String) {
        self.claimants = claimants
        self.bribeCost = bribeCost
        self.ruler = ruler
    }
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

    public init(from: CivilizationID, to: CivilizationID) {
        self.from = from
        self.to = to
    }
}

/// An army stack in a territory. At most one civilization has an army in a territory;
/// moving into a territory held by another civilization's army is a battle (build step 4).
public struct Army: Codable, Sendable, Equatable {
    public var owner: CivilizationID
    public var units: UnitCounts
    /// The formation this army fights in, attacking or defending. Nil means the rules' default.
    public var formation: FormationID?
    public var depth: LineDepth?
    public var stratagem: Stratagem?
    /// Holds the field rather than chasing a broken enemy (nil or false: pursue).
    public var holdBack: Bool?
    /// The soldiers' average number of battles survived (nil: green).
    public var battles: Int?
    /// Blocks placed by hand and given their own orders on the battlefield (see `BattlePlan`).
    public var placements: [Int: GridPoint]?
    public var orders: [Int: BlockOrder]?

    public init(owner: CivilizationID, units: UnitCounts, formation: FormationID? = nil) {
        self.owner = owner
        self.units = units
        self.formation = formation
    }

    public var plan: BattlePlan {
        BattlePlan(formation: formation, depth: depth ?? .deep, stratagem: stratagem, pursue: !(holdBack ?? false),
                   placements: placements, orders: orders)
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
    /// Battle honours of the troops aboard.
    public var cargoBattles: Int?
    /// How the ships fight: formation, line, stratagem, whether they chase.
    public var formation: FormationID?
    public var depth: LineDepth?
    public var stratagem: Stratagem?
    public var holdBack: Bool?

    public init(sea: SeaZoneID, owner: CivilizationID, ships: Int, movedShips: Int = 0, cargo: UnitCounts = .zero) {
        self.sea = sea
        self.owner = owner
        self.ships = ships
        self.movedShips = movedShips
        self.cargo = cargo
    }

    public var plan: BattlePlan {
        BattlePlan(formation: formation, depth: depth ?? .deep, stratagem: stratagem, pursue: !(holdBack ?? false))
    }
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
    /// Play went on after the victory ("one more turn"). Optional, so older saves still load.
    public var playingOn: Bool?
    /// Difficulty, scenario, the round it ends (if not the rules'), and places worth extra
    /// prestige to whoever holds them. Optional, so older saves still load.
    public var difficulty: Difficulty?
    public var scenario: ScenarioID?
    public var roundLimit: Int?
    public var objectives: [TerritoryID: Int]?
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
    /// Trade routes broken by the collapse, with the last round they stay broken.
    public var disruptedRoutes: [CivPair: Int]
    /// Tribes already approached this turn.
    public var parleyed: Set<TerritoryID> = []
    /// Units that marched along a road this turn without fighting, by where they are now: they
    /// may make one more move.
    public var roadMoved: [TerritoryID: UnitCounts] = [:]
    /// Generals who took a road step this turn (they may march once more, once).
    public var generalsRoadMoved: Set<GeneralID> = []
    /// Defensive alliances, alliance offers waiting for a person's answer, allies' calls to
    /// arms waiting for one, and the allies already asked this turn.
    public var alliances: Set<CivPair> = []
    public var allianceOffers: Set<PeaceOffer> = []
    public var warRequests: Set<WarRequest> = []
    public var calledToWar: Set<CivilizationID> = []
    /// Finished great works and where they stand; works under way, by territory.
    public var monuments: [MonumentID: TerritoryID] = [:]
    public var monumentSites: [TerritoryID: MonumentSite] = [:]
    /// Peace offers turned down, with the last round the offerer stays silent.
    public var peaceRebuffed: [PeaceOffer: Int] = [:]
    /// Walled towns under siege, by the town.
    public var sieges: [TerritoryID: Siege] = [:]
    /// The collapse has brought iron within everyone's reach.
    public var ironAge = false

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
        var startingFleets: [Fleet] = []
        for id in ids {
            guard let civ = map.civilization(id) else {
                throw MapError.invalid("unknown civilization '\(id)'")
            }
            land[civ.capital]!.owner = civ.id
            for t in rules.start.realms[civ.id] ?? [] {
                guard land[t] != nil else { throw MapError.unknownTerritory(t, context: "start realm of '\(civ.id)'") }
                land[t]!.owner = civ.id
            }
            var cs = CivState(gold: rules.start.gold, granary: rules.start.granaries?[civ.id] ?? rules.start.granary)
            let g = rules.government
            cs.government = civ.government
            cs.legitimacy = g.startLegitimacy
            cs.taxRate = rules.economy.defaultTax
            cs.ruler = Ruler(name: Self.pickName(rules.names[civ.id]?.rulers, &rng),
                             age: Self.roll(g.rulerStartAge, &rng), trait: RulerTrait.allCases.randomElement(using: &rng)!)
            if civ.government == .monarchy {
                cs.heir = Heir(name: Self.pickName(rules.names[civ.id]?.rulers, &rng),
                               age: max(0, cs.ruler.age - Self.roll(g.heirAgeGap, &rng)))
            }
            for (field, points) in rules.start.knowledge?[civ.id] ?? [:] { cs.knowledge[field] = points }
            civs[civ.id] = cs
            let army = rules.start.armies?[civ.id] ?? rules.start.army
            if !army.isEmpty {
                armies[civ.capital] = Army(owner: civ.id, units: army)
            }
            if let fleet = rules.start.fleets?[civ.id] {
                guard map.seas(bordering: civ.capital).contains(fleet.sea) else {
                    throw MapError.invalid("starting fleet of '\(civ.id)' must be in a sea next to its capital")
                }
                startingFleets.append(Fleet(sea: fleet.sea, owner: civ.id, ships: fleet.ships))
            }
            if let g = rules.start.generals[civ.id] {
                let gid = "\(civ.id)-1"
                generals[gid] = General(id: gid, name: g.name, owner: civ.id, trait: g.trait,
                                        renown: 0, location: civ.capital, loyalty: rules.government.startLoyalty)
            }
        }

        let natives = rules.start.natives
        for t in map.territories where land[t.id]!.owner == nil {
            let count = natives.tribe(in: t, island: map.landNeighbors(of: t.id).isEmpty)
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
        self.fleets = startingFleets
        self.generalsMoved = []
        self.peace = []
        self.harvestPercent = [:]
        self.bonusGold = [:]
        self.rebellions = 0
        self.disruptedRoutes = [:]
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
