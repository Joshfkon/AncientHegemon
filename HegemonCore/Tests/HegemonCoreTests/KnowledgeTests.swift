import Foundation
import Testing
@testable import HegemonCore

@Suite struct KnowledgeTests {
    let engine = try! Engine.calm()

    @Test func knowledgeFollowsExperience() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["egypt"])
        s.civs["egypt"]!.experience = [.seafaring: 50]
        for _ in 0..<6 { try engine.apply(.endTurn, to: &s) }
        let k = s.civs["egypt"]!.knowledge
        #expect((k[.seafaring] ?? 0) > (k[.warfare] ?? 0))
        #expect(engine.revealedFields(of: "egypt", in: s).contains(.seafaring))
    }

    @Test func fieldsWithoutExperienceStayHidden() throws {
        let s = try engine.newGame(seed: 1, civilizations: ["egypt"])
        #expect(engine.revealedFields(of: "egypt", in: s).isEmpty)
        #expect(engine.level(.seafaring, of: "egypt", in: s) == 0)
    }

    @Test func discoveriesAreAnnounced() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["egypt"])
        s.civs["egypt"]!.knowledge[.metallurgy] = engine.rules.knowledge.levels[1] - 1
        s.civs["egypt"]!.experience = [.metallurgy: 100]
        let events = try engine.apply(.endTurn, to: &s)
        #expect(events.contains(.discovery(civ: "egypt", field: .metallurgy, level: 2)))
        #expect(engine.levelName(.metallurgy, 2) == "Ironworking")
    }

    @Test func contactSpreadsKnowledge() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["mesopotamia", "egypt"])
        s.land["syria"]!.owner = "mesopotamia"
        s.land["petraea"]!.owner = "egypt"  // Syria borders Petraea
        s.civs["egypt"]!.knowledge[.seafaring] = 500
        s.activePlayerIndex = 1
        try engine.apply(.endTurn, to: &s)   // Mesopotamia's harvest
        #expect((s.civs["mesopotamia"]!.knowledge[.seafaring] ?? 0) > 0)
    }

    @Test func ironIsRockUntilIronworking() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["greece"])
        s.land["anatolia"]!.owner = "greece"  // iron 2, reached by sea
        #expect(engine.effectiveYield(of: .iron, for: "greece", in: s) == 0)
        s.civs["greece"]!.knowledge[.metallurgy] = engine.rules.knowledge.levels[1]
        #expect(engine.effectiveYield(of: .iron, for: "greece", in: s) == 2)
    }

    @Test func knowledgeSharpensArmiesAndShips() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["greece"])
        let plain = engine.battleArmy("greece", UnitCounts(infantry: 1, cavalry: 1), formation: nil, general: nil, s)
        #expect(plain.unitPercent[.cavalry] == 0)
        #expect(engine.shipCapacity("greece", s) == engine.rules.ships.capacity)
        s.civs["greece"]!.knowledge[.horsemanship] = engine.rules.knowledge.levels[0]
        s.civs["greece"]!.knowledge[.seafaring] = engine.rules.knowledge.levels[0]
        let riders = engine.battleArmy("greece", UnitCounts(infantry: 1, cavalry: 1), formation: nil, general: nil, s)
        #expect(riders.unitPercent[.cavalry] == engine.rules.knowledge.effects.chariotsPercent)
        #expect(engine.shipCapacity("greece", s) == engine.rules.ships.capacity + engine.rules.knowledge.effects.galleysCapacity)
    }

    @Test func battlesTeachWarfare() throws {
        let bare = try Engine.bare()
        var s = try bare.newGame(seed: 1, civilizations: ["mesopotamia", "greece"])
        s.land["persia"]!.owner = "greece"
        s.armies["persia"] = Army(owner: "greece", units: UnitCounts(infantry: 1))
        s.armies["mesopotamia"]!.units = UnitCounts(infantry: 6, cavalry: 3)
        try bare.apply(.move(from: "mesopotamia", to: "persia", units: UnitCounts(infantry: 6, cavalry: 3)), to: &s)
        #expect((s.civs["mesopotamia"]!.experience[.warfare] ?? 0) > 0)
        #expect((s.civs["mesopotamia"]!.experience[.horsemanship] ?? 0) > 0)
        #expect((s.civs["greece"]!.experience[.warfare] ?? 0) > 0)
    }
}
