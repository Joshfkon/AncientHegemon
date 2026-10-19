import Testing
@testable import HegemonCore

@Suite struct NavalDefenceTests {
    let engine = try! Engine.bare()

    /// Greece with troops aboard in the eastern Mediterranean, Egypt's coast across the water.
    func setup(defenders: Int) throws -> GameState {
        var s = try engine.newGame(seed: 3, civilizations: ["greece", "egypt"])
        s.activePlayerIndex = s.players.firstIndex(of: "greece")!
        s.fleets = [Fleet(sea: "eastern_med", owner: "greece", ships: 3, cargo: UnitCounts(infantry: 6))]
        if defenders > 0 { s.fleets.append(Fleet(sea: "eastern_med", owner: "egypt", ships: defenders)) }
        s.fleets.sort { ($0.sea, $0.owner) < ($1.sea, $1.owner) }
        return s
    }

    @Test func noDefendingShipsMeansAStraightLanding() throws {
        var s = try setup(defenders: 0)
        let events = try engine.apply(.land(sea: "eastern_med", territory: "libya", units: UnitCounts(infantry: 6)), to: &s)
        #expect(!events.contains { if case .navalBattle = $0 { true } else { false } })
        #expect(events.contains { if case .landed = $0 { true } else { false } })
    }

    @Test func defendingShipsMustBeBeatenFirst() throws {
        for seed in 1...12 {
            var s = try setup(defenders: 3)
            s.rng = SeededRNG(seed: UInt64(seed))
            let events = try engine.apply(.land(sea: "eastern_med", territory: "libya", units: UnitCounts(infantry: 6)), to: &s)
            guard case let .navalBattle(_, report)? = events.first else {
                Issue.record("no sea battle before the landing (seed \(seed))")
                continue
            }
            let landed = events.contains { if case .landed = $0 { true } else { false } }
            // Only a fleet that won at sea gets anyone ashore.
            #expect(landed == (report.winner == .attacker), "seed \(seed)")
            if !landed {
                #expect(s.armies["libya"]?.owner != "greece")
            }
        }
    }

    @Test func aLostSeaBattleKeepsTheTroopsAboard() throws {
        var s = try setup(defenders: 9)
        let events = try engine.apply(.land(sea: "eastern_med", territory: "libya", units: UnitCounts(infantry: 6)), to: &s)
        #expect(!events.contains { if case .landed = $0 { true } else { false } })
        #expect(s.armies["libya"]?.owner != "greece")
    }
}
