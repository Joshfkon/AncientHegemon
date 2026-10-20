import Testing
@testable import HegemonCore

@Suite struct MinorKingdomTests {
    let engine = try! Engine.calm()

    /// Greece holding Macedonia, next to the Thracians (3 warriors), with `troops` there.
    func greeceBesideThrace(troops: Int = 6) throws -> GameState {
        var s = try engine.newGame(seed: 1, civilizations: ["greece", "egypt"])
        s.land["macedonia"]!.owner = "greece"
        s.armies["macedonia"] = Army(owner: "greece", units: UnitCounts(infantry: troops))
        s.civs["greece"]!.gold = 100
        return s
    }

    @Test func nativeLandsArePeoplesButHomelandsAreNot() throws {
        let s = try engine.newGame(seed: 1, civilizations: ["greece", "egypt"])
        #expect(engine.people(at: "anatolia", in: s)?.name == "Hatti")
        #expect(engine.people(at: "thrace", in: s)?.temperament == .warlike)
        #expect(engine.people(at: "scythe", in: s) == nil)
        #expect(engine.people(at: "greece", in: s) == nil)
    }

    @Test func aVassalPaysTributeAndIsShielded() throws {
        var s = try greeceBesideThrace()
        let warriors = s.armies["thrace"]!.units.total
        let events = try engine.apply(.parley(territory: "thrace", .vassalage), to: &s)
        #expect(events == [.vassalSworn(civ: "greece", territory: "thrace")])
        #expect(engine.overlord(of: "thrace", in: s) == "greece")
        // They keep their land and warriors.
        #expect(s.owner(of: "thrace") == nil)
        #expect(s.armies["thrace"]?.units.total == warriors)
        #expect(engine.peoplesGold(of: "greece", in: s).tribute == engine.tribute(of: "thrace"))
        #expect(engine.prestigeBreakdown(of: "greece", in: s).contains { $0.source == "Vassals" })
        // Nobody at peace with Greece may touch them, nor Greece itself.
        s.peace.insert(CivPair("greece", "egypt"))
        #expect(engine.shielded("thrace", from: "egypt", in: s))
        #expect(engine.shielded("thrace", from: "greece", in: s))
        #expect(throws: GameError.shielded("thrace")) {
            try engine.apply(.move(from: "macedonia", to: "thrace", units: UnitCounts(infantry: 1)), to: &s)
        }
        #expect(engine.tribe(at: "thrace", for: "greece", in: s) == nil)
    }

    @Test func tooFewTroopsAndTheyRefuseAndResentIt() throws {
        var s = try greeceBesideThrace(troops: 2)
        let before = engine.attitude(of: "thrace", toward: "greece", in: s)
        let events = try engine.apply(.parley(territory: "thrace", .vassalage), to: &s)
        #expect(events == [.tribeRefused(civ: "greece", territory: "thrace", parley: .vassalage)])
        #expect(engine.attitude(of: "thrace", toward: "greece", in: s) < before)
    }

    @Test func refusedGiftsAreRememberedKindly() throws {
        let stubborn = try engine.modified { json in
            var tribes = json["tribes"] as! [String: Any]
            tribes["giftChanceMax"] = 0
            tribes["giftChanceMin"] = 0
            json["tribes"] = tribes
        }
        var s = try greeceBesideThrace(troops: 1)
        try stubborn.apply(.parley(territory: "thrace", .gifts), to: &s)
        #expect(stubborn.attitude(of: "thrace", toward: "greece", in: s) == stubborn.rules.minors.giftAttitude)
    }

    @Test func leviesAndPeacefulAnnexation() throws {
        var s = try greeceBesideThrace(troops: 8)
        s.armies["thrace"]!.units = UnitCounts(infantry: 4)
        try engine.apply(.parley(territory: "thrace", .vassalage), to: &s)
        let events = try engine.apply(.levy(territory: "thrace", to: "macedonia"), to: &s)
        #expect(events == [.levied(civ: "greece", territory: "thrace", to: "macedonia", warriors: 2)])
        #expect(s.armies["macedonia"]!.units.infantry == 10)
        #expect(s.armies["thrace"]!.units.infantry == 2)
        #expect(throws: GameError.tooSoon("thrace")) {
            try engine.apply(.levy(territory: "thrace", to: "macedonia"), to: &s)
        }
        #expect(throws: GameError.tooSoon("thrace")) { try engine.apply(.annex(territory: "thrace"), to: &s) }
        s.minors["thrace"]!.vassalSince = s.turn - engine.rules.minors.annexRounds
        try engine.apply(.annex(territory: "thrace"), to: &s)
        #expect(s.owner(of: "thrace") == "greece")
        #expect(s.armies["thrace"]?.owner == "greece")
        // Annexed in peace: not newly taken, so no unrest from it.
        #expect(s.land["thrace"]!.takenOnRound == nil)
        #expect(s.minors["thrace"] == nil)
    }

    @Test func attacksAreHatedAndFeared() throws {
        var s = try greeceBesideThrace(troops: 1)
        try engine.apply(.move(from: "macedonia", to: "thrace", units: UnitCounts(infantry: 1)), to: &s)
        #expect(engine.attitude(of: "thrace", toward: "greece", in: s) == engine.rules.minors.attackedAttitude)
        #expect(engine.attitude(of: "dacia", toward: "greece", in: s) == engine.rules.minors.fearAttitude)
    }

    @Test func warlikePeoplesRaidEmpiresTheyHate() throws {
        let fierce = try engine.modified { json in
            var minors = json["minors"] as! [String: Any]
            minors["raidPercent"] = 100
            json["minors"] = minors
        }
        var s = try greeceBesideThrace(troops: 0)
        s.armies["macedonia"] = nil
        s.armies["thrace"]!.units = UnitCounts(infantry: 6)
        s.minors["thrace"]!.attitude["greece"] = -60
        s.turn = 7
        let gold = s.civs["greece"]!.gold
        let events = fierce.minorsRound(&s)
        #expect(events.contains { if case let .peopleRaided(p, t, c, g, won) = $0 {
            p == "thrace" && t == "macedonia" && c == "greece" && g == 4 && won } else { false } })
        #expect(s.civs["greece"]!.gold == gold - 4)
        // They go home; the land stays Greek.
        #expect(s.owner(of: "macedonia") == "greece")
        #expect(s.armies["thrace"]?.owner == nativesID)
    }

    @Test func belovedEmpiresWinPeoplesOver() throws {
        let fond = try engine.modified { json in
            var minors = json["minors"] as! [String: Any]
            minors["joinPercent"] = 100
            json["minors"] = minors
        }
        var s = try greeceBesideThrace()
        s.minors["thrace"]!.attitude["greece"] = 100
        let events = fond.minorsRound(&s)
        #expect(events.contains { if case .peopleJoined("greece", "thrace", _) = $0 { true } else { false } })
        #expect(s.owner(of: "thrace") == "greece")
    }

    @Test func unwatchedVassalsBreakFree() throws {
        let restless = try engine.modified { json in
            var minors = json["minors"] as! [String: Any]
            minors["breakFreePercent"] = 100
            json["minors"] = minors
        }
        var s = try greeceBesideThrace()
        try restless.apply(.parley(territory: "thrace", .vassalage), to: &s)
        // With troops next door they stay loyal; withdraw them and they're gone.
        #expect(!restless.minorsRound(&s).contains(.vassalFreed(civ: "greece", territory: "thrace")))
        s.armies["macedonia"] = nil
        #expect(restless.minorsRound(&s).contains(.vassalFreed(civ: "greece", territory: "thrace")))
        #expect(restless.overlord(of: "thrace", in: s) == nil)
    }
}
