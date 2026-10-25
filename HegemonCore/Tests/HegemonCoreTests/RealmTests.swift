import Testing
@testable import HegemonCore

/// What war costs a realm and what building gives it (DESIGN.md, "War costs the realm").
@Suite struct RealmTests {
    let engine = try! Engine.bare()

    func egypt() throws -> GameState {
        try engine.newGame(seed: 1, civilizations: ["egypt"])
    }

    @Test func farmsMakeRoomForMorePeople() throws {
        var s = try egypt()
        let before = engine.populationCap(of: "egypt", in: s)
        s.land["egypt"]!.improvements.insert(.farm)
        #expect(engine.populationCap(of: "egypt", in: s) == engine.territoryYield(.grain, "egypt", s))
        #expect(engine.populationCap(of: "egypt", in: s) > before)
    }

    @Test func theStandingArmyAndTheWarFooting() throws {
        var s = try egypt()
        s.land["egypt"]!.population = 6
        #expect(engine.standingArmy(of: "egypt", in: s) == 6)
        #expect(engine.warFooting(people: 6) == 12)
        s.armies["egypt"]!.units = UnitCounts(infantry: 12)
        #expect(!engine.overMobilized("egypt", in: s))
        s.armies["egypt"]!.units = UnitCounts(infantry: 13)
        #expect(engine.overMobilized("egypt", in: s))
    }

    @Test func nobodyGrowsOnAWarFooting() throws {
        var s = try egypt()
        s.land["egypt"]!.population = 2
        s.land["egypt"]!.improvements.insert(.farm)
        #expect(engine.territoryYield(.grain, "egypt", s) == 10)
        // Footing 3 + 3 = 6. Six under arms: 10 grain feed 1 + 6, and the people grow.
        s.armies["egypt"]!.units = UnitCounts(infantry: 6)
        var a = s
        _ = engine.harvest("egypt", &a)
        #expect(a.population(of: "egypt") == 3)
        // Seven: there is still grain to spare, but nobody marries.
        s.armies["egypt"]!.units = UnitCounts(infantry: 7)
        _ = engine.harvest("egypt", &s)
        #expect(s.population(of: "egypt") == 2)
    }

    @Test func taxesThinWithDistanceAndNewLandPaysHalf() throws {
        var s = try egypt()
        let near = engine.map.landNeighbors(of: "egypt").sorted().first!
        s.land[near]!.owner = "egypt"
        s.armies[near] = Army(owner: "egypt", units: UnitCounts(infantry: 1))
        #expect(engine.taxPercent(near, of: "egypt", in: s) == 100)
        #expect(engine.taxPercent(near, of: "egypt", in: s, distances: [near: 4]) == 80)
        #expect(engine.taxPercent(near, of: "egypt", in: s, distances: [near: 12]) == engine.rules.realm.minTaxPercent)
        // Newly won (and garrisoned): half. Without its garrison it is restless and pays nothing.
        s.land[near]!.takenOnRound = s.turn
        #expect(engine.taxPercent(near, of: "egypt", in: s) == 50)
        s.armies[near] = nil
        #expect(engine.taxPercent(near, of: "egypt", in: s) == 0)
    }

    @Test func thePeopleRiseInProportionToTheirNumbers() throws {
        var s = try egypt()
        s.land["egypt"]!.population = 8
        #expect(engine.levy(at: "egypt", s) == 4)
        s.land["egypt"]!.population = 20
        #expect(engine.levy(at: "egypt", s) == engine.rules.battle.levy.maxUnits)
    }

    @Test func buildingsAndTradeCountTowardTheLegacy() throws {
        var s = try egypt()
        let before = engine.prestige(of: "egypt", in: s)
        s.land["egypt"]!.improvements.formUnion([.granary, .drains])
        #expect(engine.prestige(of: "egypt", in: s) == before + 2 * engine.rules.victory.prestige.perBuilding)
        #expect(engine.prestigeBreakdown(of: "egypt", in: s).contains { $0.source == "2 buildings" })
    }
}
