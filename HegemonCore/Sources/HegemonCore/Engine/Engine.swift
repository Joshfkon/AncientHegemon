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
        case let .move(from, to, units):
            return try move(from, to, units, &state)
        case let .offerPeace(to):
            return try offerPeace(to, &state)
        case let .acceptPeace(from):
            return try acceptPeace(from, &state)
        case let .declareWar(on):
            return try declareWar(on, &state)
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

    private func move(_ from: TerritoryID, _ to: TerritoryID, _ units: UnitCounts,
                      _ state: inout GameState) throws -> [GameEvent] {
        let civ = state.activePlayer
        guard units.isNonNegative, !units.isEmpty else { throw GameError.invalidCount }
        guard state.land[from] != nil else { throw GameError.unknownTerritory(from) }
        guard state.land[to] != nil else { throw GameError.unknownTerritory(to) }
        guard let army = state.armies[from], army.owner == civ else { throw GameError.insufficientUnits(from) }
        let ready = army.units - (state.moved[from] ?? .zero)
        guard units.fits(in: ready) else { throw GameError.insufficientUnits(from) }
        guard map.areLandAdjacent(from, to) else { throw GameError.notAdjacent(from, to) }
        if let defender = state.armies[to], defender.owner != civ { throw GameError.contested(to) }
        if let owner = state.owner(of: to), state.atPeace(civ, owner) { throw GameError.atPeace(to) }

        state.armies[from]!.units -= units
        if state.armies[from]!.units.isEmpty { state.armies[from] = nil }
        state.armies[to, default: Army(owner: civ, units: .zero)].units += units
        state.moved[to, default: .zero] += units

        var events: [GameEvent] = [.moved(civ: civ, from: from, to: to, units: units)]
        let previous = state.land[to]!.owner
        if previous != civ {
            state.land[to]!.owner = civ
            events.append(.captured(civ: civ, territory: to, from: previous))
            if let previous { events += checkElimination(previous, &state) }
        }
        return events
    }

    private func checkElimination(_ civ: CivilizationID, _ state: inout GameState) -> [GameEvent] {
        guard !state.civs[civ]!.eliminated, state.territories(of: civ).isEmpty,
              state.armies(of: civ).isEmpty else { return [] }
        state.civs[civ]!.eliminated = true
        var events: [GameEvent] = [.eliminated(civ: civ)]
        let alive = state.players.filter { !state.civs[$0]!.eliminated }
        if alive.count == 1 {
            state.winner = alive[0]
            events.append(.victory(civ: alive[0]))
        }
        return events
    }

    // MARK: End turn

    private func endTurn(_ state: inout GameState) -> [GameEvent] {
        state.moved = [:]
        state.civs[state.activePlayer]!.resourceUsedThisTurn = [:]

        let count = state.players.count
        var next = state.activePlayerIndex
        repeat {
            next = (next + 1) % count
            if next == 0 { state.turn += 1 }
        } while state.civs[state.players[next]]!.eliminated
        state.activePlayerIndex = next

        let civ = state.activePlayer
        var events: [GameEvent] = [.turnStarted(civ: civ, turn: state.turn)]
        events += harvest(civ, &state)
        // A civilization with no land whose last army just starved is out of the game.
        let out = checkElimination(civ, &state)
        events += out
        if !out.isEmpty, state.winner == nil { events += endTurn(&state) }
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
        state.peace.remove(CivPair(civ, on))
        state.peaceOffers.remove(PeaceOffer(from: civ, to: on))
        state.peaceOffers.remove(PeaceOffer(from: on, to: civ))
        return [.warDeclared(by: civ, on: on)]
    }
}
