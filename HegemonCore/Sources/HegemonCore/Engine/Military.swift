/// Where advancing units came from, so the beaten ones can fall back.
enum Origin {
    case territory(TerritoryID)
    case sea(SeaZoneID)
}

extension Engine {
    /// Militia that would rise to defend `territory` for its owner: a share of the people, if
    /// enough live there. Only empires raise levies; native land has its garrisons.
    public func levy(at territory: TerritoryID, _ state: GameState) -> Int {
        guard let owner = state.owner(of: territory), state.isPlayer(owner) else { return 0 }
        let l = rules.battle.levy
        let people = state.population(of: territory)
        guard people >= l.minPopulation else { return 0 }
        return min(l.maxUnits, people / max(1, l.populationPerUnit))
    }

    /// Who defends `territory` against `civ`, and with what: the garrison if it's hostile, plus
    /// the levy if the land belongs to the garrison's empire (or is undefended land of an empire).
    /// Nil when nobody would fight.
    public func defenders(of territory: TerritoryID, against civ: CivilizationID, _ state: GameState)
        -> (owner: CivilizationID, army: Army, levy: Int)? {
        let garrison = state.armies[territory].flatMap { $0.owner != civ ? $0 : nil }
        let landOwner = state.owner(of: territory)
        let owner = garrison?.owner ?? landOwner
        guard let owner, owner != civ else { return nil }
        let levy = landOwner == owner ? self.levy(at: territory, state) : 0
        if garrison == nil && levy == 0 { return nil }
        return (owner, garrison ?? Army(owner: owner, units: .zero), levy)
    }

    /// The defending side of a battle for `territory` as it would fight.
    public func defendingArmy(of territory: TerritoryID, against civ: CivilizationID, _ state: GameState) -> BattleArmy? {
        guard let d = defenders(of: territory, against: civ, state) else { return nil }
        var army = battleArmy(d.owner, d.army.units, plan: d.army.plan,
                              general: state.general(of: d.owner, at: territory), battles: d.army.battles ?? 0, state)
        army.levy = d.levy
        return army
    }

    /// Units (and optionally a general) entering `to`, by land or from the sea. Fights the army
    /// there if it belongs to an enemy, then occupies and captures the territory if they won.
    func advance(_ civ: CivilizationID, _ units: UnitCounts, general: General?, plan: BattlePlan,
                 battles: Int = 0, into to: TerritoryID, from origin: Origin, approach: Approach,
                 _ state: inout GameState) -> [GameEvent] {
        advance(civ, units, general: general, plan: plan, battles: battles, into: to, from: [(origin, units)],
                approach: approach, &state)
    }

    /// As above, for a host gathered from several places: beaten, each part falls back where it
    /// came from, in proportion.
    func advance(_ civ: CivilizationID, _ units: UnitCounts, general: General?, plan: BattlePlan,
                 battles: Int = 0, into to: TerritoryID, from origins: [(Origin, UnitCounts)], approach: Approach,
                 _ state: inout GameState) -> [GameEvent] {
        var events: [GameEvent] = []
        var units = units
        var battles = battles
        var general = general

        if defenders(of: to, against: civ, state) != nil {
            let result = fight(civ, units, general: general, plan: plan, battles: battles, at: to,
                               approach: approach, &state)
            events += result.events
            units = result.survivors
            battles = seasoned(battles)
            if let g = general { general = state.generals[g.id]!.isAlive ? state.generals[g.id] : nil }
            if !result.won {
                for (origin, part) in zip(origins.map(\.0), shares(of: units, among: origins.map(\.1))) {
                    fallBack(civ, part, battles: battles, to: origin, &state)
                }
                return events
            }
        }

        if !units.isEmpty {
            join(units, battles: battles, to: to, owner: civ, &state)
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
            state.land[to]!.construction = nil
            state.land[to]!.queue = []
            state.monumentSites[to] = nil
            state.sieges[to] = nil
            taken(to, &state)
            events.append(.captured(civ: civ, territory: to, from: previous))
            adjustLegitimacy(civ, rules.government.legitimacy.capture, &state)
            if let previous, map.civilization(previous)?.capital == to {
                adjustLegitimacy(previous, rules.government.legitimacy.capitalLost, &state)
                events += sack(to, of: previous, by: civ, &state)
            }
            if let previous { events += checkElimination(previous, &state) }
            if state.winner == nil,
               state.territories(of: civ).count * 100 >= map.territories.count * rules.victory.territoryPercent {
                events += declareVictory(civ, .domination, &state)
            }
        }
        return events
    }

    /// Resolves a land battle for `to` and applies its results to the defender and the generals.
    /// The attacker's survivors are returned for the caller to place.
    func fight(_ civ: CivilizationID, _ units: UnitCounts, general: General?, plan: BattlePlan,
                       battles: Int = 0, at to: TerritoryID, approach: Approach, _ state: inout GameState)
        -> (won: Bool, survivors: UnitCounts, events: [GameEvent]) {
        let d = defenders(of: to, against: civ, state)!
        let defender = d.army
        let defenderGeneral = state.general(of: defender.owner, at: to)
        let setup = BattleSetup(
            attacker: battleArmy(civ, units, plan: plan, general: general, battles: battles, state),
            defender: defendingArmy(of: to, against: civ, state)!,
            terrain: map.territory(to)!.terrain, approach: approach, seed: state.rng.next(),
            fortification: fortification(at: to, state))
        let report = BattleSimulator(rules: rules).resolve(setup)
        let won = report.winner == .attacker
        var events: [GameEvent] = [.battle(report)]
        events += rallyAllies(of: defender.owner, against: civ, &state)
        battleExperience(setup.attacker, &state)
        battleExperience(setup.defender, &state)
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

        // The levy's dead are the land's people.
        let fallen = d.levy - report.defenderLevySurvivors
        if fallen > 0 {
            state.land[to]!.population = max(rules.economy.minPopulation, state.population(of: to) - fallen)
        }
        let defenderBattles = seasoned(defender.battles ?? 0)
        if won {
            state.armies[to] = nil
            if !report.defenderSurvivors.isEmpty {
                events += retreat(defender.owner, report.defenderSurvivors, battles: defenderBattles, from: to, &state)
            }
        } else if report.defenderSurvivors.isEmpty {
            state.armies[to] = nil
        } else {
            state.armies[to]!.units = report.defenderSurvivors
            state.armies[to]!.battles = defenderBattles
        }
        return (won, report.attackerSurvivors, events)
    }

    /// A beaten defender falls back to an adjacent territory it holds with no foreign army,
    /// preferring its home network. With nowhere to go, the army and its general are lost.
    private func retreat(_ civ: CivilizationID, _ units: UnitCounts, battles: Int, from territory: TerritoryID,
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
        join(units, battles: battles, to: target, owner: civ, &state)
        if let general { state.generals[general.id]!.location = target }
        return units.isEmpty ? [] : [.retreated(civ: civ, from: territory, to: target, units: units)]
    }

    /// A repulsed attacker returns where it came from, its move spent.
    private func fallBack(_ civ: CivilizationID, _ units: UnitCounts, battles: Int, to origin: Origin,
                          _ state: inout GameState) {
        guard !units.isEmpty else { return }
        switch origin {
        case .territory(let from):
            join(units, battles: battles, to: from, owner: civ, &state)
            state.moved[from, default: .zero] += units
        case .sea(let sea):
            if let i = state.fleets.firstIndex(where: { $0.owner == civ && $0.sea == sea }) {
                let f = state.fleets[i]
                state.fleets[i].cargoBattles = mergedBattles(f.cargoBattles ?? 0, f.cargo.total, battles, units.total)
                state.fleets[i].cargo += units
            }
        }
    }

    /// Splits survivors back among the parts of a host, in proportion to what each brought.
    func shares(of survivors: UnitCounts, among parts: [UnitCounts]) -> [UnitCounts] {
        var result = parts.map { _ in UnitCounts.zero }
        for type in UnitType.allCases {
            let brought = parts.reduce(0) { $0 + $1[type] }
            guard brought > 0 else { continue }
            var left = survivors[type]
            for (i, part) in parts.enumerated() {
                let n = survivors[type] * part[type] / brought
                result[i][type] = n
                left -= n
            }
            // Remainders go to the parts that brought the most.
            for i in parts.indices.sorted(by: { parts[$0][type] > parts[$1][type] }) where left > 0 && parts[i][type] > 0 {
                result[i][type] += 1
                left -= 1
            }
        }
        return result
    }

    /// Damage reduction walls give a territory's defenders.
    public func fortification(at territory: TerritoryID, _ state: GameState) -> Int {
        let gate = state.monuments["lionGate"] == territory ? 30 : 0
        guard state.land[territory]?.improvements.contains(.walls) == true else { return gate }
        let builders = level(.construction, of: state.owner(of: territory), in: state) >= 2
        let walls = rules.projectEffects.wallsDefensePercent + (builders ? rules.knowledge.effects.fortificationPercent : 0) + gate
        // A siege wears the walls down.
        return max(0, walls - breach(at: territory, state))
    }

    /// The chance an attack succeeds, estimated by running the battle several times with seeds
    /// derived from the state (the game's RNG is untouched). For the UI to show before attacking.
    public func attackOdds(_ civ: CivilizationID, units: UnitCounts, into to: TerritoryID,
                           from origin: TerritoryID? = nil, formation: FormationID? = nil,
                           depth: LineDepth = .deep, stratagem: Stratagem? = nil,
                           general: General? = nil, amphibious: Bool = false,
                           samples: Int = 12, in state: GameState) -> Double? {
        let plan = BattlePlan(formation: formation, depth: depth, stratagem: stratagem)
        guard let setup = attackSetup(civ, units: units, into: to, from: origin, plan: plan, general: general,
                                      amphibious: amphibious, in: state) else { return nil }
        var salt: UInt64 = 0xCBF2_9CE4_8422_2325  // FNV-1a: stable across launches, unlike hashValue
        for byte in (to + (origin ?? "sea")).utf8 { salt = (salt ^ UInt64(byte)) &* 0x100_0000_01B3 }
        var rng = SeededRNG(seed: state.seed ^ (UInt64(state.turn) &* 0x2545_F491_4F6C_DD1D) ^ salt)
        let sim = BattleSimulator(rules: rules)
        var wins = 0
        for _ in 0..<samples {
            var trial = setup
            trial.seed = rng.next()
            if sim.resolve(trial).winner == .attacker { wins += 1 }
        }
        return Double(wins) / Double(samples)
    }

    /// The battle an attack would bring on, as it would be fought (seed 0: nothing is rolled).
    /// Nil if nobody would defend.
    public func attackSetup(_ civ: CivilizationID, units: UnitCounts, into to: TerritoryID,
                            from origin: TerritoryID? = nil, plan: BattlePlan = BattlePlan(),
                            general: General? = nil, amphibious: Bool = false,
                            in state: GameState) -> BattleSetup? {
        guard let defending = defendingArmy(of: to, against: civ, state), !units.isEmpty else { return nil }
        let approach: Approach
        if amphibious {
            approach = .amphibious
        } else {
            approach = switch origin.flatMap({ map.crossing(between: $0, and: to) }) {
            case .river: .river
            case .strait: .strait
            case nil: .overland
            }
        }
        // The force carries its army's battle honours (a landing, the fleet's cargo's).
        let honours = origin.flatMap { state.armies[$0]?.owner == civ ? state.armies[$0]?.battles : nil } ?? 0
        return BattleSetup(attacker: battleArmy(civ, units, plan: plan, general: general, battles: honours, state),
                           defender: defending, terrain: map.territory(to)!.terrain, approach: approach,
                           seed: 0, fortification: fortification(at: to, state))
    }

    /// Bad omens forbid starting a fight: entering another civ's land or any foreign army.
    func checkOmen(_ civ: CivilizationID, attacking to: TerritoryID, _ state: GameState) throws {
        guard state.civs[civ]?.omen == true else { return }
        let foreignArmy = state.armies[to].map { $0.owner != civ } ?? false
        let foreignLand = state.owner(of: to).map { $0 != civ } ?? false
        if foreignArmy || foreignLand { throw GameError.badOmen }
    }

    /// How well a civilization's forces are equipped, 0–100: bronze, plus iron once it knows
    /// ironworking (steel counts it double). Iron needs no tin and doesn't wear out.
    func bronzePercent(_ civ: CivilizationID, _ state: GameState) -> Int {
        guard let cs = state.civs[civ] else { return 0 }
        let units = state.totalUnits(of: civ).total + state.fleets(of: civ).reduce(0) { $0 + $1.cargo.total }
        let metal = level(.metallurgy, of: civ, in: state)
        let ironWeight = metal >= 3 ? rules.knowledge.effects.steelIronWeight : ironWorked(civ, state) ? 1 : 0
        return min(100, (cs.bronze + (cs.stock[.iron] ?? 0) * ironWeight) * 100 / max(1, units))
    }
}
