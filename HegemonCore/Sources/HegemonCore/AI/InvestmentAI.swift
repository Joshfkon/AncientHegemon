/// The AI's side of the economy: tax policy and projects.
extension AIPlayer {
    /// Sets the tax rate: lower when legitimacy sags or gold piles up, higher when broke at war.
    /// Gold the treasury can't spend is better left with the people, as legitimacy.
    func setTaxes(_ civ: CivilizationID, _ state: inout GameState, _ turn: inout AITurn) {
        let cs = state.civs[civ]!
        let atWar = state.players.contains { $0 != civ && !state.civs[$0]!.eliminated && state.atWar(civ, $0)
            && borders(civ, $0, state) }
        let base = rules.economy.defaultTax
        let reserve = investmentReserve(civ, state)
        let rate: Int
        if cs.gold > 6 * reserve + 60 { rate = 0 }
        else if cs.legitimacy < 35 || cs.gold > 3 * reserve + 30 { rate = base - 20 }
        else if cs.gold > reserve + 30 { rate = base - 10 }
        else if cs.gold < 10, atWar { rate = base + 20 }
        else { rate = base }
        if rate != cs.taxRate { issue(.setTaxRate(rate), &state, &turn) }
    }

    /// Gold the AI keeps back from projects: enough to raise a few troops in an emergency,
    /// more for a bigger realm.
    func investmentReserve(_ civ: CivilizationID, _ state: GameState) -> Int {
        4 * rules.stats(.infantry).cost + state.territories(of: civ).count
    }

    /// Spends gold above the reserve on projects, most needed first, several a turn if it can.
    func invest(_ civ: CivilizationID, _ state: inout GameState, _ turn: inout AITurn) {
        let reserve = investmentReserve(civ, state)
        for _ in 0..<maxProjectsPerTurn {
            guard let (kind, territory) = nextProject(civ, state),
                  state.civs[civ]!.gold - engine.projectCost(kind, for: civ, state).gold >= reserve,
                  attempt(.build(territory: territory, project: kind), &state, &turn) else { return }
        }
    }

    var maxProjectsPerTurn: Int { 4 }

    /// The most needed project the civ can start now (gold aside), or nil.
    func nextProject(_ civ: CivilizationID, _ state: GameState) -> (ProjectKind, TerritoryID)? {
        let home = engine.homeNetwork(of: civ, in: state)
        let econ = engine.economy(of: civ, in: state)
        let cs = state.civs[civ]!
        func affordable(_ kind: ProjectKind) -> Bool {
            let cost = engine.projectCost(kind, for: civ, state)
            return (cs.stock[.stone] ?? 0) >= cost.stone && (cs.stock[.timber] ?? 0) >= cost.timber
        }
        func cheapest(_ kind: ProjectKind, _ candidates: [TerritoryID]) -> TerritoryID? {
            guard affordable(kind) else { return nil }
            return candidates.first { engine.canBuild(kind, in: $0, state) }
        }
        func walled(_ t: TerritoryID) -> Bool { state.land[t]?.improvements.contains(.walls) ?? false }
        var plan: [(ProjectKind, TerritoryID?)] = []
        // Food first: a farm on the richest land.
        if econ.grainBalance < 2 {
            plan.append((.farm, cheapest(.farm, home.sorted { (map.territory($0)!.grain, $1) > (map.territory($1)!.grain, $0) })))
        }
        // A threatened capital gets walls.
        if let capital = engine.seat(of: civ, in: state), threat(to: capital, for: civ, state) > 0 {
            plan.append((.walls, cheapest(.walls, [capital])))
        }
        // Then the border posts facing the most enemy troops, where a garrison stands to use them.
        let threatened = home.filter { !walled($0) && state.armies[$0]?.owner == civ && threat(to: $0, for: civ, state) > 0 }
            .sorted { (threat(to: $0, for: civ, state), $1) > (threat(to: $1, for: civ, state), $0) }
        plan.append((.walls, cheapest(.walls, threatened)))
        // As the collapse deepens, wall the richest coast against raiders from the sea.
        if engine.collapsePressure(state) >= 25 {
            let coasts = home.filter { map.territory($0)!.isCoastal && !walled($0) }
                .sorted { (state.population(of: $0), $1) > (state.population(of: $1), $0) }
            plan.append((.walls, cheapest(.walls, Array(coasts.prefix(1)))))
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

        for case let (kind, territory?) in plan { return (kind, territory) }
        return nil
    }
}
