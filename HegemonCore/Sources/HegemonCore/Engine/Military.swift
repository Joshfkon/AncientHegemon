/// Where advancing units came from, so the beaten ones can fall back.
enum Origin {
    case territory(TerritoryID)
    case sea(SeaZoneID)
}

extension Engine {
    /// Units (and optionally a general) entering `to`, by land or from the sea. Fights the army
    /// there if it belongs to an enemy, then occupies and captures the territory if they won.
    func advance(_ civ: CivilizationID, _ units: UnitCounts, general: General?, formation: FormationID?,
                 into to: TerritoryID, from origin: Origin, approach: Approach,
                 _ state: inout GameState) -> [GameEvent] {
        var events: [GameEvent] = []
        var units = units
        var general = general

        if let defender = state.armies[to]?.owner, defender != civ {
            let result = fight(civ, units, general: general, formation: formation, at: to,
                               approach: approach, &state)
            events += result.events
            units = result.survivors
            if let g = general { general = state.generals[g.id]!.isAlive ? state.generals[g.id] : nil }
            if !result.won {
                fallBack(civ, units, to: origin, &state)
                return events
            }
        }

        if !units.isEmpty {
            state.armies[to, default: Army(owner: civ, units: .zero)].units += units
            state.moved[to, default: .zero] += units
        }
        if let g = general { state.generals[g.id]!.location = to }

        // Enemy generals left standing without an army are captured.
        for g in state.generals.values.sorted(by: { $0.id < $1.id })
        where g.location == to && g.owner != civ {
            state.generals[g.id]!.location = nil
            events.append(.generalKilled(g.id))
        }

        let previous = state.land[to]!.owner
        if previous != civ, state.armies[to]?.owner == civ {
            state.land[to]!.owner = civ
            events.append(.captured(civ: civ, territory: to, from: previous))
            adjustLegitimacy(civ, rules.government.legitimacy.capture, &state)
            if let previous, map.civilization(previous)?.capital == to {
                adjustLegitimacy(previous, rules.government.legitimacy.capitalLost, &state)
            }
            if let previous { events += checkElimination(previous, &state) }
            if state.winner == nil,
               state.territories(of: civ).count * 100 >= map.territories.count * rules.victory.territoryPercent {
                state.winner = civ
                events.append(.victory(civ: civ))
            }
        }
        return events
    }

    /// Resolves a land battle for `to` and applies its results to the defender and the generals.
    /// The attacker's survivors are returned for the caller to place.
    func fight(_ civ: CivilizationID, _ units: UnitCounts, general: General?, formation: FormationID?,
                       at to: TerritoryID, approach: Approach, _ state: inout GameState)
        -> (won: Bool, survivors: UnitCounts, events: [GameEvent]) {
        let defender = state.armies[to]!
        let defenderGeneral = state.general(of: defender.owner, at: to)
        let setup = BattleSetup(
            attacker: BattleArmy(civ: civ, units: units, formation: formation ?? rules.battle.defaultFormation,
                                 general: general, bronzePercent: bronzePercent(civ, state)),
            defender: BattleArmy(civ: defender.owner, units: defender.units,
                                 formation: defender.formation ?? rules.battle.defaultFormation,
                                 general: defenderGeneral, bronzePercent: bronzePercent(defender.owner, state)),
            terrain: map.territory(to)!.terrain, approach: approach, seed: state.rng.next())
        let report = BattleSimulator(rules: rules).resolve(setup)
        let won = report.winner == .attacker
        var events: [GameEvent] = [.battle(report)]
        let l = rules.government.legitimacy
        adjustLegitimacy(civ, won ? l.battleWon : l.battleLost, &state)
        adjustLegitimacy(defender.owner, won ? l.battleLost : l.battleWon, &state)

        for (g, killed, victor) in [(general, report.attackerGeneralKilled, won),
                                    (defenderGeneral, report.defenderGeneralKilled, !won)] {
            guard let g else { continue }
            if killed {
                state.generals[g.id]!.location = nil
                events.append(.generalKilled(g.id))
            } else if victor {
                state.generals[g.id]!.renown += 1
            }
        }

        if won {
            state.armies[to] = nil
            events += retreat(defender.owner, report.defenderSurvivors, from: to, &state)
        } else if report.defenderSurvivors.isEmpty {
            state.armies[to] = nil
        } else {
            state.armies[to]!.units = report.defenderSurvivors
        }
        return (won, report.attackerSurvivors, events)
    }

    /// A beaten defender falls back to an adjacent territory it holds with no foreign army,
    /// preferring its home network. With nowhere to go, the army and its general are lost.
    private func retreat(_ civ: CivilizationID, _ units: UnitCounts, from territory: TerritoryID,
                         _ state: inout GameState) -> [GameEvent] {
        let home = Set(homeNetwork(of: civ, in: state))
        let options = map.landNeighbors(of: territory).filter { t in
            state.owner(of: t) == civ && (state.armies[t].map { $0.owner == civ } ?? true)
        }
        let general = state.general(of: civ, at: territory)
        guard let target = options.first(where: home.contains) ?? options.first else {
            var events: [GameEvent] = []
            if !units.isEmpty { events.append(.destroyed(civ: civ, units: units, ships: 0)) }
            if let general {
                state.generals[general.id]!.location = nil
                events.append(.generalKilled(general.id))
            }
            return events
        }
        if !units.isEmpty {
            state.armies[target, default: Army(owner: civ, units: .zero)].units += units
        }
        if let general { state.generals[general.id]!.location = target }
        return units.isEmpty ? [] : [.retreated(civ: civ, from: territory, to: target, units: units)]
    }

    /// A repulsed attacker returns where it came from, its move spent.
    private func fallBack(_ civ: CivilizationID, _ units: UnitCounts, to origin: Origin,
                          _ state: inout GameState) {
        guard !units.isEmpty else { return }
        switch origin {
        case .territory(let from):
            state.armies[from, default: Army(owner: civ, units: .zero)].units += units
            state.moved[from, default: .zero] += units
        case .sea(let sea):
            if let i = state.fleets.firstIndex(where: { $0.owner == civ && $0.sea == sea }) {
                state.fleets[i].cargo += units
            }
        }
    }

    /// Bad omens forbid starting a fight: entering another civ's land or any foreign army.
    func checkOmen(_ civ: CivilizationID, attacking to: TerritoryID, _ state: GameState) throws {
        guard state.civs[civ]?.omen == true else { return }
        let foreignArmy = state.armies[to].map { $0.owner != civ } ?? false
        let foreignLand = state.owner(of: to).map { $0 != civ } ?? false
        if foreignArmy || foreignLand { throw GameError.badOmen }
    }

    /// How well a civilization's forces are equipped with bronze, 0–100.
    func bronzePercent(_ civ: CivilizationID, _ state: GameState) -> Int {
        let units = state.totalUnits(of: civ).total + state.fleets(of: civ).reduce(0) { $0 + $1.cargo.total }
        return min(100, (state.civs[civ]?.bronze ?? 0) * 100 / max(1, units))
    }
}
