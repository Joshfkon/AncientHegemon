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
    private var capacity: Int { rules.ships.capacity }

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

        var best: (SeaCampaign, Double)?
        for t in map.territories where t.isCoastal && !owned.contains(t.id) {
            if let owner = state.owner(of: t.id), state.atPeace(civ, owner) { continue }
            // Coasts next to our own land are the army's job.
            if map.landNeighbors(of: t.id).contains(where: owned.contains) { continue }
            let landing = Set(t.seas)
            let dist = seaDistances(to: landing, ships: 1, civ, state)
            guard let steps = ports.compactMap({ dist[$0] }).min() else { continue }
            let defenders = state.armies[t.id].map { $0.owner == civ ? 0 : $0.units.total } ?? 0
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
        let want = (campaign.force + capacity - 1) / capacity
        guard have < want else { return }
        let dist = seaDistances(to: campaign.landingSeas, ships: want, civ, state)
        let yards = engine.homeNetwork(of: civ, in: state).flatMap { t in
            map.seas(bordering: t).compactMap { s in dist[s].map { (t, s, $0) } }
        }.filter { !engine.blockaded($0.1, for: [civ], in: state) }
        guard let (yard, sea, _) = yards.min(by: { ($0.2, $0.0, $0.1) < ($1.2, $1.0, $1.1) }) else { return }
        // Keep enough gold for at least one recruit.
        let spare = state.civs[civ]!.gold - rules.stats(.infantry).cost
        let count = min(want - have, spare / rules.ships.cost)
        if count > 0 {
            _ = attempt(.buildShips(territory: yard, sea: sea, count: count), &state, &turn)
        }
    }

    /// Loads spare troops, sails toward the campaign target and lands when the odds are good.
    func sail(_ civ: CivilizationID, toward campaign: SeaCampaign, _ state: inout GameState, _ turn: inout AITurn) {
        for sea in state.fleets(of: civ).map(\.sea) {
            embark(civ, at: sea, upTo: campaign.force, &state, &turn)
            if land(civ, from: sea, campaign, &state, &turn) { continue }
            guard let fleet = state.fleet(of: civ, in: sea), fleet.cargo.total > 0 || fleet.ships > 0 else { continue }
            let ready = fleet.ships - fleet.movedShips
            guard ready > 0, fleet.cargo.total <= ready * capacity else { continue }
            let dist = seaDistances(to: campaign.landingSeas, ships: ready, civ, state)
            guard let here = dist[sea], here > 0,
                  let next = map.seaNeighbors(of: sea).filter({ dist[$0] == here - 1 }).min() else { continue }
            guard issue(.moveFleet(from: sea, to: next, ships: ready, cargo: fleet.cargo), &state, &turn) else { continue }
            if state.fleet(of: civ, in: next) != nil { _ = land(civ, from: next, campaign, &state, &turn) }
        }
    }

    /// Boards ready troops beyond their garrisons from coasts on `sea`, up to the force size.
    private func embark(_ civ: CivilizationID, at sea: SeaZoneID, upTo force: Int,
                        _ state: inout GameState, _ turn: inout AITurn) {
        for t in map.coastalTerritories(of: sea).sorted() where state.armies[t]?.owner == civ {
            guard let fleet = state.fleet(of: civ, in: sea) else { return }
            let room = min(fleet.ships * capacity - fleet.cargo.total, force - fleet.cargo.total)
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
            return (try? engine.checkOmen(civ, attacking: t, state)) != nil
        }
        let ranked = coasts.sorted { a, b in
            if (a == campaign.target) != (b == campaign.target) { return a == campaign.target }
            return a < b
        }
        for t in ranked {
            if let defender = state.armies[t], defender.owner != civ {
                guard landingOdds(civ, cargo, sea: sea, to: t, state) >= 0.6 else { continue }
            }
            return issue(.land(sea: sea, territory: t, units: cargo), &state, &turn)
        }
        return false
    }

    private func landingOdds(_ civ: CivilizationID, _ units: UnitCounts, sea: SeaZoneID, to: TerritoryID,
                             _ state: GameState) -> Double {
        let defender = state.armies[to]!
        let sim = BattleSimulator(rules: rules)
        let wins = seeds(state, "land" + sea + to).filter { seed in
            sim.resolve(BattleSetup(
                attacker: BattleArmy(civ: civ, units: units, formation: rules.battle.defaultFormation,
                                     bronzePercent: engine.bronzePercent(civ, state)),
                defender: BattleArmy(civ: defender.owner, units: defender.units,
                                     formation: defender.formation ?? rules.battle.defaultFormation,
                                     general: state.general(of: defender.owner, at: to),
                                     bronzePercent: engine.bronzePercent(defender.owner, state)),
                terrain: map.territory(to)!.terrain, approach: .amphibious, seed: seed)).winner == .attacker
        }.count
        return Double(wins) / Double(samples)
    }
}
