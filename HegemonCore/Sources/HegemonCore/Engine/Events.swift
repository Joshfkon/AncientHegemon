/// Random events, drawn at the start of a civilization's turn (DESIGN §8).
///
/// Weights follow geography and state, so a region's strengths carry their own risks:
/// river-valley breadbaskets get the best harvests and the worst famines and floods; trade hubs
/// get rich and get plague; empires on the steppe and forest frontier meet the migrations;
/// sprawling realms see distant provinces revolt; shaky rulers see bad omens.
extension Engine {
    func drawEvents(_ civ: CivilizationID, _ state: inout GameState) -> [GameEvent] {
        var events: [GameEvent] = []
        if state.civs[civ]!.plagueIncoming {
            state.civs[civ]!.plagueIncoming = false
            events += plague(civ, spreads: false, &state)
        }
        guard Int(state.rng.next() % 100) < rules.events.chancePercent else { return events }

        let weights = eventWeights(civ, state)
        let total = weights.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return events }
        var pick = Int(state.rng.next() % UInt64(total))
        for (kind, weight) in weights {
            if pick < weight { return events + strike(kind, civ, &state) }
            pick -= weight
        }
        return events
    }

    // MARK: Weights

    private func riverValleys(_ civ: CivilizationID, _ state: GameState) -> [TerritoryID] {
        state.territories(of: civ).filter { map.territory($0)!.has(.riverValley) }
    }

    /// Owned territories in or next to barbarian homelands the civ doesn't hold.
    private func barbarianFronts(_ civ: CivilizationID, _ state: GameState) -> [(homeland: TerritoryID, target: TerritoryID)] {
        var fronts: [(TerritoryID, TerritoryID)] = []
        for t in state.territories(of: civ) {
            if map.territory(t)!.has(.barbarianHomeland) { fronts.append((t, t)) }
            for n in map.landNeighbors(of: t) where map.territory(n)!.has(.barbarianHomeland)
                && state.owner(of: n) == nil {
                fronts.append((n, t))
            }
        }
        return fronts.sorted { ($0.0, $0.1) < ($1.0, $1.1) }
    }

    /// Territories far from the seat along supply routes, or cut off entirely.
    private func distantTerritories(_ civ: CivilizationID, _ state: GameState) -> [TerritoryID] {
        let steps = supplyDistances(of: civ, in: state)
        return state.territories(of: civ).filter { (steps[$0] ?? .max) >= rules.events.revoltDistance }
    }

    func eventWeights(_ civ: CivilizationID, _ state: GameState) -> [(EventKind, Int)] {
        let w = rules.events.weights
        let owned = state.territories(of: civ)
        let river = !riverValleys(civ, state).isEmpty
        let population = owned.reduce(0) { $0 + state.population(of: $1) }
        let cap = owned.reduce(0) { $0 + populationCap(of: $1) }
        let crowded = population * 10 >= cap * 9
        let routes = tradeRoutes(in: state).filter { $0.involves(civ) }.count
        let rugged = owned.filter { [.hills, .mountains].contains(map.territory($0)!.terrain) }.count
        let legitimacy = state.civs[civ]!.legitimacy
        return [
            (.famine, w.famine + (river ? w.famineRiverValley : 0) + (crowded ? w.faminePressure : 0)),
            (.flood, river ? w.flood : 0),
            (.goodHarvest, w.goodHarvest + (river ? w.goodHarvestRiverValley : 0)),
            (.plague, w.plague + routes * w.plaguePerRoute),
            (.goldDiscovered, w.goldDiscovered + rugged * w.goldPerHill),
            (.badOmen, max(0, 50 - legitimacy) * w.omenPerLegitimacyPoint),
            (.barbarians, barbarianFronts(civ, state).count * w.barbariansPerExposure),
            (.revolt, distantTerritories(civ, state).count * w.revoltPerDistantTerritory),
        ]
    }

    // MARK: Effects

    private func strike(_ kind: EventKind, _ civ: CivilizationID, _ state: inout GameState) -> [GameEvent] {
        let e = rules.events
        let owned = state.territories(of: civ)
        func report(_ t: TerritoryID?, _ amount: Int) -> GameEvent {
            .event(EventReport(kind: kind, civ: civ, territory: t, amount: amount))
        }
        let richest = { (ts: [TerritoryID]) in
            ts.max { (map.territory($0)!.grain, $1) < (map.territory($1)!.grain, $0) }
        }

        switch kind {
        case .famine:
            // Breadbaskets first; otherwise the most crowded land.
            let target = richest(riverValleys(civ, state)) ?? owned.max { a, b in
                let pa = state.population(of: a) * map.territory(b)!.grain
                let pb = state.population(of: b) * map.territory(a)!.grain
                return pa != pb ? pa < pb : a > b
            }
            guard let target else { return [] }
            state.harvestPercent[target] = e.famineGrainPercent
            return [report(target, e.famineGrainPercent)]

        case .goodHarvest:
            guard let target = richest(riverValleys(civ, state)) ?? richest(owned) else { return [] }
            state.harvestPercent[target] = e.goodHarvestGrainPercent
            return [report(target, e.goodHarvestGrainPercent)]

        case .flood:
            guard let target = richest(riverValleys(civ, state)) else { return [] }
            let lost = min(e.floodPopulation, state.population(of: target) - rules.economy.minPopulation)
            state.land[target]!.population -= max(0, lost)
            return [report(target, max(0, lost))]

        case .plague:
            return plague(civ, spreads: true, &state)

        case .goldDiscovered:
            let rugged = owned.filter { [.hills, .mountains].contains(map.territory($0)!.terrain) }
            let pool = rugged.isEmpty ? owned : rugged
            guard !pool.isEmpty else { return [] }
            let target = pool[Int(state.rng.next() % UInt64(pool.count))]
            state.bonusGold[target, default: 0] += 1
            return [report(target, 1)]

        case .badOmen:
            state.civs[civ]!.omen = true
            return [report(nil, 0)]

        case .barbarians:
            let fronts = barbarianFronts(civ, state)
            guard !fronts.isEmpty else { return [] }
            let (homeland, target) = fronts[Int(state.rng.next() % UInt64(fronts.count))]
            let size = e.barbarianBase + state.turn / max(1, e.barbarianTurnsPerExtra)
            let horde = UnitCounts(infantry: size - size / 2, cavalry: size / 2)
            var events = [report(target, size)]
            if homeland != target {
                // The horde gathers in its homeland, sweeping up the local tribes, then strikes.
                if let local = state.armies[homeland], local.owner == nativesID || local.owner == barbariansID {
                    state.armies[homeland]!.owner = barbariansID
                } else if state.armies[homeland] == nil {
                    state.armies[homeland] = Army(owner: barbariansID, units: .zero)
                }
            }
            events += raid(barbariansID, horde, into: target,
                           fallback: homeland == target ? nil : homeland, &state)
            if state.armies[homeland]?.units.isEmpty == true { state.armies[homeland] = nil }
            return events

        case .revolt:
            let steps = supplyDistances(of: civ, in: state)
            let seat = seat(of: civ, in: state)
            guard let target = distantTerritories(civ, state).filter({ $0 != seat })
                .max(by: { ((steps[$0] ?? .max), $1) < ((steps[$1] ?? .max), $0) }) else { return [] }
            let rebels = UnitCounts(infantry: rules.start.natives.base
                                    + map.territory(target)!.grain / max(1, rules.start.natives.grainPerUnit))
            return [report(target, rebels.total)] + raid(nativesID, rebels, into: target, fallback: nil, &state)
        }
    }

    /// Plague strikes the most populous home territories and may kill the ruler. Unless it is
    /// itself an arrival, it travels along trade routes to every partner.
    func plague(_ civ: CivilizationID, spreads: Bool, _ state: inout GameState) -> [GameEvent] {
        let e = rules.events
        let home = homeNetwork(of: civ, in: state)
        let worst = home.sorted { (state.population(of: $0), $1) > (state.population(of: $1), $0) }
            .prefix(e.plagueTerritories)
        var lost = 0
        for t in worst {
            let n = min(max(1, state.population(of: t) * e.plaguePopulationPercent / 100),
                        state.population(of: t) - rules.economy.minPopulation)
            state.land[t]!.population -= max(0, n)
            lost += max(0, n)
        }
        var events: [GameEvent] = [.event(EventReport(kind: .plague, civ: civ, territory: worst.first, amount: lost))]
        if Int(state.rng.next() % 100) < e.plagueRulerDeathPercent {
            events += rulerDies(civ, cause: .plague, &state)
        }
        if spreads {
            for route in tradeRoutes(in: state) where route.involves(civ)
                && Int(state.rng.next() % 100) < e.plagueSpreadPercent {
                state.civs[route.partner(of: civ)]!.plagueIncoming = true
            }
        }
        return events
    }

    /// A non-player force (barbarians, rebels) attacks a territory. If it wins, it holds the land,
    /// which becomes unowned; if it loses, its survivors fall back to `fallback`, if any.
    func raid(_ raider: CivilizationID, _ units: UnitCounts, into t: TerritoryID, fallback: TerritoryID?,
              _ state: inout GameState) -> [GameEvent] {
        var events: [GameEvent] = []
        var units = units
        let victim = state.owner(of: t)
        if let army = state.armies[t], army.owner != raider {
            let result = fight(raider, units, general: nil, formation: nil, at: t, approach: .overland, &state)
            events += result.events
            units = result.survivors
            guard result.won else {
                if let fallback, !units.isEmpty, state.armies[fallback]?.owner == raider {
                    state.armies[fallback]!.units += units
                }
                return events
            }
        }
        if !units.isEmpty {
            state.armies[t, default: Army(owner: raider, units: .zero)].units += units
        }
        for g in state.generals.values.sorted(by: { $0.id < $1.id }) where g.location == t {
            state.generals[g.id]!.location = nil
            events.append(.generalKilled(g.id))
        }
        state.land[t]!.owner = nil
        state.land[t]!.construction = nil
        events.append(.captured(civ: raider, territory: t, from: victim))
        if let victim {
            if map.civilization(victim)?.capital == t {
                adjustLegitimacy(victim, rules.government.legitimacy.capitalLost, &state)
            }
            events += checkElimination(victim, &state)
        }
        return events
    }
}
