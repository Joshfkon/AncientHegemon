/// What war costs a realm and what peace builds (Josh: "too easy to turn all your population into
/// troops and then march through the neighboring regions… more like CIV where there is a trade
/// off to expansion vs building your own infrastructure").
///
/// - A standing army is cheap up to a share of the people; beyond it every soldier is a man taken
///   from home who must be paid in full, and with far more soldiers than people nobody grows.
/// - Taxes thin out with distance from the capital (roads bring far lands closer), and newly won
///   land pays half while it settles.
/// - Farms let more people live on a land, so building grows a realm without conquest.
extension Engine {
    /// People a land can hold: one for each grain it yields, farms and irrigation included.
    public func populationCap(of territory: TerritoryID, in state: GameState) -> Int {
        rules.populationCap(grain: territoryYield(.grain, territory, state))
    }

    /// Soldiers (on land and aboard ship) per 100 of the realm's people.
    public func mobilization(of civ: CivilizationID, in state: GameState) -> Int {
        soldiers(of: civ, in: state) * 100 / max(1, state.totalPopulation(of: civ))
    }

    public func soldiers(of civ: CivilizationID, in state: GameState) -> Int {
        state.totalUnits(of: civ).total + state.fleets(of: civ).reduce(0) { $0 + $1.cargo.total }
    }

    /// Soldiers the realm keeps at the base wage: a guard, and a share of its people.
    public func standingArmy(of civ: CivilizationID, in state: GameState) -> Int {
        standingArmy(people: state.totalPopulation(of: civ))
    }

    public func standingArmy(people: Int) -> Int {
        rules.realm.standingBase + people * rules.realm.standingPercent / 100
    }

    /// Whether so many men are under arms (beyond the guard) that the people stop growing.
    public func overMobilized(_ civ: CivilizationID, in state: GameState) -> Bool {
        soldiers(of: civ, in: state) > warFooting(people: state.totalPopulation(of: civ))
    }

    /// Most soldiers a realm of `people` can field before its people stop growing.
    public func warFooting(people: Int) -> Int {
        rules.realm.standingBase + people * rules.realm.noGrowthPercent / 100
    }

    /// Share (percent) of a land's taxes that reaches the treasury: none from restless or
    /// besieged land, half from newly won land, less the farther it lies from the capital.
    /// `distances` are supply steps from the capital (pass them when asking for many lands).
    public func taxPercent(_ territory: TerritoryID, of civ: CivilizationID, in state: GameState,
                           distances: [TerritoryID: Int]? = nil) -> Int {
        let distances = distances ?? supplyDistances(of: civ, in: state)
        guard !restless(territory, of: civ, in: state, distances: distances), state.sieges[territory] == nil else { return 0 }
        let r = rules.realm
        let steps = distances[territory] ?? 0
        var percent = max(r.minTaxPercent, 100 - max(0, steps - r.fullTaxSteps) * r.taxLossPerStep)
        let recent = state.land[territory]?.takenOnRound.map { state.turn - $0 < rules.unrest.recentRounds } ?? false
        if recent { percent = percent * r.newLandTaxPercent / 100 }
        return percent
    }

    /// Buildings standing in a civ's land; each level of walls above the first counts too.
    public func buildings(of civ: CivilizationID, in state: GameState) -> Int {
        state.territories(of: civ).reduce(0) { total, t in
            let built = state.land[t]?.improvements ?? []
            return total + built.count + (built.contains(.walls) ? max(0, wallLevel(at: t, state) - 1) : 0)
        }
    }
}
