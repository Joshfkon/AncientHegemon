/// The AI's side of the economy: tax policy and projects.
extension AIPlayer {
    /// Sets the tax rate: lower when legitimacy sags or gold piles up, higher when broke at war.
    func setTaxes(_ civ: CivilizationID, _ state: inout GameState, _ turn: inout AITurn) {
        let cs = state.civs[civ]!
        let atWar = state.players.contains { $0 != civ && !state.civs[$0]!.eliminated && state.atWar(civ, $0)
            && borders(civ, $0, state) }
        let base = rules.economy.defaultTax
        let rate: Int
        if cs.legitimacy < 35 { rate = base - 20 }
        else if cs.gold > 60 { rate = base - 10 }
        else if cs.gold < 10, atWar { rate = base + 20 }
        else { rate = base }
        if rate != cs.taxRate { issue(.setTaxRate(rate), &state, &turn) }
    }

    /// Starts at most one project a turn with spare gold, by what the empire needs most.
    func invest(_ civ: CivilizationID, _ state: inout GameState, _ turn: inout AITurn) {
        let reserve = 2 * rules.stats(.infantry).cost + 4
        guard state.civs[civ]!.gold > reserve else { return }
        let home = engine.homeNetwork(of: civ, in: state)
        let econ = engine.economy(of: civ, in: state)
        func cheapest(_ kind: ProjectKind, _ candidates: [TerritoryID]) -> TerritoryID? {
            candidates.first { engine.canBuild(kind, in: $0, state) }
        }
        var plan: [(ProjectKind, TerritoryID?)] = []
        // Food first: a farm on the richest land.
        if econ.grainBalance < 2 {
            plan.append((.farm, cheapest(.farm, home.sorted { (map.territory($0)!.grain, $1) > (map.territory($1)!.grain, $0) })))
        }
        // A threatened capital gets walls.
        if let capital = engine.seat(of: civ, in: state), threat(to: capital, for: civ, state) > 0 {
            plan.append((.walls, cheapest(.walls, [capital])))
        }
        // Mines on scarce ore: tin and copper make bronze; iron and gold pay.
        let ore: [Resource] = [.tin, .copper, .iron, .gold, .stone]
        plan.append((.mine, cheapest(.mine, home.sorted { a, b in
            let va = ore.reduce(0) { $0 + (map.territory(a)!.resources[$1] ?? 0) }
            let vb = ore.reduce(0) { $0 + (map.territory(b)!.resources[$1] ?? 0) }
            return (va, b) > (vb, a)
        })))
        // Roads where the most troops sit at the end of long supply lines.
        let strained = state.armies(of: civ).filter { (engine.supplyStrain(of: civ, at: $0.territory, in: state)?.extraGrain ?? 0) > 0 }
            .sorted { ($0.units.total, $1.territory) > ($1.units.total, $0.territory) }
        if let route = strained.first.flatMap({ engine.supplyRoute(of: civ, to: $0.territory, in: state) }) {
            let stops = route.compactMap { node -> TerritoryID? in if case .land(let t) = node { t } else { nil } }
            plan.append((.road, cheapest(.road, Array(stops.dropFirst()))))
        }
        // Harbors once there's trade to handle.
        if !econ.tradePartners.isEmpty {
            plan.append((.harbor, cheapest(.harbor, home.filter { map.territory($0)!.isCoastal })))
        }
        // Then more farms, to grow.
        plan.append((.farm, cheapest(.farm, home.sorted { (map.territory($0)!.grain, $1) > (map.territory($1)!.grain, $0) })))

        for case let (kind, territory?) in plan {
            if attempt(.build(territory: territory, project: kind), &state, &turn) { return }
        }
    }
}
