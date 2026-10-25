import Foundation
import Testing
@testable import HegemonCore

@Suite struct AITests {
    let engine = try! Engine.bundled()

    private var conquerors: [CivilizationID: Personality] {
        Dictionary(uniqueKeysWithValues: engine.map.civilizations.map { ($0.id, Personality.conqueror) })
    }

    @Test func aiGamesAreDeterministic() throws {
        let a = try playAIMatch(engine: engine, seed: 5, personalities: [:], maxTurns: 25)
        let b = try playAIMatch(engine: engine, seed: 5, personalities: [:], maxTurns: 25)
        #expect(a.finalState == b.finalState)
        #expect(a.winner == b.winner)
    }

    @Test func aiOnlyIssuesLegalCommands() throws {
        for seed in 1...4 {
            let record = try playAIMatch(engine: engine, seed: UInt64(seed), personalities: [:], maxTurns: 40)
            for (civ, r) in record.civs {
                #expect(r.rejectedCommands == 0, "\(civ) had commands rejected in seed \(seed)")
            }
        }
    }

    @Test func aiExpandsIntoNativeLand() throws {
        var s = try engine.newGame(seed: 3, civilizations: ["mesopotamia"])
        let start = s.territories(of: "mesopotamia").count
        let ai = AIPlayer(engine: engine, personality: .conqueror)
        for _ in 0..<8 { _ = ai.play(&s) }
        // Slower than it was: soldiers beyond what the people can spare are paid in full.
        #expect(s.territories(of: "mesopotamia").count > start + 1, "held \(s.territories(of: "mesopotamia").count)")
    }

    @Test func aiSailsToCoastsItCannotWalkTo() throws {
        // Greece's heartland touches few coasts by land; the AI must build ships to reach more.
        let engine = try Engine.calm()
        var s = try engine.newGame(seed: 4, civilizations: ["greece"])
        // Kingdoms are tough now: a weakly held island worth an expedition.
        s.armies["crete"]!.units.infantry = 1
        // Greece's own fields can't feed a fleet and an expedition (soldiers are no longer raised by
        // starving the people): give it the troops, and a treasury that buys grain abroad.
        s.civs["greece"]!.gold = 80
        s.armies["greece"]!.units.infantry = 9
        // As bold as a conqueror, but spending every grain on soldiers and ships: a conqueror now
        // leaves its people grain to grow on, and this treasury can't feed both.
        let raider = Personality(name: "raider", aggression: 1.5, caution: 0.6, trade: 0.2, opportunism: 1)
        let ai = AIPlayer(engine: engine, personality: raider)
        var built = 0
        var seaborneCaptures = 0
        for _ in 0..<25 where s.winner == nil {
            var landedOn: Set<TerritoryID> = []
            for event in ai.play(&s).events {
                if case let .shipsBuilt(_, _, n) = event { built += n }
                if case let .landed(_, _, t, _) = event { landedOn.insert(t) }
                if case let .captured(_, t, _) = event, landedOn.contains(t) { seaborneCaptures += 1 }
            }
        }
        #expect(built > 0)
        #expect(seaborneCaptures > 0)
    }

    @Test func aiBeatsAPassiveRival() throws {
        var s = try engine.newGame(seed: 3, civilizations: ["mesopotamia", "egypt"])
        let ai = AIPlayer(engine: engine, personality: .conqueror)
        for _ in 0..<40 where s.winner == nil {
            if s.activePlayer == "mesopotamia" {
                _ = ai.play(&s)
            } else {
                try engine.apply(.endTurn, to: &s)
            }
        }
        #expect(s.territories(of: "mesopotamia").count > s.territories(of: "egypt").count)
    }

    @Test func richAIStartsSeveralProjectsAndKeepsAReserve() throws {
        let engine = try Engine.bare()
        var s = try engine.newGame(seed: 1, civilizations: ["mesopotamia"])
        for t in ["persia", "media", "armenia"] { s.land[t]!.owner = "mesopotamia" }
        s.civs["mesopotamia"]!.gold = 60
        s.civs["mesopotamia"]!.stock = [.stone: 30, .timber: 30]
        let ai = AIPlayer(engine: engine, personality: .opportunist)
        var turn = AITurn()
        ai.invest("mesopotamia", &s, &turn)
        let started = turn.events.filter { if case .projectStarted = $0 { true } else { false } }.count
        #expect(started >= 2)
        #expect(s.civs["mesopotamia"]!.gold >= ai.investmentReserve("mesopotamia", s))
        #expect(turn.rejected.isEmpty)
    }

    @Test func aiKeepsItsEmpireFed() throws {
        // Famine events aside, the AI shouldn't recruit its way into starvation.
        let engine = try Engine.calm()
        let record = try playAIMatch(engine: engine, seed: 2, personalities: conquerors, maxTurns: 40)
        for (civ, r) in record.civs where r.eliminatedOnTurn == nil {
            #expect(r.turnsStarving * 4 <= record.turns, "\(civ) starved \(r.turnsStarving) of \(record.turns) turns")
        }
    }

    @Test func aiTurnLeavesGameRNGAlone() throws {
        // A turn with no battles must use the game's RNG exactly as a bare end of turn does
        // (events at the next turn's start): the AI's estimates use their own seeds.
        var s = try engine.newGame(seed: 9, civilizations: ["mesopotamia"])
        s.armies = s.armies.filter { !isNative($0.value.owner) }  // nothing to fight
        var passive = s
        try engine.apply(.endTurn, to: &passive)
        let turn = AIPlayer(engine: engine, personality: .turtle).play(&s)
        #expect(!turn.events.contains { if case .battle = $0 { true } else { false } })
        #expect(s.rng == passive.rng)
    }

    @Test func shuffledOrderIsSeededAndComplete() {
        let civs = ["greece", "egypt", "italia", "mesopotamia"]
        #expect(shuffledTurnOrder(civs, seed: 7) == shuffledTurnOrder(civs, seed: 7))
        #expect(Set(shuffledTurnOrder(civs, seed: 7)) == Set(civs))
        #expect(Set((1...10).map { shuffledTurnOrder(civs, seed: UInt64($0)) }).count > 1)
    }
}

@Suite struct VictoryTests {
    let engine = try! Engine.bare()

    @Test func dominationWins() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["mesopotamia", "greece"])
        let needed = (engine.map.territories.count * engine.rules.victory.territoryPercent + 99) / 100
        // Hand Mesopotamia all but one of the territories it needs, then let it take Media.
        let extra = engine.map.territories.map(\.id)
            .filter { $0 != "media" && s.owner(of: $0) == nil }.prefix(needed - 2)
        for t in extra { s.land[t]!.owner = "mesopotamia" }
        #expect(s.territories(of: "mesopotamia").count == needed - 1)
        let events = try engine.apply(.move(from: "mesopotamia", to: "media", units: UnitCounts(infantry: 1)), to: &s)
        #expect(events.contains(.victory(civ: "mesopotamia")))
        #expect(s.winner == "mesopotamia")
    }

    @Test func nativesDefendButAreNotPlayers() throws {
        var s = try Engine.bundled().newGame(seed: 1, civilizations: ["mesopotamia"])
        let full = try Engine.bundled()
        #expect(s.armies["media"]?.owner == kingdomID("media"))
        s.armies["mesopotamia"]!.units.infantry = 15
        let events = try full.apply(.move(from: "mesopotamia", to: "media", units: UnitCounts(infantry: 15)), to: &s)
        #expect(events.contains { if case .battle = $0 { true } else { false } })
        #expect(s.owner(of: "media") == "mesopotamia")
        #expect(!events.contains(.eliminated(civ: nativesID)))
    }
}

@Suite struct VictoryKindTests {
    let engine = try! Engine.bare()

    @Test func legacyAtTheRoundLimit() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["mesopotamia", "greece"])
        for t in ["persia", "media", "armenia", "syria", "taurus", "arabia"] { s.land[t]!.owner = "mesopotamia" }
        s.turn = engine.rules.victory.roundLimit
        s.activePlayerIndex = 1
        try engine.apply(.endTurn, to: &s)
        #expect(s.winner == "mesopotamia")
        #expect(s.victory?.kind == .legacy)
        #expect(s.victory?.grade == .major)  // seven territories against Greece's lone capital
        #expect(s.victory?.standings == ["mesopotamia", "greece"])
        #expect(engine.prestige(of: "mesopotamia", in: s) > engine.prestige(of: "greece", in: s))
    }

    @Test func narrowLegacyIsMinor() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["egypt", "mesopotamia"])
        s.turn = engine.rules.victory.roundLimit
        s.activePlayerIndex = 1
        try engine.apply(.endTurn, to: &s)
        #expect(s.victory?.kind == .legacy)
        #expect(s.victory?.grade == .minor)
    }

    @Test func tradeVictoryAfterHoldingTheStraits() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["greece", "egypt"])
        for t in ["baetica", "mauretania", "thrace", "anatolia", "sicilia"] { s.land[t]!.owner = "greece" }
        s.peace.insert(CivPair("greece", "egypt"))
        #expect(engine.meetsTradeConditions("greece", in: s))
        for _ in 0..<(2 * engine.rules.victory.tradeRoundsHeld) where s.winner == nil {
            try engine.apply(.endTurn, to: &s)
        }
        #expect(s.winner == "greece")
        #expect(s.victory?.kind == .trade)
        #expect(s.victory?.grade == .decisive)
    }

    @Test func tradeNeedsEveryRival() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["greece", "egypt", "italia"])
        for t in ["baetica", "mauretania", "thrace", "anatolia", "sicilia"] { s.land[t]!.owner = "greece" }
        s.peace.insert(CivPair("greece", "egypt"))
        #expect(!engine.meetsTradeConditions("greece", in: s))
    }

    @Test func dominationIsGraded() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["mesopotamia", "greece"])
        let needed = (engine.map.territories.count * engine.rules.victory.territoryPercent + 99) / 100
        for t in engine.map.territories.map(\.id).filter({ $0 != "media" && s.owner(of: $0) == nil }).prefix(needed - 2) {
            s.land[t]!.owner = "mesopotamia"
        }
        s.turn = engine.rules.victory.decisiveBefore + 1
        try engine.apply(.move(from: "mesopotamia", to: "media", units: UnitCounts(infantry: 1)), to: &s)
        #expect(s.victory?.kind == .domination)
        #expect(s.victory?.grade == .major)
    }
}
