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

@Suite struct AISightTests {
    let engine = try! Engine.bare()

    /// Mesopotamia hemmed in by a peaceful Egypt, which keeps one great host somewhere.
    private func hemmedIn(hostAt place: TerritoryID) throws -> GameState {
        var s = try engine.newGame(seed: 1, civilizations: ["mesopotamia", "egypt"])
        s.peace.insert(CivPair("mesopotamia", "egypt"))
        for n in engine.map.landNeighbors(of: "mesopotamia") { s.land[n]!.owner = "egypt" }
        s.land["hispania"]!.owner = "egypt"
        s.armies["mesopotamia"] = Army(owner: "mesopotamia", units: UnitCounts(infantry: 12))
        s.armies[place] = Army(owner: "egypt", units: UnitCounts(infantry: 30))
        return s
    }

    private func declaresWar(_ s: GameState) -> Bool {
        var s = s
        var turn = AITurn()
        AIPlayer(engine: engine, personality: .conqueror).diplomacy("mesopotamia", &s, &turn)
        return s.atWar("mesopotamia", "egypt")
    }

    @Test func aiIsNotDeterredByAHostItCannotSee() throws {
        // Far off in Hispania, the host is only a rumour of a great army, not its true size.
        let s = try hemmedIn(hostAt: "hispania")
        #expect(!engine.sight(of: "mesopotamia", in: s).contains("hispania"))
        #expect(declaresWar(s))
    }

    @Test func aiIsDeterredByAHostItCanSee() throws {
        // In Egypt's capital, which Mesopotamia's merchants visit, the same host is seen in full.
        let s = try hemmedIn(hostAt: "egypt")
        #expect(engine.sight(of: "mesopotamia", in: s).contains("egypt"))
        #expect(!declaresWar(s))
    }

    @Test func unseenLandIsAssumedGarrisoned() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["mesopotamia", "egypt"])
        s.land["hispania"]!.owner = "egypt"
        s.armies["hispania"] = Army(owner: "egypt", units: UnitCounts(infantry: 5))
        let sight = engine.sight(of: "mesopotamia", in: s)
        let army = engine.perceivedArmy(at: "hispania", by: "mesopotamia", sight: sight, in: s)
        #expect(army?.owner == "egypt")
        #expect(army?.units == engine.rules.sight.assumedGarrison)
        // Unclaimed land out of sight is assumed to hold the tribe that lived there.
        let full = try Engine.bundled()
        var w = try full.newGame(seed: 1, civilizations: ["mesopotamia"])
        w.armies["gaul"] = nil
        let tribe = full.perceivedArmy(at: "gaul", by: "mesopotamia", sight: full.sight(of: "mesopotamia", in: w), in: w)
        #expect(tribe?.owner == nativesID)
        #expect(tribe?.units == full.rules.start.natives.tribe(in: full.map.territory("gaul")!, island: false))
    }
}
