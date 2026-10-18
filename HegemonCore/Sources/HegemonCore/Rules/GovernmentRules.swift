/// Legitimacy changes, in points (legitimacy runs 0–100).
public struct LegitimacyChanges: Codable, Sendable, Equatable {
    public let battleWon: Int
    public let battleLost: Int
    public let capture: Int
    public let capitalLost: Int
    public let starvation: Int
    public let brokePeace: Int
    /// A smooth succession.
    public let succession: Int
    /// A child or missing heir: a regency.
    public let regency: Int
    /// Paying off claimants in a contested succession.
    public let bribe: Int
}

public struct GovernmentRules: Codable, Sendable, Equatable {
    public let startLegitimacy: Int
    /// Legitimacy drifts this many points per turn toward 50.
    public let legitimacyDrift: Int
    public let legitimacy: LegitimacyChanges

    public let startLoyalty: Int
    /// A general's loyalty target is legitimacy − renown × this − supply steps from the seat × loyaltyPerStep.
    public let loyaltyPerRenown: Int
    public let loyaltyPerStep: Int
    /// Loyalty moves this fraction (1/n) of the way to its target each turn.
    public let loyaltyDriftDivisor: Int
    /// Gold per general per turn; unpaid generals lose `unpaidLoyalty`.
    public let generalPay: Int
    public let unpaidLoyalty: Int
    /// Honoring a general costs `honorCost × (1 + renown)` gold and adds `honorLoyalty`.
    public let honorCost: Int
    public let honorLoyalty: Int
    public let appointCost: Int
    /// A civilization may keep `1 + territories / territoriesPerGeneral` generals.
    public let territoriesPerGeneral: Int

    /// Below this loyalty, a general leading an army away from the capital may rebel:
    /// `rebellionChancePerPoint`% per point below, per turn.
    public let rebellionLoyalty: Int
    public let rebellionChancePerPoint: Int
    public let minRebelArmy: Int
    /// When a ruler dies, generals below this loyalty who lead an army rise up.
    public let successionDisloyalty: Int
    /// In a contested monarchy succession, generals with renown below this loyalty press claims.
    public let claimantLoyalty: Int
    public let bribePerClaimant: Int
    /// A monarchy below this legitimacy can't pass the crown smoothly.
    public let minSmoothLegitimacy: Int
    /// A republic's general with at least this renown and below this loyalty seizes power.
    public let coupRenown: Int
    public let coupLoyalty: Int

    public let rulerStartAge: [Int]
    public let heirAgeGap: [Int]
    public let electedAge: [Int]
    public let adultAge: Int
    /// Chance per turn (percent) that a monarch without an heir gets one.
    public let heirBirthChance: Int
    /// Death chance per turn: `baseDeathChance`%, plus `deathChancePerYear`% per year past `deathAge`.
    public let deathAge: Int
    public let baseDeathChance: Int
    public let deathChancePerYear: Int
}

public enum RulerTrait: String, Codable, Sendable, CaseIterable, CodingKeyRepresentable {
    case ableAdministrator, pious, cruel, weak
}

public struct RulerTraitEffects: Codable, Sendable, Equatable {
    public var incomePercent: Int?
    public var legitimacyPerTurn: Int?
    /// Shifts every general's loyalty target.
    public var loyaltyTarget: Int?
}

public enum EventKind: String, Codable, Sendable, CaseIterable {
    case famine, flood, goodHarvest, plague, goldDiscovered, badOmen, barbarians, revolt
    // The collapse
    case seaPeoples, drought, earthquake, tradeDisrupted
}

public struct EventWeights: Codable, Sendable, Equatable {
    public let famine: Int
    public let famineRiverValley: Int
    public let faminePressure: Int
    public let flood: Int
    public let goodHarvest: Int
    public let goodHarvestRiverValley: Int
    public let plague: Int
    public let plaguePerRoute: Int
    public let goldDiscovered: Int
    public let goldPerHill: Int
    public let omenPerLegitimacyPoint: Int
    public let barbariansPerExposure: Int
    public let revoltPerDistantTerritory: Int
}

public struct EventRules: Codable, Sendable, Equatable {
    /// Chance (percent) that a civilization draws an event at the start of its turn.
    public let chancePercent: Int
    public let famineGrainPercent: Int
    public let goodHarvestGrainPercent: Int
    public let floodPopulation: Int
    public let plaguePopulationPercent: Int
    /// Plague strikes this many of the most populous home territories.
    public let plagueTerritories: Int
    public let plagueRulerDeathPercent: Int
    /// Chance (percent) that a plague travels to each trade partner.
    public let plagueSpreadPercent: Int
    /// Barbarian hordes have `barbarianBase + turn / barbarianTurnsPerExtra` units.
    public let barbarianBase: Int
    public let barbarianTurnsPerExtra: Int
    /// Territories at least this many supply steps from the seat can revolt.
    public let revoltDistance: Int
    public let weights: EventWeights
}

public struct NameLists: Codable, Sendable, Equatable {
    public let rulers: [String]
    public let generals: [String]
}
