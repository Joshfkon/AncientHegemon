/// Ways to win and how convincingly (DESIGN §14.5, decided after step 6).
///
/// Domination (hold 60% of the map) and trade (hold every sea chokepoint while trading with
/// every rival, for several rounds) end the game when reached. Otherwise, at the round limit,
/// the empire with the most prestige wins a legacy victory. Every win is graded.
extension Engine {
    /// A civilization's standing: land, people, wealth and legitimacy.
    public func prestige(of civ: CivilizationID, in state: GameState) -> Int {
        guard let cs = state.civs[civ], !cs.eliminated else { return 0 }
        let p = rules.victory.prestige
        let land = state.territories(of: civ)
        let capital = map.civilization(civ)?.capital
        return land.count * p.perTerritory
            + state.totalPopulation(of: civ) * p.perPopulation
            + cs.gold / max(1, p.goldDivisor)
            + cs.legitimacy / max(1, p.legitimacyDivisor)
            + (capital.map { state.owner(of: $0) == civ } == true ? p.capitalHeld : 0)
    }

    /// Survivors by prestige, then the fallen, the last to fall first.
    public func standings(in state: GameState) -> [CivilizationID] {
        let alive = state.players.filter { !state.civs[$0]!.eliminated }
            .sorted { (prestige(of: $0, in: state), $1) > (prestige(of: $1, in: state), $0) }
        let fallen = state.players.filter { state.civs[$0]!.eliminated }
            .sorted { (state.civs[$0]!.eliminatedOnRound ?? 0, $1) > (state.civs[$1]!.eliminatedOnRound ?? 0, $0) }
        return alive + fallen
    }

    func declareVictory(_ civ: CivilizationID, _ kind: VictoryKind, _ state: inout GameState) -> [GameEvent] {
        let v = rules.victory
        let grade: VictoryGrade
        switch kind {
        case .lastStanding:
            grade = .decisive
        case .domination, .trade:
            grade = state.turn < v.decisiveBefore ? .decisive : .major
        case .legacy:
            let scores = state.players.filter { $0 != civ }.map { prestige(of: $0, in: state) }
            let runnerUp = scores.max() ?? 0
            grade = prestige(of: civ, in: state) * 100 >= runnerUp * v.majorLegacyMargin ? .major : .minor
        }
        state.winner = civ
        var ranked = standings(in: state)
        ranked.removeAll { $0 == civ }
        state.victory = Victory(kind: kind, grade: grade, round: state.turn, standings: [civ] + ranked)
        return [.victory(civ: civ)]
    }

    /// Whether a civ meets the trade-victory conditions right now: every sea chokepoint held,
    /// and a trade route with every surviving rival.
    public func meetsTradeConditions(_ civ: CivilizationID, in state: GameState) -> Bool {
        let straits = map.chokepoints.filter { $0.gatesSeaLink != nil }
        guard !straits.isEmpty, straits.allSatisfy({ holder(of: $0, in: state) == civ }) else { return false }
        let rivals = state.players.filter { $0 != civ && !state.civs[$0]!.eliminated }
        guard !rivals.isEmpty else { return false }
        let partners = Set(tradeRoutes(in: state).filter { $0.involves(civ) }.map { $0.partner(of: civ) })
        return rivals.allSatisfy(partners.contains)
    }

    /// Checked as each new round begins: trade holds advance, and the round limit may end the game.
    func roundVictoryChecks(_ state: inout GameState) -> [GameEvent] {
        for civ in state.players where !state.civs[civ]!.eliminated {
            state.tradeHold[civ] = meetsTradeConditions(civ, in: state) ? (state.tradeHold[civ] ?? 0) + 1 : 0
            if state.tradeHold[civ]! >= rules.victory.tradeRoundsHeld {
                return declareVictory(civ, .trade, &state)
            }
        }
        if state.turn > rules.victory.roundLimit, let best = standings(in: state).first {
            state.turn = rules.victory.roundLimit
            return declareVictory(best, .legacy, &state)
        }
        return []
    }
}
