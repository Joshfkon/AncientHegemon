import Testing
@testable import HegemonCore

@Suite struct RoadTests {
    let engine = try! Engine.bare()

    /// Egypt holding Petraea and Syria, with roads in Egypt, Petraea and Syria.
    func roads() throws -> GameState {
        var s = try engine.newGame(seed: 1, civilizations: ["egypt"])
        for t in ["petraea", "syria"] {
            s.land[t]!.owner = "egypt"
            s.armies[t] = nil
        }
        for t in ["egypt", "petraea", "syria"] { s.land[t]!.improvements.insert(.road) }
        s.armies["egypt"]!.units = UnitCounts(infantry: 4)
        return s
    }

    @Test func aRoadMarchLeavesOneMoreMove() throws {
        var s = try roads()
        _ = try engine.apply(.move(from: "egypt", to: "petraea", units: UnitCounts(infantry: 4), general: false), to: &s)
        // They can march on, one step further…
        _ = try engine.apply(.move(from: "petraea", to: "syria", units: UnitCounts(infantry: 4), general: false), to: &s)
        #expect(s.armies["syria"]?.units.infantry == 4)
        // …but no further this turn.
        #expect(throws: GameError.insufficientUnits("syria")) {
            try engine.apply(.move(from: "syria", to: "petraea", units: UnitCounts(infantry: 1), general: false), to: &s)
        }
    }

    @Test func noRoadNoSecondMove() throws {
        var s = try roads()
        s.land["petraea"]!.improvements.remove(.road)
        _ = try engine.apply(.move(from: "egypt", to: "petraea", units: UnitCounts(infantry: 4), general: false), to: &s)
        #expect(throws: GameError.insufficientUnits("petraea")) {
            try engine.apply(.move(from: "petraea", to: "syria", units: UnitCounts(infantry: 1), general: false), to: &s)
        }
    }

    @Test func roadsDoNotSpeedAnAttack() throws {
        var s = try roads()
        s.land["petraea"]!.owner = nil
        s.armies["petraea"] = Army(owner: nativesID, units: UnitCounts(infantry: 1))
        #expect(!engine.roadLinks("egypt", "petraea", for: "egypt", in: s))
    }
}

@Suite struct RoadGeneralTests {
    let engine = try! Engine.bare()

    @Test func aGeneralMarchesTwoRoadStepsWithHisTroops() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["egypt"])
        s.land["petraea"]!.owner = "egypt"
        s.land["egypt"]!.improvements.insert(.road)
        s.land["petraea"]!.improvements.insert(.road)
        s.armies["egypt"] = Army(owner: "egypt", units: UnitCounts(infantry: 4))
        let id = s.generals.values.first { $0.owner == "egypt" }!.id
        s.generals[id]!.location = "egypt"
        try engine.apply(.move(from: "egypt", to: "petraea", units: UnitCounts(infantry: 4), general: true), to: &s)
        try engine.apply(.move(from: "petraea", to: "arabia", units: UnitCounts(infantry: 4), general: true), to: &s)
        #expect(s.armies["arabia"]?.owner == "egypt")
        #expect(s.generals.values.contains { $0.owner == "egypt" && $0.location == "arabia" })
    }
}
