import Testing
@testable import HegemonCore

@Suite struct ArmyPayTests {
    let engine = try! Engine.bare()

    @Test func everyFourSoldiersDrawAGold() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["egypt"])
        s.armies["egypt"]!.units = UnitCounts(infantry: 9)
        #expect(engine.armyPay(of: "egypt", in: s) == 2)
        s.civs["egypt"]!.gold = 20
        let events = engine.payArmy("egypt", &s)
        #expect(s.civs["egypt"]!.gold == 18)
        #expect(events == [.armyPaid(civ: "egypt", gold: 2, deserted: 0)])
    }

    @Test func aSmallGuardIsFree() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["egypt"])
        s.armies["egypt"]!.units = UnitCounts(infantry: 3)
        #expect(engine.armyPay(of: "egypt", in: s) == 0)
        #expect(engine.payArmy("egypt", &s).isEmpty)
    }

    @Test func unpaidSoldiersGoHome() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["egypt"])
        s.armies["egypt"]!.units = UnitCounts(infantry: 12)
        s.civs["egypt"]!.gold = 1
        let events = engine.payArmy("egypt", &s)
        // 3 owed, 1 paid: 8 soldiers unpaid, half of them leave.
        #expect(s.civs["egypt"]!.gold == 0)
        #expect(s.armies["egypt"]!.units.total == 8)
        #expect(events == [.armyPaid(civ: "egypt", gold: 1, deserted: 4)])
    }
}

@Suite struct HaulTests {
    let engine = try! Engine.bare()

    /// Egypt holding the coast west to Numidia, three land steps away.
    func westward() throws -> GameState {
        var s = try engine.newGame(seed: 1, civilizations: ["egypt"])
        for t in ["libya", "cyrenaica", "numidia"] {
            s.land[t]!.owner = "egypt"
            s.armies[t] = nil
        }
        s.armies["numidia"] = Army(owner: "egypt", units: UnitCounts(infantry: 4))
        return s
    }

    @Test func cartingGrainFarOverlandCostsMore() throws {
        let s = try westward()
        let haul = try #require(engine.haul(of: "egypt", to: "numidia", in: s))
        #expect(haul.steps == 3)
        #expect(haul.extraGrain == 1)
        #expect(engine.economy(of: "egypt", in: s).eatenByDistance == 4)
    }

    @Test func roadsCarryItFree() throws {
        var s = try westward()
        s.land["cyrenaica"]!.improvements.insert(.road)
        #expect(engine.haul(of: "egypt", to: "numidia", in: s)?.extraGrain == 0)
    }

    @Test func shipsCarryItFree() throws {
        var s = try westward()
        s.fleets = [Fleet(sea: "eastern_med", owner: "egypt", ships: 1)]
        // From Egypt by ship along the coast to Libya and Cyrenaica's sea lanes: fewer cart steps.
        let byShip = try #require(engine.haul(of: "egypt", to: "numidia", in: s))
        #expect(byShip.steps < 3)
        #expect(engine.supplySteps(of: "egypt", to: "numidia", in: s) == 3)
    }
}
