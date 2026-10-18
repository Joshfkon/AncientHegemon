import Foundation
import Testing
@testable import HegemonCore

@Suite struct LevyTests {
    let engine = try! Engine.bare()

    @Test func levyGrowsWithThePeopleUpToACap() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["greece"])
        s.land["greece"]!.population = 1
        #expect(engine.levy(at: "greece", s) == 0)
        s.land["greece"]!.population = 7
        #expect(engine.levy(at: "greece", s) == 7 / engine.rules.battle.levy.populationPerUnit)
        s.land["greece"]!.population = 20
        #expect(engine.levy(at: "greece", s) == engine.rules.battle.levy.maxUnits)
        // Native and unclaimed land raises no levy.
        #expect(engine.levy(at: "macedonia", s) == 0)
    }

    @Test func emptyLandWithPeopleIsDefended() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["mesopotamia", "greece"])
        s.land["persia"]!.owner = "greece"
        s.land["persia"]!.population = 8
        s.armies["persia"] = nil
        #expect(engine.defenders(of: "persia", against: "mesopotamia", s)?.levy == engine.levy(at: "persia", s))
        #expect(engine.levy(at: "persia", s) > 0)
        s.armies["mesopotamia"]!.units = UnitCounts(infantry: 1)
        let events = try engine.apply(.move(from: "mesopotamia", to: "persia", units: UnitCounts(infantry: 1)), to: &s)
        #expect(events.contains { if case .battle = $0 { true } else { false } })
    }

    @Test func fallenMilitiaAreLostPeople() throws {
        var s = try engine.newGame(seed: 2, civilizations: ["mesopotamia", "greece"])
        s.land["persia"]!.owner = "greece"
        s.land["persia"]!.population = 8
        s.armies["persia"] = nil
        s.armies["mesopotamia"]!.units = UnitCounts(infantry: 10, cavalry: 4)
        let raised = engine.levy(at: "persia", s)
        let events = try engine.apply(.move(from: "mesopotamia", to: "persia", units: UnitCounts(infantry: 10, cavalry: 4)), to: &s)
        guard case let .battle(report)? = events.first(where: { if case .battle = $0 { true } else { false } }) else {
            Issue.record("no battle")
            return
        }
        #expect(raised > 0)
        #expect(report.setup.defender.levy == raised)
        #expect(report.frames[0].blocks.contains { $0.levy })
        #expect(s.population(of: "persia") == max(engine.rules.economy.minPopulation, 8 - (raised - report.defenderLevySurvivors)))
        #expect(report.defenderSurvivors.isEmpty)  // the levy isn't a standing army
    }

    @Test func levyStiffensAGarrison() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["mesopotamia", "greece"])
        s.land["persia"]!.owner = "greece"
        s.armies["persia"] = Army(owner: "greece", units: UnitCounts(infantry: 3))
        s.land["persia"]!.population = 1
        let alone = engine.attackOdds("mesopotamia", units: UnitCounts(infantry: 5), into: "persia", samples: 40, in: s)!
        s.land["persia"]!.population = 8
        let withLevy = engine.attackOdds("mesopotamia", units: UnitCounts(infantry: 5), into: "persia", samples: 40, in: s)!
        #expect(withLevy < alone)
    }
}
