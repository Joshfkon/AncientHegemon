/// Great works (Josh: "a Civ feel… you're building something"): wonders of the age, each tied
/// to the kind of land that raised it, each built once in the whole world. Whoever holds the
/// land holds the monument, its prestige and its effect, so they can be won in war.

public typealias MonumentID = String

public struct Monument: Codable, Sendable, Equatable, Identifiable {
    public let id: MonumentID
    public let name: String
    /// What it does, in a sentence.
    public let effect: String
    /// Where it can rise: "river_valley", "coastal", "hills" (hills or mountains) or "any".
    public let needs: String
    public let gold: Int
    public let stone: Int
    public let timber: Int
    public let turns: Int
    public let prestige: Int
}

public struct MonumentSite: Codable, Sendable, Equatable {
    public let id: MonumentID
    public var turnsLeft: Int
}

public struct MonumentRules: Codable, Sendable, Equatable {
    public let list: [Monument]
    /// Share of the gold returned when a rival finishes the same work first.
    public let raceRefundPercent: Int
    public func monument(_ id: MonumentID) -> Monument? { list.first { $0.id == id } }
}

extension Engine {
    /// Who holds a finished monument (the owner of its land), if anyone.
    public func holder(of id: MonumentID, in state: GameState) -> CivilizationID? {
        state.monuments[id].flatMap { state.owner(of: $0) }
    }

    public func holds(_ id: MonumentID, _ civ: CivilizationID, in state: GameState) -> Bool {
        holder(of: id, in: state) == civ
    }

    /// Monuments a civ holds.
    public func monuments(of civ: CivilizationID, in state: GameState) -> [Monument] {
        rules.monuments.list.filter { holds($0.id, civ, in: state) }
    }

    public func monumentPrestige(of civ: CivilizationID, in state: GameState) -> Int {
        monuments(of: civ, in: state).reduce(0) { $0 + $1.prestige }
    }

    /// Whether a monument could rise in this territory (ignoring cost).
    public func canRaise(_ id: MonumentID, in territory: TerritoryID, _ state: GameState) -> Bool {
        guard let m = rules.monuments.monument(id), state.monuments[id] == nil,
              state.monumentSites[territory] == nil, let t = map.territory(territory) else { return false }
        // One site of the same work per realm.
        let owner = state.owner(of: territory)
        if state.monumentSites.contains(where: { $0.value.id == id && state.owner(of: $0.key) == owner }) { return false }
        // One great work per territory.
        if state.monuments.values.contains(territory) { return false }
        switch m.needs {
        case "river_valley": return t.has(.riverValley)
        case "coastal": return t.isCoastal
        case "hills": return t.terrain == .hills || t.terrain == .mountains
        default: return true
        }
    }

    func buildMonument(_ id: MonumentID, in territory: TerritoryID, _ state: inout GameState) throws -> [GameEvent] {
        let civ = state.activePlayer
        guard let m = rules.monuments.monument(id) else { throw GameError.unknownMonument(id) }
        guard state.owner(of: territory) == civ else { throw GameError.notOwner(territory) }
        guard homeNetwork(of: civ, in: state).contains(territory) else { throw GameError.outOfSupply(territory) }
        guard canRaise(id, in: territory, state) else { throw GameError.monumentUnavailable(id) }
        let cs = state.civs[civ]!
        guard cs.gold >= m.gold else { throw GameError.insufficientGold(needed: m.gold, available: cs.gold) }
        for (r, n) in [(Resource.stone, m.stone), (.timber, m.timber)] where n > 0 {
            let have = cs.stock[r] ?? 0
            guard have >= n else { throw GameError.insufficientStock(r, needed: n, available: have) }
        }
        state.civs[civ]!.gold -= m.gold
        state.civs[civ]!.stock[.stone, default: 0] -= m.stone
        state.civs[civ]!.stock[.timber, default: 0] -= m.timber
        state.monumentSites[territory] = MonumentSite(id: id, turnsLeft: m.turns)
        return [.monumentStarted(civ: civ, territory: territory, monument: id)]
    }

    /// Works advance a turn; the first to finish a monument takes it, and rivals' sites for it
    /// are abandoned with part of their gold back.
    func progressMonuments(_ civ: CivilizationID, _ state: inout GameState) -> [GameEvent] {
        var events: [GameEvent] = []
        for t in state.territories(of: civ).sorted() {
            guard var site = state.monumentSites[t] else { continue }
            site.turnsLeft -= 1
            guard site.turnsLeft <= 0 else { state.monumentSites[t] = site; continue }
            state.monumentSites[t] = nil
            state.monuments[site.id] = t
            addExperience(civ, .construction, 8, &state)
            events.append(.monumentCompleted(civ: civ, territory: t, monument: site.id))
            let refund = (rules.monuments.monument(site.id)?.gold ?? 0) * rules.monuments.raceRefundPercent / 100
            for (other, rival) in state.monumentSites.sorted(by: { $0.key < $1.key }) where rival.id == site.id {
                state.monumentSites[other] = nil
                if let loser = state.owner(of: other) {
                    state.civs[loser]?.gold += refund
                    events.append(.monumentLost(civ: loser, territory: other, monument: site.id))
                }
            }
        }
        return events
    }
}
