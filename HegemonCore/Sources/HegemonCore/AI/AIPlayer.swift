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
/// leaves the game's random sequence untouched. Like a person it judges rivals' armies only
/// as far as it can see (`Engine.sight`); beyond that it goes by rumour and assumed garrisons.
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
        courtPeoples(civ, &state, &turn)
        recruit(civ, &state, &turn)
        sally(civ, &state, &turn)
        attack(civ, &state, &turn)
        besiege(civ, &state, &turn)
        invest(civ, &state, &turn)
        huntPirates(civ, &state, &turn)
        if let campaign { sail(civ, toward: campaign, &state, &turn) } else { shelterFleets(civ, &state, &turn) }
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

    /// Whether another army's owner is a danger. Tribes fight back but never attack; kingdoms
    /// attack only empires they hate, and only the warlike.
    func hostile(_ civ: CivilizationID, _ other: CivilizationID?, _ state: GameState) -> Bool {
        guard let other, other != nativesID else { return false }
        if isKingdom(other) {
            return engine.people(of: other, in: state)?.temperament == .warlike
                && engine.attitude(of: other, toward: civ, in: state) <= rules.minors.raidAttitude
        }
        return state.atWar(civ, other)
    }

    /// Enemy units on land next to a territory, as far as `civ` can tell, optionally ignoring
    /// one neighbor. Pass `sight` when calling it often for land beyond the civ's own.
    func threat(to t: TerritoryID, for civ: CivilizationID, _ state: GameState,
                excluding skip: TerritoryID? = nil, sight: Set<TerritoryID>? = nil) -> Int {
        // Everything next to your own land and armies is in sight.
        let near = state.owner(of: t) == civ || state.armies[t]?.owner == civ
        let sight = near ? nil : sight ?? engine.sight(of: civ, in: state)
        return map.landNeighbors(of: t).filter { $0 != skip }.reduce(0) { total, n in
            if let sight {
                guard let army = engine.perceivedArmy(at: n, by: civ, sight: sight, in: state),
                      hostile(civ, army.owner, state) else { return total }
                return total + army.units
            }
            guard let army = state.armies[n], hostile(civ, army.owner, state) else { return total }
            return total + army.units.total
        }
    }

    /// Soldiers on land and aboard ship, as far as `observer` can tell.
    func strength(of civ: CivilizationID, seenBy observer: CivilizationID, sight: Set<TerritoryID>,
                  _ state: GameState) -> Int {
        engine.perceivedStrength(of: civ, by: observer, ships: false, sight: sight, in: state)
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
        // Restless land needs troops to hold it down.
        if engine.needsGarrison(t, of: civ, in: state) { keep = max(keep, rules.unrest.garrisonToCalm) }
        return keep
    }

    // MARK: Diplomacy

    func diplomacy(_ civ: CivilizationID, _ state: inout GameState, _ turn: inout AITurn) {
        // A demand left waiting (a seat a person handed to the AI) gets the court's usual answer.
        for demand in state.submissionDemands.filter({ $0.to == civ }).sorted(by: { $0.from < $1.from }) {
            _ = attempt(.answerSubmission(from: demand.from, accept: engine.wouldSubmit(civ, to: demand.from, in: state)), &state, &turn)
        }
        alliances(civ, &state, &turn)
        let sight = engine.sight(of: civ, in: state)
        let mine = strength(of: civ, seenBy: civ, sight: sight, state)
        // While there's free land to claim, peace is cheap; once it's gone, neighbors are the
        // only way to grow.
        // (Land it won't settle, like a barbarian homeland, doesn't count.)
        let room = state.territories(of: civ).contains { t in
            map.landNeighbors(of: t).contains { state.owner(of: $0) == nil && value(of: $0, for: civ, state) > 0 }
        }
        // Strength edge needed to start a war: 1.0 for a conqueror, about 1.3 for a turtle.
        let warEdge = 1.6 - 0.4 * personality.aggression
        let others = state.players.filter { $0 != civ && !state.civs[$0]!.eliminated }
        // A coalition: when one empire runs away with the age, the rest stop fighting each
        // other and turn on it together.
        let menace = engine.menace(in: state)
        for other in others {
            let edge = Double(mine) / Double(max(1, strength(of: other, seenBy: civ, sight: sight, state)))
            let neighbor = borders(civ, other, state)
            let losing = edge < 0.75
            var prey = neighbor && !room && edge >= warEdge
            if let menace, menace != civ {
                // Bordering the menace is reason enough to fight it with friends; everyone else is a friend.
                if other == menace { prey = neighbor && edge >= warEdge * 0.6 }
                else if state.atWar(other, menace) { prey = false }
            }
            if state.atPeace(civ, other) {
                // Allies keep faith.
                if engine.allied(civ, other, in: state) { continue }
                // Vassalage binds both sides, and a vassal its overlord's allies.
                if !engine.mayDeclareWar(civ, on: other, in: state) { continue }
                if prey, personality.trade < 0.9 || edge >= 2 {
                    issue(.declareWar(on: other), &state, &turn)
                }
                continue
            }
            // A beaten rival that would bow is made a vassal: tribute and prestige without the
            // cost of conquering the rest. A person is asked once, and not again for a while after
            // turning it down.
            let demand = PeaceOffer(from: civ, to: other)
            if engine.wouldSubmit(other, to: civ, in: state), !state.submissionDemands.contains(demand),
               (state.submissionRebuffed[demand] ?? 0) < state.turn,
               attempt(.demandSubmission(of: other), &state, &turn),
               state.atPeace(civ, other) || state.submissionDemands.contains(demand) {
                continue
            }
            if state.submissionDemands.contains(demand) { continue }
            var wantsPeace = losing || (!prey && (!neighbor || personality.trade >= 0.8))
            if let menace, menace != civ {
                // Make common cause with the menace's other enemies; never a separate peace with it.
                if other == menace { wantsPeace = losing && edge < 0.4 }
                else if state.atWar(other, menace) { wantsPeace = true }
            }
            // Not while an ally is at war with them: a separate peace betrays it.
            if engine.allies(of: civ, in: state).contains(where: { state.atWar($0, other) && $0 != other }) { wantsPeace = losing }
            // A splendid court's envoys are hard to turn away.
            let awed = engine.magnificence(of: other, in: state) >= rules.throneRoom.peaceMagnificence && edge < 2
            if state.peaceOffers.contains(PeaceOffer(from: other, to: civ)) {
                if wantsPeace || awed { issue(.acceptPeace(from: other), &state, &turn) }
            } else if wantsPeace, !state.peaceOffers.contains(PeaceOffer(from: civ, to: other)),
                      (state.peaceRebuffed[PeaceOffer(from: civ, to: other)] ?? 0) < state.turn {
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

    // MARK: Alliances

    /// Seeks an ally against a common, dangerous enemy: AI courts answer at once; a person is
    /// asked now and then rather than every turn.
    func alliances(_ civ: CivilizationID, _ state: inout GameState, _ turn: inout AITurn) {
        // Accept a person's offer on the same terms it would make one.
        for offer in state.allianceOffers.filter({ $0.to == civ }).sorted(by: { $0.from < $1.from }) {
            if engine.wouldAlly(civ, with: offer.from, in: state) { _ = attempt(.acceptAlliance(from: offer.from), &state, &turn) }
        }
        guard engine.allies(of: civ, in: state).count < rules.alliances.maxAllies else { return }
        let candidates = state.players.filter { other in
            other != civ && !(state.civs[other]?.eliminated ?? true) && engine.wouldAlly(civ, with: other, in: state)
        }.sorted()
        for other in candidates {
            let human = state.civs[other]?.isHuman == true
            if human, state.turn % 4 != 0 || state.allianceOffers.contains(PeaceOffer(from: civ, to: other)) { continue }
            if attempt(.offerAlliance(to: other), &state, &turn) { return }
        }
    }

    // MARK: Recruitment

    func recruit(_ civ: CivilizationID, _ state: inout GameState, _ turn: inout AITurn) {
        let cheapest = UnitType.allCases.map { rules.stats($0).cost }.min()!
        let income = engine.economy(of: civ, in: state).income
        for _ in 0..<60 {
            guard state.civs[civ]!.gold >= cheapest else { return }
            // Only raise soldiers the treasury can keep paying: income, or savings for a while.
            let soldiers = state.totalUnits(of: civ).total + state.fleets(of: civ).reduce(0) { $0 + $1.cargo.total }
            let pay = engine.armyPay(soldiers: soldiers + 1)
            guard pay <= income + max(0, state.civs[civ]!.gold - cheapest) / 6 else { return }
            let home = engine.homeNetwork(of: civ, in: state)
            // Don't raise more mouths than the home granary can carry for a few turns.
            let production = engine.yield(of: .grain, in: home, state)
            let eaten = engine.grainConsumption(of: civ, in: home, state) + engine.fleetUpkeep(of: civ, state)
            // Leave room for supply lines to lengthen as the army marches out.
            let margin = state.totalUnits(of: civ).total / 4
            // Grain bought abroad counts, as far as the treasury could keep paying for it.
            let spare = max(0, state.civs[civ]!.gold - investmentReserve(civ, state))
            let imports = min(engine.grainImportCap(of: civ, in: state),
                              spare / (max(1, rules.trade.grainPrice) * importTurns))
            guard eaten + 1 + margin <= production + state.civs[civ]!.granary / 4 + imports else { return }

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

    /// Turns of grain imports the treasury must be able to pay for before the AI raises troops on them.
    var importTurns: Int { 8 }

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
                let plan = bestPlan(civ, from: best.from, to: best.to, units: best.units, state)
                if state.armies[best.from]?.plan != plan {
                    issue(.setBattlePlan(territory: best.from, plan: plan), &state, &turn)
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

    /// Peoples next door that would swear fealty: rich land is worth conquering outright; poor
    /// land is taken as a vassal (and annexed when the time comes, without battle or unrest);
    /// in between, the gentler empires take vassals and the warlike conquer. A true conqueror
    /// takes no vassals at all.
    func courtPeoples(_ civ: CivilizationID, _ state: inout GameState, _ turn: inout AITurn) {
        for k in state.kingdoms.keys.sorted() {
            let lands = engine.lands(of: k, in: state)
            guard let first = lands.first else { continue }
            if state.kingdoms[k]?.overlord == civ {
                if engine.annexWait(first, in: state) == 0 { attempt(.annex(territory: first), &state, &turn) }
                continue
            }
            // Judged by its richest land. A true conqueror takes no oaths: it conquers.
            let grain = lands.map { map.territory($0)!.grain }.max() ?? 0
            let swear = personality.aggression < 1.3 && (grain <= 3 || (grain < 5 && personality.aggression < 1))
            guard swear, let t = lands.first(where: { engine.tribe(at: $0, for: civ, in: state) != nil && !state.parleyed.contains($0) }),
                  engine.wouldSwear(t, to: civ, in: state) else { continue }
            attempt(.parley(territory: t, .vassalage), &state, &turn)
        }
    }

    /// A besieged garrison goes out to meet the besiegers when it has a fair chance.
    func sally(_ civ: CivilizationID, _ state: inout GameState, _ turn: inout AITurn) {
        // A siege made peace with lingers until the besieger's turn: no sallying against friends.
        for (town, siege) in state.sieges.sorted(by: { $0.key < $1.key }) where state.owner(of: town) == civ
            && state.atWar(civ, siege.civ) {
            let ready = readyUnits(at: town, state)
            guard ready.total > 0, state.armies[siege.camp].map({ $0.owner != civ }) == true,
                  engine.defenders(of: siege.camp, against: civ, state) != nil else { continue }
            let pWin = estimate(civ, from: town, to: siege.camp, units: ready, plan: state.armies[town]!.plan, state)
            // Hunger makes a garrison bolder.
            let bar = siege.rounds > rules.siege.storeRounds ? 0.4 : 0.55
            if pWin >= bar { issue(.move(from: town, to: siege.camp, units: ready), &state, &turn) }
        }
    }

    /// Walled towns too strong to storm are besieged instead, by an army at least nearly the
    /// garrison's size; once hunger and rams have done their work, `attack` storms them.
    func besiege(_ civ: CivilizationID, _ state: inout GameState, _ turn: inout AITurn) {
        for (camp, _) in state.armies(of: civ).sorted(by: { $0.territory < $1.territory }) {
            let ready = readyUnits(at: camp, state)
            guard ready.total > 0, !state.sieges.values.contains(where: { $0.camp == camp && $0.civ == civ }) else { continue }
            // No siege under a bad omen, as no attack.
            let towns = map.landNeighbors(of: camp).filter {
                engine.canBesiege($0, from: camp, by: civ, state) && (try? engine.checkOmen(civ, attacking: $0, state)) != nil
                    && !engine.spared($0, state)
            }
            for town in towns.sorted() {
                guard let d = engine.defenders(of: town, against: civ, state),
                      Double(ready.total) >= Double(d.army.units.total + d.levy) * 0.8,
                      value(of: town, for: civ, state) * personality.aggression > 1 else { continue }
                let pWin = estimate(civ, from: camp, to: town, units: ready, plan: state.armies[camp]!.plan, state)
                if pWin < 0.55, issue(.besiege(territory: town, from: camp), &state, &turn) { break }
            }
        }
    }

    func options(_ civ: CivilizationID, _ state: GameState, _ cache: inout [String: Double]) -> [Option] {
        let home = Set(engine.homeNetwork(of: civ, in: state))
        let sight = engine.sight(of: civ, in: state)
        var result: [Option] = []
        for (from, _) in state.armies(of: civ) {
            let ready = readyUnits(at: from, state)
            guard ready.total > 0 else { continue }
            let supplied = home.contains(from) ? 1.0 : 0.3
            // Next door, and beyond our vassals' land (kingdoms' and empires').
            let reach = map.landNeighbors(of: from) + engine.passageTargets(from: from, for: civ, in: state).keys.sorted()
                + engine.empirePassageTargets(from: from, for: civ, in: state).map(\.to)
            for to in reach {
                let owner = state.owner(of: to)
                if owner == civ { continue }
                if let owner, state.atPeace(civ, owner) { continue }
                if engine.shielded(to, from: civ, in: state) || engine.spared(to, state) { continue }
                if (try? engine.checkOmen(civ, attacking: to, state)) == nil { continue }
                let keep = garrison(from, for: civ, state, excluding: to)
                guard ready.total + (state.armies[from]!.units.total - ready.total) > keep else { continue }
                let spare = min(ready.total, state.armies[from]!.units.total - keep)
                guard spare > 0 else { continue }

                if let defender = engine.defenders(of: to, against: civ, state) {
                    let units = take(spare, from: ready)
                    let key = "\(from)>\(to)>\(units.infantry),\(units.archers),\(units.cavalry)"
                    // Judge the attack in the army's formation, without any defensive stratagem
                    // it was holding with; the plan is chosen properly once the attack is picked.
                    let pWin = cache[key] ?? estimate(civ, from: from, to: to, units: units,
                                                      plan: BattlePlan(formation: state.armies[from]!.formation), state)
                    cache[key] = pWin
                    let value = self.value(of: to, for: civ, state) * personality.aggression
                        * (1 + personality.opportunism * weakness(defender.owner, state))
                    let risk = Double(units.total) * (1 - pWin) * 0.6
                        + Double(max(0, threat(to: to, for: civ, state, excluding: from, sight: sight) - units.total)) * 0.2
                    let score = (pWin * value - risk) * supplied - 0.5
                    if pWin >= 0.55 { result.append(Option(from: from, to: to, units: units, score: score, battle: true)) }
                } else {
                    let units = take(1, from: ready)
                    let exposure = Double(threat(to: to, for: civ, state, sight: sight)) * 0.4 / personality.aggression
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
            .wine: 1, .luxuries: 1, .stone: 0.5, .iron: 1,
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
        // Unclaimed barbarian homelands breed migrations: settling one, or a new border with
        // one, invites hordes for the rest of the game. (A rival's land is worth taking anyway.)
        guard state.owner(of: t) == nil else { return v }
        if territory.has(.barbarianHomeland) { v -= 2.5 }
        let ours = Set(state.territories(of: civ))
        let newFronts = map.landNeighbors(of: t).filter { n in
            map.territory(n)!.has(.barbarianHomeland) && !ours.contains(n)
                && !map.landNeighbors(of: n).contains(where: ours.contains)
        }.count
        v -= Double(newFronts) * 1.2
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
                             plan: BattlePlan, seed: UInt64, _ state: GameState) -> BattleSetup {
        let general = state.general(of: civ, at: from).flatMap { state.generalsMoved.contains($0.id) ? nil : $0 }
        let last = map.areLandAdjacent(from, to) ? from : engine.vassalPassage(from, to, for: civ, in: state) ?? from
        let approach: Approach = switch map.crossing(between: last, and: to) {
        case .river: .river
        case .strait: .strait
        case nil: .overland
        }
        return BattleSetup(
            attacker: engine.battleArmy(civ, units, plan: plan, general: general, state),
            defender: engine.defendingArmy(of: to, against: civ, state)!,
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
                          plan: BattlePlan, _ state: GameState) -> Double {
        let sim = BattleSimulator(rules: rules)
        let wins = seeds(state, from + to).filter { seed in
            sim.resolve(battleSetup(civ, from: from, to: to, units: units, plan: plan,
                                    seed: seed, state)).winner == .attacker
        }.count
        return Double(wins) / Double(samples)
    }

    /// The best unlocked formation, then whichever unlocked stratagem or line depth improves on
    /// it (attacking stratagems only; standing fast is for defenders).
    func bestPlan(_ civ: CivilizationID, from: TerritoryID, to: TerritoryID, units: UnitCounts,
                  _ state: GameState) -> BattlePlan {
        let general = state.general(of: civ, at: from).flatMap { state.generalsMoved.contains($0.id) ? nil : $0 }
        func odds(_ plan: BattlePlan) -> Double { estimate(civ, from: from, to: to, units: units, plan: plan, state) }
        let formations = rules.battle.formations.map(\.id).filter {
            engine.formationAvailable($0, civ, general: general, in: state)
        }
        var best = BattlePlan(formation: rules.battle.defaultFormation)
        var bestOdds = -1.0
        for f in formations {
            let p = odds(BattlePlan(formation: f))
            if p > bestOdds { (best, bestOdds) = (BattlePlan(formation: f), p) }
        }
        var variants: [BattlePlan] = [BattlePlan(formation: best.formation, depth: .wide)]
        for s in [Stratagem.feignedRetreat, .flankingMarch, .shieldWall]
        where engine.stratagemAvailable(s, civ, general: general, in: state) && (s != .feignedRetreat || units.cavalry > 0) {
            variants.append(BattlePlan(formation: best.formation, stratagem: s))
        }
        for plan in variants {
            let p = odds(plan)
            if p > bestOdds { (best, bestOdds) = (plan, p) }
        }
        return best
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
            let general = state.general(of: civ, at: t)
            func holds(_ plan: BattlePlan) -> Int {
                seeds(state, "def" + t + (plan.formation ?? "") + plan.depth.rawValue + (plan.stratagem?.rawValue ?? "")).filter { seed in
                    var setup = BattleSetup(
                        attacker: engine.battleArmy(enemy.owner, enemy.units, plan: enemy.plan, general: nil, state),
                        defender: { var a = engine.battleArmy(civ, units, plan: plan, general: general, state)
                                    a.levy = engine.levy(at: t, state)
                                    return a }(),
                        terrain: map.territory(t)!.terrain, seed: seed,
                        fortification: engine.fortification(at: t, state))
                    if map.crossing(between: from, and: t) == .river { setup.approach = .river }
                    return sim.resolve(setup).winner == .defender
                }.count
            }
            var best = BattlePlan(formation: rules.battle.defaultFormation)
            var bestHolds = -1
            for formation in rules.battle.formations.map(\.id)
            where engine.formationAvailable(formation, civ, general: general, in: state) {
                let h = holds(BattlePlan(formation: formation))
                if h > bestHolds { (best, bestHolds) = (BattlePlan(formation: formation), h) }
            }
            // Then the defensive tricks: a wide line, standing fast, a shield wall.
            var variants = [BattlePlan(formation: best.formation, depth: .wide)]
            for s in [Stratagem.standFast, .shieldWall] where engine.stratagemAvailable(s, civ, general: general, in: state) {
                variants.append(BattlePlan(formation: best.formation, stratagem: s))
            }
            for plan in variants {
                let h = holds(plan)
                if h > bestHolds { (best, bestHolds) = (plan, h) }
            }
            if state.armies[t]?.plan != best {
                issue(.setBattlePlan(territory: t, plan: best), &state, &turn)
            }
        }
    }

    // MARK: Fortify

    /// Marches idle units out of safe interior territories toward the nearest border.
    func fortify(_ civ: CivilizationID, _ state: inout GameState, _ turn: inout AITurn) {
        let owned = Set(state.territories(of: civ))
        // Once the Sea Peoples are about, every coast is a front too.
        let coastsExposed = engine.collapsePressure(state) >= 25
        let frontier = owned.filter { t in
            map.landNeighbors(of: t).contains { !owned.contains($0) } || (coastsExposed && map.territory(t)!.isCoastal)
        }
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
