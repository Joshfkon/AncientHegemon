import Foundation
import Testing
@testable import HegemonCore

@Suite struct CollapseTests {
    let engine = try! Engine.bare()

    @Test func pressureRisesFromRoundTwelveToForty() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["greece"])
        s.turn = 12
        #expect(engine.collapsePressure(s) == 0)
        #expect(engine.collapseWeights("greece", s).isEmpty)
        s.turn = 26
        #expect(engine.collapsePressure(s) == 50)
        s.turn = 60
        #expect(engine.collapsePressure(s) == 100)
        let weights = Dictionary(uniqueKeysWithValues: engine.collapseWeights("greece", s))
        #expect(weights[.seaPeoples]! > 0)       // Greece is all coast
        #expect(weights[.tradeDisrupted] == 0)   // and trades with nobody
    }

    @Test func migrationsPressTheLandFrontiers() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["mesopotamia"])
        s.turn = 12
        #expect(engine.collapseWeights("mesopotamia", s).isEmpty)
        s.turn = 40
        // Mesopotamia borders the Arabian desert, a barbarian homeland.
        let fronts = engine.barbarianFronts("mesopotamia", s).count
        #expect(fronts > 0)
        let weights = Dictionary(uniqueKeysWithValues: engine.collapseWeights("mesopotamia", s))
        #expect(weights[.barbarians] == fronts * engine.rules.collapse.weights.migrationsPerExposure)
    }

    @Test func earthquakesWreckBuildings() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["greece"])
        s.land["greece"]!.improvements = [.walls]
        let events = engine.strikeCollapse(.earthquake, "greece", &s)
        #expect(events.contains(.projectDestroyed(territory: "greece", project: .walls)))
        #expect(s.land["greece"]!.improvements.isEmpty)
    }

    @Test func seaPeoplesBurnUndefendedCoasts() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["greece", "egypt"])
        s.turn = 40
        s.land["crete"]!.owner = "greece"
        s.land["crete"]!.improvements = [.farm]
        // Greece's only coast without troops is Crete; make it the only coast at all.
        s.land["greece"]!.owner = nil
        s.armies["greece"] = nil
        let events = engine.strikeCollapse(.seaPeoples, "greece", &s)
        #expect(events.contains(.projectDestroyed(territory: "crete", project: .farm)))
        #expect(s.owner(of: "crete") == nil)
        #expect(s.armies["crete"]?.owner == barbariansID)
    }

    @Test func seaPeoplesCanBeBeaten() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["greece"])
        s.turn = 13
        s.armies["greece"]!.units = UnitCounts(infantry: 20)
        let events = engine.strikeCollapse(.seaPeoples, "greece", &s)
        #expect(events.contains { if case .battle = $0 { true } else { false } })
        #expect(s.owner(of: "greece") == "greece")
    }

    @Test func brokenTradeRoutesMendAfterAFewRounds() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["greece", "egypt"])
        s.peace.insert(CivPair("greece", "egypt"))
        #expect(engine.tradeRoute(between: "greece", and: "egypt", in: s) != nil)
        let events = engine.strikeCollapse(.tradeDisrupted, "greece", &s)
        #expect(events.contains { if case let .event(r) = $0 { r.partner == "egypt" } else { false } })
        #expect(engine.tradeRoute(between: "greece", and: "egypt", in: s) == nil)
        s.turn += engine.rules.collapse.disruptionRounds
        #expect(engine.tradeRoute(between: "greece", and: "egypt", in: s) != nil)
    }

    @Test func bronzeWearsButIronHolds() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["greece"])
        s.civs["greece"]!.bronze = 40
        engine.wearBronze("greece", &s)
        #expect(s.civs["greece"]!.bronze == 38)
        s.civs["greece"]!.bronze = 1
        engine.wearBronze("greece", &s)
        #expect(s.civs["greece"]!.bronze == 0)

        // Iron in store arms troops once it can be worked; steel counts it double.
        s.armies["greece"]!.units = UnitCounts(infantry: 10)
        s.civs["greece"]!.stock[.iron] = 4
        #expect(engine.bronzePercent("greece", s) == 0)
        s.civs["greece"]!.knowledge[.metallurgy] = engine.rules.knowledge.levels[1]
        #expect(engine.bronzePercent("greece", s) == 40)
        s.civs["greece"]!.knowledge[.metallurgy] = engine.rules.knowledge.levels[2]
        #expect(engine.bronzePercent("greece", s) == 80)
    }
}

@Suite struct PacingTests {
    let engine = try! Engine.calm()

    @Test func aShortAgeBringsTheCollapseSooner() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["egypt", "greece"])
        engine.prepare(&s, human: "egypt", difficulty: .medium, scenario: nil, rounds: Engine.shortAge)
        #expect(engine.roundLimit(s) == Engine.shortAge)
        let c = engine.rules.collapse
        let short = engine.collapseRounds(s)
        #expect(short.start == c.startRound * Engine.shortAge / engine.rules.victory.roundLimit)
        #expect(short.peak < c.peakRound)
        s.turn = short.start + 1
        #expect(engine.collapsePressure(s) > 0)
        // The full age is untouched.
        let full = try engine.newGame(seed: 1, civilizations: ["egypt", "greece"])
        #expect(engine.collapseRounds(full) == (c.startRound, c.peakRound))
    }

    @Test func theCollapseIsAnnounced() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["egypt", "greece"])
        let start = engine.collapseRounds(s).start
        s.turn = start
        #expect(engine.ageTurns(s) == [.collapseNear])
        s.turn = start + 1
        #expect(engine.ageTurns(s) == [.collapseBegan])
        s.turn = start + 2
        #expect(engine.ageTurns(s).isEmpty)
    }

    @Test func theWorldFearsAMenace() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["egypt", "greece", "italia"])
        // Egypt sweeps the board.
        let free = engine.map.territories.map(\.id).filter { s.owner(of: $0) == nil }.sorted()
        for t in free.prefix(free.count / 2) { s.land[t]!.owner = "egypt" }
        #expect(engine.menace(in: s) == "egypt")
        let k = try #require(s.kingdoms.keys.sorted().first { s.kingdoms[$0]?.overlord == nil })
        let before = engine.attitude(of: k, toward: "egypt", in: s)
        for _ in 0..<20 { _ = engine.minorsRound(&s); _ = engine.diplomacyRound(&s) }
        if s.kingdoms[k] != nil {
            #expect(engine.attitude(of: k, toward: "egypt", in: s) < before)
        }
        #expect(engine.regard(of: "greece", toward: "egypt", in: s) < engine.regard(of: "greece", toward: "italia", in: s))
    }
}
