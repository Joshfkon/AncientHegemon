/// Everything that changes during a game. Fully Codable so a game can be saved, reloaded,
/// or attached to a bug report as JSON. Static map data is not stored here; `mapVersion`
/// records which map the state was built against.
public struct GameState: Codable, Sendable, Equatable {
    public var mapVersion: Int
    public var seed: UInt64
    public var turn: Int
    public var rng: SeededRNG
    /// Civilizations in play, in turn order.
    public var players: [CivilizationID]
    /// Who controls each territory. Territories absent from the dictionary are unowned.
    public var owners: [TerritoryID: CivilizationID]

    /// Starts a new game. Each participating civilization begins holding only its capital;
    /// everything else is unowned. (Larger starting realms are a balancing question for step 5.)
    public init(map: GameMap, seed: UInt64, civilizations: [CivilizationID]? = nil) throws {
        let ids = civilizations ?? map.civilizations.map(\.id)
        guard !ids.isEmpty else { throw MapError.invalid("a game needs at least one civilization") }
        guard Set(ids).count == ids.count else { throw MapError.invalid("duplicate civilization in game setup") }

        var owners: [TerritoryID: CivilizationID] = [:]
        for id in ids {
            guard let civ = map.civilization(id) else {
                throw MapError.invalid("unknown civilization '\(id)'")
            }
            owners[civ.capital] = civ.id
        }

        self.mapVersion = map.version
        self.seed = seed
        self.turn = 1
        self.rng = SeededRNG(seed: seed)
        self.players = ids
        self.owners = owners
    }

    public func owner(of territory: TerritoryID) -> CivilizationID? {
        owners[territory]
    }

    /// Territories held by a civilization, sorted for deterministic iteration.
    public func territories(of civ: CivilizationID) -> [TerritoryID] {
        owners.filter { $0.value == civ }.map(\.key).sorted()
    }
}
