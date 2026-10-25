import Foundation
import Testing
@testable import HegemonCore

@Suite struct CrisisTests {
    let engine = try! Engine.bare()

    /// Egypt, played by a person, with a famous, disloyal general leading 5 infantry in Libya.
    private func contested(gold: Int) throws -> (GameState, GeneralID) {
        var s = try engine.newGame(seed: 1, civilizations: ["egypt", "greece"])
        for t in ["libya", "cyrenaica", "petraea"] { s.land[t]!.owner = "egypt" }
        s.armies["libya"] = Army(owner: "egypt", units: UnitCounts(infantry: 5))
        let id = s.general(of: "egypt", at: "egypt")!.id
        s.generals[id]!.location = "libya"
        s.generals[id]!.renown = 3
        s.generals[id]!.loyalty = 50
        s.civs["egypt"]!.heir = nil
        s.civs["egypt"]!.gold = gold
        s.civs["egypt"]!.isHuman = true
        _ = engine.rulerDies("egypt", cause: .oldAge, &s)
        return (s, id)
    }

    @Test func humansDecideContestedSuccessions() throws {
        var (s, id) = try contested(gold: 50)
        #expect(s.civs["egypt"]!.crisis?.claimants == [id])
        #expect(throws: GameError.crisisPending) { try engine.apply(.endTurn, to: &s) }
        #expect(throws: GameError.crisisPending) {
            try engine.apply(.recruit(territory: "egypt", unit: .infantry, count: 1), to: &s)
        }
    }

    @Test func payingOff() throws {
        var (s, id) = try contested(gold: 50)
        try engine.apply(.resolveCrisis(.payOff), to: &s)
        #expect(s.civs["egypt"]!.crisis == nil)
        #expect(s.civs["egypt"]!.gold == 50 - engine.rules.government.bribePerClaimant)
        #expect(s.generals[id]!.owner == "egypt")
        try engine.apply(.endTurn, to: &s)
    }

    @Test func payingOffNeedsTheGold() throws {
        var (s, _) = try contested(gold: 0)
        #expect(throws: GameError.self) { try engine.apply(.resolveCrisis(.payOff), to: &s) }
        #expect(s.civs["egypt"]!.crisis != nil)
    }

    @Test func crowningTheClaimant() throws {
        var (s, id) = try contested(gold: 0)
        let name = s.generals[id]!.name
        let events = try engine.apply(.resolveCrisis(.crownClaimant), to: &s)
        #expect(events.contains(.succession(civ: "egypt", ruler: name, outcome: .claimantCrowned)))
        #expect(s.civs["egypt"]!.ruler.name == name)
        #expect(!s.generals[id]!.isAlive)  // left the army for the throne
        #expect(s.owner(of: "libya") == "egypt")
    }

    @Test func standingFirmMeansWar() throws {
        var (s, id) = try contested(gold: 0)
        let events = try engine.apply(.resolveCrisis(.standFirm), to: &s)
        #expect(events.contains { if case .civilWar = $0 { true } else { false } })
        #expect(s.generals[id]!.owner != "egypt")
        #expect(s.owner(of: "libya") != "egypt")
    }

    @Test func aiRulersStillResolveOnTheirOwn() throws {
        var (s, _) = try contested(gold: 50)
        s.civs["egypt"]!.crisis = nil
        s.civs["egypt"]!.isHuman = false
        s.civs["egypt"]!.heir = nil
        _ = engine.rulerDies("egypt", cause: .oldAge, &s)
        #expect(s.civs["egypt"]!.crisis == nil)
    }
}

@Suite struct OddsTests {
    let engine = try! Engine.bare()

    @Test func oddsFollowTheArmies() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["mesopotamia", "greece"])
        s.land["persia"]!.owner = "greece"
        s.armies["persia"] = Army(owner: "greece", units: UnitCounts(infantry: 4))
        let strong = try #require(engine.attackOdds("mesopotamia", units: UnitCounts(infantry: 12), into: "persia",
                                                    from: "mesopotamia", in: s))
        let weak = try #require(engine.attackOdds("mesopotamia", units: UnitCounts(infantry: 2), into: "persia",
                                                  from: "mesopotamia", in: s))
        #expect(strong > 0.8)
        #expect(weak < 0.2)
        #expect(engine.attackOdds("mesopotamia", units: UnitCounts(infantry: 12), into: "persia",
                                  from: "mesopotamia", in: s) == strong)  // stable
        #expect(engine.attackOdds("mesopotamia", units: UnitCounts(infantry: 1), into: "media", in: s) == nil)
        let before = s.rng
        _ = engine.attackOdds("mesopotamia", units: UnitCounts(infantry: 5), into: "persia", in: s)
        #expect(s.rng == before)
    }
}

@Suite struct EconomyReportTests {
    @Test func forecastMatchesTheHarvest() throws {
        let engine = try Engine.calm()
        for seed in 1...3 {
            // Play a few AI rounds to get a varied economy, then compare forecast and harvest.
            let record = try playAIMatch(engine: engine, seed: UInt64(seed), personalities: [:], maxTurns: 8)
            var s = record.finalState
            guard s.winner == nil else { continue }
            let civ = s.activePlayer
            let report = engine.economy(of: civ, in: s)
            let gold = s.civs[civ]!.gold
            s.turn = max(2, s.turn)
            let events = engine.harvest(civ, &s)
            guard case let .harvest(_, production, consumption, _, _, income)? = events.first else {
                Issue.record("no harvest")
                continue
            }
            #expect(report.grainProduced == production)
            #expect(report.grainProduced - report.grainBalance == consumption,
                    "seed \(seed): people \(report.eatenByPeople) armies \(report.eatenByArmies) haul \(report.eatenByDistance) sea \(report.eatenAtSea) vs \(consumption)")
            #expect(report.income == income)
            // Grain bought from abroad in a lean harvest is paid for out of the same treasury.
            let imports = events.reduce(0) { if case let .grainImported(_, _, cost) = $1 { $0 + cost } else { $0 } }
            // The army is paid after the harvest, and the report forecasts it.
            let paid = events.reduce(0) { if case let .armyPaid(_, gold, _) = $1 { $0 + gold } else { $0 } }
            #expect(paid == min(report.pay, gold + income - imports))
            #expect(s.civs[civ]!.gold == gold + income - imports - paid)
        }
    }

    @Test func supplyRoutesRunFromTheCapital() throws {
        let engine = try Engine.bare()
        var s = try engine.newGame(seed: 1, civilizations: ["greece"])
        for t in ["macedonia", "thrace", "dacia"] { s.land[t]!.owner = "greece" }
        let route = try #require(engine.supplyRoute(of: "greece", to: "dacia", in: s))
        #expect(route.first == .land("greece"))
        #expect(route.last == .land("dacia"))
        #expect(engine.supplySteps(of: "greece", to: "dacia", in: s) == route.count - 1)
        s.land["sicilia"]!.owner = "greece"  // reachable only by sea
        let sea = try #require(engine.supplyRoute(of: "greece", to: "sicilia", in: s))
        #expect(sea.contains { if case .sea = $0 { true } else { false } })
    }
}

@Suite struct SaveGameTests {
    @Test func longGamesRoundTripExactly() throws {
        let engine = try Engine.bundled()
        // Long enough for civil wars, rebels, events, fleets and peace treaties to appear.
        for seed in [3, 11] {
            let record = try playAIMatch(engine: engine, seed: UInt64(seed), personalities: [:], maxTurns: 30)
            var state = record.finalState
            state.civs[state.players[0]]!.isHuman = true
            let data = try JSONEncoder().encode(state)
            let restored = try JSONDecoder().decode(GameState.self, from: data)
            #expect(restored == state)
            // And play continues identically from the restored game.
            if state.winner == nil {
                var a = state, b = restored
                _ = AIPlayer(engine: engine, personality: .turtle).play(&a)
                _ = AIPlayer(engine: engine, personality: .turtle).play(&b)
                #expect(a == b)
            }
        }
    }
}
