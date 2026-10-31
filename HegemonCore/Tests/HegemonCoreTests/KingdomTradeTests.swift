import Foundation
import Testing
@testable import HegemonCore

private let macedones = kingdomID("macedonia")
private let thracians = kingdomID("thrace")

@Suite struct KingdomTradeTests {
    let engine = try! Engine.calm()

    /// Greece at home, the Macedones (timber 2, stone 1) next door and friendly enough to trade.
    func greece(gold: Int = 50) throws -> GameState {
        var s = try engine.newGame(seed: 1, civilizations: ["greece", "egypt"])
        s.armies["macedonia"] = Army(owner: macedones, units: UnitCounts(infantry: 3))
        s.armies["thrace"] = Army(owner: thracians, units: UnitCounts(infantry: 3))
        s.kingdoms[macedones]!.attitude["greece"] = 30
        s.kingdoms[thracians]!.attitude["greece"] = 30
        s.civs["greece"]!.gold = gold
        s.activePlayerIndex = s.players.firstIndex(of: "greece")!
        return s
    }

    @Test func aFriendlyKingdomNextDoorSellsWhatItsLandsYield() throws {
        var s = try greece()
        #expect(engine.kingdomYield(macedones, in: s)[.timber] == 2)
        #expect(engine.tradeSteps(from: macedones, to: "greece", in: s) == 1)
        let before = engine.effectiveYield(of: .timber, for: "greece", in: s)
        let price = engine.tradePrice(.timber, 1, from: macedones, to: "greece", in: s)
        #expect(price == engine.rules.kingdomTrade.price[.timber])
        let events = try engine.apply(.tradeWithKingdom(territory: "macedonia", resource: .timber, amount: 1), to: &s)
        #expect(events == [.kingdomTradeMade(civ: "greece", territory: "macedonia", goods: Goods(.timber, 1), gold: price)])
        #expect(s.civs["greece"]!.gold == 50 - price)
        #expect(engine.effectiveYield(of: .timber, for: "greece", in: s) == before + 1)
        #expect(engine.forSale(.timber, from: macedones, in: s) == 1)
        // Each turn the gold goes out and their regard grows.
        let regard = engine.attitude(of: macedones, toward: "greece", in: s)
        _ = engine.keepKingdomTrades("greece", &s)
        #expect(s.civs["greece"]!.gold == 50 - 2 * price)
        #expect(engine.attitude(of: macedones, toward: "greece", in: s) == regard + engine.rules.kingdomTrade.paidAttitude)
    }

    @Test func fartherGoodsCostMore() throws {
        let s = try greece()
        // Thrace lies across the Aegean from Greece: two steps, one of carriage.
        let steps = try #require(engine.tradeSteps(from: thracians, to: "greece", in: s))
        #expect(steps == 2)
        let t = engine.rules.kingdomTrade
        #expect(engine.tradePrice(.horses, 1, from: thracians, to: "greece", in: s) == t.price[.horses]! + t.stepPrice)
    }

    @Test func distrustAndPovertyKeepTheMarketShut() throws {
        var s = try greece(gold: 1)
        #expect(engine.tradeRefusal(.timber, 1, from: macedones, to: "greece", in: s) == .notEnoughGold)
        s.civs["greece"]!.gold = 50
        s.kingdoms[macedones]!.attitude["greece"] = -40
        #expect(engine.tradeRefusal(.timber, 1, from: macedones, to: "greece", in: s) == .distrust)
        #expect(throws: GameError.tradeRefused("macedonia", .distrust)) {
            try engine.apply(.tradeWithKingdom(territory: "macedonia", resource: .timber, amount: 1), to: &s)
        }
        s.kingdoms[macedones]!.attitude["greece"] = 30
        #expect(engine.tradeRefusal(.timber, 3, from: macedones, to: "greece", in: s) == .notEnoughGoods)
    }

    @Test func unpaidOrAttackedTheTradeEnds() throws {
        var s = try greece()
        try engine.apply(.tradeWithKingdom(territory: "macedonia", resource: .timber, amount: 1), to: &s)
        s.civs["greece"]!.gold = 0
        let events = engine.keepKingdomTrades("greece", &s)
        #expect(events == [.kingdomTradeEnded(civ: "greece", territory: "macedonia")])
        #expect(s.kingdomTrades.isEmpty)
        #expect(engine.attitude(of: macedones, toward: "greece", in: s) == 30 + engine.rules.kingdomTrade.brokenAttitude)

        var t = try greece()
        try engine.apply(.tradeWithKingdom(territory: "macedonia", resource: .timber, amount: 1), to: &t)
        engine.notePeopleAttacked("macedonia", by: "greece", &t)
        #expect(t.kingdomTrades.isEmpty)
    }

    @Test func neighboursTradeUnaskedUnlessTheyResentYou() throws {
        let engine = try self.engine.modified { json in
            var kt = json["kingdomTrade"] as! [String: Any]
            kt["marketPercent"] = 50
            json["kingdomTrade"] = kt
        }
        var s = try greece()
        // The Macedones next door yield 2 timber: half reaches Greece with no deal at all.
        #expect(engine.marketOpen(macedones, to: "greece", in: s))
        #expect(engine.marketGoods(from: macedones, to: "greece", in: s)[.timber] == 1)
        let open = engine.effectiveYield(of: .timber, for: "greece", in: s)
        // Attacked, they close their market.
        engine.notePeopleAttacked("macedonia", by: "greece", &s)
        #expect(!engine.marketOpen(macedones, to: "greece", in: s))
        #expect(engine.effectiveYield(of: .timber, for: "greece", in: s) == open - 1)
        // Another's vassal trades only with its overlord.
        s.kingdoms[macedones]!.attitude["greece"] = 50
        s.kingdoms[macedones]!.overlord = "egypt"
        #expect(!engine.marketOpen(macedones, to: "greece", in: s))
    }

    @Test func savesFromBeforeTradeStillLoad() throws {
        let s = try greece()
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as! [String: Any]
        json["kingdomTrades"] = nil
        let old = try JSONSerialization.data(withJSONObject: json)
        let loaded = try JSONDecoder().decode(GameState.self, from: old)
        #expect(loaded.kingdomTrades.isEmpty)
        #expect(loaded == s)
    }
}

@Suite struct RouteShareTests {
    let engine = try! Engine.calm()

    func route(steps: Int) -> TradeRoute {
        TradeRoute(partners: CivPair("greece", "egypt"), chokepoints: [], tolls: [],
                   path: (0...steps).map { .land("t\($0)") })
    }

    @Test func longerRoutesCarryLess() {
        let t = engine.rules.trade
        #expect(engine.sharePercent(of: route(steps: 1)) == t.sharePercent)
        #expect(engine.sharePercent(of: route(steps: t.shareFullSteps)) == t.sharePercent)
        #expect(engine.sharePercent(of: route(steps: t.shareFullSteps + 2)) == t.sharePercent - 2 * t.shareLossPerStep)
        #expect(engine.sharePercent(of: route(steps: 40)) == t.shareMinPercent)
        #expect(engine.shared(4, along: route(steps: 1)) == 4 * t.sharePercent / 100)
    }
}
