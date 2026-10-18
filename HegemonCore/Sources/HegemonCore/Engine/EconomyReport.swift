/// A civilization's economy as it stands, for the player: where grain comes from and goes, where
/// gold comes from, trade, bronze and the resources within reach. Computed with the same
/// formulas as the harvest, so the forecast matches what the next harvest does (before events).
public struct EconomyReport: Sendable, Equatable {
    /// Grain grown in the home network this turn.
    public let grainProduced: Int
    public let eatenByPeople: Int
    /// Base upkeep of the armies in the home network.
    public let eatenByArmies: Int
    /// Extra grain for armies far from the capital along their supply lines.
    public let eatenByDistance: Int
    /// Ships' crews and the troops aboard.
    public let eatenAtSea: Int
    public var grainBalance: Int { grainProduced - eatenByPeople - eatenByArmies - eatenByDistance - eatenAtSea }
    public let granary: Int
    public let granaryCap: Int
    public let taxes: Int
    public let mines: Int
    public let trade: Int
    /// Gold next harvest, including the ruler's administration bonus.
    public let income: Int
    public let bronze: Int
    public let bronzePerTurn: Int
    public let tradePartners: [CivilizationID]
    /// Copper, tin, horses, timber and gold available, counting trade access.
    public let resources: [Resource: Int]
    /// Territories cut off from the capital's supply.
    public let cutOff: [TerritoryID]
}

extension Engine {
    public func economy(of civ: CivilizationID, in state: GameState) -> EconomyReport {
        let pockets = supplyPockets(of: civ, in: state)
        let home = pockets.first ?? []
        let homeSet = Set(home)
        let routes = tradeRoutes(in: state)
        let produced = home.reduce(0) { $0 + map.territory($1)!.grain * (state.harvestPercent[$1] ?? 100) / 100 }
        let people = rules.grainEaten(byPopulation: home.reduce(0) { $0 + state.population(of: $1) })
        let armies = state.armies(of: civ).filter { homeSet.contains($0.territory) }
        let base = armies.reduce(0) { $0 + rules.upkeep(of: $1.units) }
        let total = grainConsumption(of: civ, in: home, state) - people
        // Taxes depend on the population after growth or starvation, so the gold forecast runs
        // the harvest itself on a scratch copy.
        var next = state
        _ = harvest(civ, &next)
        let gold = income(of: civ, home, routes, next)
        var resources: [Resource: Int] = [:]
        for r in Resource.allCases where r != .grain {
            resources[r] = effectiveYield(of: r, for: civ, in: state, routes: routes)
        }
        return EconomyReport(
            grainProduced: produced, eatenByPeople: people, eatenByArmies: base, eatenByDistance: total - base,
            eatenAtSea: fleetUpkeep(of: civ, state), granary: state.civs[civ]!.granary,
            granaryCap: produced * rules.economy.granaryCapTurns,
            taxes: gold.taxes, mines: gold.mines, trade: gold.trade, income: gold.total,
            bronze: state.civs[civ]!.bronze, bronzePerTurn: min(resources[.copper] ?? 0, resources[.tin] ?? 0),
            tradePartners: routes.filter { $0.involves(civ) }.map { $0.partner(of: civ) },
            resources: resources, cutOff: pockets.dropFirst().flatMap { $0 })
    }

    /// Supply steps from the capital to a territory, and the extra grain each unit there eats.
    public func supplyStrain(of civ: CivilizationID, at territory: TerritoryID,
                             in state: GameState) -> (steps: Int, extraGrain: Int)? {
        guard let steps = supplyDistances(of: civ, in: state)[territory] else { return nil }
        return (steps, steps / rules.supply.stepsPerExtraGrain)
    }
}
