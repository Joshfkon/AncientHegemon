import Testing
@testable import HegemonCore

@Suite struct VeteranTests {
    let engine = try! Engine.bare()

    @Test func ranksFollowBattlesSurvived() {
        #expect(engine.rank(battles: 0) == .green)
        #expect(engine.rank(battles: 1) == .blooded)
        #expect(engine.rank(battles: 3) == .veteran)
        #expect(engine.rank(battles: 6) == .elite)
    }

    @Test func survivorsOfABattleAreSeasoned() throws {
        var s = try engine.newGame(seed: 2, civilizations: ["egypt"])
        s.armies["egypt"]!.units = UnitCounts(infantry: 8)
        s.armies["libya"] = Army(owner: nativesID, units: UnitCounts(infantry: 1))
        _ = try engine.apply(.move(from: "egypt", to: "libya", units: UnitCounts(infantry: 8), general: false), to: &s)
        let army = try #require(s.armies["libya"])
        #expect(army.owner == "egypt")
        #expect(army.battles == 1)
        #expect(engine.rank(of: army) == .blooded)
    }

    @Test func greenRecruitsDiluteHonours() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["egypt"])
        s.armies["egypt"]!.units = UnitCounts(infantry: 3)
        s.armies["egypt"]!.battles = 4
        s.civs["egypt"]!.gold = 50
        s.land["egypt"]!.population = 8
        _ = try engine.apply(.recruit(territory: "egypt", unit: .infantry, count: 1), to: &s)
        #expect(s.armies["egypt"]!.battles == 3)  // (4×3 + 0×1) / 4
    }

    @Test func veteransFightHarder() throws {
        let s = try engine.newGame(seed: 1, civilizations: ["egypt"])
        let green = engine.battleArmy("egypt", UnitCounts(infantry: 4), plan: BattlePlan(), general: nil, s)
        let elite = engine.battleArmy("egypt", UnitCounts(infantry: 4), plan: BattlePlan(), general: nil, battles: 5, s)
        #expect(elite.unitPercent[.infantry]! == (green.unitPercent[.infantry] ?? 0) + 3 * engine.rules.veterans.strengthPercentPerRank)
        #expect(elite.morale == green.morale + 3 * engine.rules.veterans.moralePerRank)
    }

    @Test func honoursSailWithTheTroops() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["egypt"])
        s.armies["egypt"]!.units = UnitCounts(infantry: 2)
        s.armies["egypt"]!.battles = 3
        s.fleets = [Fleet(sea: "eastern_med", owner: "egypt", ships: 1)]
        _ = try engine.apply(.embark(territory: "egypt", sea: "eastern_med", units: UnitCounts(infantry: 2)), to: &s)
        #expect(s.fleets[0].cargoBattles == 3)
        s.land["libya"]!.owner = "egypt"
        s.armies["libya"] = nil
        _ = try engine.apply(.land(sea: "eastern_med", territory: "libya", units: UnitCounts(infantry: 2)), to: &s)
        #expect(s.armies["libya"]?.battles == 3)
    }
}
