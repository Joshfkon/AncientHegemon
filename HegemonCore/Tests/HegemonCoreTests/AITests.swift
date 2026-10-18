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
        for _ in 0..<8 { _ = ai.playTurn(&s) }
        #expect(s.territories(of: "mesopotamia").count > start + 2)
    }

    @Test func aiSailsToCoastsItCannotWalkTo() throws {
        // Greece's heartland touches few coasts by land; the AI must build ships to reach more.
        var s = try engine.newGame(seed: 4, civilizations: ["greece"])
        let ai = AIPlayer(engine: engine, personality: .conqueror)
        var built = 0
        var seaborneCaptures = 0
        for _ in 0..<25 where s.winner == nil {
            var landedOn: Set<TerritoryID> = []
            for event in ai.playTurn(&s).events {
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
                _ = ai.playTurn(&s)
            } else {
                try engine.apply(.endTurn, to: &s)
            }
        }
        #expect(s.territories(of: "mesopotamia").count > s.territories(of: "egypt").count)
    }

    @Test func aiKeepsItsEmpireFed() throws {
        let record = try playAIMatch(engine: engine, seed: 2, personalities: conquerors, maxTurns: 40)
        for (civ, r) in record.civs where r.eliminatedOnTurn == nil {
            #expect(r.turnsStarving * 4 <= record.turns, "\(civ) starved \(r.turnsStarving) of \(record.turns) turns")
        }
    }

    @Test func aiTurnLeavesGameRNGAlone() throws {
        // A turn with no battles must not advance the game's RNG: estimates use their own seeds.
        var s = try engine.newGame(seed: 9, civilizations: ["mesopotamia"])
        s.armies = s.armies.filter { $0.value.owner != nativesID }  // nothing to fight
        let before = s.rng
        let turn = AIPlayer(engine: engine, personality: .turtle).playTurn(&s)
        #expect(!turn.events.contains { if case .battle = $0 { true } else { false } })
        #expect(s.rng == before)
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
        #expect(s.armies["media"]?.owner == nativesID)
        s.armies["mesopotamia"]!.units.infantry = 15
        let events = try full.apply(.move(from: "mesopotamia", to: "media", units: UnitCounts(infantry: 15)), to: &s)
        #expect(events.contains { if case .battle = $0 { true } else { false } })
        #expect(s.owner(of: "media") == "mesopotamia")
        #expect(!events.contains(.eliminated(civ: nativesID)))
    }
}
