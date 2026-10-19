/// What one territory gives its realm, and what each trade route brings, for the city and trade
/// screens. Computed with the same rules as the harvest.

public struct TerritoryReport: Sendable, Equatable {
    public let grain: Int
    public let people: Int
    public let peopleCap: Int
    /// Gold a turn from this land's taxes (its share of the realm's), mines, wine and harbor.
    public let taxes: Int
    public let mines: Int
    public let wine: Int
    public let harbor: Int
    public var gold: Int { taxes + mines + wine + harbor }
    /// Resources it yields (ore, horses, timber, stone, luxuries), after improvements.
    public let resources: [Resource: Int]
    /// Supply steps from the capital; nil if cut off.
    public let supplySteps: Int?
    /// How much harder walls make it to take, in percent.
    public let fortification: Int
}

public struct TradeReport: Sendable, Equatable {
    public let partner: CivilizationID
    /// What the partner sends us, and what we send them.
    public let received: [Resource: Int]
    public let sent: [Resource: Int]
    /// Gold this route earns us after tolls, and the tolls paid.
    public let gold: Int
    public let tolls: [CivilizationID]
    /// Extra gold from selling wine to a partner who has none.
    public let wineSales: Int
    public let grainImport: Int
    public let chokepoints: [ChokepointID]
}

extension Engine {
    public func territoryReport(_ territory: TerritoryID, for civ: CivilizationID, in state: GameState) -> TerritoryReport {
        let routes = tradeRoutes(in: state)
        let home = homeNetwork(of: civ, in: state)
        let inSupply = home.contains(territory)
        let e = rules.economy
        let coinage = level(.administration, of: civ, in: state) >= 2 ? rules.knowledge.effects.coinagePercent : 0
        let rate = state.civs[civ]?.taxRate ?? e.defaultTax
        let taxes = inSupply ? state.population(of: territory) * rate * (100 + coinage) / max(1, e.populationPerGold * e.defaultTax * 100) : 0
        let mines = inSupply ? territoryYield(.gold, territory, state) + (state.bonusGold[territory] ?? 0) : 0
        let wine = inSupply ? territoryYield(.wine, territory, state) * e.winePerGold : 0
        let trading = routes.contains { $0.involves(civ) }
        let harbor = inSupply && trading && state.land[territory]?.improvements.contains(.harbor) == true
            ? rules.projectEffects.harborGold : 0
        var resources: [Resource: Int] = [:]
        for r in Resource.allCases where r != .grain && r != .gold && r != .wine {
            let n = territoryYield(r, territory, state)
            if n > 0 { resources[r] = n }
        }
        return TerritoryReport(grain: territoryYield(.grain, territory, state), people: state.population(of: territory),
                               peopleCap: populationCap(of: territory), taxes: taxes, mines: mines, wine: wine, harbor: harbor,
                               resources: resources, supplySteps: supplyDistances(of: civ, in: state)[territory],
                               fortification: fortification(at: territory, state))
    }

    public func tradeReports(for civ: CivilizationID, in state: GameState) -> [TradeReport] {
        let routes = tradeRoutes(in: state).filter { $0.involves(civ) }
        let toll = rules.trade.chokepointToll
        let home = homeNetwork(of: civ, in: state)
        let ourWine = yield(of: .wine, in: home, state)
        return routes.map { route in
            let partner = route.partner(of: civ)
            let flows = goods(along: route, in: state)
            let theirWine = yield(of: .wine, in: homeNetwork(of: partner, in: state), state)
            let sales = ourWine > 0 && theirWine == 0 ? min(ourWine, rules.economy.wineExportCap) * rules.economy.winePerGold : 0
            return TradeReport(partner: partner, received: flows[civ] ?? [:], sent: flows[partner] ?? [:],
                               gold: max(0, rules.trade.goldPerRoute - toll * route.tolls.count),
                               tolls: route.tolls, wineSales: sales, grainImport: rules.trade.grainPerRoute,
                               chokepoints: route.chokepoints)
        }.sorted { $0.partner < $1.partner }
    }
}
