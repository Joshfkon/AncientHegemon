import Foundation

/// What a court can see. The lie of the land and who holds it are common knowledge (merchants
/// and travellers carry that much), but armies, people and works are seen only near your own
/// land, troops and ships, through allies' eyes, and in the capitals your merchants visit.
/// Very large armies are talked about everywhere.
public struct SightRules: Codable, Sendable, Equatable {
    /// An army at least this large is rumoured far beyond your sight.
    public let rumouredArmy: Int
}

extension Engine {
    /// Territories a civ sees clearly.
    public func sight(of civ: CivilizationID, in state: GameState) -> Set<TerritoryID> {
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
}
