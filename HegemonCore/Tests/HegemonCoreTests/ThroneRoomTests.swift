import Testing
@testable import HegemonCore

@Suite struct ThroneRoomTests {
    let engine = try! Engine.bare()

    @Test func decoratingCostsGoldAndStoneAndAddsPrestige() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["egypt"])
        s.civs["egypt"]!.gold = 20
        s.civs["egypt"]!.stock[.stone] = 5
        let before = engine.prestige(of: "egypt", in: s)
        let events = try engine.apply(.decorate("statue"), to: &s)
        #expect(events == [.decorated(civ: "egypt", decoration: "statue")])
        #expect(s.civs["egypt"]!.gold == 10)
        #expect(s.civs["egypt"]!.stock[.stone] == 1)
        #expect(engine.magnificence(of: "egypt", in: s) == 3)
        // Gold spent costs prestige (gold ÷ 2), the statue gives 3 × 2.
        #expect(engine.prestige(of: "egypt", in: s) == before - 5 + 6)
        #expect(throws: GameError.alreadyDecorated("statue")) { try engine.apply(.decorate("statue"), to: &s) }
    }

    @Test func notWithoutTheStone() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["egypt"])
        s.civs["egypt"]!.gold = 20
        #expect(throws: GameError.insufficientStock(.stone, needed: 3, available: 0)) {
            try engine.apply(.decorate("mosaic"), to: &s)
        }
    }

    @Test func takingACapitalWinsItsStandardOnce() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["egypt", "greece"])
        let capture: [GameEvent] = [.captured(civ: "egypt", territory: "greece", from: "greece")]
        _ = engine.awardTrophies(capture, &s)
        _ = engine.awardTrophies(capture, &s)
        #expect(s.civs["egypt"]!.trophies.map(\.kind) == [.standard("greece")])
        #expect(engine.magnificence(of: "egypt", in: s) == 2)
    }

    @Test func splendourEasesSuccession() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["egypt"])
        s.civs["egypt"]!.decorations = ["throne", "statue", "hangings", "mosaic"]
        #expect(engine.magnificence(of: "egypt", in: s) == 10)
        #expect(engine.successionEase(of: "egypt", in: s) == 5)
    }
}
