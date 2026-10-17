/// Harvest & upkeep, run at the start of each civilization's turn (DESIGN §3, step 2).
///
/// Grain is pooled across the whole empire. Build step 3 restricts the pool to territories
/// connected by supply routes.
extension Engine {
    func harvest(_ civ: CivilizationID, _ state: inout GameState) -> [GameEvent] {
        let econ = rules.economy
        let owned = state.territories(of: civ)
        let production = yield(of: .grain, for: civ, in: state)
        let consumption = grainConsumption(of: civ, in: state)
        var granary = state.civs[civ]!.granary
        var grown = 0
        var events: [GameEvent] = []

        if production >= consumption {
            // Surplus feeds growth first, emptiest-relative-to-land first; the rest is stored.
            // Each new person costs a full grain to raise.
            var surplus = production - consumption
            let candidates = owned
                .filter { state.population(of: $0) < populationCap(of: $0) }
                .sorted { a, b in
                    let pa = state.population(of: a) * map.territory(b)!.grain
                    let pb = state.population(of: b) * map.territory(a)!.grain
                    return pa != pb ? pa < pb : a < b
                }
            for id in candidates where surplus > 0 {
                let room = populationCap(of: id) - state.population(of: id)
                let n = min(econ.growthPerTerritory, room, surplus)
                state.land[id]!.population += n
                surplus -= n
                grown += n
            }
            granary = min(granary + surplus, production * econ.granaryCapTurns)
        } else {
            let available = production + granary
            let (popLost, unitsLost) = starve(civ, toFit: available, owned, &state)
            granary = max(0, available - grainConsumption(of: civ, in: state))
            if popLost + unitsLost > 0 {
                events.append(.starvation(civ: civ, populationLost: popLost, unitsLost: unitsLost))
            }
        }
        state.civs[civ]!.granary = granary

        let income = state.totalPopulation(of: civ) / econ.populationPerGold
            + yield(of: .gold, for: civ, in: state)
        state.civs[civ]!.gold += income

        events.insert(.harvest(civ: civ, production: production, consumption: consumption,
                               grown: grown, granary: granary, income: income), at: 0)
        return events
    }

    func populationCap(of territory: TerritoryID) -> Int {
        rules.populationCap(grain: map.territory(territory)!.grain)
    }

    /// Grain eaten per turn by a civilization's population and armies.
    public func grainConsumption(of civ: CivilizationID, in state: GameState) -> Int {
        rules.grainEaten(byPopulation: state.totalPopulation(of: civ))
            + rules.upkeep(of: state.totalUnits(of: civ))
    }

    /// Removes mouths until consumption fits in `available` grain: population first, from the
    /// territories most over their local grain; then army units desert, from the largest stack.
    private func starve(_ civ: CivilizationID, toFit available: Int, _ owned: [TerritoryID],
                        _ state: inout GameState) -> (population: Int, units: Int) {
        let floor = rules.economy.minPopulation
        var popLost = 0
        var unitsLost = 0

        while grainConsumption(of: civ, in: state) > available {
            let victim = owned
                .filter { state.population(of: $0) > floor }
                .max { a, b in
                    let oa = state.population(of: a) - map.territory(a)!.grain
                    let ob = state.population(of: b) - map.territory(b)!.grain
                    return oa != ob ? oa < ob : a > b
                }
            if let victim {
                state.land[victim]!.population -= 1
                popLost += 1
                continue
            }
            let stacks = state.armies(of: civ)
            guard let stack = stacks.max(by: { a, b in
                a.units.total != b.units.total ? a.units.total < b.units.total : a.territory > b.territory
            }) else { break }
            let type = UnitType.allCases.max { stack.units[$0] < stack.units[$1] }!
            state.armies[stack.territory]!.units[type] -= 1
            if state.armies[stack.territory]!.units.isEmpty { state.armies[stack.territory] = nil }
            unitsLost += 1
        }
        return (popLost, unitsLost)
    }
}
