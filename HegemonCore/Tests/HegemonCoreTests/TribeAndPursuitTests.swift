import Foundation
import Testing
@testable import HegemonCore

@Suite struct TribeTests {
    let engine = try! Engine.calm()

    func game() throws -> GameState {
        var s = try engine.newGame(seed: 1, civilizations: ["egypt"])
        s.civs["egypt"]!.gold = 50
        return s
    }

    @Test func onlyNeighbouringTribesCanBeApproached() throws {
        var s = try game()
        #expect(engine.tribe(at: "libya", for: "egypt", in: s) != nil)
        #expect(engine.tribe(at: "gaul", for: "egypt", in: s) == nil)
        #expect(throws: GameError.noTribe("gaul")) {
            try engine.apply(.parley(territory: "gaul", .gifts), to: &s)
        }
    }

    @Test func overwhelmingForceMakesThemBow() throws {
        var s = try game()
        let warriors = s.armies["libya"]!.units.total
        s.armies["egypt"]!.units = UnitCounts(infantry: warriors * engine.rules.tribes.demandRatio)
        #expect(engine.demandWorks(at: "libya", for: "egypt", in: s))
        let events = try engine.apply(.parley(territory: "libya", .demand), to: &s)
        #expect(s.owner(of: "libya") == "egypt")
        #expect(events.contains { if case .tribeJoined = $0 { true } else { false } })
        #expect(s.armies["libya"]?.owner == "egypt")
    }

    @Test func aRefusedDemandCostsFaceAndStiffensThem() throws {
        var s = try game()
        s.armies["egypt"]!.units = UnitCounts(infantry: 1)
        let warriors = s.armies["libya"]!.units.total
        let legitimacy = s.civs["egypt"]!.legitimacy
        try engine.apply(.parley(territory: "libya", .demand), to: &s)
        #expect(s.owner(of: "libya") == nil)
        #expect(s.armies["libya"]!.units.total == warriors + 1)
        #expect(s.civs["egypt"]!.legitimacy < legitimacy)
        #expect(throws: GameError.alreadyParleyed("libya")) {
            try engine.apply(.parley(territory: "libya", .gifts), to: &s)
        }
    }

    @Test func giftsBuyGoodwillNeverLand() throws {
        var s = try game()
        let k = try #require(engine.kingdom(at: "libya", in: s))
        let before = engine.attitude(of: k, toward: "egypt", in: s)
        let cost = engine.giftCost(at: "libya", in: s)
        let events = try engine.apply(.parley(territory: "libya", .gifts), to: &s)
        #expect(s.civs["egypt"]!.gold == 50 - cost)
        #expect(s.owner(of: "libya") == nil)
        #expect(engine.kingdom(at: "libya", in: s) == k)
        let gained = engine.attitude(of: k, toward: "egypt", in: s) - before
        #expect(gained == engine.rules.minors.giftAttitude || gained == 2 * engine.rules.minors.giftAttitude)
        #expect(events == [.giftsReceived(civ: "egypt", territory: "libya", regard: gained)])
    }
}
