import Foundation

/// What a court can see. The lie of the land and who holds it are common knowledge (merchants
/// and travellers carry that much), but armies, people and works are seen only near your own
/// land, troops and ships, through allies' eyes, and in the capitals your merchants visit.
/// Very large armies are talked about everywhere.
public struct SightRules: Codable, Sendable, Equatable {
    /// Off (the default): everything on the board is in plain view, as on the tabletop.
    public let limited: Bool
    /// An army at least this large is rumoured far beyond your sight.
    public let rumouredArmy: Int
    /// The garrison a court assumes holds each piece of a rival's land it can't see.
    public let assumedGarrison: Int
}

extension Engine {
    /// Territories a civ sees clearly.
    public func sight(of civ: CivilizationID, in state: GameState) -> Set<TerritoryID> {
        guard rules.sight.limited else { return Set(map.territories.map(\.id)) }
        var seen = Set<TerritoryID>()
        func look(from t: TerritoryID) {
            seen.insert(t)
            seen.formUnion(map.landNeighbors(of: t))
        }
        func eyes(of c: CivilizationID) {
            for t in state.territories(of: c) { look(from: t) }
            for a in state.armies(of: c) { look(from: a.territory) }
            let seas = Set(state.fleets(of: c).map(\.sea))
            for t in map.territories where !seas.isDisjoint(with: t.seas) { seen.insert(t.id) }
        }
        eyes(of: civ)
        for ally in allies(of: civ, in: state) { eyes(of: ally) }
        // Merchants report what they see in their partners' capitals.
        for route in tradeRoutes(in: state) where route.partners.a == civ || route.partners.b == civ {
            let partner = route.partners.a == civ ? route.partners.b : route.partners.a
            if let seat = seat(of: partner, in: state) { seen.insert(seat) }
        }
        return seen
    }

    /// Whether an army is large enough to be talked about beyond sight.
    public func rumoured(_ units: UnitCounts) -> Bool {
        units.total >= rules.sight.rumouredArmy
    }

    /// What `civ` believes stands in `t`: the army it sees there; out of sight, a rumoured host
    /// at the rumoured size, else the assumed garrison of whoever holds the land, or on
    /// unclaimed land the tribe that lived there at the start; nil when it sees nothing there.
    public func perceivedArmy(at t: TerritoryID, by civ: CivilizationID, sight: Set<TerritoryID>,
                              in state: GameState) -> (owner: CivilizationID, units: Int)? {
        if sight.contains(t) { return state.armies[t].map { ($0.owner, $0.units.total) } }
        if let army = state.armies[t], army.owner != civ, rumoured(army.units) {
            return (army.owner, rules.sight.rumouredArmy)
        }
        guard let owner = state.owner(of: t) else {
            let tribe = rules.start.natives.tribe(in: map.territory(t)!, island: map.landNeighbors(of: t).isEmpty)
            return tribe > 0 ? (nativesID, tribe) : nil
        }
        return owner == civ ? nil : (owner, rules.sight.assumedGarrison)
    }

    /// The soldiers (and, with `ships`, the hulls) `observer` believes `civ` commands: what it
    /// sees, rumours, an assumed garrison on land it can't see, and fleets on seas it watches.
    public func perceivedStrength(of civ: CivilizationID, by observer: CivilizationID, ships: Bool,
                                  sight: Set<TerritoryID>? = nil, in state: GameState) -> Int {
        let fleets = state.fleets(of: civ)
        guard civ != observer else {
            return state.totalUnits(of: civ).total + fleets.reduce(0) { $0 + $1.cargo.total + (ships ? $1.ships : 0) }
        }
        let sight = sight ?? self.sight(of: observer, in: state)
        let places = Set(state.territories(of: civ)).union(state.armies(of: civ).map(\.territory))
        let land = places.reduce(0) { total, t in
            guard let army = perceivedArmy(at: t, by: observer, sight: sight, in: state), army.owner == civ else { return total }
            return total + army.units
        }
        let watched = Set(map.territories.filter { sight.contains($0.id) }.flatMap(\.seas))
        return land + fleets.filter { watched.contains($0.sea) }.reduce(0) { $0 + $1.cargo.total + (ships ? $1.ships : 0) }
    }
}
