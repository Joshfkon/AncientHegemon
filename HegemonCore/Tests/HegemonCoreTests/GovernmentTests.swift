import Foundation
import Testing
@testable import HegemonCore

private func own(_ s: inout GameState, _ civ: CivilizationID, _ territories: TerritoryID...) {
    for t in territories { s.land[t]!.owner = civ }
}

@Suite struct SuccessionTests {
    let engine = try! Engine.bare()

    @Test func adultHeirSucceedsSmoothly() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["egypt"])
        s.civs["egypt"]!.heir = Heir(name: "Ramesses", age: 30)
        let events = engine.rulerDies("egypt", cause: .oldAge, &s)
        #expect(events.contains(.succession(civ: "egypt", ruler: "Ramesses", outcome: .smooth)))
        #expect(s.civs["egypt"]!.ruler.name == "Ramesses")
        #expect(s.civs["egypt"]!.heir == nil)
    }

    @Test func childHeirMeansRegency() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["egypt"])
        s.civs["egypt"]!.heir = Heir(name: "Tut", age: 9)
        let before = s.civs["egypt"]!.legitimacy
        let events = engine.rulerDies("egypt", cause: .oldAge, &s)
        #expect(events.contains(.succession(civ: "egypt", ruler: "Tut", outcome: .regency)))
        #expect(s.civs["egypt"]!.legitimacy == before + engine.rules.government.legitimacy.regency)
    }

    /// Egypt with a famous, disloyal general leading 5 infantry in Libya.
    private func egyptWithAmbitiousGeneral(gold: Int) throws -> (GameState, GeneralID) {
        var s = try engine.newGame(seed: 1, civilizations: ["egypt"])
        own(&s, "egypt", "libya", "cyrenaica", "petraea")
        s.armies["libya"] = Army(owner: "egypt", units: UnitCounts(infantry: 5))
        let id = s.general(of: "egypt", at: "egypt")!.id
        s.generals[id]!.location = "libya"
        s.generals[id]!.renown = 3
        s.generals[id]!.loyalty = 50
        s.civs["egypt"]!.heir = nil
        s.civs["egypt"]!.gold = gold
        return (s, id)
    }

    @Test func claimantsCanBeBoughtOff() throws {
        var (s, id) = try egyptWithAmbitiousGeneral(gold: 50)
        let events = engine.rulerDies("egypt", cause: .oldAge, &s)
        #expect(events.contains { if case .succession(_, _, .bribed) = $0 { true } else { false } })
        #expect(s.generals[id]!.owner == "egypt")
        #expect(s.civs["egypt"]!.gold == 50 - engine.rules.government.bribePerClaimant)
    }

    @Test func unpaidClaimantsStartACivilWar() throws {
        var (s, id) = try egyptWithAmbitiousGeneral(gold: 0)
        let events = engine.rulerDies("egypt", cause: .oldAge, &s)
        guard case let .civilWar(civ, rebel, general, territories)? = events.first(where: {
            if case .civilWar = $0 { true } else { false }
        }) else {
            Issue.record("no civil war in \(events)")
            return
        }
        #expect(civ == "egypt" && general == id)
        // Libya and Cyrenaica are nearer the general than the capital; Petraea is not.
        #expect(territories == ["cyrenaica", "libya"])
        #expect(s.owner(of: "libya") == rebel && s.armies["libya"]!.owner == rebel)
        #expect(s.owner(of: "petraea") == "egypt")
        #expect(s.players.contains(rebel))
        #expect(s.atWar("egypt", rebel))
        #expect(s.civs[rebel]!.rebelledFrom == "egypt")
        #expect(s.generals[id]!.owner == rebel)
    }

    @Test func famousGeneralSeizesTheRepublic() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["italia"])
        let id = s.general(of: "italia", at: "italia")!.id
        s.generals[id]!.renown = 5
        s.generals[id]!.loyalty = 30
        let events = engine.rulerDies("italia", cause: .oldAge, &s)
        #expect(events.contains { if case .succession(_, _, .coup) = $0 { true } else { false } })
        #expect(s.civs["italia"]!.government == .monarchy)
        #expect(s.civs["italia"]!.ruler.name == s.generals[id]!.name)
    }

    @Test func republicsElectWithoutFuss() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["italia"])
        let events = engine.rulerDies("italia", cause: .oldAge, &s)
        #expect(events.contains { if case .succession(_, _, .smooth) = $0 { true } else { false } })
        #expect(s.civs["italia"]!.government == .republic)
    }
}

@Suite struct LoyaltyTests {
    let engine = try! Engine.bare()

    @Test func renownAndDistanceErodeLoyalty() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["mesopotamia"])
        own(&s, "mesopotamia", "media", "armenia", "anatolia")
        let id = s.general(of: "mesopotamia", at: "mesopotamia")!.id
        var home = s
        s.generals[id]!.location = "anatolia"
        s.generals[id]!.renown = 4
        for _ in 0..<6 {
            _ = engine.governmentPhase("mesopotamia", &s)
            _ = engine.governmentPhase("mesopotamia", &home)
        }
        #expect(s.generals[id]!.loyalty < home.generals[id]!.loyalty)
        #expect(s.generals[id]!.loyalty < 40)
    }

    @Test func honorsRestoreLoyaltyForGold() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["mesopotamia"])
        let id = s.general(of: "mesopotamia", at: "mesopotamia")!.id
        s.generals[id]!.loyalty = 20
        s.generals[id]!.renown = 2
        s.civs["mesopotamia"]!.gold = 20
        try engine.apply(.honorGeneral(id), to: &s)
        #expect(s.generals[id]!.loyalty == 20 + engine.rules.government.honorLoyalty)
        #expect(s.civs["mesopotamia"]!.gold == 20 - engine.rules.government.honorCost * 3)
    }

    @Test func appointingGeneralsIsCappedBySize() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["mesopotamia"])
        s.civs["mesopotamia"]!.gold = 100
        #expect(throws: GameError.tooManyGenerals) {
            try engine.apply(.appointGeneral(territory: "mesopotamia"), to: &s)
        }
        own(&s, "mesopotamia", "media", "armenia", "persia", "syria", "taurus")
        let events = try engine.apply(.appointGeneral(territory: "mesopotamia"), to: &s)
        guard case let .generalAppointed(_, id)? = events.first else {
            Issue.record("no appointment")
            return
        }
        #expect(s.generals[id]!.location == "mesopotamia")
        #expect(s.civs["mesopotamia"]!.gold == 100 - engine.rules.government.appointCost)
    }

    @Test func legitimacyFollowsVictoryAndDefeat() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["mesopotamia", "greece"])
        own(&s, "greece", "persia")
        s.armies["persia"] = Army(owner: "greece", units: UnitCounts(infantry: 1))
        s.armies["mesopotamia"]!.units.infantry = 12
        let (m, g) = (s.civs["mesopotamia"]!.legitimacy, s.civs["greece"]!.legitimacy)
        try engine.apply(.move(from: "mesopotamia", to: "persia", units: UnitCounts(infantry: 12)), to: &s)
        let l = engine.rules.government.legitimacy
        #expect(s.civs["mesopotamia"]!.legitimacy == m + l.battleWon + l.capture)
        #expect(s.civs["greece"]!.legitimacy == g + l.battleLost)
    }
}

@Suite struct EventTests {
    let engine = try! Engine.bundled()

    private func weight(_ kind: EventKind, _ civ: CivilizationID, _ s: GameState) -> Int {
        engine.eventWeights(civ, s).first { $0.0 == kind }!.1
    }

    @Test func riverValleysCarryBothFortunes() throws {
        let s = try engine.newGame(seed: 1)
        #expect(weight(.famine, "egypt", s) > weight(.famine, "greece", s))
        #expect(weight(.goodHarvest, "egypt", s) > weight(.goodHarvest, "greece", s))
        #expect(weight(.flood, "mesopotamia", s) > 0)
        #expect(weight(.flood, "italia", s) == 0)
    }

    @Test func frontierEmpiresMeetTheMigrations() throws {
        var s = try engine.newGame(seed: 1)
        #expect(weight(.barbarians, "italia", s) == 0)
        s.land["media"]!.owner = "mesopotamia"  // next to Dahā
        #expect(weight(.barbarians, "mesopotamia", s) > 0)
    }

    @Test func tradeBringsPlague() throws {
        var s = try engine.newGame(seed: 1)
        let alone = weight(.plague, "greece", s)
        s.peace.insert(CivPair("greece", "egypt"))
        s.peace.insert(CivPair("greece", "italia"))
        #expect(weight(.plague, "greece", s) > alone)
    }

    @Test func plagueTravelsAlongRoutes() throws {
        let calm = try Engine.calm()
        var s = try calm.newGame(seed: 3)
        s.peace.insert(CivPair("greece", "egypt"))
        s.peace.insert(CivPair("greece", "italia"))
        let before = calm.homeNetwork(of: "greece", in: s).reduce(0) { $0 + s.population(of: $1) }
        var infected = 0
        for seed in 0..<20 {
            var t = s
            t.rng = SeededRNG(seed: UInt64(seed))
            _ = calm.plague("greece", spreads: true, &t)
            infected += ["egypt", "italia"].filter { t.civs[$0]!.plagueIncoming }.count
            #expect(calm.homeNetwork(of: "greece", in: t).reduce(0) { $0 + t.population(of: $1) } < before)
        }
        #expect(infected > 0 && infected < 40)
    }

    @Test func badOmenForbidsAttacks() throws {
        let bare = try Engine.bare()
        var s = try bare.newGame(seed: 1, civilizations: ["mesopotamia", "greece"])
        own(&s, "greece", "persia")
        s.civs["mesopotamia"]!.omen = true
        #expect(throws: GameError.badOmen) {
            try bare.apply(.move(from: "mesopotamia", to: "persia", units: UnitCounts(infantry: 1)), to: &s)
        }
        // Walking into empty, unclaimed land is still allowed.
        try bare.apply(.move(from: "mesopotamia", to: "media", units: UnitCounts(infantry: 1)), to: &s)
    }

    @Test func raidersCanEndAGame() throws {
        let bare = try Engine.bare()
        var s = try bare.newGame(seed: 1, civilizations: ["greece"])
        s.armies["greece"] = nil
        let events = bare.raid(barbariansID, UnitCounts(infantry: 5), into: "greece", fallback: nil, &s)
        #expect(events.contains(.eliminated(civ: "greece")))
        #expect(s.winner == barbariansID)
        #expect(s.armies["greece"]?.owner == barbariansID)
        #expect(s.owner(of: "greece") == nil)
    }

    @Test func goldDiscoveriesPay() throws {
        let calm = try Engine.calm()
        var s = try calm.newGame(seed: 1, civilizations: ["mesopotamia"])
        var plain = s
        s.bonusGold["mesopotamia"] = 2
        try calm.apply(.endTurn, to: &s)
        try calm.apply(.endTurn, to: &plain)
        #expect(s.civs["mesopotamia"]!.gold == plain.civs["mesopotamia"]!.gold + 2)
    }

    @Test func famineHalvesTheHarvest() throws {
        let calm = try Engine.calm()
        var s = try calm.newGame(seed: 1, civilizations: ["egypt"])
        s.turn = 2
        s.harvestPercent["egypt"] = 50
        let events = calm.harvest("egypt", &s)
        guard case let .harvest(_, production, _, _, _, _)? = events.first else {
            Issue.record("no harvest")
            return
        }
        // Egypt 10 → 5, plus Libya 1, Petraea 1 and Syria 4.
        #expect(production == 11)
        #expect(s.harvestPercent.isEmpty)
    }
}
