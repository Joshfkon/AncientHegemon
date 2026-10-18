import Foundation
import Testing
@testable import HegemonCore

// Expected numbers below follow the bundled rules.json. If those values are rebalanced, update
// the arithmetic in the comments along with the expectations.

@Suite struct RecruitTests {
    let engine = try! Engine.bare()

    @Test func recruitCostsGoldAndPopulation() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["mesopotamia", "greece"])
        // Mesopotamia: grain 9, population 5, gold 6, 2 infantry.
        try engine.apply(.recruit(territory: "mesopotamia", unit: .infantry, count: 2), to: &s)
        #expect(s.civs["mesopotamia"]!.gold == 2)
        #expect(s.population(of: "mesopotamia") == 3)
        #expect(s.armies["mesopotamia"]!.units == UnitCounts(infantry: 4))
        #expect(throws: GameError.insufficientGold(needed: 2, available: 0)) {
            var s2 = s
            s2.civs["mesopotamia"]!.gold = 0
            try engine.apply(.recruit(territory: "mesopotamia", unit: .archers, count: 1), to: &s2)
        }
    }

    @Test func recruitKeepsMinimumPopulation() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["greece"])
        // Greece: grain 3, population 2.
        #expect(throws: GameError.insufficientPopulation("greece")) {
            try engine.apply(.recruit(territory: "greece", unit: .infantry, count: 2), to: &s)
        }
    }

    @Test func recruitOnlyInOwnTerritory() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["mesopotamia", "egypt"])
        #expect(throws: GameError.notOwner("egypt")) {
            try engine.apply(.recruit(territory: "egypt", unit: .infantry, count: 1), to: &s)
        }
        #expect(throws: GameError.invalidCount) {
            try engine.apply(.recruit(territory: "mesopotamia", unit: .infantry, count: 0), to: &s)
        }
    }

    @Test func cavalryNeedsHorses() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["mesopotamia"])
        s.civs["mesopotamia"]!.gold = 100
        #expect(throws: GameError.resourceLimit(.horses)) {
            try engine.apply(.recruit(territory: "mesopotamia", unit: .cavalry, count: 1), to: &s)
        }
        // Media yields 2 horses: two cavalry per turn.
        try engine.apply(.move(from: "mesopotamia", to: "media", units: UnitCounts(infantry: 1)), to: &s)
        try engine.apply(.recruit(territory: "mesopotamia", unit: .cavalry, count: 2), to: &s)
        #expect(throws: GameError.resourceLimit(.horses)) {
            try engine.apply(.recruit(territory: "mesopotamia", unit: .cavalry, count: 1), to: &s)
        }
        try engine.apply(.endTurn, to: &s)
        try engine.apply(.recruit(territory: "mesopotamia", unit: .cavalry, count: 1), to: &s)
        #expect(s.armies["mesopotamia"]!.units.cavalry == 3)
    }
}

@Suite struct MoveTests {
    let engine = try! Engine.bare()

    @Test func moveCapturesUnownedTerritory() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["mesopotamia", "greece"])
        let events = try engine.apply(
            .move(from: "mesopotamia", to: "media", units: UnitCounts(infantry: 1)), to: &s)
        #expect(events.contains(.captured(civ: "mesopotamia", territory: "media", from: nil)))
        #expect(s.owner(of: "media") == "mesopotamia")
        #expect(s.armies["media"]!.units.infantry == 1)
        #expect(s.armies["mesopotamia"]!.units.infantry == 1)
    }

    @Test func emptiedTerritoryStaysOwned() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["mesopotamia"])
        try engine.apply(.move(from: "mesopotamia", to: "media", units: UnitCounts(infantry: 2)), to: &s)
        #expect(s.armies["mesopotamia"] == nil)
        #expect(s.owner(of: "mesopotamia") == "mesopotamia")
    }

    @Test func unitsMoveOncePerTurn() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["mesopotamia"])
        try engine.apply(.move(from: "mesopotamia", to: "media", units: UnitCounts(infantry: 1)), to: &s)
        #expect(throws: GameError.insufficientUnits("media")) {
            try engine.apply(.move(from: "media", to: "mesopotamia", units: UnitCounts(infantry: 1)), to: &s)
        }
        #expect(throws: GameError.insufficientUnits("mesopotamia")) {
            try engine.apply(.move(from: "mesopotamia", to: "persia", units: UnitCounts(infantry: 2)), to: &s)
        }
        try engine.apply(.endTurn, to: &s)
        try engine.apply(.move(from: "media", to: "mesopotamia", units: UnitCounts(infantry: 1)), to: &s)
        #expect(s.armies["mesopotamia"]!.units.infantry == 2)
    }

    @Test func movesNeedLandBorder() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["mesopotamia"])
        #expect(throws: GameError.notAdjacent("mesopotamia", "egypt")) {
            try engine.apply(.move(from: "mesopotamia", to: "egypt", units: UnitCounts(infantry: 1)), to: &s)
        }
    }

    @Test func failedCommandLeavesStateUnchanged() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["mesopotamia"])
        let before = s
        _ = try? engine.apply(.move(from: "mesopotamia", to: "egypt", units: UnitCounts(infantry: 1)), to: &s)
        _ = try? engine.apply(.recruit(territory: "mesopotamia", unit: .infantry, count: 99), to: &s)
        #expect(s == before)
    }

    @Test func capturingLastTerritoryEliminatesAndWins() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["mesopotamia", "greece"])
        // Strip Greece down to an undefended Media.
        s.land["greece"]!.owner = nil
        s.armies["greece"] = nil
        s.land["media"]!.owner = "greece"
        let events = try engine.apply(
            .move(from: "mesopotamia", to: "media", units: UnitCounts(infantry: 1)), to: &s)
        #expect(events.contains(.eliminated(civ: "greece")))
        #expect(events.contains(.victory(civ: "mesopotamia")))
        #expect(s.winner == "mesopotamia")
        #expect(throws: GameError.gameOver) { try engine.apply(.endTurn, to: &s) }
    }
}

@Suite struct TurnTests {
    let engine = try! Engine.bare()

    @Test func turnOrderAndCounter() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["greece", "egypt", "italia"])
        #expect(s.activePlayer == "greece")
        try engine.apply(.endTurn, to: &s)
        #expect(s.activePlayer == "egypt")
        #expect(s.turn == 1)
        try engine.apply(.endTurn, to: &s)
        try engine.apply(.endTurn, to: &s)
        #expect(s.activePlayer == "greece")
        #expect(s.turn == 2)
    }

    @Test func eliminatedPlayersAreSkipped() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["greece", "egypt", "italia"])
        s.civs["egypt"]!.eliminated = true
        try engine.apply(.endTurn, to: &s)
        #expect(s.activePlayer == "italia")
    }

    @Test func surplusGrowsPopulationAndFillsGranary() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["mesopotamia"])
        // Production 9; eaten ceil(5/2)=3 by people + 2 by infantry = 5; surplus 4.
        // One person grows (cap 1/territory/turn), 3 go to the granary (6+3=9, cap 9).
        // Income: population 6 / 2 = 3.
        let events = try engine.apply(.endTurn, to: &s)
        #expect(events.contains(.harvest(civ: "mesopotamia", production: 9, consumption: 5,
                                         grown: 1, granary: 9, income: 3)))
        #expect(s.population(of: "mesopotamia") == 6)
        #expect(s.civs["mesopotamia"]!.gold == 9)
    }

    @Test func populationStopsAtCap() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["mesopotamia"])
        for _ in 0..<20 { try engine.apply(.endTurn, to: &s) }
        #expect(s.population(of: "mesopotamia") == 9)
    }

    @Test func deficitDrawsOnGranaryFirst() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["greece"])
        s.armies["greece"]!.units.infantry = 3
        // Production 3; eaten 1 + 3 infantry = 4. Granary 6 covers the 1 short.
        let events = try engine.apply(.endTurn, to: &s)
        #expect(s.civs["greece"]!.granary == 5)
        #expect(!events.contains { if case .starvation = $0 { true } else { false } })
    }

    @Test func starvationTakesPopulationThenUnits() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["mesopotamia"])
        s.civs["mesopotamia"]!.granary = 0
        s.civs["mesopotamia"]!.gold = 0  // nothing to buy grain with
        s.armies["mesopotamia"]!.units.infantry = 10
        // Production 9; eaten ceil(5/2)=3 + 10 = 13. Population falls to the floor of 1
        // (eaten 1 + 10 = 11), then 2 infantry desert (1 + 8 = 9).
        let events = try engine.apply(.endTurn, to: &s)
        #expect(events.contains(.starvation(civ: "mesopotamia", populationLost: 4, unitsLost: 2)))
        #expect(s.population(of: "mesopotamia") == 1)
        #expect(s.armies["mesopotamia"]!.units.infantry == 8)
        #expect(s.civs["mesopotamia"]!.granary == 0)
    }

    @Test func sameCommandsSameResult() throws {
        func play() throws -> GameState {
            var s = try engine.newGame(seed: 7)
            for _ in 0..<40 {
                let civ = s.activePlayer
                let capital = engine.map.civilization(civ)!.capital
                _ = try? engine.apply(.recruit(territory: capital, unit: .infantry, count: 1), to: &s)
                if let to = engine.map.landNeighbors(of: capital).first {
                    _ = try? engine.apply(.move(from: capital, to: to, units: UnitCounts(infantry: 1)), to: &s)
                }
                try engine.apply(.endTurn, to: &s)
            }
            return s
        }
        let a = try play()
        let b = try play()
        #expect(a == b)
        let roundTripped = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(a))
        #expect(roundTripped == a)
    }

    @Test func commandsAreCodable() throws {
        let commands: [Command] = [
            .recruit(territory: "egypt", unit: .archers, count: 2),
            .move(from: "egypt", to: "libya", units: UnitCounts(infantry: 1, cavalry: 1)),
            .endTurn,
        ]
        let decoded = try JSONDecoder().decode([Command].self, from: JSONEncoder().encode(commands))
        #expect(decoded == commands)
    }
}
