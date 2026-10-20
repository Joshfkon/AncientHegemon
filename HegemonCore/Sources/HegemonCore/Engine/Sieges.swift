/// Sieges. An army camped beside a walled town cuts it off: no harvest from its fields and no
/// taxes, the garrison goes hungry (a granary holds out a few rounds), and the walls are worn
/// down round by round (faster with rams, from the second level of Construction). The defender
/// can sally against the camp, a relief army can attack it, and the besieger can storm the
/// weakened walls whenever it likes. Moving the camp's army away lifts the siege.

public struct Siege: Codable, Sendable, Equatable {
    public let civ: CivilizationID
    public let camp: TerritoryID
    public var rounds: Int

    public init(civ: CivilizationID, camp: TerritoryID, rounds: Int = 0) {
        self.civ = civ
        self.camp = camp
        self.rounds = rounds
    }
}

public struct SiegeRules: Codable, Sendable, Equatable {
    /// Wall defence lost per round of siege, in points of the walls' percent.
    public let wallDamagePercent: Int
    /// With rams (Construction level 2).
    public let ramsDamagePercent: Int
    /// Share of the garrison lost to hunger each round, once any granary is empty.
    public let starvePercent: Int
    /// Rounds a granary in the town holds off hunger.
    public let granaryRounds: Int
}

extension Engine {
    /// How far a siege has worn down a town's walls, in percent of defence.
    public func breach(at territory: TerritoryID, _ state: GameState) -> Int {
        guard let siege = state.sieges[territory] else { return 0 }
        let rams = level(.construction, of: siege.civ, in: state) >= 2
        return siege.rounds * (rams ? rules.siege.ramsDamagePercent : rules.siege.wallDamagePercent)
    }

    /// Whether `civ` could lay siege to `territory` from `camp` now.
    public func canBesiege(_ territory: TerritoryID, from camp: TerritoryID, by civ: CivilizationID,
                           _ state: GameState) -> Bool {
        guard let owner = state.owner(of: territory), owner != civ, state.isPlayer(owner), state.atWar(civ, owner),
              state.land[territory]?.improvements.contains(.walls) == true, state.sieges[territory] == nil,
              map.areLandAdjacent(camp, territory),
              let army = state.armies[camp], army.owner == civ,
              !(army.units - (state.moved[camp] ?? .zero)).isEmpty else { return false }
        return true
    }

    func besiege(_ territory: TerritoryID, from camp: TerritoryID, _ state: inout GameState) throws -> [GameEvent] {
        let civ = state.activePlayer
        guard state.land[territory]?.improvements.contains(.walls) == true else { throw GameError.notWalled(territory) }
        if let owner = state.owner(of: territory), state.atPeace(civ, owner) { throw GameError.atPeace(territory) }
        guard map.areLandAdjacent(camp, territory) else { throw GameError.notAdjacent(camp, territory) }
        guard canBesiege(territory, from: camp, by: civ, state) else { throw GameError.insufficientUnits(camp) }
        try checkOmen(civ, attacking: territory, state)
        state.sieges[territory] = Siege(civ: civ, camp: camp)
        // The whole army sits down before the walls for the turn.
        state.moved[camp] = state.armies[camp]!.units
        return [.siegeLaid(civ: civ, territory: territory, camp: camp)]
    }

    func liftSiege(_ territory: TerritoryID, _ state: inout GameState) throws -> [GameEvent] {
        let civ = state.activePlayer
        guard state.sieges[territory]?.civ == civ else { throw GameError.noSiege(territory) }
        state.sieges[territory] = nil
        return [.siegeLifted(civ: civ, territory: territory)]
    }

    /// Each round, at the besieger's turn: the siege holds only while its army stays in camp and
    /// the war goes on; the garrison starves and the walls crumble a little more.
    func pressSieges(_ civ: CivilizationID, _ state: inout GameState) -> [GameEvent] {
        var events: [GameEvent] = []
        for (town, siege) in state.sieges.sorted(by: { $0.key < $1.key }) where siege.civ == civ {
            let owner = state.owner(of: town)
            guard state.armies[siege.camp]?.owner == civ, let owner, owner != civ, state.atWar(civ, owner),
                  state.land[town]?.improvements.contains(.walls) == true else {
                state.sieges[town] = nil
                events.append(.siegeLifted(civ: civ, territory: town))
                continue
            }
            let rounds = siege.rounds + 1
            state.sieges[town]!.rounds = rounds
            var starved = 0
            let stores = state.land[town]?.improvements.contains(.granary) == true ? rules.siege.granaryRounds : 0
            if rounds > stores, let garrison = state.armies[town], garrison.owner != civ {
                starved = max(1, garrison.units.total * rules.siege.starvePercent / 100)
                var units = garrison.units
                var left = starved
                while left > 0, !units.isEmpty {
                    let biggest = UnitType.allCases.max { units[$0] < units[$1] }!
                    units[biggest] -= 1
                    left -= 1
                }
                state.armies[town] = units.isEmpty ? nil : { var a = garrison; a.units = units; return a }()
                state.land[town]!.population = max(rules.economy.minPopulation, state.population(of: town) - 1)
            }
            events.append(.siegePressed(civ: civ, territory: town, rounds: rounds, starved: starved))
        }
        return events
    }
}
