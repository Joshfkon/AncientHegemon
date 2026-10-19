import Testing
@testable import HegemonCore

@Suite struct UnrestTests {
    let engine = try! Engine.bare()

    @Test func newlyTakenLandIsRestlessUntilGarrisoned() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["egypt"])
        s.land["libya"]!.owner = "egypt"
        s.land["libya"]!.takenOnRound = s.turn
        s.armies["libya"] = nil
        #expect(engine.restless("libya", of: "egypt", in: s))
        s.armies["libya"] = Army(owner: "egypt", units: UnitCounts(infantry: engine.rules.unrest.garrisonToCalm))
        #expect(!engine.restless("libya", of: "egypt", in: s))
        // In time it settles down, garrison or not.
        s.armies["libya"] = nil
        s.turn += engine.rules.unrest.recentRounds
        #expect(!engine.restless("libya", of: "egypt", in: s))
    }

    @Test func restlessLandPaysNoTaxes() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["egypt"])
        s.land["libya"]!.owner = "egypt"
        s.land["libya"]!.population = 6
        s.armies["libya"] = nil
        let calm = engine.economy(of: "egypt", in: s).taxes
        s.land["libya"]!.takenOnRound = s.turn
        #expect(engine.economy(of: "egypt", in: s).taxes < calm)
    }

    @Test func aRunawayIsAMenace() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["egypt", "greece", "italia"])
        #expect(engine.menace(in: s) == nil)
        for t in ["libya", "cyrenaica", "petraea", "syria", "arabia", "cyprus", "crete", "anatolia", "taurus"] {
            s.land[t]!.owner = "egypt"
        }
        #expect(engine.menace(in: s) == "egypt")
    }
}
