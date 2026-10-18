import Foundation
import Testing
@testable import HegemonCore

@Suite struct ResourceGuideTests {
    let engine = try! Engine.bare()

    @Test func egyptHasNoHorsesAndSeesTheNearest() throws {
        let s = try engine.newGame(seed: 1, civilizations: ["egypt"])
        #expect(engine.recruitAllowance(.cavalry, for: "egypt", in: s)! == (0, 0))
        #expect(engine.recruitAllowance(.infantry, for: "egypt", in: s) == nil)
        let horses = engine.sources(of: .horses, for: "egypt", in: s)
        #expect(!horses.isEmpty)
        #expect(horses.map(\.steps) == horses.map(\.steps).sorted())
        #expect(horses.allSatisfy { $0.steps > 0 })
    }

    @Test func allowanceCountsDownAsYouRecruit() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["greece"])
        s.land["thrace"]!.owner = "greece"  // horses 1
        let before = engine.recruitAllowance(.cavalry, for: "greece", in: s)!
        #expect(before.left == before.perTurn && before.perTurn > 0)
        s.civs["greece"]!.gold = 50
        try engine.apply(.recruit(territory: "greece", unit: .cavalry, count: 1), to: &s)
        #expect(engine.recruitAllowance(.cavalry, for: "greece", in: s)!.left == before.left - 1)
    }

    @Test func tradeBringsResources() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["greece", "egypt"])
        s.land["thrace"]!.owner = "greece"
        s.land["scythe"]!.owner = "greece"
        s.peace.insert(CivPair("greece", "egypt"))
        let income = engine.resourceIncome(.horses, for: "egypt", in: s)
        #expect(income.own == 0)
        #expect(income.trade.first?.partner == "greece")
    }
}
