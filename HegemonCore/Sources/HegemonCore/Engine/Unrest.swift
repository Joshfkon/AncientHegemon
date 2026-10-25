/// Overextension (Josh: "stop the runaway leader… realistic"). Land taken in the last few
/// rounds, or far from the capital along the supply line, is restless unless a garrison holds
/// it: it pays no taxes, and the bigger the realm the likelier one of its restless lands rises
/// in revolt. Roads shorten the supply line, so they calm far provinces too.

public struct UnrestRules: Codable, Sendable, Equatable {
    /// Land stays restless this many rounds after it is taken.
    public let recentRounds: Int
    /// A garrison this big keeps restless land quiet.
    public let garrisonToCalm: Int
    /// Revolt weight for each restless territory, and for each territory beyond `sizeCalm`.
    public let revoltPerRestless: Int
    public let sizeCalm: Int
    public let revoltPerExtraLand: Int
}

extension Engine {
    /// Whether a territory of `civ` is restless: newly taken or far from the capital, and not
    /// held by a garrison. The capital is never restless.
    /// `distances` are supply steps from the capital (pass them when asking for many lands).
    public func restless(_ territory: TerritoryID, of civ: CivilizationID, in state: GameState,
                         distances: [TerritoryID: Int]? = nil) -> Bool {
        let garrison = state.armies[territory].map { $0.owner == civ ? $0.units.total : 0 } ?? 0
        return garrison < rules.unrest.garrisonToCalm && needsGarrison(territory, of: civ, in: state, distances: distances)
    }

    /// Land that is restless unless garrisoned: newly taken or far from the capital.
    public func needsGarrison(_ territory: TerritoryID, of civ: CivilizationID, in state: GameState,
                              distances: [TerritoryID: Int]? = nil) -> Bool {
        guard state.owner(of: territory) == civ, seat(of: civ, in: state) != territory else { return false }
        let u = rules.unrest
        let recent = state.land[territory]?.takenOnRound.map { state.turn - $0 < u.recentRounds } ?? false
        let far = ((distances ?? supplyDistances(of: civ, in: state))[territory] ?? .max) >= rules.events.revoltDistance
        return recent || far
    }

    public func restlessLands(of civ: CivilizationID, in state: GameState) -> [TerritoryID] {
        state.territories(of: civ).filter { restless($0, of: civ, in: state) }.sorted()
    }

    func revoltWeight(_ civ: CivilizationID, _ state: GameState) -> Int {
        let u = rules.unrest
        let restless = restlessLands(of: civ, in: state).count
        guard restless > 0 else { return 0 }
        return restless * u.revoltPerRestless + max(0, state.territories(of: civ).count - u.sizeCalm) * u.revoltPerExtraLand
    }

    /// Marks land as newly taken.
    func taken(_ territory: TerritoryID, _ state: inout GameState) {
        state.land[territory]?.takenOnRound = state.turn
    }
}
