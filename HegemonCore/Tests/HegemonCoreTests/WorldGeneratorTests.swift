import Foundation
import Testing
@testable import HegemonCore

/// Random worlds: the same checks tools/validate_map.py makes of the classic map, plus the art,
/// fair starts and saves.
@Suite struct WorldGeneratorTests {
    static let classic = try! GameMap.bundled()

    static func world(_ seed: UInt64) throws -> GameMap {
        try WorldGenerator.generate(seed: seed, template: classic)
    }

    static func encoded(_ map: GameMap) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(map)
    }

    @Test func aSeedAlwaysMakesTheSameWorld() throws {
        #expect(try Self.encoded(Self.world(42)) == Self.encoded(Self.world(42)))
        #expect(try Self.encoded(Self.world(42)) != Self.encoded(Self.world(43)))
    }

    @Test func aWorldSurvivesASave() throws {
        let map = try Self.world(7)
        let back = try JSONDecoder().decode(GameMap.self, from: Self.encoded(map))
        #expect(try Self.encoded(back) == Self.encoded(map))
        #expect(back.worldSeed == 7)
        #expect(back.version == WorldGenerator.mapVersion)
    }

    @Test(arguments: Array(UInt64(1)...UInt64(60)))
    func everyWorldIsSound(_ seed: UInt64) throws {
        let map = try Self.world(seed)
        let ids = Set(map.territories.map(\.id))
        #expect(ids.count == map.territories.count)
        #expect((30...50).contains(map.territories.count))
        #expect(map.seas.count >= 5)

        // Borders run both ways.
        for t in map.territories {
            #expect(t.grain >= 1)
            for n in map.landNeighbors(of: t.id) {
                #expect(map.landNeighbors(of: n).contains(t.id), "\(t.id)–\(n) one-way")
            }
        }
        // Every sea has a shore; every land and sea can be reached by land or sea.
        for s in map.seas { #expect(!map.coastalTerritories(of: s.id).isEmpty, "\(s.id) has no coast") }
        var reached: Set<String> = [map.territories[0].id]
        var queue = [map.territories[0].id]
        while let node = queue.popLast() {
            let next: [String] = ids.contains(node)
                ? map.landNeighbors(of: node) + map.seas(bordering: node)
                : map.seaNeighbors(of: node) + map.coastalTerritories(of: node)
            for m in next where !reached.contains(m) { reached.insert(m); queue.append(m) }
        }
        #expect(reached.count == map.territories.count + map.seas.count)

        // The four empires, on coasts, apart from one another.
        #expect(map.civilizations.map(\.id) == Self.classic.baseCivilizations.map(\.id))
        for civ in map.civilizations {
            let capital = try #require(map.territory(civ.capital))
            #expect(capital.isCoastal)
            #expect(capital.grain == Self.classic.territory(civ.id)!.grain)
            for other in map.civilizations where other.id != civ.id {
                #expect(!map.areLandAdjacent(civ.capital, other.capital))
            }
        }
        // Tin somewhere, never beside a capital.
        let tin = map.territories.filter { ($0.resources[.tin] ?? 0) > 0 }
        #expect(!tin.isEmpty)
        for t in tin { for civ in map.civilizations { #expect(!map.areLandAdjacent(t.id, civ.capital)) } }

        // Kingdoms everywhere but the capitals and the tribes' homelands.
        let capitals = Set(map.civilizations.map(\.capital))
        for t in map.territories where !capitals.contains(t.id) {
            #expect((map.peoples?[t.id] != nil) != t.has(.barbarianHomeland), "\(t.id) people/homeland")
        }

        // Art for every territory, with its name and army token inside its outline.
        let art = try #require(map.art)
        for t in map.territories {
            let shape = try #require(art.territories[t.id])
            #expect(shape.polygon.count >= 6)
            #expect(Self.inside(shape.token, shape.polygon), "\(t.id) token outside")
            #expect(Self.inside(shape.label, shape.polygon), "\(t.id) label outside")
            for p in shape.polygon { #expect(p[0] >= 100 && p[0] <= 1905 && p[1] >= 5 && p[1] <= 920) }
        }
        for s in map.seas { #expect(art.seas[s.id] != nil) }
    }

    @Test func aGameOnARandomWorldSetsUpAndPlays() throws {
        let engine = try Engine.randomWorld(seed: 11)
        let s = try engine.newGame(seed: 3)
        #expect(s.worldSeed == 11)
        #expect(s.mapVersion == WorldGenerator.mapVersion)
        #expect(!s.kingdoms.isEmpty)
        for k in s.kingdoms.values { #expect(engine.map.peoples?[k.homeland]?.name == k.name) }
        for fleet in s.fleets {
            #expect(engine.map.seas(bordering: engine.map.civilization(fleet.owner)!.capital).contains(fleet.sea))
        }
        let record = try playAIMatch(engine: engine, seed: 3, personalities: [:], maxTurns: 12)
        #expect(record.turns >= 12 || record.winner != nil)
    }

    static func inside(_ p: [Double], _ polygon: [[Double]]) -> Bool {
        var inside = false
        var j = polygon.count - 1
        for i in polygon.indices {
            let a = polygon[i], b = polygon[j]
            if (a[1] > p[1]) != (b[1] > p[1]), p[0] < (b[0] - a[0]) * (p[1] - a[1]) / (b[1] - a[1]) + a[0] { inside.toggle() }
            j = i
        }
        return inside
    }
}
