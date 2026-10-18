/// Validates and applies commands. Holds the static map and rules; all mutable facts live
/// in the `GameState` passed in. Applying the same commands to the same state always gives
/// the same result.
public struct Engine: Sendable {
    public let map: GameMap
    public let rules: Rules

    public init(map: GameMap, rules: Rules) {
        self.map = map
        self.rules = rules
    }

    public static func bundled() throws -> Engine {
        try Engine(map: .bundled(), rules: .bundled())
    }

    public func newGame(seed: UInt64, civilizations: [CivilizationID]? = nil) throws -> GameState {
        try GameState(map: map, rules: rules, seed: seed, civilizations: civilizations)
    }

    /// Applies a command from the active player. On error the state is left unchanged.
    @discardableResult
    public func apply(_ command: Command, to state: inout GameState) throws -> [GameEvent] {
        guard state.winner == nil else { throw GameError.gameOver }
        switch command {
        case let .recruit(territory, unit, count):
            return try recruit(territory, unit, count, &state)
        case let .move(from, to, units, general):
            return try move(from, to, units, general, &state)
        case let .setFormation(territory, formation):
            return try setFormation(territory, formation, &state)
        case let .buildShips(territory, sea, count):
            return try buildShips(territory, sea, count, &state)
        case let .moveFleet(from, to, ships, cargo):
            return try moveFleet(from, to, ships, cargo, &state)
        case let .embark(territory, sea, units):
            return try embark(territory, sea, units, &state)
        case let .land(sea, territory, units):
            return try land(sea, territory, units, &state)
        case let .offerPeace(to):
            return try offerPeace(to, &state)
        case let .acceptPeace(from):
            return try acceptPeace(from, &state)
        case let .declareWar(on):
            return try declareWar(on, &state)
        case let .appointGeneral(territory):
            return try appointGeneral(territory, &state)
        case let .honorGeneral(id):
            return try honorGeneral(id, &state)
        case .endTurn:
            return endTurn(&state)
        }
    }

    // MARK: Recruit

    private func recruit(_ territory: TerritoryID, _ unit: UnitType, _ count: Int,
                         _ state: inout GameState) throws -> [GameEvent] {
        let civ = state.activePlayer
        guard count > 0 else { throw GameError.invalidCount }
        guard let t = state.land[territory] else { throw GameError.unknownTerritory(territory) }
        guard t.owner == civ else { throw GameError.notOwner(territory) }
        if let army = state.armies[territory], army.owner != civ { throw GameError.contested(territory) }
        guard homeNetwork(of: civ, in: state).contains(territory) else {
            throw GameError.outOfSupply(territory)
        }

        let stats = rules.stats(unit)
        let cost = stats.cost * count
        let gold = state.civs[civ]!.gold
        guard gold >= cost else { throw GameError.insufficientGold(needed: cost, available: gold) }
        guard t.population - count >= rules.economy.minPopulation else {
            throw GameError.insufficientPopulation(territory)
        }
        if let resource = stats.requires {
            let used = state.civs[civ]!.resourceUsedThisTurn[resource] ?? 0
            guard used + count <= effectiveYield(of: resource, for: civ, in: state) else {
                throw GameError.resourceLimit(resource)
            }
            state.civs[civ]!.resourceUsedThisTurn[resource] = used + count
        }

        state.civs[civ]!.gold -= cost
        state.land[territory]!.population -= count
        var added = UnitCounts.zero
        added[unit] = count
        state.armies[territory, default: Army(owner: civ, units: .zero)].units += added
        return [.recruited(civ: civ, territory: territory, unit: unit, count: count)]
    }

    // MARK: Move

    private func move(_ from: TerritoryID, _ to: TerritoryID, _ units: UnitCounts, _ withGeneral: Bool,
                      _ state: inout GameState) throws -> [GameEvent] {
        let civ = state.activePlayer
        guard units.isNonNegative, !units.isEmpty else { throw GameError.invalidCount }
        guard state.land[from] != nil else { throw GameError.unknownTerritory(from) }
        guard state.land[to] != nil else { throw GameError.unknownTerritory(to) }
        guard let army = state.armies[from], army.owner == civ else { throw GameError.insufficientUnits(from) }
        let ready = army.units - (state.moved[from] ?? .zero)
        guard units.fits(in: ready) else { throw GameError.insufficientUnits(from) }
        guard map.areLandAdjacent(from, to) else { throw GameError.notAdjacent(from, to) }
        if let owner = state.owner(of: to), state.atPeace(civ, owner) { throw GameError.atPeace(to) }
        try checkOmen(civ, attacking: to, state)
        var general: General?
        if withGeneral {
            guard let g = state.general(of: civ, at: from), !state.generalsMoved.contains(g.id) else {
                throw GameError.noGeneral(from)
            }
            general = g
            state.generalsMoved.insert(g.id)
        }

        state.armies[from]!.units -= units
        if state.armies[from]!.units.isEmpty { state.armies[from] = nil }
        let approach: Approach = switch map.crossing(between: from, and: to) {
        case .river: .river
        case .strait: .strait
        case nil: .overland
        }
        let events: [GameEvent] = [.moved(civ: civ, from: from, to: to, units: units)]
        return events + advance(civ, units, general: general, formation: army.formation, into: to,
                                from: .territory(from), approach: approach, &state)
    }

    private func setFormation(_ territory: TerritoryID, _ formation: FormationID,
                              _ state: inout GameState) throws -> [GameEvent] {
        let civ = state.activePlayer
        guard rules.battle.formation(formation) != nil else { throw GameError.unknownFormation(formation) }
        guard let army = state.armies[territory], army.owner == civ else {
            throw GameError.insufficientUnits(territory)
        }
        state.armies[territory]!.formation = formation
        return [.formationSet(civ: civ, territory: territory, formation: formation)]
    }

    func checkElimination(_ civ: CivilizationID, _ state: inout GameState) -> [GameEvent] {
        guard !state.civs[civ]!.eliminated, state.territories(of: civ).isEmpty,
              state.armies(of: civ).isEmpty, state.fleets(of: civ).isEmpty else { return [] }
        state.civs[civ]!.eliminated = true
        var events: [GameEvent] = [.eliminated(civ: civ)]
        let alive = state.players.filter { !state.civs[$0]!.eliminated }
        if alive.count <= 1 {
            // If raiders destroyed everyone, the barbarians have the last word.
            let winner = alive.first ?? barbariansID
            state.winner = winner
            events.append(.victory(civ: winner))
        }
        return events
    }

    // MARK: End turn

    private func endTurn(_ state: inout GameState) -> [GameEvent] {
        state.moved = [:]
        state.generalsMoved = []
        for i in state.fleets.indices { state.fleets[i].movedShips = 0 }
        state.civs[state.activePlayer]!.resourceUsedThisTurn = [:]
        state.civs[state.activePlayer]!.omen = false

        let count = state.players.count
        var next = state.activePlayerIndex
        repeat {
            next = (next + 1) % count
            if next == 0 { state.turn += 1 }
        } while state.civs[state.players[next]]!.eliminated
        state.activePlayerIndex = next

        let civ = state.activePlayer
        var events: [GameEvent] = [.turnStarted(civ: civ, turn: state.turn)]
        // The start of a turn: events, then harvest, then government (DESIGN §3). Nothing happens
        // on turn 1, so every civ starts on equal terms whatever its seat.
        if state.turn > 1 {
            events += drawEvents(civ, &state)
            if !state.civs[civ]!.eliminated {
                events += harvest(civ, &state)
                events += governmentPhase(civ, &state)
            }
        }
        // A civ can fall before it moves: overrun by raiders, or its last army starved.
        events += checkElimination(civ, &state)
        if state.civs[civ]!.eliminated, state.winner == nil { events += endTurn(&state) }
        return events
    }

    // MARK: Diplomacy

    private func rival(_ other: CivilizationID, _ state: GameState) throws -> CivilizationID {
        guard other != state.activePlayer, let c = state.civs[other], !c.eliminated else {
            throw GameError.unknownCivilization(other)
        }
        return other
    }

    private func offerPeace(_ to: CivilizationID, _ state: inout GameState) throws -> [GameEvent] {
        let civ = state.activePlayer
        _ = try rival(to, state)
        guard !state.atPeace(civ, to) else { throw GameError.alreadyAtPeace(to) }
        state.peaceOffers.insert(PeaceOffer(from: civ, to: to))
        return [.peaceOffered(from: civ, to: to)]
    }

    private func acceptPeace(_ from: CivilizationID, _ state: inout GameState) throws -> [GameEvent] {
        let civ = state.activePlayer
        _ = try rival(from, state)
        guard state.peaceOffers.contains(PeaceOffer(from: from, to: civ)) else {
            throw GameError.noPeaceOffer(from)
        }
        state.peaceOffers.remove(PeaceOffer(from: from, to: civ))
        state.peaceOffers.remove(PeaceOffer(from: civ, to: from))
        state.peace.insert(CivPair(civ, from))
        return [.peaceMade(CivPair(civ, from))]
    }

    private func declareWar(_ on: CivilizationID, _ state: inout GameState) throws -> [GameEvent] {
        let civ = state.activePlayer
        _ = try rival(on, state)
        guard state.atPeace(civ, on) else { throw GameError.notAtPeace(on) }
        adjustLegitimacy(civ, rules.government.legitimacy.brokePeace, &state)
        state.peace.remove(CivPair(civ, on))
        state.peaceOffers.remove(PeaceOffer(from: civ, to: on))
        state.peaceOffers.remove(PeaceOffer(from: on, to: civ))
        return [.warDeclared(by: civ, on: on)]
    }
}
