import Testing
@testable import HegemonCore

@Suite struct CourtDiplomacyTests {
    let engine = try! Engine.calm()

    /// Greece (to move) and Egypt, at peace, both well off.
    func courts(egyptHuman: Bool = false) throws -> GameState {
        var s = try engine.newGame(seed: 1, civilizations: ["greece", "egypt"])
        s.peace.insert(CivPair("greece", "egypt"))
        s.civs["greece"]!.gold = 100
        s.civs["egypt"]!.gold = 100
        s.civs["egypt"]!.isHuman = egyptHuman
        return s
    }

    @Test func giftsWarmTheReceiver() throws {
        var s = try courts()
        let events = try engine.apply(.propose(to: "egypt", .gift(.gold(10))), to: &s)
        #expect(events == [.giftSent(from: "greece", to: "egypt", goods: .gold(10))])
        #expect(s.civs["greece"]!.gold == 90 && s.civs["egypt"]!.gold == 110)
        #expect(engine.regard(of: "egypt", toward: "greece", in: s) == 20)
    }

    @Test func marriagesNeedRegardAndBindTheHouses() throws {
        var s = try courts()
        let before = s.civs["greece"]!.legitimacy
        #expect(try engine.apply(.propose(to: "egypt", .marriage), to: &s) == [.dealRefused(from: "greece", to: "egypt", deal: .marriage)])
        s.regard[Opinion("egypt", about: "greece")] = 30
        s.lastProposal = [:]
        try engine.apply(.propose(to: "egypt", .marriage), to: &s)
        #expect(engine.married("greece", "egypt", in: s))
        #expect(s.civs["greece"]!.legitimacy == min(100, before + engine.rules.diplomacy.marriageLegitimacy))
        #expect(throws: GameError.alreadyMarried("egypt")) { try engine.apply(.propose(to: "egypt", .marriage), to: &s) }
    }

    @Test func bargainsMoveGoodsEveryTurn() throws {
        var s = try courts()
        // Egypt holds Cyprus and its copper; Greece pays gold for some of it.
        s.land["cyprus"]!.owner = "egypt"
        s.armies["cyprus"] = nil
        let copper = engine.yield(of: .copper, in: engine.homeNetwork(of: "egypt", in: s), s)
        try #require(copper >= 1)
        let greekCopper = engine.effectiveYield(of: .copper, for: "greece", in: s)
        try engine.apply(.propose(to: "egypt", .bargain(give: .gold(5), get: Goods(.copper, 1))), to: &s)
        #expect(s.bargains.count == 1)
        #expect(engine.effectiveYield(of: .copper, for: "greece", in: s) == greekCopper + 1)
        let gold = s.civs["egypt"]!.gold
        _ = engine.keepBargains("greece", &s)
        #expect(s.civs["egypt"]!.gold == gold + 5)
    }

    @Test func theWeakPayTributeAndTheStrongGiveCauseForWar() throws {
        var s = try courts()
        s.armies["greece"] = Army(owner: "greece", units: UnitCounts(infantry: 20))
        s.armies["egypt"] = Army(owner: "egypt", units: UnitCounts(infantry: 3))
        try engine.apply(.propose(to: "egypt", .tribute(gold: 10)), to: &s)
        #expect(s.civs["greece"]!.gold == 110)
        #expect(engine.regard(of: "egypt", toward: "greece", in: s) < 0)
        // A strong Egypt refuses: Greece has its cause, and declares war without shame.
        s.armies["egypt"] = Army(owner: "egypt", units: UnitCounts(infantry: 30))
        s.lastProposal = [:]
        try engine.apply(.propose(to: "egypt", .tribute(gold: 10)), to: &s)
        #expect(engine.casusBelli("greece", against: "egypt", in: s))
        let legitimacy = s.civs["greece"]!.legitimacy
        try engine.apply(.declareWar(on: "egypt"), to: &s)
        #expect(s.civs["greece"]!.legitimacy == legitimacy)
    }

    @Test func breakingAPactCostsDearly() throws {
        var s = try courts()
        s.regard[Opinion("egypt", about: "greece")] = 20
        try engine.apply(.propose(to: "egypt", .pact), to: &s)
        #expect(engine.pact("greece", "egypt", in: s) != nil)
        let legitimacy = s.civs["greece"]!.legitimacy
        let events = try engine.apply(.declareWar(on: "egypt"), to: &s)
        #expect(events.contains(.pactBroken(by: "greece", with: "egypt")))
        #expect(s.civs["greece"]!.legitimacy == max(0, legitimacy + engine.rules.government.legitimacy.brokePeace
                                                       + engine.rules.diplomacy.pactBrokenLegitimacy))
        #expect(engine.regard(of: "egypt", toward: "greece", in: s) <= 25 + engine.rules.diplomacy.pactBrokenRegard)
    }

    @Test func accessLetsArmiesCrossAndStand() throws {
        var s = try courts()
        s.land["libya"]!.owner = "egypt"
        s.armies["libya"] = nil
        s.land["cyrenaica"]!.owner = "greece"
        s.armies["cyrenaica"] = Army(owner: "greece", units: UnitCounts(infantry: 4))
        #expect(throws: GameError.atPeace("libya")) {
            try engine.apply(.move(from: "cyrenaica", to: "libya", units: UnitCounts(infantry: 2)), to: &s)
        }
        s.regard[Opinion("egypt", about: "greece")] = 60
        try engine.apply(.propose(to: "egypt", .access), to: &s)
        #expect(engine.grantsAccess("egypt", to: "greece", in: s))
        try engine.apply(.move(from: "cyrenaica", to: "libya", units: UnitCounts(infantry: 2)), to: &s)
        #expect(s.armies["libya"]?.owner == "greece")
        #expect(s.owner(of: "libya") == "egypt")
        // Leave withdrawn: they go home.
        s.activePlayerIndex = s.players.firstIndex(of: "egypt")!
        try engine.apply(.revokeAccess(from: "greece"), to: &s)
        #expect(s.armies["libya"] == nil)
        #expect(s.armies["cyrenaica"]?.units.infantry == 4)
    }

    @Test func embargoesCloseTradeRoutes() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["greece", "egypt", "italia"])
        for pair in [CivPair("greece", "egypt"), CivPair("greece", "italia"), CivPair("egypt", "italia")] { s.peace.insert(pair) }
        try #require(engine.tradeRoute(between: "egypt", and: "italia", in: s) != nil)
        s.regard[Opinion("egypt", about: "greece")] = 40
        s.regard[Opinion("egypt", about: "italia")] = -10
        try engine.apply(.propose(to: "egypt", .embargo(against: "italia")), to: &s)
        #expect(engine.tradeRoute(between: "egypt", and: "italia", in: s) == nil)
    }

    @Test func aPersonAnswersOnTheirTurn() throws {
        var s = try courts(egyptHuman: true)
        let events = try engine.apply(.propose(to: "egypt", .pact), to: &s)
        #expect(events == [.dealProposed(from: "greece", to: "egypt", deal: .pact)])
        #expect(engine.pact("greece", "egypt", in: s) == nil)
        try engine.apply(.endTurn, to: &s)
        try engine.apply(.answer(from: "greece", .pact, accept: true), to: &s)
        #expect(engine.pact("greece", "egypt", in: s) != nil)
        #expect(s.proposals.isEmpty)
    }

    @Test func warSoursRegardOverTime() throws {
        var s = try courts()
        s.peace = []
        for _ in 0..<5 { _ = engine.diplomacyRound(&s) }
        #expect(engine.regard(of: "egypt", toward: "greece", in: s) < 0)
    }
}
