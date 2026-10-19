import Testing
@testable import HegemonCore

@Suite struct AllianceTests {
    let engine = try! Engine.bare()

    /// Egypt (the player) and Mesopotamia at peace, both at war with a strong Greece.
    func world() throws -> GameState {
        var s = try engine.newGame(seed: 1, civilizations: ["egypt", "mesopotamia", "greece"])
        s.civs["egypt"]!.isHuman = true
        s.activePlayerIndex = s.players.firstIndex(of: "egypt")!
        s.peace.insert(CivPair("egypt", "mesopotamia"))
        s.armies["greece"]!.units = UnitCounts(infantry: 12)
        s.armies["mesopotamia"]!.units = UnitCounts(infantry: 8)
        return s
    }

    @Test func aCommonDangerousEnemyMakesAnAlly() throws {
        var s = try world()
        let events = try engine.apply(.offerAlliance(to: "mesopotamia"), to: &s)
        #expect(events == [.allianceMade(CivPair("egypt", "mesopotamia"))])
        #expect(engine.allies(of: "egypt", in: s) == ["mesopotamia"])
    }

    @Test func noCommonEnemyNoAlliance() throws {
        var s = try world()
        s.peace.insert(CivPair("mesopotamia", "greece"))
        let events = try engine.apply(.offerAlliance(to: "mesopotamia"), to: &s)
        #expect(events == [.allianceRefused(by: "mesopotamia", to: "egypt")])
    }

    @Test func anAllyJoinsYourWarIfTheEnemyIsNotOverwhelming() throws {
        var s = try world()
        s.peace.insert(CivPair("mesopotamia", "greece"))
        s.alliances.insert(CivPair("egypt", "mesopotamia"))
        let events = try engine.apply(.callToWar(ally: "mesopotamia", against: "greece"), to: &s)
        #expect(events == [.joinedWar(civ: "mesopotamia", against: "greece", ally: "egypt")])
        #expect(s.atWar("mesopotamia", "greece"))
    }

    @Test func anAllyRefusesAHopelessWar() throws {
        var s = try world()
        s.peace.insert(CivPair("mesopotamia", "greece"))
        s.alliances.insert(CivPair("egypt", "mesopotamia"))
        s.armies["greece"]!.units = UnitCounts(infantry: 40)
        let events = try engine.apply(.callToWar(ally: "mesopotamia", against: "greece"), to: &s)
        #expect(events == [.warRefused(by: "mesopotamia", ally: "egypt", against: "greece")])
        #expect(s.atPeace("mesopotamia", "greece"))
    }

    @Test func attackingAnAllyCallsTheOtherToArms() throws {
        var s = try world()
        s.peace.insert(CivPair("mesopotamia", "greece"))
        s.alliances.insert(CivPair("egypt", "mesopotamia"))
        // Greece declares war on Mesopotamia: the person, Egypt, is asked to answer.
        s.peace.insert(CivPair("greece", "egypt"))
        s.activePlayerIndex = s.players.firstIndex(of: "greece")!
        let events = try engine.apply(.declareWar(on: "mesopotamia"), to: &s)
        #expect(events.contains(.calledToWar(WarRequest(from: "mesopotamia", to: "egypt", against: "greece"))))
        // Egypt refuses: the alliance ends and Egypt's standing suffers.
        s.activePlayerIndex = s.players.firstIndex(of: "egypt")!
        let before = s.civs["egypt"]!.legitimacy
        _ = try engine.apply(.answerCallToWar(from: "mesopotamia", against: "greece", join: false), to: &s)
        #expect(!engine.allied("egypt", "mesopotamia", in: s))
        #expect(s.civs["egypt"]!.legitimacy == before - engine.rules.alliances.betrayalLegitimacy)
    }
}
