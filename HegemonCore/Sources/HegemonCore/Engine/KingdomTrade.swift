/// Trade with the kingdoms. A kingdom that thinks well enough of an empire, and that its
/// merchants can reach (land next door, or a coast on a sea the empire's coasts touch), sells it
/// a share of what its lands yield (timber, stone, copper, tin, horses, iron, wine or luxuries)
/// for gold every turn, for some rounds. The goods arrive as if from the empire's own land. A
/// trade lapses when the gold runs out, when the kingdom no longer has the goods (its land taken),
/// or when the empire attacks it. Kept faithfully, trade warms them.

public struct KingdomTrade: Codable, Sendable, Hashable {
    public let kingdom: CivilizationID
    public let civ: CivilizationID
    /// What the kingdom sends each turn.
    public let goods: Goods
    /// What the empire pays each turn.
    public let gold: Int
    /// The last round of the trade.
    public let until: Int
}

/// Why a kingdom won't sell.
public enum TradeRefusal: Codable, Sendable, Hashable {
    case gone, answersTo(CivilizationID), outOfReach, alreadyTrading, notEnoughGoods, distrust, notEnoughGold
}

public struct KingdomTradeRules: Codable, Sendable, Equatable {
    /// The least regard each temperament needs before it will trade.
    public let minAttitude: [Temperament: Int]
    /// Gold a turn for each unit, by resource; mercantile peoples ask less.
    public let price: [Resource: Int]
    public let mercantileDiscountPercent: Int
    public let rounds: Int
    /// Kingdoms trade with empires up to this many land and sea steps away; every step beyond
    /// the first adds `stepPrice` gold a unit.
    public let maxSteps: Int
    public let stepPrice: Int
    /// Open markets: a kingdom next door to an empire, or across a sea their coasts share, trades
    /// with it unasked while it regards the empire at least this well (by temperament), sending
    /// `marketPercent` of what its lands yield of each good (rounded).
    public let marketAttitude: [Temperament: Int]
    public let marketPercent: Int
    /// Regard gained each turn the gold arrives, and lost when an empire breaks the trade.
    public let paidAttitude: Int
    public let brokenAttitude: Int
}

extension Engine {
    /// Goods a kingdom can sell: what its lands yield (grain and gold aside).
    public static let tradeGoods: [Resource] = [.timber, .stone, .copper, .tin, .horses, .iron, .wine, .luxuries]

    /// What a kingdom's lands yield of each good, before what it has already promised.
    public func kingdomYield(_ kingdom: CivilizationID, in state: GameState) -> [Resource: Int] {
        let lands = lands(of: kingdom, in: state)
        var out: [Resource: Int] = [:]
        for r in Self.tradeGoods {
            let n = yield(of: r, in: lands, state)
            if n > 0 { out[r] = n }
        }
        return out
    }

    /// The trades in force with a kingdom.
    public func trades(with kingdom: CivilizationID, in state: GameState) -> [KingdomTrade] {
        state.kingdomTrades.filter { $0.kingdom == kingdom && $0.until >= state.turn }
    }

    /// What a kingdom still has to sell of a good.
    public func forSale(_ resource: Resource, from kingdom: CivilizationID, in state: GameState) -> Int {
        let promised = trades(with: kingdom, in: state).filter { $0.goods.resource == resource }.reduce(0) { $0 + $1.goods.amount }
        return max(0, (kingdomYield(kingdom, in: state)[resource] ?? 0) - promised)
    }

    /// How many land and sea steps a kingdom's goods travel to the nearest land of `civ`, if it
    /// is within `maxSteps`. Land next door is one step; across a sea from coast to coast, two.
    /// Goods don't pass through the land of an empire at war with `civ`.
    public func tradeSteps(from kingdom: CivilizationID, to civ: CivilizationID, in state: GameState) -> Int? {
        let limit = rules.kingdomTrade.maxSteps
        var seen = Set(lands(of: kingdom, in: state).map(NetworkNode.land))
        var frontier = Array(seen)
        for steps in 1...max(1, limit) {
            var next: [NetworkNode] = []
            for node in frontier {
                let around: [NetworkNode] = switch node {
                case .land(let t): map.landNeighbors(of: t).map(NetworkNode.land) + map.seas(bordering: t).map(NetworkNode.sea)
                case .sea(let s): map.seaNeighbors(of: s).map(NetworkNode.sea) + map.coastalTerritories(of: s).map(NetworkNode.land)
                }
                for n in around where !seen.contains(n) {
                    seen.insert(n)
                    if case .land(let t) = n, let owner = state.owner(of: t) {
                        if owner == civ { return steps }
                        if state.atWar(owner, civ) { continue }
                    }
                    next.append(n)
                }
            }
            frontier = next
        }
        return nil
    }

    /// Whether a kingdom's merchants can reach `civ` at all.
    public func withinReach(_ kingdom: CivilizationID, of civ: CivilizationID, in state: GameState) -> Bool {
        tradeSteps(from: kingdom, to: civ, in: state) != nil
    }

    /// Gold a turn a kingdom asks `civ` for `amount` of a good: dearer the farther it travels.
    public func tradePrice(_ resource: Resource, _ amount: Int, from kingdom: CivilizationID, to civ: CivilizationID,
                           in state: GameState) -> Int {
        let t = rules.kingdomTrade
        let steps = tradeSteps(from: kingdom, to: civ, in: state) ?? t.maxSteps
        let each = (t.price[resource] ?? 2) + max(0, steps - 1) * t.stepPrice
        let full = each * amount
        guard people(of: kingdom, in: state)?.temperament == .mercantile else { return full }
        return max(amount, full * (100 - t.mercantileDiscountPercent) / 100)
    }

    /// Why a kingdom won't sell `amount` of a good to `civ` now, or nil if it would.
    public func tradeRefusal(_ resource: Resource, _ amount: Int, from kingdom: CivilizationID, to civ: CivilizationID,
                             in state: GameState) -> TradeRefusal? {
        guard let k = state.kingdoms[kingdom], let people = people(of: kingdom, in: state) else { return .gone }
        if let lord = k.overlord, lord != civ { return .answersTo(lord) }
        guard withinReach(kingdom, of: civ, in: state) else { return .outOfReach }
        guard !state.kingdomTrades.contains(where: {
            $0.kingdom == kingdom && $0.civ == civ && $0.goods.resource == resource && $0.until >= state.turn
        }) else { return .alreadyTrading }
        guard amount > 0, forSale(resource, from: kingdom, in: state) >= amount else { return .notEnoughGoods }
        let need = rules.kingdomTrade.minAttitude[people.temperament] ?? 0
        guard k.overlord == civ || attitude(of: kingdom, toward: civ, in: state) >= need else { return .distrust }
        let gold = state.civs[civ]?.gold ?? 0
        guard gold >= tradePrice(resource, amount, from: kingdom, to: civ, in: state) else { return .notEnoughGold }
        return nil
    }

    /// Goods arriving from kingdoms' trade, as yield.
    func kingdomTradeYield(_ resource: Resource, for civ: CivilizationID, in state: GameState) -> Int {
        state.kingdomTrades.filter { $0.civ == civ && $0.until >= state.turn && $0.goods.resource == resource }
            .reduce(0) { $0 + $1.goods.amount }
    }

    // MARK: Open markets

    /// Each kingdom's lands, in one pass over the map.
    func kingdomLands(in state: GameState) -> [CivilizationID: [TerritoryID]] {
        var out: [CivilizationID: [TerritoryID]] = [:]
        for t in map.territories { if let k = kingdom(at: t.id, in: state) { out[k, default: []].append(t.id) } }
        return out
    }

    /// Whether a kingdom trades with `civ` unasked: it lies next door or across a sea their
    /// coasts share, and doesn't resent the empire. A vassal trades only with its overlord.
    public func marketOpen(_ kingdom: CivilizationID, to civ: CivilizationID, in state: GameState) -> Bool {
        let coasts = Set(state.territories(of: civ).flatMap { map.seas(bordering: $0) })
        return marketOpen(kingdom, to: civ, lands: lands(of: kingdom, in: state), coasts: coasts, state)
    }

    private func marketOpen(_ kingdom: CivilizationID, to civ: CivilizationID, lands: [TerritoryID],
                            coasts: Set<SeaZoneID>, _ state: GameState) -> Bool {
        guard let k = state.kingdoms[kingdom], let people = people(of: kingdom, in: state) else { return false }
        if let lord = k.overlord, lord != civ { return false }
        if k.overlord == nil, attitude(of: kingdom, toward: civ, in: state) < rules.kingdomTrade.marketAttitude[people.temperament] ?? 0 {
            return false
        }
        return lands.contains { t in
            map.landNeighbors(of: t).contains { state.owner(of: $0) == civ }
                || map.seas(bordering: t).contains(where: coasts.contains)
        }
    }

    /// What a kingdom's open market sends `civ` of each good a turn.
    public func marketGoods(from kingdom: CivilizationID, to civ: CivilizationID, in state: GameState) -> [Resource: Int] {
        guard marketOpen(kingdom, to: civ, in: state) else { return [:] }
        return kingdomYield(kingdom, in: state).mapValues { ($0 * rules.kingdomTrade.marketPercent + 50) / 100 }.filter { $0.value > 0 }
    }

    /// Goods arriving from the kingdoms' open markets, as yield.
    func marketYield(_ resource: Resource, for civ: CivilizationID, in state: GameState) -> Int {
        guard Self.tradeGoods.contains(resource), state.civs[civ] != nil else { return 0 }
        let coasts = Set(state.territories(of: civ).flatMap { map.seas(bordering: $0) })
        return kingdomLands(in: state).sorted { $0.key < $1.key }.reduce(0) { total, entry in
            guard marketOpen(entry.key, to: civ, lands: entry.value, coasts: coasts, state) else { return total }
            return total + (yield(of: resource, in: entry.value, state) * rules.kingdomTrade.marketPercent + 50) / 100
        }
    }

    // MARK: Orders

    func tradeWithKingdom(_ territory: TerritoryID, _ resource: Resource, _ amount: Int, _ state: inout GameState) throws -> [GameEvent] {
        let civ = state.activePlayer
        guard let k = kingdom(at: territory, in: state) else { throw GameError.noTribe(territory) }
        if let why = tradeRefusal(resource, amount, from: k, to: civ, in: state) { throw GameError.tradeRefused(territory, why) }
        let gold = tradePrice(resource, amount, from: k, to: civ, in: state)
        state.kingdomTrades.append(KingdomTrade(kingdom: k, civ: civ, goods: Goods(resource, amount), gold: gold,
                                                until: state.turn + rules.kingdomTrade.rounds - 1))
        // The first payment goes with the agreement; the rest come each turn.
        state.civs[civ]!.gold -= gold
        return [.kingdomTradeMade(civ: civ, territory: territory, goods: Goods(resource, amount), gold: gold)]
    }

    /// At the start of `civ`'s turn: it pays for its trades with the kingdoms. A trade it can't
    /// pay for, or whose goods the kingdom no longer has, lapses; expired trades are cleared.
    func keepKingdomTrades(_ civ: CivilizationID, _ state: inout GameState) -> [GameEvent] {
        let t = rules.kingdomTrade
        var events: [GameEvent] = []
        let turn = state.turn
        state.kingdomTrades.removeAll { $0.until < turn }
        for (i, trade) in state.kingdomTrades.enumerated().reversed() where trade.civ == civ {
            let homeland = state.kingdoms[trade.kingdom]?.homeland
            let place = homeland ?? String(trade.kingdom.dropFirst(2))
            let yields = state.kingdoms[trade.kingdom] == nil ? 0 : kingdomYield(trade.kingdom, in: state)[trade.goods.resource ?? .gold] ?? 0
            let promised = trades(with: trade.kingdom, in: state).filter { $0.goods.resource == trade.goods.resource }
                .reduce(0) { $0 + $1.goods.amount }
            let paid = state.civs[civ]!.gold >= trade.gold
            guard homeland != nil, yields >= promised, paid else {
                state.kingdomTrades.remove(at: i)
                if !paid { changeAttitude(of: trade.kingdom, toward: civ, by: t.brokenAttitude, &state) }
                events.append(.kingdomTradeEnded(civ: civ, territory: place))
                continue
            }
            state.civs[civ]!.gold -= trade.gold
            changeAttitude(of: trade.kingdom, toward: civ, by: t.paidAttitude, &state)
        }
        return events
    }

    /// An empire attacks a kingdom: their trade is over.
    func endKingdomTrades(_ kingdom: CivilizationID, with civ: CivilizationID, _ state: inout GameState) {
        state.kingdomTrades.removeAll { $0.kingdom == kingdom && $0.civ == civ }
    }
}
