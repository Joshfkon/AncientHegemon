import Foundation
import Testing
@testable import HegemonCore

@Suite struct RNGTests {
    @Test func sameSeedSameSequence() {
        var a = SeededRNG(seed: 42)
        var b = SeededRNG(seed: 42)
        for _ in 0..<1000 { #expect(a.next() == b.next()) }
    }

    @Test func differentSeedsDiverge() {
        var a = SeededRNG(seed: 1)
        var b = SeededRNG(seed: 2)
        #expect((0..<10).map { _ in a.next() } != (0..<10).map { _ in b.next() })
    }

    /// Pins the algorithm: if this changes, old saves and replays stop reproducing.
    @Test func knownValues() {
        var rng = SeededRNG(seed: 0)
        #expect(rng.next() == 0xE220_A839_7B1D_CDAF)
        #expect(rng.next() == 0x6E78_9E6A_A1B9_65F4)
    }

    @Test func survivesCodableRoundTrip() throws {
        var rng = SeededRNG(seed: 7)
        _ = rng.next()
        var copy = try JSONDecoder().decode(SeededRNG.self, from: JSONEncoder().encode(rng))
        #expect(copy.next() == rng.next())
    }
}

@Suite struct GameStateTests {
    let map = try! GameMap.bundled()
    let rules = try! Rules.bundled()

    @Test func civsStartWithTheirCapitalAndOwnStart() throws {
        let state = try GameState(map: map, rules: rules, seed: 1)
        #expect(state.turn == 1)
        #expect(state.players.count == 4)
        for civ in map.civilizations {
            let realm = [civ.capital] + (rules.start.realms[civ.id] ?? [])
            #expect(state.owner(of: civ.capital) == civ.id)
            #expect(state.territories(of: civ.id) == realm.sorted())
            #expect(state.armies[civ.capital]?.units == rules.start.armies?[civ.id] ?? rules.start.army)
            #expect(state.civs[civ.id]?.granary == rules.start.granaries?[civ.id] ?? rules.start.granary)
            #expect(state.fleets(of: civ.id).first?.ships == rules.start.fleets?[civ.id]?.ships)
            for (field, points) in rules.start.knowledge?[civ.id] ?? [:] {
                #expect(state.civs[civ.id]?.knowledge[field] == points)
            }
            #expect(state.civs[civ.id]?.gold == rules.start.gold)
            #expect(state.general(of: civ.id, at: civ.capital)?.name == rules.start.generals[civ.id]?.name)
        }
    }

    @Test func unclaimedLandHasNativeGarrisons() throws {
        let state = try GameState(map: map, rules: rules, seed: 1)
        let n = rules.start.natives
        for t in map.territories where state.owner(of: t.id) == nil {
            #expect(state.armies[t.id]?.owner == nativesID)
            let base = map.landNeighbors(of: t.id).isEmpty ? n.islandBase ?? n.base : n.base
            #expect(state.armies[t.id]?.units.infantry == base + t.grain / n.grainPerUnit)
        }
        #expect(!state.players.contains(nativesID))
    }

    @Test func populationStartsAtHalfCap() throws {
        let state = try GameState(map: map, rules: rules, seed: 1)
        for t in map.territories {
            #expect(state.population(of: t.id) == rules.startingPopulation(grain: t.grain))
        }
    }

    @Test func subsetOfCivs() throws {
        let state = try GameState(map: map, rules: rules, seed: 1, civilizations: ["greece", "egypt"])
        #expect(state.players == ["greece", "egypt"])
        #expect(state.owner(of: "italia") == nil)
    }

    @Test func rejectsUnknownCiv() {
        #expect(throws: MapError.self) {
            try GameState(map: map, rules: rules, seed: 1, civilizations: ["atlantis"])
        }
    }

    @Test func codableRoundTrip() throws {
        var state = try GameState(map: map, rules: rules, seed: 99)
        _ = state.rng.next()
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(GameState.self, from: data)
        #expect(decoded == state)
    }
}
