/// The AI's use of ships: amphibious campaigns against coasts it can't reach by land.
///
/// Stateless like the rest of the AI: each turn it picks the best target across the water,
/// builds transports if it lacks them, loads spare troops at the nearest coast, sails one sea
/// toward the target, and lands when the battle sim says the landing should succeed.
struct SeaCampaign {
    let target: TerritoryID
    /// Seas bordering the target, where a fleet can land.
    let landingSeas: Set<SeaZoneID>
    /// Units the landing force wants.
    let force: Int
}

extension AIPlayer {


    /// Seas a fleet of `ships` may sail through: open lanes, and no enemy fleet it can't beat.
    private func sailable(_ sea: SeaZoneID, ships: Int, _ civ: CivilizationID, _ state: GameState) -> Bool {
        let enemy = state.fleets.filter { $0.sea == sea && state.atWar(civ, $0.owner) }.reduce(0) { $0 + $1.ships }
        return enemy == 0 || Double(ships) >= Double(enemy) * 1.5
    }

    /// Sea steps from each sea to the nearest sea in `goals`, for a fleet of `ships`.
    private func seaDistances(to goals: Set<SeaZoneID>, ships: Int, _ civ: CivilizationID,
                              _ state: GameState) -> [SeaZoneID: Int] {
        var dist: [SeaZoneID: Int] = [:]
        var queue = goals.sorted()
        for s in queue { dist[s] = 0 }
        var i = 0
        while i < queue.count {
            let s = queue[i]
            i += 1
            for n in map.seaNeighbors(of: s) where dist[n] == nil
                && engine.seaLinkOpen(s, n, for: [civ], in: state) && sailable(n, ships: ships, civ, state) {
                dist[n] = dist[s]! + 1
                queue.append(n)
            }
        }
        return dist
    }

    /// The most valuable coast reachable only by sea, if any is worth an expedition.
    func seaCampaign(_ civ: CivilizationID, _ state: GameState) -> SeaCampaign? {
        let home = engine.homeNetwork(of: civ, in: state)
        let ports = Set(home.flatMap { map.seas(bordering: $0) })
        guard !ports.isEmpty else { return nil }
        let owned = Set(state.territories(of: civ))
        let sight = engine.sight(of: civ, in: state)

        var best: (SeaCampaign, Double)?
        for t in map.territories where t.isCoastal && !owned.contains(t.id) {
            if let owner = state.owner(of: t.id), state.atPeace(civ, owner) { continue }
            if engine.shielded(t.id, from: civ, in: state) || engine.spared(t.id, state) { continue }
            // Coasts next to our own land are the army's job.
            if map.landNeighbors(of: t.id).contains(where: owned.contains) { continue }
            let landing = Set(t.seas)
            let dist = seaDistances(to: landing, ships: 1, civ, state)
            guard let steps = ports.compactMap({ dist[$0] }).min() else { continue }
            // Across the water the AI often goes by rumour and guesswork.
            let defenders = engine.perceivedArmy(at: t.id, by: civ, sight: sight, in: state)
                .map { $0.owner == civ ? 0 : $0.units } ?? 0
                + (state.owner(of: t.id) != civ ? engine.levy(at: t.id, state) : 0)
            let score = value(of: t.id, for: civ, state) * personality.aggression
                - Double(defenders) * 0.7 - Double(steps) * 0.75
            let force = min(8, defenders * 2 + 1)
            if score > 2, best.map({ score > $0.1 }) ?? true {
                best = (SeaCampaign(target: t.id, landingSeas: landing, force: force), score)
            }
        }
        return best?.0
    }

    /// Builds ships at the home coast nearest the campaign until the fleet can carry the force.
    func buildTransports(_ civ: CivilizationID, for campaign: SeaCampaign,
                         _ state: inout GameState, _ turn: inout AITurn) {
        let have = state.fleets(of: civ).reduce(0) { $0 + $1.ships }
        let want = transportsWanted(civ, for: campaign, state)
        guard have < want else { return }
        let dist = seaDistances(to: campaign.landingSeas, ships: want, civ, state)
        let yards = engine.homeNetwork(of: civ, in: state).flatMap { t in
            map.seas(bordering: t).compactMap { s in dist[s].map { (t, s, $0) } }
        }.filter { !engine.blockaded($0.1, for: [civ], in: state) }
        guard let (yard, sea, _) = yards.min(by: { ($0.2, $0.0, $0.1) < ($1.2, $1.0, $1.1) }) else { return }
        // Keep enough gold for at least one recruit, and only build crews the harvest can feed.
        let spare = state.civs[civ]!.gold - rules.stats(.infantry).cost
        // Grain bought abroad counts, as far as the treasury could keep paying for it.
        let imports = min(engine.grainImportCap(of: civ, in: state),
                          max(0, spare - rules.ships.cost) / (max(1, rules.trade.grainPrice) * importTurns))
        let fed = max(0, engine.economy(of: civ, in: state).grainBalance - growthReserve(civ, state) + imports)
            / max(1, rules.ships.upkeep)
        let count = min(want - have, spare / rules.ships.cost, fed)
        if count > 0 {
            _ = attempt(.buildShips(territory: yard, sea: sea, count: count), &state, &turn)
        }
    }

    /// Loads spare troops, sails toward the campaign target and lands when the odds are good.
    func sail(_ civ: CivilizationID, toward campaign: SeaCampaign, _ state: inout GameState, _ turn: inout AITurn) {
        // Whether any home coast has troops to spare, before this turn's boarding takes them.
        let reinforcements = !portSeas(civ, state).isEmpty
        for sea in state.fleets(of: civ).map(\.sea) {
            // Board only a force that could land: a half-filled expedition just sails back and
            // unloads, turn after turn.
            if let fleet = state.fleet(of: civ, in: sea) {
                let full = min(campaign.force, fleet.ships * engine.shipCapacity(civ, state))
                if fleet.cargo.total + spareOnCoasts(of: sea, civ, state) >= max(2, full * 2 / 3) {
                    embark(civ, at: sea, upTo: campaign.force, &state, &turn)
                }
            }
            if land(civ, from: sea, campaign, &state, &turn) { continue }
            guard let fleet = state.fleet(of: civ, in: sea), fleet.cargo.total > 0 || fleet.ships > 0 else { continue }
            let ready = fleet.ships - fleet.movedShips
            guard ready > 0, fleet.cargo.total <= ready * engine.shipCapacity(civ, state) else { continue }
            // Too weak to land: go back to a port with spare troops instead of idling at sea. If
            // there are none to add, bring the troops home rather than let them starve aboard.
            let ports = portSeas(civ, state)
            let weak = fleet.cargo.total > 0 && fleet.cargo.total < campaign.force
            let homeCoasts = engine.homeNetwork(of: civ, in: state).filter { map.territory($0)!.seas.contains(sea) }
            if weak, !reinforcements, fleet.movedShips == 0, let coast = homeCoasts.sorted().first,
               state.armies[coast].map({ $0.owner == civ }) ?? true,
               !(turn.events.contains { if case let .embarked(_, _, s, _) = $0 { s == sea } else { false } }) {
                if issue(.land(sea: sea, territory: coast, units: fleet.cargo), &state, &turn) { continue }
            }
            let homeSeas = Set(engine.homeNetwork(of: civ, in: state).flatMap { map.seas(bordering: $0) })
            // An empty fleet waits where troops can board, or goes to fetch them.
            if fleet.cargo.total == 0, ports.contains(sea) || ports.isEmpty { continue }
            let goal = fleet.cargo.total == 0 ? ports
                : weak && !ports.contains(sea) && !ports.isEmpty ? ports
                : weak && ports.isEmpty && !homeSeas.isEmpty ? homeSeas
                : campaign.landingSeas
            let dist = seaDistances(to: goal, ships: ready, civ, state)
            // As far toward the goal as a turn's sailing goes.
            guard let here = dist[sea], here > 0,
                  let next = engine.fleetPaths(from: sea, for: civ, in: state)
                      .compactMap({ s, path in dist[s].map { (s, $0, path.count) } })
                      .filter({ $0.1 < here })
                      .min(by: { ($0.1, $0.2, $0.0) < ($1.1, $1.2, $1.0) })?.0 else { continue }
            guard issue(.moveFleet(from: sea, to: next, ships: ready, cargo: fleet.cargo), &state, &turn) else { continue }
            if state.fleet(of: civ, in: next) != nil { _ = land(civ, from: next, campaign, &state, &turn) }
        }
    }

    /// Sends ready ships against pirates within a turn's sailing, when the battle looks won.
    func huntPirates(_ civ: CivilizationID, _ state: inout GameState, _ turn: inout AITurn) {
        for sea in state.fleets(of: civ).map(\.sea).sorted() {
            guard let fleet = state.fleet(of: civ, in: sea) else { continue }
            let ready = fleet.ships - fleet.movedShips
            guard ready > 0, fleet.cargo.total <= ready * engine.shipCapacity(civ, state) else { continue }
            let reach = engine.fleetPaths(from: sea, for: civ, in: state)
            let prey = engine.pirateFleets(in: state).map(\.sea).filter { reach[$0] != nil }.sorted()
            for target in prey {
                guard let odds = engine.fleetAttackOdds(civ, ships: ready, into: target, plan: fleet.plan, in: state),
                      odds >= 0.65 else { continue }
                if issue(.moveFleet(from: sea, to: target, ships: ready, cargo: fleet.cargo), &state, &turn) { break }
            }
        }
    }

    /// With no expedition afoot, idle empty ships ride out the weather off a harbour of their own.
    /// Ships needed to carry a campaign's force.
    func transportsWanted(_ civ: CivilizationID, for campaign: SeaCampaign, _ state: GameState) -> Int {
        let capacity = engine.shipCapacity(civ, state)
        return (campaign.force + capacity - 1) / capacity
    }

    /// With no campaign afoot, idle crews that eat the grain the people need to grow are sent
    /// home, one ship a turn, down to a single ship.
    func trimFleets(_ civ: CivilizationID, _ state: inout GameState, _ turn: inout AITurn) {
        let ships = state.fleets(of: civ).reduce(0) { $0 + $1.ships }
        guard ships > 1, growthReserve(civ, state) > 0, engine.economy(of: civ, in: state).grainBalance < growthReserve(civ, state),
              let fleet = state.fleets(of: civ).filter({ $0.cargo.isEmpty && $0.movedShips == 0 })
                .max(by: { ($0.ships, $1.sea) < ($1.ships, $0.sea) }) else { return }
        _ = attempt(.disbandShips(sea: fleet.sea, ships: 1), &state, &turn)
    }

    func shelterFleets(_ civ: CivilizationID, _ state: inout GameState, _ turn: inout AITurn) {
        for sea in state.fleets(of: civ).map(\.sea).sorted() where !engine.sheltered(sea, for: civ, in: state) {
            guard let fleet = state.fleet(of: civ, in: sea), fleet.movedShips == 0, fleet.cargo.isEmpty else { continue }
            let haven = engine.fleetPaths(from: sea, for: civ, in: state)
                .filter { s, _ in engine.sheltered(s, for: civ, in: state)
                    && !state.fleets.contains { $0.sea == s && state.atWar(civ, $0.owner) } }
                .min { ($0.value.count, $0.key) < ($1.value.count, $1.key) }
            if let haven { issue(.moveFleet(from: sea, to: haven.key, ships: fleet.ships), &state, &turn) }
        }
    }

    /// Seas next to home coasts where troops beyond their garrisons are ready to board.
    private func portSeas(_ civ: CivilizationID, _ state: GameState) -> Set<SeaZoneID> {
        var seas: Set<SeaZoneID> = []
        for t in engine.homeNetwork(of: civ, in: state) where state.armies[t]?.owner == civ {
            let spare = min(readyUnits(at: t, state).total, state.armies[t]!.units.total - garrison(t, for: civ, state) - 1)
            if spare > 0 { seas.formUnion(map.seas(bordering: t)) }
        }
        return seas
    }

    /// Ready troops beyond their garrisons on the coasts of `sea`.
    private func spareOnCoasts(of sea: SeaZoneID, _ civ: CivilizationID, _ state: GameState) -> Int {
        map.coastalTerritories(of: sea).reduce(0) { total, t in
            guard state.armies[t]?.owner == civ else { return total }
            return total + max(0, min(readyUnits(at: t, state).total, state.armies[t]!.units.total - garrison(t, for: civ, state) - 1))
        }
    }

    /// Boards ready troops beyond their garrisons from coasts on `sea`, up to the force size.
    private func embark(_ civ: CivilizationID, at sea: SeaZoneID, upTo force: Int,
                        _ state: inout GameState, _ turn: inout AITurn) {
        for t in map.coastalTerritories(of: sea).sorted() where state.armies[t]?.owner == civ {
            guard let fleet = state.fleet(of: civ, in: sea) else { return }
            let room = min(fleet.ships * engine.shipCapacity(civ, state) - fleet.cargo.total, force - fleet.cargo.total)
            guard room > 0 else { return }
            let spare = min(readyUnits(at: t, state).total, state.armies[t]!.units.total - garrison(t, for: civ, state) - 1)
            guard spare > 0 else { continue }
            issue(.embark(territory: t, sea: sea, units: take(min(room, spare), from: readyUnits(at: t, state))),
                  &state, &turn)
        }
    }

    /// Lands the fleet's cargo on the target, or any weaker hostile coast of this sea, when the
    /// landing is likely to succeed.
    private func land(_ civ: CivilizationID, from sea: SeaZoneID, _ campaign: SeaCampaign,
                      _ state: inout GameState, _ turn: inout AITurn) -> Bool {
        guard let cargo = state.fleet(of: civ, in: sea)?.cargo, cargo.total > 0 else { return false }
        let coasts = map.coastalTerritories(of: sea).filter { t in
            guard state.owner(of: t) != civ else { return false }
            if let owner = state.owner(of: t), state.atPeace(civ, owner) { return false }
            if engine.shielded(t, from: civ, in: state) || engine.spared(t, state) { return false }
            return (try? engine.checkOmen(civ, attacking: t, state)) != nil
        }
        let ranked = coasts.sorted { a, b in
            if (a == campaign.target) != (b == campaign.target) { return a == campaign.target }
            return a < b
        }
        for t in ranked {
            if engine.defenders(of: t, against: civ, state) != nil {
                guard landingOdds(civ, cargo, sea: sea, to: t, state) >= 0.6 else { continue }
            }
            return issue(.land(sea: sea, territory: t, units: cargo), &state, &turn)
        }
        return false
    }

    private func landingOdds(_ civ: CivilizationID, _ units: UnitCounts, sea: SeaZoneID, to: TerritoryID,
                             _ state: GameState) -> Double {
        let sim = BattleSimulator(rules: rules)
        let wins = seeds(state, "land" + sea + to).filter { seed in
            sim.resolve(BattleSetup(
                attacker: engine.battleArmy(civ, units, formation: nil, general: nil, state),
                defender: engine.defendingArmy(of: to, against: civ, state)!,
                terrain: map.territory(to)!.terrain, approach: .amphibious, seed: seed,
                fortification: engine.fortification(at: to, state))).winner == .attacker
        }.count
        return Double(wins) / Double(samples)
    }
}
