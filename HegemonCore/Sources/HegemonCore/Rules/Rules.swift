import Foundation

public enum UnitType: String, Codable, Sendable, CaseIterable, CodingKeyRepresentable {
    case infantry, archers, cavalry
}

public struct UnitStats: Codable, Sendable, Equatable {
    /// Gold to recruit one unit.
    public let cost: Int
    /// Grain eaten per turn.
    public let upkeep: Int
    /// Resource the empire must produce to recruit this unit. Each point of yield allows one
    /// recruit of this type per turn.
    public let requires: Resource?
}

public struct PrestigeRules: Codable, Sendable, Equatable {
    public let perTerritory: Int
    public let perPopulation: Int
    /// Prestige gains 1 per this much gold in the treasury.
    public let goldDivisor: Int
    public let legitimacyDivisor: Int
    /// Bonus for still holding your own capital.
    public let capitalHeld: Int
}

public struct VictoryRules: Codable, Sendable, Equatable {
    /// Holding this share of all territories wins (domination).
    public let territoryPercent: Int
    /// If nobody has won by the end of this round, the highest prestige wins (legacy).
    public let roundLimit: Int
    /// Domination or trade victories before this round are decisive.
    public let decisiveBefore: Int
    /// Rounds a civ must hold every sea chokepoint while trading with every rival (trade victory).
    public let tradeRoundsHeld: Int
    /// A legacy win is major when the winner's prestige is at least this percent of the runner-up's.
    public let majorLegacyMargin: Int
    public let prestige: PrestigeRules
}

public struct EconomyRules: Codable, Sendable, Equatable {
    /// Mouths fed by one grain. An empire's population eats `ceil(population / populationPerGrain)`.
    public let populationPerGrain: Int
    /// A territory's population can grow to `grain × populationCapPerGrain`. At the cap, a
    /// territory still has grain left over to feed armies.
    public let populationCapPerGrain: Int
    /// Maximum population growth per territory per turn.
    public let growthPerTerritory: Int
    /// Gold income per turn is `total population / populationPerGold`, plus gold yields.
    public let populationPerGold: Int
    /// The granary holds at most this many turns of grain production.
    public let granaryCapTurns: Int
    /// Starvation and recruitment never take a territory below this population.
    public let minPopulation: Int
    /// The tax rate (percent) at which taxes are `population / populationPerGold` and legitimacy
    /// and growth are unaffected.
    public let defaultTax: Int
    /// Legitimacy changes by 1 a turn for every this many points the tax rate is below (+) or
    /// above (−) the default. Above the default, growth slows in proportion.
    public let taxLegitimacyStep: Int
    /// Most of any stockpiled resource a civilization can hold.
    public let stockCap: Int
    /// Gold per unit of wine and oil produced, and extra per unit exported to a partner lacking it.
    public let winePerGold: Int
    public let wineExportCap: Int
    /// Legitimacy +1 a turn per this many luxuries within reach, up to the cap.
    public let luxuriesPerLegitimacy: Int
    public let luxuryLegitimacyCap: Int
}

/// Building projects in territories: the "industrializing" side of the economy.
public enum ProjectKind: String, Codable, Sendable, CaseIterable, CodingKeyRepresentable {
    /// Supply lines through this territory cost nothing.
    case road
    /// The defender takes less damage here.
    case walls
    /// More grain.
    case farm
    /// More of each ore the territory already yields.
    case mine
    /// Trade income, and cheaper ships built here.
    case harbor
}

public struct ProjectCost: Codable, Sendable, Equatable {
    public let gold: Int
    public let stone: Int
    public let timber: Int
    public let turns: Int
}

public struct ProjectEffects: Codable, Sendable, Equatable {
    public let farmGrain: Int
    public let farmRiverValleyGrain: Int
    public let mineBonus: Int
    public let wallsDefensePercent: Int
    public let harborGold: Int
    public let harborShipDiscount: Int
}

public struct SupplyRules: Codable, Sendable, Equatable {
    /// Units lost per stack per turn when cut off from the home supply network.
    public let outOfSupplyAttrition: Int
    /// Extra units lost when the cut-off stack is in desert.
    public let desertAttrition: Int
    /// Each unit eats one more grain for every this many steps along its supply route from the
    /// seat (a sea crossing counts as 2 steps). Distant armies strain the granary.
    public let stepsPerExtraGrain: Int
}

public struct TradeRules: Codable, Sendable, Equatable {
    /// Gold each side earns per trade route per turn, before tolls.
    public let goldPerRoute: Int
    /// Gold a third-party chokepoint holder takes from each side of a route crossing it.
    public let chokepointToll: Int
    /// A trade partner shares `yield / shareDivisor` of each non-grain resource.
    public let shareDivisor: Int
}

public struct StartRules: Codable, Sendable, Equatable {
    public let gold: Int
    public let granary: Int
    /// Starting population of every territory, as a percentage of its population cap
    /// (rounded up, at least 1).
    public let populationPercent: Int
    /// Army placed in each civilization's capital.
    public let army: UnitCounts
    /// The general leading each civilization's starting army.
    public let generals: [CivilizationID: StartingGeneral]
    /// Native garrisons in unclaimed territories.
    public let natives: NativeRules
    /// Territories each civilization holds at the start besides its capital (its heartland).
    public let realms: [CivilizationID: [TerritoryID]]
}

/// Every territory no civilization starts in is held by local tribes: `base + grain / grainPerUnit`
/// infantry that defend but never move. Conquering them costs armies in proportion to the
/// land's worth.
public struct NativeRules: Codable, Sendable, Equatable {
    public let base: Int
    public let grainPerUnit: Int
}

/// Tunable game rules, loaded from `rules.json`.
public struct Rules: Codable, Sendable, Equatable {
    public let version: Int
    public let units: [UnitType: UnitStats]
    public let victory: VictoryRules
    public let economy: EconomyRules
    public let projects: [ProjectKind: ProjectCost]
    public let projectEffects: ProjectEffects
    public let supply: SupplyRules
    public let trade: TradeRules
    public let ships: ShipRules
    public let battle: BattleRules
    public let naval: NavalRules
    public let generals: GeneralRules
    public let government: GovernmentRules
    public let rulerTraits: [RulerTrait: RulerTraitEffects]
    public let events: EventRules
    public let names: [CivilizationID: NameLists]
    public let start: StartRules

    public static func bundled() throws -> Rules {
        guard let url = Bundle.module.url(forResource: "rules", withExtension: "json") else {
            throw MapError.resourceMissing("rules.json")
        }
        return try Rules(json: Data(contentsOf: url))
    }

    public init(json: Data) throws {
        self = try JSONDecoder().decode(Rules.self, from: json)
        for type in UnitType.allCases where units[type] == nil {
            throw MapError.invalid("rules.json has no stats for unit '\(type.rawValue)'")
        }
        if economy.populationPerGold < 1 || economy.populationPerGrain < 1 || economy.populationCapPerGrain < 1
            || trade.shareDivisor < 1 || supply.stepsPerExtraGrain < 1 {
            throw MapError.invalid("rules.json economy divisors must be at least 1")
        }
        guard battle.formation(battle.defaultFormation) != nil else {
            throw MapError.invalid("rules.json default formation '\(battle.defaultFormation)' is not defined")
        }
        for t in Terrain.allCases where battle.terrain[t] == nil {
            throw MapError.invalid("rules.json has no battle rules for terrain '\(t.rawValue)'")
        }
        for type in UnitType.allCases {
            guard battle.attack[type] != nil, battle.speed[type] != nil,
                  UnitType.allCases.allSatisfy({ battle.matchupPercent[type]?[$0] != nil }) else {
                throw MapError.invalid("rules.json battle stats incomplete for '\(type.rawValue)'")
            }
        }
    }

    public func stats(_ type: UnitType) -> UnitStats { units[type]! }

    /// Grain eaten per turn by a population.
    public func grainEaten(byPopulation population: Int) -> Int {
        (population + economy.populationPerGrain - 1) / economy.populationPerGrain
    }

    public func populationCap(grain: Int) -> Int {
        grain * economy.populationCapPerGrain
    }

    public func startingPopulation(grain: Int) -> Int {
        max(1, (populationCap(grain: grain) * start.populationPercent + 99) / 100)
    }

    public func upkeep(of units: UnitCounts) -> Int {
        UnitType.allCases.reduce(0) { $0 + units[$1] * stats($1).upkeep }
    }
}
