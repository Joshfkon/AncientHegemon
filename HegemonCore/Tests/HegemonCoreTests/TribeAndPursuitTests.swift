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

    @Test func giftsCostGoldAndSometimesWork() throws {
        var joined = 0
        for seed in 1...20 {
            var s = try engine.newGame(seed: UInt64(seed), civilizations: ["egypt"])
            s.civs["egypt"]!.gold = 50
            let cost = engine.giftCost(at: "libya", in: s)
            try engine.apply(.parley(territory: "libya", .gifts), to: &s)
            #expect(s.civs["egypt"]!.gold == 50 - cost)
            if s.owner(of: "libya") == "egypt" { joined += 1 }
        }
        #expect(joined > 0 && joined < 20)
    }
}

@Suite struct PursuitTests {
    let engine = try! Engine.calm()
    var sim: BattleSimulator { BattleSimulator(rules: engine.rules) }

    @Test func holdingTheFieldSparesTheBeaten() {
        func defenderLeft(_ pursue: Bool) -> Int {
            var attacker = BattleArmy(civ: "a", units: UnitCounts(infantry: 10, cavalry: 4), formation: "phalanx")
            attacker.pursue = pursue
            let r = sim.resolve(BattleSetup(attacker: attacker,
                                            defender: BattleArmy(civ: "d", units: UnitCounts(infantry: 5), formation: "phalanx"),
                                            terrain: .plains, seed: 3))
            #expect(r.winner == .attacker)
            #expect((r.pursuit != nil) == pursue)
            return r.defenderSurvivors.total
        }
        #expect(defenderLeft(false) >= defenderLeft(true))
    }
}
