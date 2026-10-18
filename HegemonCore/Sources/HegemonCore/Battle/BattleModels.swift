public typealias GeneralID = String

/// A named commander. Generals lead the army in the territory where they stand.
public struct General: Codable, Sendable, Equatable, Identifiable {
    public let id: GeneralID
    public let name: String
    public var owner: CivilizationID
    public let trait: GeneralTrait
    public var renown: Int
    /// Where the general stands. Nil once dead.
    public var location: TerritoryID?
    /// Loyalty to the throne, 0–100. Falls with renown and distance; low loyalty means rebellion.
    public var loyalty = 70

    public var isAlive: Bool { location != nil }
}

public enum BattleSide: String, Codable, Sendable {
    case attacker, defender
}

/// How the attacker reached the battlefield, for crossing penalties.
public enum Approach: String, Codable, Sendable {
    case overland, river, strait, amphibious
}

/// One side's input to a land battle.
public struct BattleArmy: Codable, Sendable, Equatable {
    public var civ: CivilizationID
    public var units: UnitCounts
    public var formation: FormationID
    public var general: General?
    /// How well-equipped with bronze the army is, 0–100.
    public var bronzePercent: Int
    /// Attack bonuses per unit type from the civilization's knowledge, in percent.
    public var unitPercent: [UnitType: Int]
    /// Extra starting morale from the civilization's knowledge.
    public var morale: Int
    public var depth: LineDepth
    public var stratagem: Stratagem?
    /// Militia raised from the population of the land being defended.
    public var levy: Int
    /// If the enemy breaks, chase them down (more of them fall, but archers covering the
    /// retreat can sting the pursuers) or hold the field.
    public var pursue: Bool = true

    public init(civ: CivilizationID, units: UnitCounts, formation: FormationID,
                general: General? = nil, bronzePercent: Int = 0,
                unitPercent: [UnitType: Int] = [:], morale: Int = 0,
                depth: LineDepth = .deep, stratagem: Stratagem? = nil, levy: Int = 0) {
        self.civ = civ
        self.units = units
        self.formation = formation
        self.general = general
        self.bronzePercent = bronzePercent
        self.unitPercent = unitPercent
        self.morale = morale
        self.depth = depth
        self.stratagem = stratagem
        self.levy = levy
    }
}

/// An army's standing orders for battle: formation, line depth and stratagem.
public struct BattlePlan: Codable, Sendable, Hashable {
    /// Nil means the rules' default formation.
    public var formation: FormationID?
    public var depth: LineDepth
    public var stratagem: Stratagem?
    public var pursue: Bool

    public init(formation: FormationID? = nil, depth: LineDepth = .deep, stratagem: Stratagem? = nil, pursue: Bool = true) {
        self.formation = formation
        self.depth = depth
        self.stratagem = stratagem
        self.pursue = pursue
    }
}

public struct BattleSetup: Codable, Sendable, Equatable {
    public var attacker: BattleArmy
    public var defender: BattleArmy
    public var terrain: Terrain
    public var approach: Approach
    public var seed: UInt64
    /// Extra damage reduction for the defender from walls, in percent.
    public var fortification: Int

    public init(attacker: BattleArmy, defender: BattleArmy, terrain: Terrain,
                approach: Approach = .overland, seed: UInt64, fortification: Int = 0) {
        self.attacker = attacker
        self.defender = defender
        self.terrain = terrain
        self.approach = approach
        self.seed = seed
        self.fortification = fortification
    }
}

public enum BlockStatus: String, Codable, Sendable {
    case fighting, routed, destroyed
}

/// A block's state at the end of a round, for playback.
public struct BlockSnapshot: Codable, Sendable, Equatable {
    public let id: Int
    public let side: BattleSide
    public let type: UnitType
    public let position: GridPoint
    public let units: Int
    public let morale: Int
    public let status: BlockStatus
    /// Townsfolk raised to defend their home: weak, and not part of the standing army.
    public let levy: Bool
}

public struct BattleStrike: Codable, Sendable, Equatable {
    public let from: Int
    public let to: Int
    public let damage: Int
    public let ranged: Bool
}

/// One round of a battle. Frame 0 is the deployment, with no strikes.
public struct BattleFrame: Codable, Sendable, Equatable {
    public let round: Int
    public let blocks: [BlockSnapshot]
    public let strikes: [BattleStrike]
}

/// Everything about a resolved battle: the outcome and a full replay.
public struct BattleReport: Codable, Sendable, Equatable {
    public let setup: BattleSetup
    public let impassable: [GridPoint]
    public let frames: [BattleFrame]
    public let winner: BattleSide
    public let rounds: Int
    /// Units left after the battle and the loser's retreat.
    public let attackerSurvivors: UnitCounts
    public let defenderSurvivors: UnitCounts
    public let attackerGeneralKilled: Bool
    public let defenderGeneralKilled: Bool
    /// Militia who came home; the rest of the levy fell.
    public let defenderLevySurvivors: Int
    /// The winner chased the broken enemy: how many of the beaten side fell in the rout, and how
    /// many pursuers the rearguard's archers cut down. Nil when the winner held the field.
    public let pursuit: Pursuit?

    public var attackerLosses: UnitCounts { setup.attacker.units - attackerSurvivors }
    public var defenderLosses: UnitCounts { setup.defender.units - defenderSurvivors }
}

public struct Pursuit: Codable, Sendable, Equatable {
    public let routed: Int
    public let pursuersLost: Int
}

public struct NavalReport: Codable, Sendable, Equatable {
    public let attacker: CivilizationID
    public let defender: CivilizationID
    public let attackerShips: Int
    public let defenderShips: Int
    public let winner: BattleSide
    public let rounds: Int
    public let attackerShipsLeft: Int
    public let defenderShipsLeft: Int
}
