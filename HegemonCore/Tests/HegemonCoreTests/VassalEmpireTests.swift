import Testing
@testable import HegemonCore

@Suite struct VassalEmpireTests {
    let engine = try! Engine.bare()

    /// Mesopotamia (to move) at war with Egypt, which holds Syria next door; `egypt` and
    /// `meso` infantry in each capital.
    func world(egypt: Int = 10, meso: Int = 10, civs: [CivilizationID] = ["mesopotamia", "egypt"]) throws -> GameState {
        var s = try engine.newGame(seed: 1, civilizations: civs)
        s.land["syria"]!.owner = "egypt"
        s.armies["egypt"]!.units = UnitCounts(infantry: egypt)
        s.armies["mesopotamia"]!.units = UnitCounts(infantry: meso)
        s.activePlayerIndex = s.players.firstIndex(of: "mesopotamia")!
        return s
    }

    func passTurn(_ s: inout GameState) throws -> [GameEvent] {
        try engine.apply(.endTurn, to: &s)
    }

    // MARK: Acceptance

    @Test func aStrongCourtRefuses() throws {
        var s = try world(egypt: 8, meso: 10)
        let events = try engine.apply(.demandSubmission(of: "egypt"), to: &s)
        #expect(events == [.submissionRefused(by: "egypt", to: "mesopotamia")])
        #expect(engine.liege(of: "egypt", in: s) == nil)
        #expect(s.atWar("egypt", "mesopotamia"))
    }

    @Test func aBadlyOutnumberedCourtSubmits() throws {
        var s = try world(egypt: 3, meso: 10)
        #expect(engine.wouldSubmit("egypt", to: "mesopotamia", in: s))
        let events = try engine.apply(.demandSubmission(of: "egypt"), to: &s)
        #expect(events.first == .submitted(vassal: "egypt", overlord: "mesopotamia"))
        #expect(events.contains(.peaceMade(CivPair("egypt", "mesopotamia"))))
        #expect(engine.liege(of: "egypt", in: s) == "mesopotamia")
        #expect(engine.vassalEmpires(of: "mesopotamia", in: s) == ["egypt"])
        #expect(s.atPeace("egypt", "mesopotamia"))
    }

    @Test func aDistantEmpireIsNotFeared() throws {
        var s = try world(egypt: 2, meso: 12)
        // Without Syria, no land of Egypt's touches Mesopotamia's.
        s.land["syria"]!.owner = nil
        #expect(!engine.wouldSubmit("egypt", to: "mesopotamia", in: s))
        let events = try engine.apply(.demandSubmission(of: "egypt"), to: &s)
        #expect(events == [.submissionRefused(by: "egypt", to: "mesopotamia")])
    }

    @Test func losingTheCapitalToTheDemanderIsEnough() throws {
        var s = try world(egypt: 7, meso: 10)
        #expect(!engine.wouldSubmit("egypt", to: "mesopotamia", in: s))
        // Egypt's army fell back to Syria; Mesopotamia holds Thebes.
        s.armies["syria"] = s.armies["egypt"]
        s.armies["egypt"] = nil
        s.land["egypt"]!.owner = "mesopotamia"
        #expect(engine.wouldSubmit("egypt", to: "mesopotamia", in: s))
        // …but not to someone who doesn't hold it, nor when it is still the stronger.
        s.armies["syria"]!.units = UnitCounts(infantry: 12)
        #expect(!engine.wouldSubmit("egypt", to: "mesopotamia", in: s))
    }

    @Test func onlyAtWarAndOnlyOnce() throws {
        var s = try world(egypt: 3, meso: 10)
        s.peace.insert(CivPair("egypt", "mesopotamia"))
        #expect(throws: GameError.notAtWar("egypt")) { try engine.apply(.demandSubmission(of: "egypt"), to: &s) }
        s.peace.remove(CivPair("egypt", "mesopotamia"))
        _ = try engine.apply(.demandSubmission(of: "egypt"), to: &s)
        // A vassal demands nothing of anyone.
        s.activePlayerIndex = s.players.firstIndex(of: "egypt")!
        #expect(!engine.wouldSubmit("mesopotamia", to: "egypt", in: s))
    }

    @Test func aPersonIsAskedAndMayRefuse() throws {
        var s = try world(egypt: 3, meso: 10)
        s.civs["egypt"]!.isHuman = true
        let events = try engine.apply(.demandSubmission(of: "egypt"), to: &s)
        #expect(events == [.submissionDemanded(from: "mesopotamia", to: "egypt")])
        #expect(s.submissionDemands.contains(PeaceOffer(from: "mesopotamia", to: "egypt")))
        s.activePlayerIndex = s.players.firstIndex(of: "egypt")!
        let answer = try engine.apply(.answerSubmission(from: "mesopotamia", accept: false), to: &s)
        #expect(answer == [.submissionRefused(by: "egypt", to: "mesopotamia")])
        #expect(s.submissionDemands.isEmpty)
        #expect(engine.liege(of: "egypt", in: s) == nil)
        #expect(throws: GameError.noSubmissionDemand("mesopotamia")) {
            try engine.apply(.answerSubmission(from: "mesopotamia", accept: true), to: &s)
        }
    }

    @Test func aPersonMayBow() throws {
        var s = try world(egypt: 3, meso: 10)
        s.civs["egypt"]!.isHuman = true
        _ = try engine.apply(.demandSubmission(of: "egypt"), to: &s)
        s.activePlayerIndex = s.players.firstIndex(of: "egypt")!
        let answer = try engine.apply(.answerSubmission(from: "mesopotamia", accept: true), to: &s)
        #expect(answer.first == .submitted(vassal: "egypt", overlord: "mesopotamia"))
        #expect(engine.liege(of: "egypt", in: s) == "mesopotamia")
    }

    // MARK: Effects

    @Test func neitherMayBreakThePeace() throws {
        var s = try world(egypt: 3, meso: 10)
        _ = try engine.apply(.demandSubmission(of: "egypt"), to: &s)
        #expect(throws: GameError.vassalBound("egypt")) { try engine.apply(.declareWar(on: "egypt"), to: &s) }
        s.activePlayerIndex = s.players.firstIndex(of: "egypt")!
        #expect(throws: GameError.vassalBound("mesopotamia")) { try engine.apply(.declareWar(on: "mesopotamia"), to: &s) }
    }

    @Test func theVassalMakesPeaceWithTheOverlordsAlliesAndKeepsNoAlliesOfItsOwn() throws {
        var s = try world(egypt: 3, meso: 10, civs: ["mesopotamia", "egypt", "greece", "italia"])
        s.peace.insert(CivPair("mesopotamia", "greece"))
        s.alliances.insert(CivPair("mesopotamia", "greece"))
        s.peace.insert(CivPair("egypt", "italia"))
        s.alliances.insert(CivPair("egypt", "italia"))
        let events = try engine.apply(.demandSubmission(of: "egypt"), to: &s)
        #expect(events.contains(.allianceEnded(CivPair("egypt", "italia"), by: "egypt")))
        #expect(events.contains(.peaceMade(CivPair("egypt", "greece"))))
        #expect(s.atPeace("egypt", "greece"))
        #expect(!engine.mayDeclareWar("egypt", on: "greece", in: s))
        #expect(engine.mayDeclareWar("egypt", on: "italia", in: s))
        s.activePlayerIndex = s.players.firstIndex(of: "egypt")!
        #expect(throws: GameError.vassalBound("greece")) { try engine.apply(.declareWar(on: "greece"), to: &s) }
        #expect(throws: GameError.vassalBound("mesopotamia")) { try engine.apply(.offerAlliance(to: "italia"), to: &s) }
    }

    @Test func theOverlordGainsPrestige() throws {
        var s = try world(egypt: 3, meso: 10)
        let before = engine.prestige(of: "mesopotamia", in: s)
        _ = try engine.apply(.demandSubmission(of: "egypt"), to: &s)
        #expect(engine.prestige(of: "mesopotamia", in: s) == before + engine.rules.submission.prestige)
        #expect(engine.prestigeBreakdown(of: "mesopotamia", in: s).contains {
            $0.source == "Vassal empires" && $0.points == engine.rules.submission.prestige
        })
    }

    @Test func theVassalPaysAFifthOfItsIncome() throws {
        var s = try world(egypt: 3, meso: 10)
        _ = try engine.apply(.demandSubmission(of: "egypt"), to: &s)
        // Mesopotamia ends its turn; Egypt's turn 1 has no harvest, so play on to turn 2.
        _ = try passTurn(&s)
        _ = try passTurn(&s)
        _ = try passTurn(&s)
        #expect(s.activePlayer == "egypt")
        let income = engine.economy(of: "egypt", in: s).income
        let forecast = engine.economy(of: "egypt", in: s).tributePaid
        #expect(forecast == income * engine.rules.submission.tributePercent / 100)
        // Egypt's harvest happens as its next turn begins.
        _ = try passTurn(&s)
        let lordGold = s.civs["mesopotamia"]!.gold
        let events = try passTurn(&s)
        guard let paid = events.lazy.compactMap({ e -> Int? in
            if case let .tributePaid("egypt", "mesopotamia", gold) = e { gold } else { nil }
        }).first else {
            Issue.record("no tribute paid: \(events)")
            return
        }
        #expect(paid > 0)
        var harvested = 0
        for e in events { if case let .harvest("egypt", _, _, _, _, income) = e { harvested = income } }
        #expect(paid == harvested * engine.rules.submission.tributePercent / 100)
        #expect(s.civs["mesopotamia"]!.gold == lordGold + paid)
        #expect(s.vassalage["egypt"]?.lastTribute == paid)
        #expect(engine.economy(of: "mesopotamia", in: s).tributeReceived == paid)
    }

    // MARK: Going free

    @Test func aVassalThatOutgrowsItsOverlordGoesFree() throws {
        var s = try world(egypt: 3, meso: 10)
        _ = try engine.apply(.demandSubmission(of: "egypt"), to: &s)
        s.armies["egypt"]!.units = UnitCounts(infantry: 15)
        let events = try passTurn(&s)
        #expect(events.contains(.vassalEmpireFreed(vassal: "egypt", overlord: "mesopotamia", overlordFell: false)))
        #expect(engine.liege(of: "egypt", in: s) == nil)
        // The peace stands, but it can be broken now.
        #expect(s.atPeace("egypt", "mesopotamia"))
        #expect(engine.mayDeclareWar("egypt", on: "mesopotamia", in: s))
    }

    @Test func aVassalGoesFreeWhenItsOverlordFalls() throws {
        var s = try world(egypt: 3, meso: 10, civs: ["mesopotamia", "egypt", "greece"])
        _ = try engine.apply(.demandSubmission(of: "egypt"), to: &s)
        // Greece overruns everything Mesopotamia has.
        s.land["mesopotamia"]!.owner = "greece"
        s.armies["mesopotamia"] = nil
        let events = engine.checkElimination("mesopotamia", &s)
        #expect(events.contains(.eliminated(civ: "mesopotamia")))
        #expect(events.contains(.vassalEmpireFreed(vassal: "egypt", overlord: "mesopotamia", overlordFell: true)))
        #expect(s.vassalage.isEmpty)
    }

    // MARK: The AI

    @Test func anAIOverlordDemandsSubmissionFromABeatenRival() throws {
        var s = try world(egypt: 2, meso: 12)
        let ai = AIPlayer(engine: engine, personality: .conqueror)
        let turn = ai.playTurn(&s)
        #expect(turn.events.contains(.submitted(vassal: "egypt", overlord: "mesopotamia")))
        #expect(engine.liege(of: "egypt", in: s) == "mesopotamia")
        #expect(turn.rejected.isEmpty)
    }

    @Test func anAIAsksAPersonOnceAndThenWaits() throws {
        var s = try world(egypt: 2, meso: 12)
        s.civs["egypt"]!.isHuman = true
        let ai = AIPlayer(engine: engine, personality: .conqueror)
        let turn = ai.playTurn(&s)
        #expect(turn.events.contains(.submissionDemanded(from: "mesopotamia", to: "egypt")))
        #expect(!turn.events.contains(.peaceOffered(from: "mesopotamia", to: "egypt")))
        #expect(s.submissionDemands.contains(PeaceOffer(from: "mesopotamia", to: "egypt")))
    }

    @Test func anAIVassalNeverTurnsOnItsOverlord() throws {
        // Egypt is a vassal next to a Mesopotamia only a little stronger: as a free conqueror
        // it would fall on it.
        var s = try world(egypt: 3, meso: 10)
        _ = try engine.apply(.demandSubmission(of: "egypt"), to: &s)
        s.armies["egypt"]!.units = UnitCounts(infantry: 9)
        let ai = AIPlayer(engine: engine, personality: .conqueror)
        for _ in 0..<6 where s.winner == nil {
            if s.activePlayer == "egypt" {
                let turn = ai.playTurn(&s)
                #expect(turn.rejected.isEmpty)
            } else {
                _ = try passTurn(&s)
            }
            #expect(s.atPeace("egypt", "mesopotamia"))
        }
    }

    // MARK: Military access

    /// Egypt, Mesopotamia's vassal, holds Syria (next to Mesopotamia) with no army in it.
    func vassalWorld(civs: [CivilizationID] = ["mesopotamia", "egypt"]) throws -> GameState {
        var s = try world(egypt: 3, meso: 10, civs: civs)
        _ = try engine.apply(.demandSubmission(of: "egypt"), to: &s)
        return s
    }

    @Test func anOverlordStationsTroopsInItsVassalsLand() throws {
        var s = try vassalWorld()
        let events = try engine.apply(.move(from: "mesopotamia", to: "syria", units: UnitCounts(infantry: 3)), to: &s)
        #expect(events == [.moved(civ: "mesopotamia", from: "mesopotamia", to: "syria", units: UnitCounts(infantry: 3))])
        #expect(s.owner(of: "syria") == "egypt")
        #expect(s.armies["syria"]?.owner == "mesopotamia")
        #expect(engine.hasAccess("mesopotamia", to: "syria", in: s))
        // The vassal feeds them: no losses out of supply at the overlord's harvest.
        var harvest: [GameEvent] = []
        for _ in 0..<4 { harvest += try passTurn(&s) }
        #expect(!harvest.contains { if case .outOfSupply("mesopotamia", "syria", _) = $0 { true } else { false } })
        #expect(s.armies["syria"]?.units.total == 3)
    }

    @Test func troopsMarchThroughAVassalsLandInOneOrder() throws {
        var s = try vassalWorld()
        // The vassal's own army stands in Syria: no room to stop, but the road is open.
        s.armies["syria"] = Army(owner: "egypt", units: UnitCounts(infantry: 2))
        #expect(throws: GameError.contested("syria")) {
            try engine.apply(.move(from: "mesopotamia", to: "syria", units: UnitCounts(infantry: 2)), to: &s)
        }
        #expect(engine.empirePassage(from: "mesopotamia", to: "petraea", for: "mesopotamia", in: s) == "syria")
        #expect(engine.empirePassageTargets(from: "mesopotamia", for: "mesopotamia", in: s).contains { $0 == ("petraea", "syria") })
        let events = try engine.apply(.move(from: "mesopotamia", to: "petraea", units: UnitCounts(infantry: 2)), to: &s)
        #expect(events.contains(.moved(civ: "mesopotamia", from: "mesopotamia", to: "syria", units: UnitCounts(infantry: 2))))
        #expect(events.contains(.moved(civ: "mesopotamia", from: "syria", to: "petraea", units: UnitCounts(infantry: 2))))
        #expect(s.owner(of: "petraea") == "mesopotamia")
        #expect(s.armies["syria"]?.owner == "egypt")
        // Nobody else gets through: Greece has no vassal there.
        #expect(engine.empirePassage(from: "mesopotamia", to: "petraea", for: "greece", in: s) == nil)
    }

    @Test func aGarrisonShieldsTheVassalFromTheOverlordsFriends() throws {
        var s = try vassalWorld(civs: ["mesopotamia", "egypt", "greece"])
        _ = try engine.apply(.move(from: "mesopotamia", to: "syria", units: UnitCounts(infantry: 3)), to: &s)
        // Greece, at peace with Mesopotamia but at war with Egypt, stands next door in Taurus.
        s.peace.insert(CivPair("greece", "mesopotamia"))
        s.land["taurus"]!.owner = "greece"
        s.armies["taurus"] = Army(owner: "greece", units: UnitCounts(infantry: 8))
        s.activePlayerIndex = s.players.firstIndex(of: "greece")!
        #expect(throws: GameError.atPeace("syria")) {
            try engine.apply(.move(from: "taurus", to: "syria", units: UnitCounts(infantry: 8)), to: &s)
        }
    }

    @Test func theVassalCannotFallOnTheGarrison() throws {
        var s = try vassalWorld()
        _ = try engine.apply(.move(from: "mesopotamia", to: "syria", units: UnitCounts(infantry: 3)), to: &s)
        s.land["petraea"]!.owner = "egypt"
        s.armies["petraea"] = Army(owner: "egypt", units: UnitCounts(infantry: 2))
        s.activePlayerIndex = s.players.firstIndex(of: "egypt")!
        #expect(throws: GameError.atPeace("syria")) {
            try engine.apply(.move(from: "petraea", to: "syria", units: UnitCounts(infantry: 2)), to: &s)
        }
    }

    @Test func garrisonsGoHomeWhenTheVassalGoesFree() throws {
        var s = try vassalWorld()
        _ = try engine.apply(.move(from: "mesopotamia", to: "syria", units: UnitCounts(infantry: 3)), to: &s)
        s.armies["egypt"]!.units = UnitCounts(infantry: 20)
        let events = try passTurn(&s)
        #expect(events.contains(.vassalEmpireFreed(vassal: "egypt", overlord: "mesopotamia", overlordFell: false)))
        #expect(events.contains(.moved(civ: "mesopotamia", from: "syria", to: "mesopotamia", units: UnitCounts(infantry: 3))))
        #expect(s.armies["syria"] == nil)
        #expect(s.armies["mesopotamia"]?.units.total == 10)
    }
}
