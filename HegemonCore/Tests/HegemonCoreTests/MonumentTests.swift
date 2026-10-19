import Testing
@testable import HegemonCore

@Suite struct MonumentTests {
    let engine = try! Engine.bare()

    func rich(_ s: inout GameState, _ civ: CivilizationID) {
        s.civs[civ]!.gold = 100
        s.civs[civ]!.stock = [.stone: 20, .timber: 20]
    }

    @Test func aPyramidRisesOnTheNileAndAwesTheLand() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["egypt"])
        rich(&s, "egypt")
        #expect(engine.canRaise("pyramid", in: "egypt", s))
        _ = try engine.apply(.buildMonument(territory: "egypt", monument: "pyramid"), to: &s)
        let before = engine.prestige(of: "egypt", in: s)
        for _ in 0..<engine.rules.monuments.monument("pyramid")!.turns {
            _ = engine.progressMonuments("egypt", &s)
        }
        #expect(engine.holds("pyramid", "egypt", in: s))
        #expect(engine.prestige(of: "egypt", in: s) == before + 40)
        // One in the world: nobody can start another.
        #expect(!engine.canRaise("pyramid", in: "egypt", s))
    }

    @Test func theFirstToFinishWinsTheRace() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["egypt", "greece"])
        s.monumentSites["egypt"] = MonumentSite(id: "library", turnsLeft: 1)
        s.monumentSites["greece"] = MonumentSite(id: "library", turnsLeft: 4)
        let gold = s.civs["greece"]!.gold
        let events = engine.progressMonuments("egypt", &s)
        #expect(events.contains(.monumentLost(civ: "greece", territory: "greece", monument: "library")))
        #expect(s.monumentSites["greece"] == nil)
        #expect(s.civs["greece"]!.gold == gold + 12)
    }

    @Test func wrongGroundIsRefused() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["greece"])
        rich(&s, "greece")
        #expect(throws: GameError.monumentUnavailable("pyramid")) {
            try engine.apply(.buildMonument(territory: "greece", monument: "pyramid"), to: &s)
        }
    }
}
