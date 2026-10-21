import Testing
@testable import HegemonCore

private let thrace = kingdomID("thrace")

@Suite struct MinorKingdomTests {
    let engine = try! Engine.calm()

    /// Greece holding Macedonia, next to the Thracians (3 warriors), with `troops` there.
    func greeceBesideThrace(troops: Int = 6) throws -> GameState {
        var s = try engine.newGame(seed: 1, civilizations: ["greece", "egypt"])
        s.land["macedonia"]!.owner = "greece"
        s.armies["macedonia"] = troops > 0 ? Army(owner: "greece", units: UnitCounts(infantry: troops)) : nil
        s.armies["thrace"] = Army(owner: thrace, units: UnitCounts(infantry: 3))
        s.civs["greece"]!.gold = 100
        return s
    }

    @Test func nativeLandsAreKingdomsButHomelandsAreTribes() throws {
        let s = try engine.newGame(seed: 1, civilizations: ["greece", "egypt"])
        #expect(engine.people(at: "anatolia", in: s)?.name == "Hatti")
        #expect(s.armies["anatolia"]?.owner == kingdomID("anatolia"))
        #expect(engine.people(at: "thrace", in: s)?.temperament == .warlike)
        #expect(engine.people(at: "scythe", in: s) == nil)
        #expect(s.armies["scythe"]?.owner == nativesID)
        #expect(engine.people(at: "greece", in: s) == nil)
    }

    @Test func aVassalPaysTributeAndIsShielded() throws {
        var s = try greeceBesideThrace()
        let events = try engine.apply(.parley(territory: "thrace", .vassalage), to: &s)
        #expect(events == [.vassalSworn(civ: "greece", territory: "thrace")])
        #expect(engine.overlord(of: "thrace", in: s) == "greece")
        // They keep their land and warriors.
        #expect(s.owner(of: "thrace") == nil)
        #expect(s.armies["thrace"]?.units.total == 3)
        #expect(engine.peoplesGold(of: "greece", in: s).tribute == engine.tribute(of: thrace, in: s))
        #expect(engine.prestigeBreakdown(of: "greece", in: s).contains { $0.source == "Vassals" })
        // Nobody at peace with Greece may touch them, nor Greece itself (its troops march in
        // only as a garrison).
        s.peace.insert(CivPair("greece", "egypt"))
        #expect(engine.shielded("thrace", from: "egypt", in: s))
        #expect(engine.shielded("thrace", from: "greece", in: s))
        s.land["dacia"]!.owner = "egypt"
        s.armies["dacia"] = Army(owner: "egypt", units: UnitCounts(infantry: 9))
        s.activePlayerIndex = s.players.firstIndex(of: "egypt")!
        #expect(throws: GameError.shielded("thrace")) {
            try engine.apply(.move(from: "dacia", to: "thrace", units: UnitCounts(infantry: 1)), to: &s)
        }
        #expect(engine.tribe(at: "thrace", for: "greece", in: s) == nil)
    }

    @Test func tooFewTroopsAndTheyRefuseAndResentIt() throws {
        var s = try greeceBesideThrace(troops: 2)
        let before = engine.attitude(of: thrace, toward: "greece", in: s)
        let events = try engine.apply(.parley(territory: "thrace", .vassalage), to: &s)
        #expect(events == [.tribeRefused(civ: "greece", territory: "thrace", parley: .vassalage)])
        #expect(engine.attitude(of: thrace, toward: "greece", in: s) < before)
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
        #expect(stubborn.attitude(of: thrace, toward: "greece", in: s) == stubborn.rules.minors.giftAttitude)
    }

    @Test func aKingdomOfSeveralLandsSwearsAndJoinsAsAWhole() throws {
        var s = try greeceBesideThrace(troops: 25)
        // Thrace has taken Dacia: its terms reckon with all its warriors, and it comes over whole.
        s.armies["dacia"] = Army(owner: thrace, units: UnitCounts(infantry: 4))
        #expect(engine.lands(of: thrace, in: s) == ["dacia", "thrace"])
        #expect(engine.warriors(of: thrace, in: s) == 7)
        #expect(engine.giftCost(at: "thrace", in: s) > engine.giftCost(at: "anatolia", in: s))
        try engine.apply(.parley(territory: "thrace", .demand), to: &s)
        #expect(s.owner(of: "thrace") == "greece")
        #expect(s.owner(of: "dacia") == "greece")
        #expect(s.kingdoms[thrace] == nil)
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
        s.kingdoms[thrace]!.vassalSince = s.turn - engine.rules.minors.annexRounds
        try engine.apply(.annex(territory: "thrace"), to: &s)
        #expect(s.owner(of: "thrace") == "greece")
        #expect(s.armies["thrace"]?.owner == "greece")
        // Annexed in peace: not newly taken, so no unrest from it.
        #expect(s.land["thrace"]!.takenOnRound == nil)
        #expect(s.kingdoms[thrace] == nil)
    }

    @Test func annexingTakesLoyaltyGoldAndForce() throws {
        var s = try greeceBesideThrace(troops: 8)
        s.armies["thrace"]!.units = UnitCounts(infantry: 4)
        try engine.apply(.parley(territory: "thrace", .vassalage), to: &s)
        let m = engine.rules.minors
        #expect(throws: GameError.tooSoon("thrace")) { try engine.apply(.annex(territory: "thrace"), to: &s) }
        s.kingdoms[thrace]!.vassalSince = s.turn - m.annexRounds
        // Too few troops at hand: 4 warriors need 8 of ours with them or next door.
        s.armies["macedonia"]!.units.infantry = 5
        #expect(!engine.canAnnex("thrace", for: "greece", in: s))
        #expect(throws: GameError.insufficientUnits("thrace")) { try engine.apply(.annex(territory: "thrace"), to: &s) }
        // Enough troops, too little gold.
        s.armies["macedonia"]!.units.infantry = 8
        let terms = engine.annexTerms("thrace", for: "greece", in: s)
        #expect(terms.gold == m.annexGoldPerLand + 4 * m.annexGoldPerWarrior)
        s.civs["greece"]!.gold = terms.gold - 1
        #expect(throws: GameError.insufficientGold(needed: terms.gold, available: terms.gold - 1)) {
            try engine.apply(.annex(territory: "thrace"), to: &s)
        }
        s.civs["greece"]!.gold = terms.gold
        try engine.apply(.annex(territory: "thrace"), to: &s)
        #expect(s.owner(of: "thrace") == "greece")
        #expect(s.civs["greece"]!.gold == 0)
    }

    @Test func attacksAreHatedAndFeared() throws {
        var s = try greeceBesideThrace(troops: 1)
        try engine.apply(.move(from: "macedonia", to: "thrace", units: UnitCounts(infantry: 1)), to: &s)
        #expect(engine.attitude(of: thrace, toward: "greece", in: s) == engine.rules.minors.attackedAttitude)
        #expect(engine.attitude(of: kingdomID("dacia"), toward: "greece", in: s) == engine.rules.minors.fearAttitude)
    }

    @Test func warlikeKingdomsRaidEmpiresTheyHate() throws {
        let fierce = try engine.modified { json in
            var minors = json["minors"] as! [String: Any]
            minors["raidPercent"] = 100
            minors["expandPercent"] = ["warlike": 0, "proud": 0, "mercantile": 0, "peaceable": 0]
            json["minors"] = minors
        }
        var s = try greeceBesideThrace(troops: 0)
        s.armies["thrace"]!.units = UnitCounts(infantry: 6)
        s.kingdoms[thrace]!.attitude["greece"] = -60
        s.turn = 7
        let gold = s.civs["greece"]!.gold
        let events = fierce.minorsRound(&s)
        #expect(events.contains { if case let .peopleRaided(p, t, c, g, won) = $0 {
            p == "thrace" && t == "macedonia" && c == "greece" && g == 4 && won } else { false } })
        #expect(s.civs["greece"]!.gold == gold - 4)
        // They go home; the land stays Greek.
        #expect(s.owner(of: "macedonia") == "greece")
        #expect(s.armies["thrace"]?.owner == thrace)
    }

    @Test func warlikeKingdomsTakeWeakLandNextDoor() throws {
        let hungry = try engine.modified { json in
            var minors = json["minors"] as! [String: Any]
            minors["expandPercent"] = ["warlike": 100, "proud": 0, "mercantile": 0, "peaceable": 0]
            json["minors"] = minors
        }
        var s = try greeceBesideThrace(troops: 0)
        s.armies["thrace"]!.units = UnitCounts(infantry: 9)
        // Their neighbours are thin on the ground; Macedonia is Greek, and Thrace doesn't hate Greece.
        for n in ["dacia", "anatolia"] { s.armies[n] = Army(owner: kingdomID(n), units: UnitCounts(infantry: 1)) }
        let events = hungry.minorsRound(&s)
        let took = events.compactMap { e -> TerritoryID? in
            if case let .kingdomExpanded(k, t, _) = e, k == thrace { t } else { nil }
        }
        #expect(took.count == 1)
        let won = try #require(took.first)
        #expect(hungry.kingdom(at: won, in: s) == thrace)
        #expect(hungry.lands(of: thrace, in: s).count == 2)
        // One warrior stays home.
        #expect(s.armies["thrace"]?.units.total == 1)
        #expect(s.owner(of: "macedonia") == "greece")
    }

    @Test func gentleKingdomsOnlySettleEmptyLand() throws {
        let settlers = try engine.modified { json in
            var minors = json["minors"] as! [String: Any]
            minors["expandPercent"] = ["warlike": 0, "proud": 0, "mercantile": 100, "peaceable": 100]
            json["minors"] = minors
        }
        var s = try engine.newGame(seed: 1, civilizations: ["greece", "egypt"])
        // The Sicels (peaceable) beside a weak Italian-born kingdom: they won't attack it…
        let sicels = kingdomID("sicilia")
        s.armies["sicilia"] = Army(owner: sicels, units: UnitCounts(infantry: 9))
        for n in engine.map.landNeighbors(of: "sicilia") { s.armies[n] = Army(owner: nativesID, units: UnitCounts(infantry: 1)) }
        let before = engine.lands(of: sicels, in: s).count
        _ = settlers.minorsRound(&s)
        #expect(settlers.lands(of: sicels, in: s).count == before)
        // …but empty land next door they settle.
        guard let empty = engine.map.landNeighbors(of: "sicilia").sorted().first else { return }
        s.armies[empty] = nil
        _ = settlers.minorsRound(&s)
        #expect(settlers.kingdom(at: empty, in: s) == sicels)
    }

    @Test func belovedEmpiresWinKingdomsOver() throws {
        let fond = try engine.modified { json in
            var minors = json["minors"] as! [String: Any]
            minors["joinPercent"] = 100
            json["minors"] = minors
        }
        var s = try greeceBesideThrace()
        s.kingdoms[thrace]!.attitude["greece"] = 100
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

@Suite struct VassalPassageTests {
    let engine = try! Engine.calm()

    /// Greece holds Macedonia with an army; Thrace is its vassal; beyond Thrace lies Anatolia.
    func greeceWithThraceSworn() throws -> GameState {
        var s = try engine.newGame(seed: 1, civilizations: ["greece", "egypt"])
        s.land["macedonia"]!.owner = "greece"
        s.armies["macedonia"] = Army(owner: "greece", units: UnitCounts(infantry: 12))
        s.kingdoms[thrace]!.overlord = "greece"
        s.kingdoms[thrace]!.vassalSince = s.turn
        return s
    }

    @Test func armiesMarchThroughAVassalsLand() throws {
        var s = try greeceWithThraceSworn()
        #expect(engine.passageTargets(from: "macedonia", for: "greece", in: s)["anatolia"] == "thrace")
        let warriors = s.armies["thrace"]!.units
        try engine.apply(.move(from: "macedonia", to: "anatolia", units: UnitCounts(infantry: 12)), to: &s)
        #expect(s.owner(of: "anatolia") == "greece")
        // The vassal's warriors stand aside and stay home.
        #expect(s.armies["thrace"]?.units == warriors)
        #expect(s.armies["thrace"]?.owner == thrace)
        // No passage without a vassal on the way.
        s.kingdoms[thrace]!.overlord = nil
        s.armies["macedonia"] = Army(owner: "greece", units: UnitCounts(infantry: 3))
        #expect(throws: GameError.notAdjacent("macedonia", "anatolia")) {
            try engine.apply(.move(from: "macedonia", to: "anatolia", units: UnitCounts(infantry: 1)), to: &s)
        }
    }

    @Test func supplyRunsThroughAVassalButItIsNotYourLand() throws {
        var s = try greeceWithThraceSworn()
        s.land["greece"]!.owner = "greece"
        s.land["anatolia"]!.owner = "greece"
        s.armies["anatolia"] = nil
        #expect(engine.homeNetwork(of: "greece", in: s).contains("anatolia"))
        #expect(!engine.homeNetwork(of: "greece", in: s).contains("thrace"))
        // Egyptian ships close every sea: the only way is overland, through Thrace.
        s.fleets = engine.map.seas.map { Fleet(sea: $0.id, owner: "egypt", ships: 1) }
        #expect(engine.supplyRoute(of: "greece", to: "anatolia", in: s)?.contains(.land("thrace")) == true)
        s.kingdoms[thrace]!.overlord = nil
        #expect(!engine.homeNetwork(of: "greece", in: s).contains("anatolia"))
    }
}

@Suite struct VassalGarrisonTests {
    let engine = try! Engine.calm()

    func greeceWithThraceSworn() throws -> GameState {
        var s = try engine.newGame(seed: 1, civilizations: ["greece", "egypt"])
        s.land["macedonia"]!.owner = "greece"
        s.armies["macedonia"] = Army(owner: "greece", units: UnitCounts(infantry: 8))
        s.armies["thrace"] = Army(owner: thrace, units: UnitCounts(infantry: 3))
        s.kingdoms[thrace]!.overlord = "greece"
        s.kingdoms[thrace]!.vassalSince = s.turn
        return s
    }

    @Test func troopsStationedInAVassalStandWithItsWarriors() throws {
        var s = try greeceWithThraceSworn()
        let events = try engine.apply(.move(from: "macedonia", to: "thrace", units: UnitCounts(infantry: 5)), to: &s)
        #expect(!events.contains { if case .battle = $0 { true } else { false } })
        #expect(s.armies["thrace"]?.owner == "greece")
        #expect(s.armies["thrace"]?.units.infantry == 5)
        #expect(engine.warriors(at: "thrace", in: s) == 3)
        #expect(engine.garrisoned("thrace", in: s))
        #expect(s.owner(of: "thrace") == nil)
        #expect(engine.overlord(of: "thrace", in: s) == "greece")
        // The warriors fight beside the garrison, as its levy.
        #expect(engine.defenders(of: "thrace", against: "egypt", s)?.levy == 3)
        #expect(engine.defenders(of: "thrace", against: "greece", s) == nil)
    }

    @Test func whenTheGarrisonLeavesThePeopleHoldTheirLandAgain() throws {
        var s = try greeceWithThraceSworn()
        try engine.apply(.move(from: "macedonia", to: "thrace", units: UnitCounts(infantry: 5)), to: &s)
        s.moved = [:]
        try engine.apply(.move(from: "thrace", to: "macedonia", units: UnitCounts(infantry: 5)), to: &s)
        #expect(s.armies["thrace"]?.owner == thrace)
        #expect(s.armies["thrace"]?.units.infantry == 3)
        #expect(s.stationed["thrace"] == nil)
        #expect(engine.overlord(of: "thrace", in: s) == "greece")
    }

    @Test func aGarrisonedVassalStaysLoyalAndFeedsItsGarrison() throws {
        let restless = try engine.modified { json in
            var minors = json["minors"] as! [String: Any]
            minors["breakFreePercent"] = 100
            json["minors"] = minors
        }
        var s = try greeceWithThraceSworn()
        try restless.apply(.move(from: "macedonia", to: "thrace", units: UnitCounts(infantry: 5)), to: &s)
        s.armies["macedonia"] = nil
        #expect(!restless.minorsRound(&s).contains(.vassalFreed(civ: "greece", territory: "thrace")))
        for _ in 0..<4 { try restless.apply(.endTurn, to: &s) }
        #expect(s.armies["thrace"]?.units.infantry == 5)
    }
}

@Suite struct VassalRoadTests {
    let engine = try! Engine.calm()

    func greeceWithThraceSworn() throws -> GameState {
        var s = try engine.newGame(seed: 1, civilizations: ["greece", "egypt"])
        s.land["macedonia"]!.owner = "greece"
        s.armies["macedonia"] = Army(owner: "greece", units: UnitCounts(infantry: 4))
        s.kingdoms[thrace]!.overlord = "greece"
        s.kingdoms[thrace]!.vassalSince = s.turn
        s.civs["greece"]!.gold = 200
        s.civs["greece"]!.stock[.stone] = 20
        return s
    }

    @Test func anOverlordLaysRoadsThroughItsVassalsLand() throws {
        var s = try greeceWithThraceSworn()
        #expect(engine.canBuildRoad(through: "thrace", for: "greece", s))
        let gold = s.civs["greece"]!.gold
        try engine.apply(.build(territory: "thrace", project: .road), to: &s)
        #expect(s.civs["greece"]!.gold < gold)
        #expect(s.land["thrace"]!.construction?.builder == "greece")
        let turns = s.land["thrace"]!.construction!.turnsLeft
        for _ in 0..<(turns * 2) { try engine.apply(.endTurn, to: &s) }
        #expect(s.land["thrace"]!.improvements.contains(.road))
        // The land is still the kingdom's.
        #expect(s.owner(of: "thrace") == nil)
        #expect(engine.overlord(of: "thrace", in: s) == "greece")
    }

    @Test func notThroughSomeoneElsesLand() throws {
        var s = try greeceWithThraceSworn()
        s.kingdoms[thrace]!.overlord = nil
        #expect(!engine.canBuildRoad(through: "thrace", for: "greece", s))
        #expect(throws: GameError.notOwner("thrace")) {
            try engine.apply(.build(territory: "thrace", project: .road), to: &s)
        }
    }

    @Test func andThroughAVassalEmpiresLand() throws {
        var s = try greeceWithThraceSworn()
        s.peace.insert(CivPair("greece", "egypt"))
        s.land["petraea"]!.owner = "greece"
        s.armies["petraea"] = nil
        try #require(engine.homeNetwork(of: "greece", in: s).contains("petraea"))
        #expect(!engine.canBuildRoad(through: "egypt", for: "greece", s))
        _ = engine.submit("egypt", to: "greece", &s)
        #expect(engine.canBuildRoad(through: "egypt", for: "greece", s))
        try engine.apply(.build(territory: "egypt", project: .road), to: &s)
        let turns = s.land["egypt"]!.construction!.turnsLeft
        for _ in 0..<(turns * 2) { try engine.apply(.endTurn, to: &s) }
        #expect(s.land["egypt"]!.improvements.contains(.road))
        #expect(s.owner(of: "egypt") == "egypt")
    }

    @Test func aRoadThroughAVassalSpeedsTheSupply() throws {
        var s = try greeceWithThraceSworn()
        s.land["greece"]!.owner = "greece"
        s.land["anatolia"]!.owner = "greece"
        s.armies["anatolia"] = nil
        // Seas closed: the only way to Anatolia is overland, through Thrace.
        s.fleets = engine.map.seas.map { Fleet(sea: $0.id, owner: "egypt", ships: 1) }
        let before = try #require(engine.supplySteps(of: "greece", to: "anatolia", in: s))
        s.land["thrace"]!.improvements.insert(.road)
        let after = try #require(engine.supplySteps(of: "greece", to: "anatolia", in: s))
        #expect(after < before)
    }
}
