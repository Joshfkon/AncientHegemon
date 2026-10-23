import Foundation
import Testing
@testable import HegemonCore

/// Expansion empires (DESIGN.md, "Paid expansions"): defined by data alone, seated only when a
/// game asks for them, and playable on the classic board and on generated worlds.
@Suite struct ExpansionTests {
    static let everyone = ["greece", "egypt", "italia", "mesopotamia", "hatti"]

    @Test func theClassicFourAreTheDefaultTable() throws {
        let engine = try Engine.bundled()
        #expect(engine.map.baseCivilizations.map(\.id) == ["greece", "egypt", "italia", "mesopotamia"])
        #expect(engine.map.civilization("hatti")?.expansion == "hittites")
        let s = try engine.newGame(seed: 1)
        #expect(s.players.count == 4)
        #expect(s.civs["hatti"] == nil)
        // Without the Hittites, Anatolia is the Hatti kingdom's, as before.
        #expect(s.armies["anatolia"]?.owner == kingdomID("anatolia"))
    }

    @Test func theHittitesHoldAnatoliaOnTheClassicBoard() throws {
        let engine = try Engine.bundled()
        let s = try engine.newGame(seed: 1, civilizations: Self.everyone)
        #expect(s.players.count == 5)
        #expect(s.owner(of: "anatolia") == "hatti")
        #expect(s.kingdoms[kingdomID("anatolia")] == nil)
        #expect(s.armies["anatolia"]?.owner == "hatti")
        #expect(s.armies["anatolia"]?.units == UnitCounts(infantry: 2, cavalry: 1))
        #expect(s.civs["hatti"]!.government == .monarchy)
        #expect(s.civs["hatti"]!.granary == 20)
        #expect(s.civs["hatti"]!.heir != nil)
        #expect(engine.rules.names["hatti"]!.rulers.contains(s.civs["hatti"]!.ruler.name))
        #expect(s.generals.values.contains { $0.owner == "hatti" && $0.name == "Muwatalli" })
        // The rest of the board is as it is without them.
        let base = try engine.newGame(seed: 1)
        for t in engine.map.territories.map(\.id) where t != "anatolia" {
            #expect(s.armies[t]?.units == base.armies[t]?.units)
        }
    }

    @Test func personalitiesComeFromTheMap() {
        #expect(Personality.default(for: "greece").name == "merchant")
        #expect(Personality.default(for: "egypt").name == "turtle")
        #expect(Personality.default(for: "italia").name == "conqueror")
        #expect(Personality.default(for: "mesopotamia").name == "opportunist")
        #expect(Personality.default(for: "hatti").name == "opportunist")
        #expect(Personality.default(for: "rebels-of-somewhere").name == "opportunist")
    }

    @Test func aClassicWorldIsUnchangedByTheCatalog() throws {
        let classic = try GameMap.bundled()
        let explicit = try WorldGenerator.generate(seed: 42, template: classic,
                                                   civilizations: ["greece", "egypt", "italia", "mesopotamia"])
        let implicit = try WorldGenerator.generate(seed: 42, template: classic)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        #expect(try encoder.encode(explicit) == encoder.encode(implicit))
        #expect(implicit.civilizations.map(\.id) == ["greece", "egypt", "italia", "mesopotamia"])
    }

    @Test(arguments: Array(UInt64(1)...UInt64(30)))
    func everyWorldSeatsTheHittites(_ seed: UInt64) throws {
        let map = try WorldGenerator.generate(seed: seed, template: .bundled(), civilizations: Self.everyone)
        #expect(map.civilizations.map(\.id) == Self.everyone)
        #expect(map.civilization("hatti")?.expansion == "hittites")
        let capitals = map.civilizations.map(\.capital)
        #expect(Set(capitals).count == 5)
        for c in capitals {
            #expect(!map.seas(bordering: c).isEmpty)
            for d in capitals where d != c { #expect(!map.landNeighbors(of: c).contains(d)) }
        }
        // The Hittites' homeland keeps Anatolia's character, and no minor people is also "Hatti".
        let home = map.territory("hatti")!
        let anatolia = try GameMap.bundled().territory("anatolia")!
        #expect(home.name == "Anatolia")
        #expect(home.grain == anatolia.grain)
        #expect(home.terrain == anatolia.terrain)
        #expect(!(map.peoples ?? [:]).values.contains { $0.name == "Hatti" })
        let s = try Engine(map: map, rules: .bundled()).newGame(seed: seed, civilizations: Self.everyone)
        #expect(s.owner(of: "hatti") == "hatti")
    }

    @Test func theAIPlaysTheHittitesToAnEnd() throws {
        let engine = try Engine.bundled()
        let record = try playAIMatch(engine: engine, seed: 3, personalities: [:],
                                     civilizations: shuffledTurnOrder(Self.everyone, seed: 3), maxTurns: 25)
        #expect(record.civs["hatti"]?.personality == "opportunist")
        #expect(record.civs["hatti"]!.peakTerritories > 1)
        #expect(record.civs["hatti"]!.rejectedCommands == 0)
    }

    @Test func aHittiteGameOnAGeneratedWorldPlays() throws {
        let engine = try Engine.randomWorld(seed: 11, civilizations: Self.everyone)
        let record = try playAIMatch(engine: engine, seed: 11, personalities: [:],
                                     civilizations: Self.everyone, maxTurns: 15)
        #expect(record.civs["hatti"]!.rejectedCommands == 0)
        #expect(record.finalState.worldSeed == 11)
    }
}
