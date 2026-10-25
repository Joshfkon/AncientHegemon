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
            _ = ais[s.activePlayer]!.play(&s)
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

@Suite struct QuietOpeningTests {
    let engine = try! Engine.calm()

    /// A guided Greece, holding Macedonia with one soldier, beside a Mesopotamian host in Thrace.
    func guided() throws -> GameState {
        var s = try engine.newGame(seed: 1, civilizations: ["greece", "mesopotamia"])
        s.civs["greece"]!.isHuman = true
        engine.prepare(&s, human: "greece", difficulty: .medium, scenario: nil, guided: true)
        s.land["macedonia"]!.owner = "greece"
        s.armies["macedonia"] = Army(owner: "greece", units: UnitCounts(infantry: 1))
        s.land["thrace"]!.owner = "mesopotamia"
        s.armies["thrace"] = Army(owner: "mesopotamia", units: UnitCounts(infantry: 12))
        // Thrace's other neighbours are already Mesopotamian: Macedonia is the only prize.
        for t in ["dacia", "anatolia"] { s.land[t]!.owner = "mesopotamia"; s.armies[t] = nil }
        s.activePlayerIndex = s.players.firstIndex(of: "mesopotamia")!
        return s
    }

    @Test func rivalsLeaveAGuidedPlayerAloneAtFirst() throws {
        var s = try guided()
        #expect(s.quietUntil == s.turn - 1 + Engine.quietRounds)
        #expect(engine.inQuietOpening("greece", s))
        #expect(!engine.inQuietOpening("mesopotamia", s))
        let ai = AIPlayer(engine: engine, personality: .conqueror)
        let turn = ai.play(&s)
        #expect(!turn.events.contains { if case let .battle(r) = $0 { r.setup.defender.civ == "greece" } else { false } })
        #expect(s.owner(of: "macedonia") == "greece")
    }

    @Test func afterTheQuietOpeningTheyCome() throws {
        var s = try guided()
        s.turn = s.quietUntil! + 1
        #expect(!engine.inQuietOpening("greece", s))
        let ai = AIPlayer(engine: engine, personality: .conqueror)
        _ = ai.play(&s)
        #expect(s.owner(of: "macedonia") == "mesopotamia")
    }

    @Test func noDisastersInTheQuietOpening() throws {
        let stormy = try engine.modified { json in
            var events = json["events"] as! [String: Any]
            events["chancePercent"] = 100
            json["events"] = events
        }
        var s = try guided()
        #expect(stormy.drawEvents("greece", &s).isEmpty)
        s.turn = s.quietUntil! + 1
        #expect(!stormy.drawEvents("greece", &s).isEmpty)
    }
}

@Suite struct PeacefulStartTests {
    let engine = try! Engine.bundled()

    @Test func theEmpiresBeginAtPeace() throws {
        let s = try engine.newGame(seed: 1)
        for a in s.players { for b in s.players where a != b { #expect(s.atPeace(a, b)) } }
        // Natives and kingdoms are another matter.
        #expect(s.atWar("greece", kingdomID("thrace")))
    }

    @Test func scenariosAreWarsAlreadyUnderWay() throws {
        var s = try engine.newGame(seed: 1)
        engine.prepare(&s, human: nil, difficulty: .medium, scenario: Scenario.named("kadesh"))
        #expect(s.atWar("egypt", "mesopotamia"))
    }

    @Test func goingToWarBreaksThePeaceAtACost() throws {
        var s = try engine.newGame(seed: 1)
        let civ = s.activePlayer
        let other = s.players.first { $0 != civ }!
        let legitimacy = s.civs[civ]!.legitimacy
        try engine.apply(.declareWar(on: other), to: &s)
        #expect(s.atWar(civ, other))
        #expect(s.civs[civ]!.legitimacy < legitimacy)
    }
}
