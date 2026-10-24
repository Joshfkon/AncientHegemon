/// Questions the player asks about resources: how much do I have, what is it limiting, and
/// where can I get more?
extension Engine {
    /// A place a resource comes from, as seen by one civilization.
    public struct ResourceSource: Sendable, Equatable {
        public let territory: TerritoryID
        public let amount: Int
        /// Who holds it now (nil when unclaimed).
        public let owner: CivilizationID?
        /// Land steps from the nearest territory the civ holds (0 = already theirs).
        public let steps: Int
    }

    /// How many units of a type (or ships, for timber) the resource still allows this turn, and
    /// the per-turn allowance. Nil when nothing limits it.
    public func recruitAllowance(_ unit: UnitType, for civ: CivilizationID, in state: GameState) -> (left: Int, perTurn: Int)? {
        guard let resource = rules.stats(unit).requires else { return nil }
        let perTurn = effectiveYield(of: resource, for: civ, in: state) * recruitsPerPoint(unit, civ, state)
        let used = state.civs[civ]?.resourceUsedThisTurn[resource] ?? 0
        return (max(0, perTurn - used), perTurn)
    }

    public func shipAllowance(for civ: CivilizationID, in state: GameState) -> (left: Int, perTurn: Int) {
        let resource = rules.ships.requires
        let perTurn = effectiveYield(of: resource, for: civ, in: state)
        let used = state.civs[civ]?.resourceUsedThisTurn[resource] ?? 0
        return (max(0, perTurn - used), perTurn)
    }

    /// Every territory yielding a resource, nearest to the civ's land first.
    public func sources(of resource: Resource, for civ: CivilizationID, in state: GameState) -> [ResourceSource] {
        // Land steps out from everything the civ holds.
        var steps: [TerritoryID: Int] = [:]
        var queue = state.territories(of: civ).sorted()
        for t in queue { steps[t] = 0 }
        var i = 0
        while i < queue.count {
            let t = queue[i]
            i += 1
            for n in map.landNeighbors(of: t) where steps[n] == nil {
                steps[n] = steps[t]! + 1
                queue.append(n)
            }
        }
        return map.territories.compactMap { t -> ResourceSource? in
            let amount = territoryYield(resource, t.id, state)
            guard amount > 0 else { return nil }
            return ResourceSource(territory: t.id, amount: amount, owner: state.owner(of: t.id), steps: steps[t.id] ?? 99)
        }
        .sorted { ($0.steps, -$0.amount, $0.territory) < ($1.steps, -$1.amount, $1.territory) }
    }

    /// How much of a resource reaches the civ from its own land, and how much from each partner.
    public func resourceIncome(_ resource: Resource, for civ: CivilizationID, in state: GameState)
        -> (own: Int, trade: [(partner: CivilizationID, amount: Int)]) {
        if resource == .iron, !ironWorked(civ, state) { return (0, []) }
        let own = yield(of: resource, in: homeNetwork(of: civ, in: state), state)
        let trade = tradeRoutes(in: state).filter { $0.involves(civ) }.compactMap { route -> (CivilizationID, Int)? in
            let partner = route.partner(of: civ)
            let n = shared(yield(of: resource, in: homeNetwork(of: partner, in: state), state), along: route)
            return n > 0 ? (partner, n) : nil
        }
        // Kingdoms selling goods each turn count as partners too.
        let kingdoms = state.kingdomTrades.filter { $0.civ == civ && $0.until >= state.turn && $0.goods.resource == resource }
            .map { (partner: $0.kingdom, amount: $0.goods.amount) }
        return (own, trade.map { (partner: $0.0, amount: $0.1) } + kingdoms)
    }
}
