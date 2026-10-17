/// Harvest & upkeep, run at the start of each civilization's turn (DESIGN §3, step 2).
///
/// Each supply pocket feeds itself from its own grain. The home pocket (around the seat) holds
/// the granary, pays taxes and makes bronze; cut-off pockets have none of that, and their armies
/// suffer attrition.
extension Engine {
    func harvest(_ civ: CivilizationID, _ state: inout GameState) -> [GameEvent] {
        let pockets = supplyPockets(of: civ, in: state)
        var events: [GameEvent] = []
        var home: (production: Int, consumption: Int, grown: Int) = (0, 0, 0)
        var popLost = 0
        var unitsLost = 0

        for (i, pocket) in pockets.enumerated() {
            let isHome = i == 0
            let production = yield(of: .grain, in: pocket)
            // Ships' crews and the troops they carry are fed from home.
            let atSea = isHome ? fleetUpkeep(of: civ, state) : 0
            let consumption = grainConsumption(of: civ, in: pocket, state) + atSea
            var granary = isHome ? state.civs[civ]!.granary : 0
            var grown = 0

            if production >= consumption {
                grown = grow(pocket, surplus: production - consumption, &state)
                granary = min(granary + production - consumption - grown,
                              production * rules.economy.granaryCapTurns)
            } else {
                let available = production + granary - atSea
                let lost = starve(civ, pocket, toFit: available, &state)
                popLost += lost.population
                unitsLost += lost.units
                granary = max(0, available - grainConsumption(of: civ, in: pocket, state))
            }
            if isHome {
                state.civs[civ]!.granary = granary
                home = (production, consumption, grown)
            }
        }
        if popLost + unitsLost > 0 {
            events.append(.starvation(civ: civ, populationLost: popLost, unitsLost: unitsLost))
        }
        events += attrition(civ, outside: Set(pockets.first ?? []), &state)

        // Income, trade and bronze come from the home network only.
        let homeNet = pockets.first ?? []
        let routes = tradeRoutes(in: state)
        let tradeIncome = tradeGold(for: civ, routes)
        let taxes = homeNet.reduce(0) { $0 + state.population(of: $1) } / rules.economy.populationPerGold
        let income = taxes + yield(of: .gold, in: homeNet) + tradeIncome
        state.civs[civ]!.gold += income

        let bronze = min(effectiveYield(of: .copper, for: civ, in: state, routes: routes),
                         effectiveYield(of: .tin, for: civ, in: state, routes: routes))
        state.civs[civ]!.bronze += bronze

        events.insert(.harvest(civ: civ, production: home.production, consumption: home.consumption,
                               grown: home.grown, granary: state.civs[civ]!.granary, income: income),
                      at: 0)
        let civRoutes = routes.filter { $0.involves(civ) }
        if !civRoutes.isEmpty || tradeIncome != 0 {
            events.append(.trade(civ: civ, partners: civRoutes.map { $0.partner(of: civ) }, income: tradeIncome))
        }
        if bronze > 0 { events.append(.bronzeMade(civ: civ, amount: bronze)) }
        return events
    }

    func populationCap(of territory: TerritoryID) -> Int {
        rules.populationCap(grain: map.territory(territory)!.grain)
    }

    /// Grain eaten per turn by the population of `territories` and the civilization's armies in them.
    public func grainConsumption(of civ: CivilizationID, in territories: [TerritoryID],
                                 _ state: GameState) -> Int {
        let set = Set(territories)
        let population = territories.reduce(0) { $0 + state.population(of: $1) }
        let units = state.armies(of: civ).filter { set.contains($0.territory) }.reduce(.zero) { $0 + $1.units }
        return rules.grainEaten(byPopulation: population) + rules.upkeep(of: units)
    }

    func fleetUpkeep(of civ: CivilizationID, _ state: GameState) -> Int {
        state.fleets(of: civ).reduce(0) { $0 + $1.ships * rules.ships.upkeep + rules.upkeep(of: $1.cargo) }
    }

    /// Gold a civilization earns from trade: its own routes net of tolls, plus tolls it collects
    /// as a chokepoint holder on other civilizations' routes.
    func tradeGold(for civ: CivilizationID, _ routes: [TradeRoute]) -> Int {
        let toll = rules.trade.chokepointToll
        var gold = 0
        for route in routes {
            if route.involves(civ) {
                gold += max(0, rules.trade.goldPerRoute - toll * route.tolls.count)
            }
            // Each side of the route pays every third-party holder.
            gold += route.tolls.filter { $0 == civ }.count * toll * 2
        }
        return gold
    }

    /// Surplus feeds growth, emptiest-relative-to-land first. Each new person costs a full grain.
    private func grow(_ pocket: [TerritoryID], surplus: Int, _ state: inout GameState) -> Int {
        var surplus = surplus
        var grown = 0
        let candidates = pocket
            .filter { state.population(of: $0) < populationCap(of: $0) }
            .sorted { a, b in
                let pa = state.population(of: a) * map.territory(b)!.grain
                let pb = state.population(of: b) * map.territory(a)!.grain
                return pa != pb ? pa < pb : a < b
            }
        for id in candidates where surplus > 0 {
            let room = populationCap(of: id) - state.population(of: id)
            let n = min(rules.economy.growthPerTerritory, room, surplus)
            state.land[id]!.population += n
            surplus -= n
            grown += n
        }
        return grown
    }

    /// Removes mouths until consumption fits in `available` grain: population first, from the
    /// territories most over their local grain; then army units desert, from the largest stack.
    private func starve(_ civ: CivilizationID, _ pocket: [TerritoryID], toFit available: Int,
                        _ state: inout GameState) -> (population: Int, units: Int) {
        let floor = rules.economy.minPopulation
        let set = Set(pocket)
        var popLost = 0
        var unitsLost = 0

        while grainConsumption(of: civ, in: pocket, state) > available {
            let victim = pocket
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
            let stacks = state.armies(of: civ).filter { set.contains($0.territory) }
            guard let stack = stacks.max(by: { a, b in
                a.units.total != b.units.total ? a.units.total < b.units.total : a.territory > b.territory
            }) else { break }
            removeUnits(1, from: stack.territory, &state)
            unitsLost += 1
        }
        return (popLost, unitsLost)
    }

    /// Armies outside the home network are out of supply and lose units every turn.
    private func attrition(_ civ: CivilizationID, outside home: Set<TerritoryID>,
                           _ state: inout GameState) -> [GameEvent] {
        var events: [GameEvent] = []
        for (territory, units) in state.armies(of: civ) where !home.contains(territory) {
            var loss = rules.supply.outOfSupplyAttrition
            if map.territory(territory)!.terrain == .desert { loss += rules.supply.desertAttrition }
            loss = min(loss, units.total)
            guard loss > 0 else { continue }
            removeUnits(loss, from: territory, &state)
            events.append(.outOfSupply(civ: civ, territory: territory, unitsLost: loss))
        }
        return events
    }

    /// Removes units from a stack, most numerous type first.
    private func removeUnits(_ count: Int, from territory: TerritoryID, _ state: inout GameState) {
        for _ in 0..<count {
            guard let units = state.armies[territory]?.units, !units.isEmpty else { return }
            let type = UnitType.allCases.max { units[$0] < units[$1] }!
            state.armies[territory]!.units[type] -= 1
            if state.armies[territory]!.units.isEmpty { state.armies[territory] = nil }
        }
    }
}
