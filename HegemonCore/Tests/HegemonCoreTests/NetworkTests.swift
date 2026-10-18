import Foundation
import Testing
@testable import HegemonCore

// Scenarios set ownership directly to build the geography under test. Sea facts used here:
// the Persian Gulf links only to the Red Sea, which links nowhere else; the Black Sea links
// only to the Aegean, through the Bosporus (held by Thrace + Anatolia).

private func own(_ s: inout GameState, _ civ: CivilizationID, _ territories: TerritoryID...) {
    for t in territories { s.land[t]!.owner = civ }
}

@Suite struct SupplyTests {
    let engine = try! Engine.bare()

    @Test func connectedLandIsOnePocket() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["mesopotamia"])
        own(&s, "mesopotamia", "media", "armenia")
        #expect(engine.supplyPockets(of: "mesopotamia", in: s) == [["armenia", "media", "mesopotamia"]])
    }

    @Test func seaLanesConnectCoasts() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["greece"])
        own(&s, "greece", "sicilia", "britain")  // Ionian → Tyrrhenian → W. Med → Gibraltar → Atlantic
        #expect(engine.supplyPockets(of: "greece", in: s).count == 1)
    }

    @Test func unreachableTerritoryIsCutOff() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["mesopotamia"])
        own(&s, "mesopotamia", "dacia")
        #expect(engine.supplyPockets(of: "mesopotamia", in: s) == [["mesopotamia"], ["dacia"]])
    }

    @Test func enemyChokepointClosesSeaLane() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["greece", "mesopotamia"])
        own(&s, "greece", "dacia")
        #expect(engine.supplyPockets(of: "greece", in: s).count == 1)
        own(&s, "mesopotamia", "thrace", "anatolia")
        #expect(engine.holder(of: engine.map.chokepoints.first { $0.id == "bosporus" }!, in: s) == "mesopotamia")
        #expect(engine.supplyPockets(of: "greece", in: s) == [["greece"], ["dacia"]])
        s.peace.insert(CivPair("greece", "mesopotamia"))
        #expect(engine.supplyPockets(of: "greece", in: s).count == 1)
    }

    @Test func halfHeldChokepointStaysOpen() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["greece", "mesopotamia"])
        own(&s, "greece", "dacia")
        own(&s, "mesopotamia", "thrace")
        #expect(engine.supplyPockets(of: "greece", in: s).count == 1)
    }

    @Test func seatFallsBackWhenCapitalIsLost() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["mesopotamia"])
        own(&s, "mesopotamia", "media", "persia")
        s.land["mesopotamia"]!.owner = nil
        #expect(engine.seat(of: "mesopotamia", in: s) == "persia")  // grain 4 beats Media's 3
    }

    @Test func cutOffArmiesSufferAttrition() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["mesopotamia", "greece"])
        own(&s, "greece", "dacia", "libya")
        own(&s, "mesopotamia", "thrace", "anatolia")
        s.armies["dacia"] = Army(owner: "greece", units: UnitCounts(infantry: 3))
        s.armies["libya"] = Army(owner: "greece", units: UnitCounts(infantry: 3))
        s.peace.insert(CivPair("greece", "egypt"))  // irrelevant third party; Libya is reachable by sea
        s.turn = 2  // turn 1 has no harvest
        let events = try engine.apply(.endTurn, to: &s)  // Greece's harvest
        // Dacia is behind the enemy-held Bosporus: 1 unit lost. Libya connects via the Aegean.
        #expect(events.contains(.outOfSupply(civ: "greece", territory: "dacia", unitsLost: 1)))
        #expect(s.armies["dacia"]!.units.infantry == 2)
        #expect(s.armies["libya"]!.units.infantry == 3)
    }

    @Test func desertAttritionIsWorse() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["greece", "mesopotamia"])
        // Arabia (desert) and Persia share the Persian Gulf, which can't reach the Mediterranean.
        // Their grain (1 + 4) feeds their people (1 + 1) and the 3 infantry exactly.
        own(&s, "greece", "arabia", "persia")
        s.armies["arabia"] = Army(owner: "greece", units: UnitCounts(infantry: 3))
        s.activePlayerIndex = 1
        let events = try engine.apply(.endTurn, to: &s)
        #expect(events.contains(.outOfSupply(civ: "greece", territory: "arabia", unitsLost: 2)))
    }

    @Test func cutOffPocketFeedsItselfWithoutGranary() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["mesopotamia"])
        own(&s, "mesopotamia", "dacia")
        // Dacia: grain 4, population 2 (eats 1). 10 infantry there eat 10: starve to fit 4.
        s.armies["dacia"] = Army(owner: "mesopotamia", units: UnitCounts(infantry: 10))
        let events = try engine.apply(.endTurn, to: &s)
        // Population falls to 1 (eats 1); 7 desert (1 + 3 = 4); then 1 more to attrition.
        #expect(events.contains(.starvation(civ: "mesopotamia", populationLost: 1, unitsLost: 7)))
        #expect(s.armies["dacia"]!.units.infantry == 2)
        // The home granary was untouched by Dacia's hunger.
        #expect(s.civs["mesopotamia"]!.granary == 9)
    }

    @Test func recruitingNeedsHomeSupply() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["mesopotamia"])
        own(&s, "mesopotamia", "dacia")
        #expect(throws: GameError.outOfSupply("dacia")) {
            try engine.apply(.recruit(territory: "dacia", unit: .infantry, count: 1), to: &s)
        }
    }

    @Test func taxesComeFromHomeNetworkOnly() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["mesopotamia"])
        own(&s, "mesopotamia", "dacia")  // Dacia: population 2, gold 2, cut off
        s.civs["mesopotamia"]!.gold = 0
        let events = try engine.apply(.endTurn, to: &s)
        // Home population 6 after growth → 3 gold. Dacia's gold and people don't count.
        #expect(events.contains { if case .harvest(_, _, _, _, _, 3) = $0 { true } else { false } })
    }
}

@Suite struct DiplomacyTests {
    let engine = try! Engine.bare()

    @Test func peaceNeedsOfferAndAcceptance() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["greece", "egypt"])
        #expect(s.atWar("greece", "egypt"))
        try engine.apply(.offerPeace(to: "egypt"), to: &s)
        #expect(throws: GameError.noPeaceOffer("egypt")) {
            try engine.apply(.acceptPeace(from: "egypt"), to: &s)
        }
        try engine.apply(.endTurn, to: &s)
        let events = try engine.apply(.acceptPeace(from: "greece"), to: &s)
        #expect(events == [.peaceMade(CivPair("greece", "egypt"))])
        #expect(s.atPeace("egypt", "greece"))
        #expect(s.peaceOffers.isEmpty)
    }

    @Test func cannotInvadePeacePartner() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["mesopotamia", "egypt"])
        own(&s, "egypt", "media")
        s.peace.insert(CivPair("mesopotamia", "egypt"))
        #expect(throws: GameError.atPeace("media")) {
            try engine.apply(.move(from: "mesopotamia", to: "media", units: UnitCounts(infantry: 1)), to: &s)
        }
        try engine.apply(.declareWar(on: "egypt"), to: &s)
        try engine.apply(.move(from: "mesopotamia", to: "media", units: UnitCounts(infantry: 1)), to: &s)
        #expect(s.owner(of: "media") == "mesopotamia")
    }

    @Test func invalidDiplomacy() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["greece", "egypt"])
        #expect(throws: GameError.unknownCivilization("greece")) { try engine.apply(.offerPeace(to: "greece"), to: &s) }
        #expect(throws: GameError.unknownCivilization("rome")) { try engine.apply(.offerPeace(to: "rome"), to: &s) }
        #expect(throws: GameError.notAtPeace("egypt")) { try engine.apply(.declareWar(on: "egypt"), to: &s) }
        s.peace.insert(CivPair("greece", "egypt"))
        #expect(throws: GameError.alreadyAtPeace("egypt")) { try engine.apply(.offerPeace(to: "egypt"), to: &s) }
    }
}

@Suite struct TradeTests {
    let engine = try! Engine.bare()

    @Test func noTradeAtWar() throws {
        let s = try engine.newGame(seed: 1, civilizations: ["greece", "egypt"])
        #expect(engine.tradeRoutes(in: s).isEmpty)
    }

    @Test func peacefulCoastsTrade() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["greece", "egypt"])
        s.peace.insert(CivPair("greece", "egypt"))
        let route = try #require(engine.tradeRoute(between: "greece", and: "egypt", in: s))
        #expect(route.chokepoints.isEmpty)
        #expect(route.tolls.isEmpty)
        #expect(engine.tradeGold(for: "greece", [route]) == 2)
    }

    @Test func landlockedPartnersDontTrade() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["greece", "mesopotamia"])
        s.peace.insert(CivPair("greece", "mesopotamia"))
        // Mesopotamia's only sea is the Persian Gulf, cut off from the Mediterranean.
        #expect(engine.tradeRoute(between: "greece", and: "mesopotamia", in: s) == nil)
        own(&s, "mesopotamia", "syria")  // a Mediterranean coast
        #expect(engine.tradeRoute(between: "greece", and: "mesopotamia", in: s) != nil)
    }

    @Test func thirdPartyChokepointTakesToll() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["greece", "egypt", "italia"])
        // Greece's home is only Dacia, on the Black Sea.
        s.land["greece"]!.owner = nil
        own(&s, "greece", "dacia")
        own(&s, "italia", "thrace", "anatolia")
        s.peace.insert(CivPair("greece", "egypt"))
        s.peace.insert(CivPair("greece", "italia"))
        s.peace.insert(CivPair("egypt", "italia"))

        let route = try #require(engine.tradeRoute(between: "greece", and: "egypt", in: s))
        #expect(route.chokepoints == ["bosporus"])
        #expect(route.tolls == ["italia"])
        let routes = engine.tradeRoutes(in: s)
        let greeceEgypt = routes.filter { $0.partners == CivPair("greece", "egypt") }
        #expect(engine.tradeGold(for: "greece", greeceEgypt) == 1)
        #expect(engine.tradeGold(for: "italia", greeceEgypt) == 2)

        // At war with the holder, the strait is shut and the route is gone.
        s.peace.remove(CivPair("greece", "italia"))
        #expect(engine.tradeRoute(between: "greece", and: "egypt", in: s) == nil)
    }

    @Test func bronzeFromOwnCopperAndTin() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["egypt"])
        own(&s, "egypt", "cyprus", "britain")  // copper 3, tin 2
        let events = try engine.apply(.endTurn, to: &s)
        #expect(events.contains(.bronzeMade(civ: "egypt", amount: 2)))
        #expect(s.civs["egypt"]!.bronze == 2)
    }

    @Test func tradeSharesResources() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["egypt", "greece"])
        own(&s, "egypt", "cyprus")    // copper 3
        own(&s, "greece", "britain")  // tin 2
        #expect(engine.effectiveYield(of: .tin, for: "egypt", in: s) == 0)
        s.peace.insert(CivPair("egypt", "greece"))
        #expect(engine.effectiveYield(of: .tin, for: "egypt", in: s) == 1)
        #expect(engine.effectiveYield(of: .copper, for: "greece", in: s) == 1)
        #expect(engine.effectiveYield(of: .grain, for: "egypt", in: s) == 12)  // grain isn't shared
    }

    @Test func tradedHorsesAllowCavalry() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["greece", "egypt"])
        own(&s, "egypt", "thrace", "scythe")  // horses 1 + 2 = 3 → Greece gets 1
        s.peace.insert(CivPair("greece", "egypt"))
        s.civs["greece"]!.gold = 100
        s.land["greece"]!.population = 2
        try engine.apply(.recruit(territory: "greece", unit: .cavalry, count: 1), to: &s)
        #expect(s.armies["greece"]!.units.cavalry == 1)
    }
}
