/// An order from the active player. The UI and the AI issue the same commands.
public enum Command: Codable, Sendable, Equatable {
    /// Recruit units in an owned territory. Costs gold and turns population into soldiers.
    case recruit(territory: TerritoryID, unit: UnitType, count: Int)
    /// Move units across a land border. Each unit moves once per turn. Entering an unowned or
    /// undefended enemy territory captures it.
    case move(from: TerritoryID, to: TerritoryID, units: UnitCounts)
    /// End the active player's turn.
    case endTurn
}

/// Something that happened as a result of a command, for the UI, logs and the simulator.
public enum GameEvent: Codable, Sendable, Equatable {
    case harvest(civ: CivilizationID, production: Int, consumption: Int, grown: Int, granary: Int, income: Int)
    case starvation(civ: CivilizationID, populationLost: Int, unitsLost: Int)
    case recruited(civ: CivilizationID, territory: TerritoryID, unit: UnitType, count: Int)
    case moved(civ: CivilizationID, from: TerritoryID, to: TerritoryID, units: UnitCounts)
    case captured(civ: CivilizationID, territory: TerritoryID, from: CivilizationID?)
    case eliminated(civ: CivilizationID)
    case victory(civ: CivilizationID)
    case turnStarted(civ: CivilizationID, turn: Int)
}

public enum GameError: Error, Equatable, Sendable {
    case gameOver
    case unknownTerritory(TerritoryID)
    case notOwner(TerritoryID)
    case invalidCount
    case insufficientGold(needed: Int, available: Int)
    case insufficientPopulation(TerritoryID)
    case resourceLimit(Resource)
    case notAdjacent(TerritoryID, TerritoryID)
    case insufficientUnits(TerritoryID)
    /// Moving into a territory held by another civilization's army needs a battle (build step 4).
    case contested(TerritoryID)
}
