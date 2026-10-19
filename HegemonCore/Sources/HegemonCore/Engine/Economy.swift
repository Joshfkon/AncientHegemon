/// Harvest & upkeep, run at the start of each civilization's turn (DESIGN §3, step 2).
///
/// Each supply pocket feeds itself from its own grain. The home pocket (around the seat) holds
/// the granary, pays taxes and makes bronze; cut-off pockets have none of that, and their armies
/// suffer attrition.
extension Engine {
    func harvest(_ civ: CivilizationID, _ state: inout GameState) -> [GameEvent] {
        let pockets = supplyPockets(of: civ, in: state)
        let importCap = grainImportCap(of: civ, in: state)
        var events: [GameEvent] = []
        var home: (production: Int, consumption: Int, grown: Int) = (0, 0, 0)
        var popLost = 0
        var unitsLost = 0

        for (i, pocket) in pockets.enumerated() {
            let isHome = i == 0
            let production = pocket.reduce(0) { total, t in
                total + territoryYield(.grain, t, state) * (state.harvestPercent[t] ?? 100) / 100
            }
            // Ships' crews and the troops they carry are fed from home.
            let atSea = isHome ? fleetUpkeep(of: civ, state) : 0
            let consumption = grainConsumption(of: civ, in: pocket, state) + atSea
            var granary = isHome ? state.civs[civ]!.granary : 0
            var grown = 0

            if production >= consumption {
                // High taxes leave less for families to grow on.
                let forGrowth = (production - consumption) * growthPercent(civ, state) / 100
                grown = grow(pocket, surplus: forGrowth, &state)
                granary = min(granary + production - consumption - grown,
                              granaryCap(civ, production: production, state))
            } else {
                var available = production + granary - atSea
                if isHome {
                    // The granary is drawn first; then grain is bought abroad, as far as gold allows.
                    let short = grainConsumption(of: civ, in: pocket, state) - available
                    let price = max(1, rules.trade.grainPrice)
                    let bought = min(short, importCap, state.civs[civ]!.gold / price)
                    if bought > 0 {
                        state.civs[civ]!.gold -= bought * price
                        available += bought
                        events.append(.grainImported(civ: civ, grain: bought, gold: bought * price))
                    }
                }
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
        for t in state.territories(of: civ) { state.harvestPercent[t] = nil }
        if popLost + unitsLost > 0 {
            events.append(.starvation(civ: civ, populationLost: popLost, unitsLost: unitsLost))
            adjustLegitimacy(civ, rules.government.legitimacy.starvation, &state)
        }
        events += attrition(civ, outside: Set(pockets.first ?? []), &state)

        // Income, trade and bronze come from the home network only.
        let homeNet = pockets.first ?? []
        let routes = tradeRoutes(in: state)
        stockpile(civ, routes, &state)
        events += progressConstruction(civ, &state)
        events += progressMonuments(civ, &state)
        let gold = income(of: civ, homeNet, routes, state)
        let tradeIncome = gold.trade
        let income = gold.total
        state.civs[civ]!.gold += income
        events += payArmy(civ, &state)

        wearBronze(civ, &state)
        var bronze = min(effectiveYield(of: .copper, for: civ, in: state, routes: routes),
                         effectiveYield(of: .tin, for: civ, in: state, routes: routes))
        if level(.metallurgy, of: civ, in: state) >= 1 {
            bronze = bronze * (100 + rules.knowledge.effects.bronzeCastingPercent) / 100
        }
        state.civs[civ]!.bronze += bronze

        events.insert(.harvest(civ: civ, production: home.production, consumption: home.consumption,
                               grown: home.grown, granary: state.civs[civ]!.granary, income: income),
                      at: 0)
        let civRoutes = routes.filter { $0.involves(civ) }
        if !civRoutes.isEmpty || tradeIncome != 0 {
            events.append(.trade(civ: civ, partners: civRoutes.map { $0.partner(of: civ) }, income: tradeIncome))
        }
        if bronze > 0 { events.append(.bronzeMade(civ: civ, amount: bronze)) }
        events += payPatrons(civ, &state)
        events += learn(civ, production: home.production, bronze: bronze, income: income, routes: routes, &state)
        return events
    }

    /// Gold owed each turn to the civilization's soldiers, on land and aboard ship.
    public func armyPay(of civ: CivilizationID, in state: GameState) -> Int {
        armyPay(soldiers: state.totalUnits(of: civ).total + state.fleets(of: civ).reduce(0) { $0 + $1.cargo.total })
    }

    public func armyPay(soldiers: Int) -> Int {
        soldiers / max(1, rules.economy.soldiersPerGold)
    }

    /// Pays the army from the treasury. What can't be paid sends some of the unpaid home, from
    /// the largest stacks.
    func payArmy(_ civ: CivilizationID, _ state: inout GameState) -> [GameEvent] {
        let owed = armyPay(of: civ, in: state)
        guard owed > 0 else { return [] }
        let paid = min(owed, state.civs[civ]!.gold)
        state.civs[civ]!.gold -= paid
        var deserted = 0
        if paid < owed {
            let unpaid = (owed - paid) * rules.economy.soldiersPerGold
            var leaving = max(1, unpaid * rules.economy.unpaidDesertPercent / 100)
            while leaving > 0, let stack = state.armies(of: civ).max(by: { a, b in
                a.units.total != b.units.total ? a.units.total < b.units.total : a.territory > b.territory
            }) {
                removeUnits(1, from: stack.territory, &state)
                leaving -= 1
                deserted += 1
            }
        }
        return [.armyPaid(civ: civ, gold: paid, deserted: deserted)]
    }

    /// Gold a civilization takes in per turn, by source.
    func income(of civ: CivilizationID, _ homeNet: [TerritoryID], _ routes: [TradeRoute], _ state: GameState)
        -> (taxes: Int, mines: Int, trade: Int, total: Int) {
        let e = rules.economy
        // Restless land pays nothing.
        let population = homeNet.filter { !restless($0, of: civ, in: state) }.reduce(0) { $0 + state.population(of: $1) }
        let coinage = level(.administration, of: civ, in: state) >= 2 ? rules.knowledge.effects.coinagePercent : 0
        let taxes = population * state.civs[civ]!.taxRate * (100 + coinage) / max(1, e.populationPerGold * e.defaultTax * 100)
        let mines = yield(of: .gold, in: homeNet, state) + homeNet.reduce(0) { $0 + (state.bonusGold[$1] ?? 0) }
        let administration = rules.rulerTraits[state.civs[civ]!.ruler.trait]?.incomePercent ?? 0
        let trade = tradeGold(for: civ, routes) + wineGold(civ, homeNet, routes, state)
            + harborGold(civ, homeNet, routes, state)
        return (taxes, mines, trade, (taxes + mines) * (100 + administration) / 100 + trade)
    }

    /// Most grain a civilization can buy from its trade partners this turn.
    public func grainImportCap(of civ: CivilizationID, in state: GameState, routes: [TradeRoute]? = nil) -> Int {
        let coasts = homeNetwork(of: civ, in: state).filter { map.territory($0)!.isCoastal }
        let harbors = coasts.filter { state.land[$0]?.improvements.contains(.harbor) ?? false }
        return (routes ?? tradeRoutes(in: state)).filter { $0.involves(civ) }.count * rules.trade.grainPerRoute
            + coasts.count * rules.trade.grainPerCoast + harbors.count * rules.trade.grainPerHarbor
            + (holds("lighthouse", civ, in: state) ? 2 : 0)
    }

    public func populationCap(of territory: TerritoryID) -> Int {
        rules.populationCap(grain: map.territory(territory)!.grain)
    }

    /// Grain eaten per turn by the population of `territories` and the civilization's armies in them.
    /// Armies in the home network also pay for hauling grain overland to them.
    public func grainConsumption(of civ: CivilizationID, in territories: [TerritoryID],
                                 _ state: GameState) -> Int {
        let set = Set(territories)
        let population = territories.reduce(0) { $0 + state.population(of: $1) }
        let haul = supplyDistances(of: civ, overlandOnly: true, in: state)
        let armies = state.armies(of: civ).filter { set.contains($0.territory) }
        return rules.grainEaten(byPopulation: population) + armies.reduce(0) { total, stack in
            let extra = (haul[stack.territory] ?? 0) / rules.supply.overlandStepsPerExtraGrain
            return total + rules.upkeep(of: stack.units) + stack.units.total * extra
        }
    }

    public func fleetUpkeep(of civ: CivilizationID, _ state: GameState) -> Int {
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
