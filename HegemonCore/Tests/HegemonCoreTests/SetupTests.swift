import Testing
@testable import HegemonCore

@Suite struct DifficultyTests {
    let engine = try! Engine.calm()

    @Test func easyGivesThePlayerAHeadStart() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["egypt", "greece"])
        s.civs["egypt"]!.isHuman = true
        let before = s.armies["egypt"]?.units.total ?? 0, gold = s.civs["egypt"]!.gold
        engine.prepare(&s, human: "egypt", difficulty: .easy, scenario: nil)
        #expect(s.armies["egypt"]!.units.total == before + engine.rules.difficulty[.easy]!.playerStartUnits)
        #expect(s.civs["egypt"]!.gold == gold + engine.rules.difficulty[.easy]!.playerStartGold)
    }

    @Test func godModeRivalsAreRicherAndBetterArmed() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["egypt", "greece"])
        s.civs["egypt"]!.isHuman = true
        var plain = s
        engine.prepare(&plain, human: "egypt", difficulty: .medium, scenario: nil)
        engine.prepare(&s, human: "egypt", difficulty: .god, scenario: nil)
        #expect(s.armies["greece"]!.units.total == plain.armies["greece"]!.units.total + engine.rules.difficulty[.god]!.aiStartUnits)
        #expect(engine.aiIncomePercent("greece", s) == engine.rules.difficulty[.god]!.aiIncomePercent)
        #expect(engine.aiIncomePercent("egypt", s) == 100)
    }
}

@Suite struct ScenarioTests {
    let engine = try! Engine.calm()

    @Test(arguments: Scenario.all.map(\.id))
    func everyScenarioSetsUpAndPlays(_ id: ScenarioID) throws {
        let scenario = Scenario.named(id)!
        var s = try engine.newGame(seed: 1)
        let human = scenario.suggested[0]
        s.civs[human]!.isHuman = true
        engine.prepare(&s, human: human, difficulty: .medium, scenario: scenario)
        #expect(s.scenario == id)
        #expect(engine.roundLimit(s) == s.turn - 1 + scenario.rounds)
        // Play it out with every court run by the AI: it must end in a victory by the limit.
        for c in s.players { s.civs[c]!.isHuman = false }
        let ais = Dictionary(uniqueKeysWithValues: s.players.map { ($0, AIPlayer(engine: engine, personality: .default(for: $0))) })
        var guardRounds = 0
        while s.winner == nil, guardRounds < 2000 {
            _ = ais[s.activePlayer]!.playTurn(&s)
            guardRounds += 1
        }
        #expect(s.victory != nil)
        #expect((s.victory?.round ?? 99) <= engine.roundLimit(s))
    }

    @Test func holdingTheObjectiveIsWorthPrestige() throws {
        var s = try engine.newGame(seed: 1)
        engine.prepare(&s, human: "egypt", difficulty: .medium, scenario: Scenario.named("kadesh"))
        let meso = engine.prestige(of: "mesopotamia", in: s)
        s.land["syria"]!.owner = "egypt"
        #expect(engine.prestige(of: "mesopotamia", in: s) < meso)
    }
}
