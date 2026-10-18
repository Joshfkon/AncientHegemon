/// The result of an AI turn: everything that happened, and how many of its commands the engine
/// rejected. Rejections mean the AI misjudged the rules; the simulator reports them as bugs.
public struct AITurn: Sendable {
    public var events: [GameEvent] = []
    public var rejected: [Command] = []
}

/// A Risk-style heuristic AI (DESIGN §12), extended with supply, trade value and resources.
///
/// It plays through the same `Command`s as a human. It never reads the game's RNG: its battle
/// estimates use their own seeds derived from the state, so an AI turn is deterministic and
/// leaves the game's random sequence untouched.
public struct AIPlayer: Sendable {
    public let engine: Engine
    public let personality: Personality
    /// Battle simulations per P(win) estimate.
    public var samples = 4

    public init(engine: Engine, personality: Personality) {
        self.engine = engine
        self.personality = personality
    }

    var map: GameMap { engine.map }
    var rules: Rules { engine.rules }

    /// Plays the active civilization's turn, including ending it.
    public func playTurn(_ state: inout GameState) -> AITurn {
        var turn = AITurn()
        let civ = state.activePlayer
        diplomacy(civ, &state, &turn)
        setTaxes(civ, &state, &turn)
        court(civ, &state, &turn)
        let campaign = seaCampaign(civ, state)
        if let campaign { buildTransports(civ, for: campaign, &state, &turn) }
        recruit(civ, &state, &turn)
        attack(civ, &state, &turn)
        invest(civ, &state, &turn)
        if let campaign { sail(civ, toward: campaign, &state, &turn) }
        fortify(civ, &state, &turn)
        chooseDefensiveFormations(civ, &state, &turn)
        issue(.endTurn, &state, &turn)
        return turn
    }

    @discardableResult
    func issue(_ command: Command, _ state: inout GameState, _ turn: inout AITurn) -> Bool {
        guard state.winner == nil else { return false }
        do {
            turn.events += try engine.apply(command, to: &state)
            return true
        } catch {
            turn.rejected.append(command)
            return false
        }
    }

    /// Tries a command whose failure is an expected outcome, not an AI mistake.
    func attempt(_ command: Command, _ state: inout GameState, _ turn: inout AITurn) -> Bool {
        guard state.winner == nil, let events = try? engine.apply(command, to: &state) else { return false }
        turn.events += events
        return true
    }

    // MARK: Assessment

    /// Whether another army's owner is a danger. Natives fight back but never attack.
    func hostile(_ civ: CivilizationID, _ other: CivilizationID?, _ state: GameState) -> Bool {
        guard let other, other != nativesID else { return false }
        return state.atWar(civ, other)
    }

    /// Enemy units on land next to a territory, optionally ignoring one neighbor.
    func threat(to t: TerritoryID, for civ: CivilizationID, _ state: GameState,
                        excluding skip: TerritoryID? = nil) -> Int {
        map.landNeighbors(of: t).filter { $0 != skip }.reduce(0) { total, n in
            guard let army = state.armies[n], hostile(civ, army.owner, state) else { return total }
            return total + army.units.total
        }
    }

    func strength(of civ: CivilizationID, _ state: GameState) -> Int {
        state.totalUnits(of: civ).total + state.fleets(of: civ).reduce(0) { $0 + $1.cargo.total }
    }

    func borders(_ a: CivilizationID, _ b: CivilizationID, _ state: GameState) -> Bool {
        state.territories(of: a).contains { t in map.landNeighbors(of: t).contains { state.owner(of: $0) == b } }
    }

    func readyUnits(at t: TerritoryID, _ state: GameState) -> UnitCounts {
        guard let army = state.armies[t] else { return .zero }
        let ready = army.units - (state.moved[t] ?? .zero)
        return UnitCounts(infantry: max(0, ready.infantry), archers: max(0, ready.archers),
                          cavalry: max(0, ready.cavalry))
    }

    /// Units a territory should keep at home against the enemies next to it.
    func garrison(_ t: TerritoryID, for civ: CivilizationID, _ state: GameState,
                          excluding skip: TerritoryID? = nil) -> Int {
        let t0 = threat(to: t, for: civ, state, excluding: skip)
        var keep = Int((Double(t0) * personality.caution).rounded(.up))
        if map.civilization(civ)?.capital == t, t0 > 0 { keep += 1 }
        return keep
    }

    // MARK: Diplomacy

    func diplomacy(_ civ: CivilizationID, _ state: inout GameState, _ turn: inout AITurn) {
        let mine = strength(of: civ, state)
        // While there's free land to claim, peace is cheap; once it's gone, neighbors are the
        // only way to grow.
        let room = state.territories(of: civ).contains { t in
            map.landNeighbors(of: t).contains { state.owner(of: $0) == nil }
        }
        // Strength edge needed to start a war: 1.0 for a conqueror, about 1.3 for a turtle.
        let warEdge = 1.6 - 0.4 * personality.aggression
        let others = state.players.filter { $0 != civ && !state.civs[$0]!.eliminated }
        for other in others {
            let edge = Double(mine) / Double(max(1, strength(of: other, state)))
            let neighbor = borders(civ, other, state)
            let losing = edge < 0.75
            let prey = neighbor && !room && edge >= warEdge
            if state.atPeace(civ, other) {
                if prey, personality.trade < 0.9 || edge >= 2 {
                    issue(.declareWar(on: other), &state, &turn)
                }
                continue
            }
            let wantsPeace = losing || (!prey && (!neighbor || personality.trade >= 0.8))
            if state.peaceOffers.contains(PeaceOffer(from: other, to: civ)) {
                if wantsPeace { issue(.acceptPeace(from: other), &state, &turn) }
            } else if wantsPeace, !state.peaceOffers.contains(PeaceOffer(from: civ, to: other)) {
                issue(.offerPeace(to: other), &state, &turn)
            }
        }
    }

    // MARK: Court

    /// Keeps generals loyal and puts commanders at the head of large armies.
    func court(_ civ: CivilizationID, _ state: inout GameState, _ turn: inout AITurn) {
        let g = rules.government
        // Honor the least loyal generals while they're still worth saving, most dangerous first.
        let wavering = engine.livingGenerals(of: civ, state)
            .filter { $0.loyalty < g.successionDisloyalty + 5 }
            .sorted { ($0.loyalty, $0.id) < ($1.loyalty, $1.id) }
        for general in wavering {
            let cost = g.honorCost * (1 + general.renown)
            guard state.civs[civ]!.gold >= cost + rules.stats(.infantry).cost else { break }
            issue(.honorGeneral(general.id), &state, &turn)
        }
        // Appoint a general for the biggest leaderless army near the front, if affordable.
        guard engine.livingGenerals(of: civ, state).count < engine.maxGenerals(of: civ, in: state),
              state.civs[civ]!.gold >= g.appointCost + 2 * rules.stats(.infantry).cost else { return }
        let home = Set(engine.homeNetwork(of: civ, in: state))
        let led = Set(engine.livingGenerals(of: civ, state).compactMap(\.location))
        let candidate = state.armies(of: civ)
            .filter { home.contains($0.territory) && !led.contains($0.territory) && $0.units.total >= 4 }
            .max { ($0.units.total, $1.territory) < ($1.units.total, $0.territory) }
        if let candidate { issue(.appointGeneral(territory: candidate.territory), &state, &turn) }
    }

    // MARK: Recruitment

    func recruit(_ civ: CivilizationID, _ state: inout GameState, _ turn: inout AITurn) {
        let cheapest = UnitType.allCases.map { rules.stats($0).cost }.min()!
        for _ in 0..<60 {
            guard state.civs[civ]!.gold >= cheapest else { return }
            let home = engine.homeNetwork(of: civ, in: state)
            // Don't raise more mouths than the home granary can carry for a few turns.
            let production = engine.yield(of: .grain, in: home, state)
            let eaten = engine.grainConsumption(of: civ, in: home, state) + engine.fleetUpkeep(of: civ, state)
            // Leave room for supply lines to lengthen as the army marches out.
            let margin = state.totalUnits(of: civ).total / 4
            guard eaten + 1 + margin <= production + state.civs[civ]!.granary / 4 else { return }

            let spots = home.filter { t in
                state.population(of: t) - 1 >= rules.economy.minPopulation
                    && (state.armies[t].map { $0.owner == civ } ?? true)
            }
            guard let spot = spots.max(by: { a, b in
                let na = need(a, civ, state), nb = need(b, civ, state)
                if na != nb { return na < nb }
                let ga = map.territory(a)!.grain, gb = map.territory(b)!.grain
                return ga != gb ? ga < gb : a > b
            }) else { return }

            // A preferred type can hit its resource limit (e.g. horses); infantry always works.
            let preferred = unitType(for: spot, civ, state)
            guard attempt(.recruit(territory: spot, unit: preferred, count: 1), &state, &turn)
                    || issue(.recruit(territory: spot, unit: .infantry, count: 1), &state, &turn) else { return }
        }
    }

    /// How badly a territory wants reinforcements: threat beyond its garrison, plus a nudge
    /// toward territories with land to grab next door.
    func need(_ t: TerritoryID, _ civ: CivilizationID, _ state: GameState) -> Double {
        let own = Double(state.armies[t].map { $0.owner == civ ? $0.units.total : 0 } ?? 0)
        let danger = Double(threat(to: t, for: civ, state)) * personality.caution
        let frontier = map.landNeighbors(of: t).contains { n in
            state.owner(of: n) != civ && !(state.owner(of: n).map { state.atPeace(civ, $0) } ?? false)
        }
        return danger - own + (frontier ? 1.5 : 0)
    }

    /// Counters whatever the nearby enemy fields most of; otherwise keeps a balanced mix.
    func unitType(for t: TerritoryID, _ civ: CivilizationID, _ state: GameState) -> UnitType {
        var near = UnitCounts.zero
        for n in map.landNeighbors(of: t) {
            if let army = state.armies[n], hostile(civ, army.owner, state) { near += army.units }
        }
        if near.total > 0 {
            let top = UnitType.allCases.max { near[$0] < near[$1] }!
            switch top {
            case .cavalry: return .infantry
            case .infantry: return .archers
            case .archers: return .cavalry
            }
        }
        let have = state.totalUnits(of: civ)
        let target: [UnitType: Double] = [.infantry: 0.55, .archers: 0.25, .cavalry: 0.20]
        let total = Double(max(1, have.total))
        return UnitType.allCases.max { a, b in
            target[a]! - Double(have[a]) / total < target[b]! - Double(have[b]) / total
        }!
    }

    // MARK: Attack

    struct Option {
        let from: TerritoryID
        let to: TerritoryID
        let units: UnitCounts
        let score: Double
        let battle: Bool
    }

    func attack(_ civ: CivilizationID, _ state: inout GameState, _ turn: inout AITurn) {
        var cache: [String: Double] = [:]
        for _ in 0..<40 {
            guard state.winner == nil,
                  let best = options(civ, state, &cache).max(by: { a, b in
                      a.score != b.score ? a.score < b.score : (a.from, a.to) > (b.from, b.to)
                  }), best.score > 0 else { return }
            if best.battle {
                let formation = bestFormation(civ, from: best.from, to: best.to, units: best.units, state)
                if state.armies[best.from]?.formation != formation {
                    issue(.setFormation(territory: best.from, formation: formation), &state, &turn)
                }
            }
            let general = state.general(of: civ, at: best.from).map { !state.generalsMoved.contains($0.id) } ?? false
            let leads = general && best.battle
            if !issue(.move(from: best.from, to: best.to, units: best.units, general: leads), &state, &turn) {
                return
            }
            cache = [:]
        }
    }

    func options(_ civ: CivilizationID, _ state: GameState, _ cache: inout [String: Double]) -> [Option] {
        let home = Set(engine.homeNetwork(of: civ, in: state))
        var result: [Option] = []
        for (from, _) in state.armies(of: civ) {
            let ready = readyUnits(at: from, state)
            guard ready.total > 0 else { continue }
            let supplied = home.contains(from) ? 1.0 : 0.3
            for to in map.landNeighbors(of: from) {
                let owner = state.owner(of: to)
                if owner == civ { continue }
                if let owner, state.atPeace(civ, owner) { continue }
                if (try? engine.checkOmen(civ, attacking: to, state)) == nil { continue }
                let keep = garrison(from, for: civ, state, excluding: to)
                guard ready.total + (state.armies[from]!.units.total - ready.total) > keep else { continue }
                let spare = min(ready.total, state.armies[from]!.units.total - keep)
                guard spare > 0 else { continue }

                if let defender = state.armies[to], defender.owner != civ {
                    let units = take(spare, from: ready)
                    let key = "\(from)>\(to)>\(units.infantry),\(units.archers),\(units.cavalry)"
                    let pWin = cache[key] ?? estimate(civ, from: from, to: to, units: units,
                                                      formation: state.armies[from]!.formation, state)
                    cache[key] = pWin
                    let value = self.value(of: to, for: civ, state) * personality.aggression
                        * (1 + personality.opportunism * weakness(defender.owner, state))
                    let risk = Double(units.total) * (1 - pWin) * 0.6
                        + Double(max(0, threat(to: to, for: civ, state, excluding: from) - units.total)) * 0.2
                    let score = (pWin * value - risk) * supplied - 0.5
                    if pWin >= 0.55 { result.append(Option(from: from, to: to, units: units, score: score, battle: true)) }
                } else {
                    let units = take(1, from: ready)
                    let exposure = Double(threat(to: to, for: civ, state)) * 0.4 / personality.aggression
                    let score = (value(of: to, for: civ, state) * personality.aggression - exposure) * supplied
                    result.append(Option(from: from, to: to, units: units, score: score, battle: false))
                }
            }
        }
        return result
    }

    /// Picks `count` units from `ready`, sending cavalry and infantry before archers.
    func take(_ count: Int, from ready: UnitCounts) -> UnitCounts {
        var left = count
        var units = UnitCounts.zero
        for type in [UnitType.infantry, .cavalry, .archers] {
            let n = min(left, ready[type])
            units[type] = n
            left -= n
        }
        return units
    }

    /// How much a territory is worth to `civ`.
    func value(of t: TerritoryID, for civ: CivilizationID, _ state: GameState) -> Double {
        let territory = map.territory(t)!
        let tin = engine.effectiveYield(of: .tin, for: civ, in: state)
        let copper = engine.effectiveYield(of: .copper, for: civ, in: state)
        let weights: [Resource: Double] = [
            .tin: tin == 0 ? 4 : 1.5, .copper: copper == 0 ? 3 : 1, .horses: 1.5, .timber: 1, .gold: 2,
        ]
        var v = Double(territory.grain) * 0.8
        for (resource, amount) in territory.resources.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            v += Double(amount) * (weights[resource] ?? 0)
        }
        if let owner = state.owner(of: t) {
            if map.civilization(owner)?.capital == t { v += 6 }
            if state.territories(of: owner).count <= 2 { v += 5 }
        }
        for c in map.chokepoints where c.heldBy.contains(t) {
            if c.heldBy.allSatisfy({ $0 == t || state.owner(of: $0) == civ }) { v += 3 }
        }
        return v
    }

    /// 0 for a healthy civilization, rising toward 1 as it shrinks or fights on several fronts.
    func weakness(_ civ: CivilizationID, _ state: GameState) -> Double {
        let wars = state.players.filter { $0 != civ && !state.civs[$0]!.eliminated && state.atWar(civ, $0) }.count
        let land = state.territories(of: civ).count
        return min(1, Double(max(0, wars - 1)) * 0.25 + (land <= 3 ? 0.5 : 0))
    }

    // MARK: Battle estimates

    func battleSetup(_ civ: CivilizationID, from: TerritoryID, to: TerritoryID, units: UnitCounts,
                             formation: FormationID?, seed: UInt64, _ state: GameState) -> BattleSetup {
        let defender = state.armies[to]!
        let general = state.general(of: civ, at: from).flatMap { state.generalsMoved.contains($0.id) ? nil : $0 }
        let approach: Approach = switch map.crossing(between: from, and: to) {
        case .river: .river
        case .strait: .strait
        case nil: .overland
        }
        return BattleSetup(
            attacker: engine.battleArmy(civ, units, formation: formation, general: general, state),
            defender: engine.battleArmy(defender.owner, defender.units, formation: defender.formation,
                                        general: state.general(of: defender.owner, at: to), state),
            terrain: map.territory(to)!.terrain, approach: approach, seed: seed,
            fortification: engine.fortification(at: to, state))
    }

    /// Seeds for estimates, derived from the state so the AI is deterministic without touching
    /// the game's RNG.
    func seeds(_ state: GameState, _ salt: String) -> [UInt64] {
        var h: UInt64 = state.seed ^ (UInt64(state.turn) &* 0x9E37_79B9_7F4A_7C15)
        for byte in salt.utf8 { h = (h ^ UInt64(byte)) &* 0x100_0000_01B3 }
        var rng = SeededRNG(seed: h)
        return (0..<samples).map { _ in rng.next() }
    }

    func estimate(_ civ: CivilizationID, from: TerritoryID, to: TerritoryID, units: UnitCounts,
                          formation: FormationID?, _ state: GameState) -> Double {
        let sim = BattleSimulator(rules: rules)
        let wins = seeds(state, from + to).filter { seed in
            sim.resolve(battleSetup(civ, from: from, to: to, units: units, formation: formation,
                                    seed: seed, state)).winner == .attacker
        }.count
        return Double(wins) / Double(samples)
    }

    func bestFormation(_ civ: CivilizationID, from: TerritoryID, to: TerritoryID, units: UnitCounts,
                               _ state: GameState) -> FormationID {
        rules.battle.formations.map(\.id).max { a, b in
            let pa = estimate(civ, from: from, to: to, units: units, formation: a, state)
            let pb = estimate(civ, from: from, to: to, units: units, formation: b, state)
            return pa != pb ? pa < pb : a > b
        }!
    }

    /// For each army facing an enemy stack, the formation that defends best against the
    /// strongest neighbor attacking with everything.
    func chooseDefensiveFormations(_ civ: CivilizationID, _ state: inout GameState, _ turn: inout AITurn) {
        let sim = BattleSimulator(rules: rules)
        for (t, units) in state.armies(of: civ) {
            let foes = map.landNeighbors(of: t).compactMap { n -> (TerritoryID, Army)? in
                guard let a = state.armies[n], hostile(civ, a.owner, state) else { return nil }
                return (n, a)
            }
            guard let (from, enemy) = foes.max(by: { $0.1.units.total < $1.1.units.total }) else { continue }
            var bestID = rules.battle.defaultFormation
            var bestHolds = -1
            for formation in rules.battle.formations.map(\.id) {
                let holds = seeds(state, "def" + t + formation).filter { seed in
                    var setup = BattleSetup(
                        attacker: engine.battleArmy(enemy.owner, enemy.units, formation: enemy.formation,
                                                    general: nil, state),
                        defender: engine.battleArmy(civ, units, formation: formation,
                                                    general: state.general(of: civ, at: t), state),
                        terrain: map.territory(t)!.terrain, seed: seed,
                        fortification: engine.fortification(at: t, state))
                    if map.crossing(between: from, and: t) == .river { setup.approach = .river }
                    return sim.resolve(setup).winner == .defender
                }.count
                if holds > bestHolds { (bestID, bestHolds) = (formation, holds) }
            }
            if state.armies[t]?.formation != bestID {
                issue(.setFormation(territory: t, formation: bestID), &state, &turn)
            }
        }
    }

    // MARK: Fortify

    /// Marches idle units out of safe interior territories toward the nearest border.
    func fortify(_ civ: CivilizationID, _ state: inout GameState, _ turn: inout AITurn) {
        let owned = Set(state.territories(of: civ))
        let frontier = owned.filter { t in map.landNeighbors(of: t).contains { !owned.contains($0) } }
        var distance: [TerritoryID: Int] = [:]
        var queue = frontier.sorted()
        for t in queue { distance[t] = 0 }
        var i = 0
        while i < queue.count {
            let t = queue[i]
            i += 1
            for n in map.landNeighbors(of: t) where owned.contains(n) && distance[n] == nil {
                distance[n] = distance[t]! + 1
                queue.append(n)
            }
        }
        for (t, _) in state.armies(of: civ) where (distance[t] ?? 0) > 0 {
            let ready = readyUnits(at: t, state)
            guard ready.total > 0,
                  let next = map.landNeighbors(of: t).filter({ distance[$0] != nil })
                      .min(by: { (distance[$0]!, $0) < (distance[$1]!, $1) }),
                  distance[next]! < distance[t]! else { continue }
            let general = state.general(of: civ, at: t).map { !state.generalsMoved.contains($0.id) } ?? false
            issue(.move(from: t, to: next, units: ready, general: general), &state, &turn)
        }
    }
}
