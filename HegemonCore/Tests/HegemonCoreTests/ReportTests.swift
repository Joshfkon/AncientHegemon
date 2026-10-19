import Testing
@testable import HegemonCore

@Suite struct ReportTests {
    let engine = try! Engine.bare()

    @Test func aCityReportsWhatItYields() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["egypt"])
        s.land["egypt"]!.improvements.insert(.walls)
        let r = engine.territoryReport("egypt", for: "egypt", in: s)
        #expect(r.grain == engine.territoryYield(.grain, "egypt", s))
        #expect(r.people == s.population(of: "egypt"))
        #expect(r.supplySteps == 0)
        #expect(r.fortification > 0)
        // With only the capital, its share of taxes and mines is the realm's.
        let e = engine.economy(of: "egypt", in: s)
        #expect(r.taxes == e.taxes)
    }

    @Test func tradeReportsMatchTheGoodsAlongTheRoute() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["egypt", "mesopotamia"])
        s.peace.insert(CivPair("egypt", "mesopotamia"))
        let reports = engine.tradeReports(for: "egypt", in: s)
        if let route = engine.tradeRoute(between: "egypt", and: "mesopotamia", in: s) {
            let flows = engine.goods(along: route, in: s)
            #expect(reports.first?.received == (flows["egypt"] ?? [:]))
            #expect(reports.first?.partner == "mesopotamia")
        } else {
            #expect(reports.isEmpty)
        }
    }
}
