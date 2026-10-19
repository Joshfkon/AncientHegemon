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
}
