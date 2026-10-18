import Foundation
import Testing
@testable import HegemonCore

@Suite struct DisbandTests {
    let engine = try! Engine.bare()

    @Test func soldiersGoHomeAsPeople() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["egypt"])
        s.armies["egypt"]!.units = UnitCounts(infantry: 4, cavalry: 1)
        s.land["egypt"]!.population = 2
        let gold = s.civs["egypt"]!.gold
        let events = try engine.apply(.disband(territory: "egypt", units: UnitCounts(infantry: 2)), to: &s)
        #expect(s.armies["egypt"]!.units == UnitCounts(infantry: 2, cavalry: 1))
        #expect(s.population(of: "egypt") == 4)
        #expect(s.civs["egypt"]!.gold == gold)  // no refund
        #expect(events == [.disbanded(civ: "egypt", territory: "egypt", units: UnitCounts(infantry: 2), rejoined: 2)])
    }

    @Test func disbandingEveryoneClearsTheArmy() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["egypt"])
        let all = s.armies["egypt"]!.units
        try engine.apply(.disband(territory: "egypt", units: all), to: &s)
        #expect(s.armies["egypt"] == nil)
    }

    @Test func peopleCannotOverfillTheLand() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["egypt"])
        let cap = engine.populationCap(of: "egypt")
        s.land["egypt"]!.population = cap - 1
        s.armies["egypt"]!.units = UnitCounts(infantry: 5)
        try engine.apply(.disband(territory: "egypt", units: UnitCounts(infantry: 5)), to: &s)
        #expect(s.population(of: "egypt") == cap)
    }

    @Test func abroadTheyJustScatter() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["egypt"])
        s.armies["libya"] = Army(owner: "egypt", units: UnitCounts(infantry: 2))
        let before = s.population(of: "libya")
        try engine.apply(.disband(territory: "libya", units: UnitCounts(infantry: 2)), to: &s)
        #expect(s.armies["libya"] == nil)
        #expect(s.population(of: "libya") == before)
    }

    @Test func cannotDisbandMoreThanThereAre() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["egypt"])
        #expect(throws: GameError.insufficientUnits("egypt")) {
            try engine.apply(.disband(territory: "egypt", units: UnitCounts(infantry: 99)), to: &s)
        }
    }
}
