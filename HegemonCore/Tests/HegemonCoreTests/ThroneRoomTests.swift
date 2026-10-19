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

    @Test func everyConquestBringsSpoils() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["egypt", "greece"])
        for t in ["libya", "cyrenaica"] {
            _ = engine.awardTrophies([.captured(civ: "egypt", territory: t, from: nil)], &s)
        }
        #expect(s.civs["egypt"]!.trophies.map(\.kind) == [.spoils("libya"), .spoils("cyrenaica")])
        #expect(engine.magnificence(of: "egypt", in: s) == 2)
        // Spoils stop counting past the cap.
        for i in 0..<20 { s.civs["egypt"]!.trophies.append(Trophy(kind: .spoils("x\(i)"), round: 1)) }
        #expect(engine.magnificence(of: "egypt", in: s) == engine.rules.throneRoom.spoilsCap)
    }

    @Test func aSplendidCourtShoresUpTheThroneAndCharmsTribes() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["egypt"])
        s.land["libya"]!.owner = nil
        let plainLegitimacy = engine.taxAndLuxuryLegitimacy("egypt", s)
        let plainGifts = engine.giftChance(at: "libya", for: "egypt", in: s)
        s.civs["egypt"]!.decorations = ["throne", "statue", "hangings", "mosaic"]  // magnificence 10
        #expect(engine.courtLegitimacy(of: "egypt", in: s) == 2)
        #expect(engine.taxAndLuxuryLegitimacy("egypt", s) == plainLegitimacy + 2)
        #expect(engine.giftChance(at: "libya", for: "egypt", in: s) >= min(engine.rules.tribes.giftChanceMax, plainGifts + 10))
    }

    @Test func splendourEasesSuccession() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["egypt"])
        s.civs["egypt"]!.decorations = ["throne", "statue", "hangings", "mosaic"]
        #expect(engine.magnificence(of: "egypt", in: s) == 10)
        #expect(engine.successionEase(of: "egypt", in: s) == 5)
    }
}
