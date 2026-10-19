/// Crossing the sea in one order: which coasts an army can reach this turn with the ships
/// already off its shore. Either the ships sit in a sea that touches the target, or they're
/// fresh enough to sail one sea further first.
public struct SeaRoute: Sendable, Equatable {
    /// Where the army boards.
    public let board: SeaZoneID
    /// Where it lands from (the same sea, or the one next door).
    public let land: SeaZoneID
    /// How many troops fit aboard.
    public let room: Int
    public var sails: Bool { board != land }
}

extension Engine {
    /// Coasts the army in `from` could sail to and land on this turn, best route first.
    public func seaRoutes(from: TerritoryID, for civ: CivilizationID, in state: GameState) -> [TerritoryID: SeaRoute] {
        guard let territory = map.territory(from) else { return [:] }
        let capacity = shipCapacity(civ, state)
        var routes: [TerritoryID: SeaRoute] = [:]
        func consider(_ target: TerritoryID, _ route: SeaRoute) {
            guard target != from, !map.areLandAdjacent(from, target), state.owner(of: target) != civ else { return }
            if let owner = state.owner(of: target), state.atPeace(civ, owner) { return }
            if let army = state.armies[target], army.owner != civ, state.isPlayer(army.owner), state.atPeace(civ, army.owner) { return }
            // No sailing beats sailing; then more room.
            if let old = routes[target], (!old.sails && route.sails) || (old.sails == route.sails && old.room >= route.room) { return }
            routes[target] = route
        }
        for sea in territory.seas.sorted() {
            guard let fleet = state.fleet(of: civ, in: sea), fleet.ships > 0 else { continue }
            let room = fleet.ships * capacity - fleet.cargo.total
            guard room > 0 else { continue }
            for t in map.coastalTerritories(of: sea) { consider(t, SeaRoute(board: sea, land: sea, room: room)) }
            // A fleet that hasn't moved can carry the army one sea further.
            guard fleet.movedShips == 0 else { continue }
            for next in map.seaNeighbors(of: sea).sorted() where seaLinkOpen(sea, next, for: [civ], in: state) {
                for t in map.coastalTerritories(of: next) { consider(t, SeaRoute(board: sea, land: next, room: room)) }
            }
        }
        return routes
    }
}
