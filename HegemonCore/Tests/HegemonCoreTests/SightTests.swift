import Testing
@testable import HegemonCore

@Suite struct SightTests {
    let engine = try! Engine.bare()

    @Test func youSeeYourLandAndWhatBordersIt() throws {
        let s = try engine.newGame(seed: 1, civilizations: ["egypt", "greece"])
        let seen = engine.sight(of: "egypt", in: s)
        #expect(seen.contains("egypt"))
        #expect(engine.map.landNeighbors(of: "egypt").allSatisfy { seen.contains($0) })
        #expect(!seen.contains("hispania"))
        #expect(!seen.contains("greece"))
    }

    @Test func shipsSeeTheCoastsOfTheirSea() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["egypt", "greece"])
        s.fleets.append(Fleet(sea: "atlantic", owner: "egypt", ships: 1))
        #expect(engine.sight(of: "egypt", in: s).contains("hispania"))
    }

    @Test func alliesShareWhatTheySee() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["egypt", "greece", "mesopotamia"])
        #expect(!engine.sight(of: "egypt", in: s).contains("greece"))
        s.alliances.insert(CivPair("egypt", "greece"))
        #expect(engine.sight(of: "egypt", in: s).contains("greece"))
    }

    @Test func merchantsSeeTheirPartnersCapital() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["egypt", "greece"])
        #expect(!engine.sight(of: "egypt", in: s).contains("greece"))
        s.peace.insert(CivPair("egypt", "greece"))
        #expect(engine.sight(of: "egypt", in: s).contains("greece"))
    }

    @Test func greatHostsAreRumoured() {
        #expect(engine.rumoured(UnitCounts(infantry: engine.rules.sight.rumouredArmy)))
        #expect(!engine.rumoured(UnitCounts(infantry: 2)))
    }
}
