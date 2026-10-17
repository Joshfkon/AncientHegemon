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

    @Test func civsStartWithTheirCapitals() throws {
        let state = try GameState(map: map, seed: 1)
        #expect(state.turn == 1)
        #expect(state.players.count == 4)
        for civ in map.civilizations {
            #expect(state.owner(of: civ.capital) == civ.id)
            #expect(state.territories(of: civ.id) == [civ.capital])
        }
    }

    @Test func subsetOfCivs() throws {
        let state = try GameState(map: map, seed: 1, civilizations: ["greece", "egypt"])
        #expect(state.players == ["greece", "egypt"])
        #expect(state.owner(of: "italia") == nil)
    }

    @Test func rejectsUnknownCiv() {
        #expect(throws: MapError.self) { try GameState(map: map, seed: 1, civilizations: ["atlantis"]) }
    }

    @Test func codableRoundTrip() throws {
        var state = try GameState(map: map, seed: 99)
        _ = state.rng.next()
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(GameState.self, from: data)
        #expect(decoded == state)
    }
}
