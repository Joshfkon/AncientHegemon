/// Supply and trade both travel over the same network: land borders between territories a set
/// of civilizations owns, coastlines, and sea lanes. A sea lane gated by a chokepoint is closed to
/// travelers when the chokepoint's holder is at war with any of them.
///
/// A sea holding an enemy fleet, and none of the travelers' own, is blockaded and impassable.
/// A stop on a supply or trade route: a territory or a sea zone.
public enum NetworkNode: Hashable, Codable, Sendable {
    case land(TerritoryID)
    case sea(SeaZoneID)
}

/// An automatic trade route between two civilizations at peace whose home networks connect.
public struct TradeRoute: Codable, Sendable, Equatable {
    public let partners: CivPair
    /// Chokepoints the route crosses, in path order.
    public let chokepoints: [ChokepointID]
    /// Third-party civilizations that take a toll from each side, one entry per chokepoint.
    public let tolls: [CivilizationID]
    /// The way the goods travel, from one partner's land to the other's.
    public let path: [NetworkNode]

    public func involves(_ civ: CivilizationID) -> Bool {
        partners.a == civ || partners.b == civ
    }

    public func partner(of civ: CivilizationID) -> CivilizationID {
        partners.a == civ ? partners.b : partners.a
    }
}

extension Engine {
    // MARK: Chokepoints

    /// The civilization holding every territory a chokepoint requires, if any.
    public func holder(of chokepoint: Chokepoint, in state: GameState) -> CivilizationID? {
        guard let first = state.owner(of: chokepoint.heldBy[0]) else { return nil }
        return chokepoint.heldBy.allSatisfy { state.owner(of: $0) == first } ? first : nil
    }

    func seaLinkOpen(_ a: SeaZoneID, _ b: SeaZoneID, for travelers: [CivilizationID],
                     in state: GameState) -> Bool {
        guard let gate = map.chokepoint(gating: a, b), let holder = holder(of: gate, in: state) else {
            return true
        }
        return !travelers.contains { state.atWar(holder, $0) }
    }

    // MARK: Traversal

    private func neighbors(of node: NetworkNode, through owners: Set<CivilizationID>,
                           travelers: [CivilizationID], in state: GameState) -> [NetworkNode] {
        func passable(_ t: TerritoryID) -> Bool { state.owner(of: t).map(owners.contains) ?? false }
        func open(_ s: SeaZoneID) -> Bool { !blockaded(s, for: travelers, in: state) }
        switch node {
        case .land(let t):
            return map.landNeighbors(of: t).filter(passable).map(NetworkNode.land)
                + map.seas(bordering: t).filter(open).map(NetworkNode.sea)
        case .sea(let s):
            return map.seaNeighbors(of: s)
                .filter { seaLinkOpen(s, $0, for: travelers, in: state) && open($0) }.map(NetworkNode.sea)
                + map.coastalTerritories(of: s).filter(passable).map(NetworkNode.land)
        }
    }

    /// Breadth-first search from `starts`. Returns each reached node's parent (starts map to nil).
    private func search(from starts: [NetworkNode], through owners: Set<CivilizationID>,
                        travelers: [CivilizationID], in state: GameState,
                        until done: (NetworkNode) -> Bool = { _ in false })
        -> (parents: [NetworkNode: NetworkNode?], found: NetworkNode?) {
        var parents: [NetworkNode: NetworkNode?] = [:]
        var queue = starts
        for s in starts { parents[s] = .some(nil) }
        var i = 0
        while i < queue.count {
            let node = queue[i]
            i += 1
            if done(node) { return (parents, node) }
            for next in neighbors(of: node, through: owners, travelers: travelers, in: state)
            where parents[next] == nil {
                parents[next] = .some(node)
                queue.append(next)
            }
        }
        return (parents, nil)
    }

    // MARK: Supply

    /// The territory a civilization's supply is traced from: its capital, or if that has fallen,
    /// its most productive territory.
    public func seat(of civ: CivilizationID, in state: GameState) -> TerritoryID? {
        if let capital = map.civilization(civ)?.capital, state.owner(of: capital) == civ {
            return capital
        }
        return state.territories(of: civ).max { a, b in
            let ga = map.territory(a)!.grain, gb = map.territory(b)!.grain
            return ga != gb ? ga < gb : a > b
        }
    }

    /// A civilization's territories grouped into supply pockets. The first pocket is the home
    /// network around the seat; any others are cut off. Each pocket is sorted.
    public func supplyPockets(of civ: CivilizationID, in state: GameState) -> [[TerritoryID]] {
        guard let seat = seat(of: civ, in: state) else { return [] }
        var remaining = state.territories(of: civ)
        remaining.removeAll { $0 == seat }
        remaining.insert(seat, at: 0)
        var assigned = Set<TerritoryID>()
        var pockets: [[TerritoryID]] = []
        for start in remaining where !assigned.contains(start) {
            let reached = search(from: [.land(start)], through: [civ], travelers: [civ], in: state).parents
            let pocket = reached.keys.compactMap { node -> TerritoryID? in
                if case .land(let t) = node { t } else { nil }
            }.sorted()
            assigned.formUnion(pocket)
            pockets.append(pocket)
        }
        return pockets
    }

    /// Steps along the supply route from the seat to each territory of the home network.
    /// Land borders count 1; sailing counts 1 per sea zone plus 1 to land.
    public func supplyDistances(of civ: CivilizationID, in state: GameState) -> [TerritoryID: Int] {
        guard let seat = seat(of: civ, in: state) else { return [:] }
        // 0-1 breadth-first search: entering a territory with a road is free.
        var steps: [NetworkNode: Int] = [.land(seat): 0]
        var deque: [NetworkNode] = [.land(seat)]
        var head = 0
        while head < deque.count {
            let node = deque[head]
            head += 1
            for next in neighbors(of: node, through: [civ], travelers: [civ], in: state) {
                var cost = 1
                if case .land(let t) = next, state.land[t]?.improvements.contains(.road) == true { cost = 0 }
                let d = steps[node]! + cost
                if d < steps[next] ?? .max {
                    steps[next] = d
                    if cost == 0 { deque.insert(next, at: head) } else { deque.append(next) }
                }
            }
        }
        var result: [TerritoryID: Int] = [:]
        for (node, n) in steps {
            if case .land(let t) = node { result[t] = n }
        }
        return result
    }

    /// The supply line from the seat to a territory in the home network, through owned land and
    /// open sea lanes. Nil if the territory is cut off (or not the civilization's).
    public func supplyRoute(of civ: CivilizationID, to territory: TerritoryID,
                            in state: GameState) -> [NetworkNode]? {
        guard let seat = seat(of: civ, in: state) else { return nil }
        let (parents, found) = search(from: [.land(seat)], through: [civ], travelers: [civ], in: state) {
            $0 == .land(territory)
        }
        guard let found else { return nil }
        var path: [NetworkNode] = [found]
        while let parent = parents[path.last!] ?? nil { path.append(parent) }
        return path.reversed()
    }

    /// Territories in a civilization's home supply network.
    public func homeNetwork(of civ: CivilizationID, in state: GameState) -> [TerritoryID] {
        supplyPockets(of: civ, in: state).first ?? []
    }

    // MARK: Trade

    /// The trade route between two civilizations, if they are at peace and their home networks
    /// connect through their own land and open sea lanes.
    public func tradeRoute(between a: CivilizationID, and b: CivilizationID,
                           in state: GameState) -> TradeRoute? {
        guard state.atPeace(a, b) else { return nil }
        let homeA = homeNetwork(of: a, in: state)
        let homeB = Set(homeNetwork(of: b, in: state))
        guard !homeA.isEmpty, !homeB.isEmpty else { return nil }

        let (parents, found) = search(from: homeA.map(NetworkNode.land), through: [a, b],
                                      travelers: [a, b], in: state) { node in
            if case .land(let t) = node { homeB.contains(t) } else { false }
        }
        guard let found else { return nil }

        var path: [NetworkNode] = [found]
        while let parent = parents[path.last!] ?? nil { path.append(parent) }
        path.reverse()

        var chokepoints: [ChokepointID] = []
        var tolls: [CivilizationID] = []
        for (x, y) in zip(path, path.dropFirst()) {
            guard case .sea(let s1) = x, case .sea(let s2) = y,
                  let gate = map.chokepoint(gating: s1, s2) else { continue }
            chokepoints.append(gate.id)
            if let h = holder(of: gate, in: state), h != a, h != b { tolls.append(h) }
        }
        return TradeRoute(partners: CivPair(a, b), chokepoints: chokepoints, tolls: tolls, path: path)
    }

    /// Every active trade route in the game, in a stable order.
    public func tradeRoutes(in state: GameState) -> [TradeRoute] {
        let alive = state.players.filter { !state.civs[$0]!.eliminated }
        var routes: [TradeRoute] = []
        for (i, a) in alive.enumerated() {
            for b in alive[(i + 1)...] {
                if let r = tradeRoute(between: a, and: b, in: state) { routes.append(r) }
            }
        }
        return routes
    }

    /// A resource available to a civilization: its home network's yield plus a share of each
    /// trade partner's. Grain is not traded; it feeds each network locally.
    public func effectiveYield(of resource: Resource, for civ: CivilizationID, in state: GameState,
                               routes: [TradeRoute]? = nil) -> Int {
        // Iron ore is just rock until a civilization learns ironworking.
        if resource == .iron, level(.metallurgy, of: civ, in: state) < 2 { return 0 }
        let own = yield(of: resource, in: homeNetwork(of: civ, in: state), state)
        guard resource != .grain else { return own }
        let shared = (routes ?? tradeRoutes(in: state)).filter { $0.involves(civ) }.reduce(0) {
            let partner = $1.partner(of: civ)
            return $0 + yield(of: resource, in: homeNetwork(of: partner, in: state), state) / rules.trade.shareDivisor
        }
        return own + shared
    }

    /// Total yield of a resource across territories, counting farms and mines.
    public func yield(of resource: Resource, in territories: [TerritoryID], _ state: GameState) -> Int {
        territories.reduce(0) { $0 + territoryYield(resource, $1, state) }
    }
}
