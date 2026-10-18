/// A square on the 5×5 battle board, encoded in JSON as `[col, row]`.
/// Rows 0–1 are the attacker's, row 2 is no-man's-land, rows 3–4 are the defender's.
/// In formation slots, the second number is a rank instead: 0 = front, 1 = back.
public struct GridPoint: Codable, Sendable, Hashable {
    public var col: Int
    public var row: Int

    public init(_ col: Int, _ row: Int) {
        self.col = col
        self.row = row
    }

    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        col = try c.decode(Int.self)
        row = try c.decode(Int.self)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(col)
        try c.encode(row)
    }

    func distance(to other: GridPoint) -> Int {
        abs(col - other.col) + abs(row - other.row)
    }
}

public typealias FormationID = String

public struct Formation: Codable, Sendable, Equatable, Identifiable {
    public let id: FormationID
    public let name: String
    /// Unit types in the order they claim slots.
    public let order: [UnitType]
    /// Preferred `[col, rank]` slots per unit type, best first.
    public let slots: [UnitType: [GridPoint]]
    /// Whether each unit type advances toward the enemy or holds its ground.
    public let advance: [UnitType: Bool]
}

public struct TerrainBattleRules: Codable, Sendable, Equatable {
    /// Attack bonus or penalty per unit type, in percent.
    public let unitPercent: [UnitType: Int]
    /// Damage reduction for the defender, in percent.
    public let defensePercent: Int
    /// Board squares nobody can enter.
    public let impassable: [GridPoint]
    /// Overrides the default archer range.
    public let archerRange: Int?
}

public struct BattleRules: Codable, Sendable, Equatable {
    public let hpPerUnit: Int
    /// Each side fields at most this many blocks; bigger armies make heavier blocks.
    public let maxBlocks: Int
    /// After this many rounds without a result, the defender holds.
    public let maxRounds: Int
    /// The attacker's holding blocks start advancing after this many rounds.
    public let attackerHoldRounds: Int
    public let attack: [UnitType: Int]
    public let speed: [UnitType: Int]
    public let archerRange: Int
    public let archerMeleePercent: Int
    /// Extra damage on a cavalry block's first melee attack.
    public let chargeBonusPercent: Int
    /// Damage multiplier by attacker type, then target type.
    public let matchupPercent: [UnitType: [UnitType: Int]]
    public let randomSpreadPercent: Int
    /// Each round, each side's damage as a whole swings by up to this much (the fortunes of war).
    /// Unlike the per-strike spread, this doesn't average out over many blocks.
    public let fortunePercent: Int
    /// Each side's luck on the day: drawn once per battle, it scales all of that side's damage by
    /// up to this much either way. It doesn't average out over rounds, so a modest edge in numbers
    /// or ground makes a battle likely, not certain.
    public let dayFortunePercent: Int
    /// Extra morale lost by a block attacked by two or more enemies in one round.
    public let flankMoraleLoss: Int
    /// An army breaks once it has lost this share of its starting strength.
    public let breakPercent: Int
    /// The loser loses this share of its surviving units in the retreat.
    public let pursuitPercent: Int
    /// Attack bonus for a fully bronze-equipped army (bronze stockpile ≥ army size).
    public let bronzeBonusPercent: Int
    public let crossingPenaltyPercent: [String: Int]
    /// Damage reduction every defender gets for fighting on ground it knows and has prepared,
    /// on top of terrain and walls.
    public let homeGroundPercent: Int
    public let terrain: [Terrain: TerrainBattleRules]
    public let fallbackSlots: [GridPoint]
    public let formations: [Formation]
    public let defaultFormation: FormationID
    public let plans: BattlePlanRules
    /// Extra share of the routed cut down when the pursuers have cavalry.
    public let pursuitCavalryPercent: Int
    /// Fleeing archers cost the pursuers one unit per this many.
    public let rearguardArchersPerLoss: Int
    public let levy: LevyRules

    public func formation(_ id: FormationID) -> Formation? {
        formations.first { $0.id == id }
    }
}

/// How an army lines up: the formation as drawn, or every block in the front rank.
public enum LineDepth: String, Codable, Sendable, CaseIterable {
    case deep, wide
}

/// A battle trick on top of the formation.
public enum Stratagem: String, Codable, Sendable, CaseIterable, CodingKeyRepresentable {
    /// Nobody advances unless struck; extra morale.
    case standFast
    /// The cavalry falls back at first; enemy blocks that pursue are caught disordered.
    case feignedRetreat
    /// Infantry locks shields: less hurt by arrows, but slow.
    case shieldWall
    /// The wings start a rank further forward, on the enemy's flanks.
    case flankingMarch
}

/// What unlocks a formation or stratagem: a level of knowledge in a field, or a general with
/// the trait leading the army. Either is enough; with neither set, it is always available.
public struct PlanRequirement: Codable, Sendable, Equatable {
    public let field: KnowledgeField?
    public let level: Int?
    public let trait: GeneralTrait?
}

public struct BattlePlanRules: Codable, Sendable, Equatable {
    public let formationRequires: [FormationID: PlanRequirement]
    public let stratagemRequires: [Stratagem: PlanRequirement]
    public let standFastMorale: Int
    /// Extra damage pursuers take while disordered, in percent.
    public let feignedRetreatPercent: Int
    /// Rounds during which advancing enemies are drawn into disorder.
    public let feignedRetreatRounds: Int
    /// Less arrow damage for infantry in a shield wall, in percent.
    public let shieldWallArrowPercent: Int
}

/// The levy: when land is attacked, its people take up arms beside the garrison.
public struct LevyRules: Codable, Sendable, Equatable {
    /// One militiaman per this many people…
    public let populationPerUnit: Int
    /// …up to this many, and only where at least `minPopulation` live.
    public let maxUnits: Int
    public let minPopulation: Int
    /// Militia hit this hard (percent of an infantryman)…
    public let damagePercent: Int
    /// …and start with this much less morale.
    public let moralePenalty: Int
}

public struct NavalRules: Codable, Sendable, Equatable {
    public let attackPerShip: Int
    public let hpPerShip: Int
    public let maxRounds: Int
    public let randomSpreadPercent: Int
    /// A fleet retreats once it has lost this share of its starting ships.
    public let retreatPercent: Int
}

public struct ShipRules: Codable, Sendable, Equatable {
    public let cost: Int
    /// Grain eaten per ship per turn (the crew).
    public let upkeep: Int
    /// Each point of this resource's yield allows one ship built per turn.
    public let requires: Resource
    /// Land units carried per ship.
    public let capacity: Int
}

public enum GeneralTrait: String, Codable, Sendable, CaseIterable, CodingKeyRepresentable {
    case tactician, cavalryCommander, cautious, reckless
}

public struct TraitEffects: Codable, Sendable, Equatable {
    public var moralePercent: Int?
    public var unitPercent: [UnitType: Int]?
    public var attackPercent: Int?
    public var defensePercent: Int?
    public var deathChanceMultiplier: Int?
}

public struct GeneralRules: Codable, Sendable, Equatable {
    public let traits: [GeneralTrait: TraitEffects]
    /// Starting morale bonus for blocks of an army led by a general.
    public let presentMorale: Int
    public let renownAttackPercent: Int
    public let maxRenownAttackPercent: Int
    public let deathChanceOnDefeatPercent: Int
    public let deathChanceOnVictoryPercent: Int
}

public struct StartingGeneral: Codable, Sendable, Equatable {
    public let name: String
    public let trait: GeneralTrait
}
