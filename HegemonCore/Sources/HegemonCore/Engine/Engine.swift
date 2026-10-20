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
        let events = try perform(command, &state)
        return events + awardTrophies(events, &state)
    }

    private func perform(_ command: Command, _ state: inout GameState) throws -> [GameEvent] {
        guard state.winner == nil else { throw GameError.gameOver }
        if state.civs[state.activePlayer]!.crisis != nil {
            guard case .resolveCrisis = command else { throw GameError.crisisPending }
        }
        switch command {
        case let .recruit(territory, unit, count):
            return try recruit(territory, unit, count, &state)
        case let .move(from, to, units, general):
            return try move(from, to, units, general, &state)
        case let .setFormation(territory, formation):
            return try setFormation(territory, formation, &state)
        case let .parley(territory, kind):
            return try parley(territory, kind, &state)
        case let .setFleetPlan(sea, plan):
            return try setFleetPlan(sea, plan, &state)
        case let .offerAlliance(to):
            return try offerAlliance(to, &state)
        case let .acceptAlliance(from):
            return try acceptAlliance(from, &state)
        case let .leaveAlliance(with):
            return try leaveAlliance(with, &state)
        case let .callToWar(ally, against):
            return try callToWar(ally, against: against, &state)
        case let .answerCallToWar(from, against, join):
            return try answerCallToWar(from, against: against, join: join, &state)
        case let .decide(accept):
            return try decide(accept, &state)
        case let .setPatronage(field):
            return try setPatronage(field, &state)
        case let .buildMonument(territory, monument):
            return try buildMonument(monument, in: territory, &state)
        case let .decorate(id):
            return try decorate(id, &state)
        case let .disband(territory, units):
            return try disband(territory, units, &state)
        case let .setBattlePlan(territory, plan):
            return try setBattlePlan(territory, plan, &state)
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
        case let .declinePeace(from):
            return try declinePeace(from, &state)
        case let .declareWar(on):
            return try declareWar(on, &state)
        case let .appointGeneral(territory):
            return try appointGeneral(territory, &state)
        case let .honorGeneral(id):
            return try honorGeneral(id, &state)
        case let .setTaxRate(rate):
            return try setTaxRate(rate, &state)
        case let .build(territory, project):
            return try build(project, in: territory, &state)
        case let .queueProject(territory, project):
            return try queueProject(project, in: territory, &state)
        case let .clearQueue(territory):
            return try clearQueue(territory, &state)
        case let .besiege(territory, from):
            return try besiege(territory, from: from, &state)
        case let .liftSiege(territory):
            return try liftSiege(territory, &state)
        case let .assault(territory, groups, general):
            return try assault(territory, groups, general: general, &state)
        case let .resolveCrisis(choice):
            return try resolveCrisis(choice, &state)
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
            guard used + count <= effectiveYield(of: resource, for: civ, in: state) * recruitsPerPoint(unit, civ, state) else {
                throw GameError.resourceLimit(resource)
            }
            state.civs[civ]!.resourceUsedThisTurn[resource] = used + count
        }

        state.civs[civ]!.gold -= cost
        state.land[territory]!.population -= count
        var added = UnitCounts.zero
        added[unit] = count
        // Recruits are green: they dilute the army's battle honours.
        join(added, battles: 0, to: territory, owner: civ, &state)
        return [.recruited(civ: civ, territory: territory, unit: unit, count: count)]
    }

    /// Soldiers go home. On the civ's own land each becomes a person again (up to the land's
    /// population cap); abroad they simply scatter. No gold comes back.
    private func disband(_ territory: TerritoryID, _ units: UnitCounts, _ state: inout GameState) throws -> [GameEvent] {
        let civ = state.activePlayer
        guard units.isNonNegative, !units.isEmpty else { throw GameError.invalidCount }
        guard let army = state.armies[territory], army.owner == civ else { throw GameError.insufficientUnits(territory) }
        let left = army.units - units
        guard left.isNonNegative else { throw GameError.insufficientUnits(territory) }
        if left.isEmpty { state.armies[territory] = nil } else { state.armies[territory]!.units = left }
        if let moved = state.moved[territory] {
            let still = moved - units
            state.moved[territory] = UnitCounts(infantry: max(0, min(still.infantry, left.infantry)),
                                                archers: max(0, min(still.archers, left.archers)),
                                                cavalry: max(0, min(still.cavalry, left.cavalry)))
        }
        var rejoined = 0
        if state.owner(of: territory) == civ {
            let room = max(0, populationCap(of: territory) - state.population(of: territory))
            rejoined = min(units.total, room)
            state.land[territory]!.population += rejoined
        }
        return [.disbanded(civ: civ, territory: territory, units: units, rejoined: rejoined)]
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

        // Units that already took a road step this turn are on their second move.
        let onRoad = state.roadMoved[from] ?? .zero
        var second = UnitCounts.zero
        for type in UnitType.allCases { second[type] = min(units[type], onRoad[type]) }
        state.roadMoved[from] = onRoad - second
        if state.roadMoved[from]!.isEmpty { state.roadMoved[from] = nil }
        // A road march: from road to road, through our own land, with no one to fight.
        let roadMarch = roadLinks(from, to, for: civ, in: state)

        state.armies[from]!.units -= units
        if state.armies[from]!.units.isEmpty { state.armies[from] = nil }
        let approach: Approach = switch map.crossing(between: from, and: to) {
        case .river: .river
        case .strait: .strait
        case nil: .overland
        }
        let events: [GameEvent] = [.moved(civ: civ, from: from, to: to, units: units)]
        let result = events + advance(civ, units, general: general, plan: army.plan, battles: army.battles ?? 0, into: to,
                                      from: .territory(from), approach: approach, &state)
        // Fresh units that marched by road may move once more this turn.
        if roadMarch, state.armies[to]?.owner == civ {
            let fresh = units - second
            if let moved = state.moved[to] {
                var left = moved
                for type in UnitType.allCases { left[type] = max(0, moved[type] - fresh[type]) }
                state.moved[to] = left.isEmpty ? nil : left
            }
            state.roadMoved[to, default: .zero] += fresh
        }
        return result
    }

    /// Whether a march from `from` to `to` runs along a road: both have one, both are the civ's,
    /// and nobody would fight at the far end.
    public func roadLinks(_ from: TerritoryID, _ to: TerritoryID, for civ: CivilizationID, in state: GameState) -> Bool {
        let road = { (t: TerritoryID) in state.land[t]?.improvements.contains(.road) == true }
        return road(from) && road(to) && state.owner(of: from) == civ && state.owner(of: to) == civ
            && defenders(of: to, against: civ, state) == nil
    }

    private func setFormation(_ territory: TerritoryID, _ formation: FormationID,
                              _ state: inout GameState) throws -> [GameEvent] {
        let civ = state.activePlayer
        guard rules.battle.formation(formation) != nil else { throw GameError.unknownFormation(formation) }
        guard let army = state.armies[territory], army.owner == civ else {
            throw GameError.insufficientUnits(territory)
        }
        guard formationAvailable(formation, civ, general: state.general(of: civ, at: territory), in: state) else {
            throw GameError.planLocked
        }
        state.armies[territory]!.formation = formation
        return [.formationSet(civ: civ, territory: territory, formation: formation)]
    }

    func checkElimination(_ civ: CivilizationID, _ state: inout GameState) -> [GameEvent] {
        guard !state.civs[civ]!.eliminated, state.territories(of: civ).isEmpty,
              state.armies(of: civ).isEmpty, state.fleets(of: civ).isEmpty else { return [] }
        state.civs[civ]!.eliminated = true
        state.civs[civ]!.eliminatedOnRound = state.turn
        var events: [GameEvent] = [.eliminated(civ: civ)]
        let alive = state.players.filter { !state.civs[$0]!.eliminated }
        if alive.count <= 1 {
            // If raiders destroyed everyone, the barbarians have the last word.
            if let last = alive.first {
                events += declareVictory(last, .lastStanding, &state)
            } else {
                // Raiders destroyed everyone: the barbarians have the last word.
                state.winner = barbariansID
                events.append(.victory(civ: barbariansID))
            }
        }
        return events
    }

    // MARK: End turn

    private func endTurn(_ state: inout GameState) -> [GameEvent] {
        // An unanswered dilemma is a no.
        var closing: [GameEvent] = []
        if state.civs[state.activePlayer]?.decision != nil, let answered = try? decide(false, &state) { closing = answered }
        state.moved = [:]
        state.roadMoved = [:]
        state.calledToWar = []
        state.parleyed = []
        state.generalsMoved = []
        for i in state.fleets.indices { state.fleets[i].movedShips = 0 }
        state.civs[state.activePlayer]!.resourceUsedThisTurn = [:]
        state.civs[state.activePlayer]!.omen = false

        let count = state.players.count
        let roundBefore = state.turn
        var next = state.activePlayerIndex
        repeat {
            next = (next + 1) % count
            if next == 0 { state.turn += 1 }
        } while state.civs[state.players[next]]!.eliminated
        state.activePlayerIndex = next
        var age: [GameEvent] = []
        if state.turn > roundBefore {
            state.disruptedRoutes = state.disruptedRoutes.filter { $0.value >= state.turn }
            let ended = roundVictoryChecks(&state)
            if !ended.isEmpty { return closing + ended }
            age = dawnOfIron(&state)
        }

        let civ = state.activePlayer
        var events: [GameEvent] = closing + [.turnStarted(civ: civ, turn: state.turn)] + age
        events += expireWarRequests(from: civ, &state)
        state.allianceOffers = state.allianceOffers.filter { $0.from != civ }
        // The start of a turn: events, then harvest, then government (DESIGN §3). Nothing happens
        // on turn 1, so every civ starts on equal terms whatever its seat.
        if state.turn > 1 {
            events += drawEvents(civ, &state)
            if !state.civs[civ]!.eliminated {
                events += harvest(civ, &state)
                events += pressSieges(civ, &state)
                events += governmentPhase(civ, &state)
                events += updateSplendour(civ, &state)
                events += offerDecision(civ, after: events, &state)
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

    private func declinePeace(_ from: CivilizationID, _ state: inout GameState) throws -> [GameEvent] {
        let civ = state.activePlayer
        _ = try rival(from, state)
        let offer = PeaceOffer(from: from, to: civ)
        guard state.peaceOffers.contains(offer) else { throw GameError.noPeaceOffer(from) }
        state.peaceOffers.remove(offer)
        state.peaceRebuffed[offer] = state.turn + rules.alliances.rebuffedRounds
        return [.peaceDeclined(by: civ, offerer: from)]
    }

    private func declareWar(_ on: CivilizationID, _ state: inout GameState) throws -> [GameEvent] {
        let civ = state.activePlayer
        _ = try rival(on, state)
        guard state.atPeace(civ, on) else { throw GameError.notAtPeace(on) }
        adjustLegitimacy(civ, rules.government.legitimacy.brokePeace, &state)
        state.peace.remove(CivPair(civ, on))
        state.peaceOffers.remove(PeaceOffer(from: civ, to: on))
        state.peaceOffers.remove(PeaceOffer(from: on, to: civ))
        var events: [GameEvent] = [.warDeclared(by: civ, on: on)]
        // Turning on an ally ends the alliance, with the shame of it.
        if allied(civ, on, in: state) {
            state.alliances.remove(CivPair(civ, on))
            adjustLegitimacy(civ, -rules.alliances.betrayalLegitimacy, &state)
            events.append(.allianceEnded(CivPair(civ, on), by: civ))
        }
        return events + rallyAllies(of: on, against: civ, &state)
    }
}
