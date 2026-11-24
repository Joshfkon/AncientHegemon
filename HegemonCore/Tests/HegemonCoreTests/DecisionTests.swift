import Testing
@testable import HegemonCore

@Suite struct DecisionTests {
    let engine = try! Engine.bare()

    func court(_ kind: DecisionKind) throws -> GameState {
        var s = try engine.newGame(seed: 1, civilizations: ["egypt"])
        s.civs["egypt"]!.isHuman = true
        s.civs["egypt"]!.decision = kind
        s.civs["egypt"]!.gold = 30
        s.civs["egypt"]!.granary = 10
        return s
    }

    @Test func openingTheGranariesWinsHearts() throws {
        var s = try court(.famine(territory: "egypt", grain: 4))
        let l = s.civs["egypt"]!.legitimacy
        _ = try engine.apply(.decide(accept: true), to: &s)
        #expect(s.civs["egypt"]!.granary == 6)
        #expect(s.civs["egypt"]!.legitimacy == l + engine.rules.decisions.famineLegitimacy)
        #expect(s.civs["egypt"]!.decision == nil)
    }

    @Test func mercenariesJoinAtTheCapital() throws {
        var s = try court(.mercenaries(warriors: 3, gold: 9))
        let before = s.armies["egypt"]?.units.infantry ?? 0
        _ = try engine.apply(.decide(accept: true), to: &s)
        #expect(s.armies["egypt"]!.units.infantry == before + 3)
        #expect(s.civs["egypt"]!.gold == 21)
    }

    @Test func anUnansweredDilemmaIsANo() throws {
        var s = try court(.famine(territory: "egypt", grain: 4))
        let l = s.civs["egypt"]!.legitimacy
        _ = try engine.apply(.endTurn, to: &s)
        #expect(s.civs["egypt"]!.decision == nil || s.activePlayer == "egypt")
        #expect(s.civs["egypt"]!.legitimacy <= l - engine.rules.decisions.famineLegitimacy + 5)
    }

    @Test func offeringsAfterADisasterBuyLegitimacy() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["egypt"])
        s.civs["egypt"]!.isHuman = true
        s.civs["egypt"]!.gold = 30
        let flood = GameEvent.event(EventReport(kind: .flood, civ: "egypt", territory: "egypt", amount: 1))
        _ = engine.offerDecision("egypt", after: [flood], &s)
        let d = engine.rules.decisions
        #expect(s.civs["egypt"]!.decision == .offerings(gold: d.offeringsGold))
        #expect(s.civs["egypt"]!.lastDecision == s.turn)
        let l = s.civs["egypt"]!.legitimacy
        _ = try engine.apply(.decide(accept: true), to: &s)
        #expect(s.civs["egypt"]!.gold == 30 - d.offeringsGold)
        #expect(s.civs["egypt"]!.legitimacy == l + d.offeringsLegitimacy)
    }

    @Test func noDilemmasInTheQuietOpening() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["egypt"])
        s.civs["egypt"]!.isHuman = true
        s.civs["egypt"]!.gold = 30
        s.quietUntil = s.turn + 3
        let flood = GameEvent.event(EventReport(kind: .flood, civ: "egypt", territory: "egypt", amount: 1))
        #expect(engine.offerDecision("egypt", after: [flood], &s).isEmpty)
    }

    @Test func feedingAHungryNeighbourIsRemembered() throws {
        let engine = try Engine.calm()
        var s = try engine.newGame(seed: 1, civilizations: ["egypt"])
        s.civs["egypt"]!.isHuman = true
        s.civs["egypt"]!.granary = 10
        let k = try #require(s.kingdoms.keys.sorted().first)
        let before = engine.attitude(of: k, toward: "egypt", in: s)
        s.civs["egypt"]!.decision = .plea(kingdom: k, grain: 3)
        _ = try engine.apply(.decide(accept: true), to: &s)
        #expect(s.civs["egypt"]!.granary == 7)
        #expect(engine.attitude(of: k, toward: "egypt", in: s) == min(100, before + engine.rules.decisions.pleaAttitude))
    }

    @Test func refusedRaidersStrike() throws {
        let engine = try Engine.calm()
        var s = try engine.newGame(seed: 1, civilizations: ["egypt"])
        s.civs["egypt"]!.isHuman = true
        s.civs["egypt"]!.gold = 30
        let home = try #require(engine.map.territories.first { $0.has(.barbarianHomeland) && s.owner(of: $0.id) == nil }?.id)
        s.civs["egypt"]!.decision = .raiders(homeland: home, target: "egypt", gold: 6)
        var paid = s
        _ = try engine.apply(.decide(accept: true), to: &paid)
        #expect(paid.civs["egypt"]!.gold == 24)
        let events = try engine.apply(.decide(accept: false), to: &s)
        #expect(s.civs["egypt"]!.gold == 30)
        #expect(events.contains { if case let .event(r) = $0 { r.kind == .barbarians && r.territory == "egypt" } else { false } })
    }
}

