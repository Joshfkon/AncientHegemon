import Testing
@testable import HegemonCore

private func play(_ s: inout GameState, as civ: CivilizationID) {
    s.activePlayerIndex = s.players.firstIndex(of: civ)!
}

@Suite struct QueueTests {
    let engine = try! Engine.bare()

    func rich() throws -> GameState {
        var s = try engine.newGame(seed: 1, civilizations: ["egypt"])
        s.civs["egypt"]!.gold = 200
        s.civs["egypt"]!.stock = [.stone: 20, .timber: 20]
        return s
    }

    @Test func queuedWorkStartsWhenTheSiteIsFree() throws {
        var s = try rich()
        try engine.apply(.build(territory: "egypt", project: .farm), to: &s)
        try engine.apply(.queueProject(territory: "egypt", project: .road), to: &s)
        #expect(s.land["egypt"]!.queue == [.road])
        for _ in 0..<3 { try engine.apply(.endTurn, to: &s) }
        #expect(s.land["egypt"]!.improvements.contains(.farm))
        #expect(s.land["egypt"]!.construction?.kind == .road)
        #expect(s.land["egypt"]!.queue.isEmpty)
    }

    @Test func queueingOnAnIdleSiteStartsAtOnce() throws {
        var s = try rich()
        let events = try engine.apply(.queueProject(territory: "egypt", project: .walls), to: &s)
        #expect(events.contains(.projectStarted(civ: "egypt", territory: "egypt", project: .walls)))
        #expect(s.land["egypt"]!.queue.isEmpty)
    }
}

@Suite struct SplendourAndIronTests {
    let engine = try! Engine.bare()

    @Test func aSecureLeadingRealmEntersSplendour() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["egypt"])
        s.turn = 7
        s.civs["egypt"]!.legitimacy = 90
        let events = try engine.apply(.endTurn, to: &s)
        #expect(events.contains(.splendourBegan(civ: "egypt")))
        #expect(s.civs["egypt"]!.splendour == engine.rules.splendour.rounds)
    }

    @Test func splendourBuildsTwiceAsFast() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["egypt"])
        s.turn = 3
        s.civs["egypt"]!.splendour = 3
        s.land["egypt"]!.construction = Construction(kind: .walls, turnsLeft: 4)
        try engine.apply(.endTurn, to: &s)
        #expect(s.land["egypt"]!.construction?.turnsLeft == 2)
    }

    @Test func theIronAgeComesWithTheCollapse() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["egypt"])
        #expect(!engine.ironWorked("egypt", s))
        s.turn = engine.rules.collapse.peakRound
        try engine.apply(.endTurn, to: &s)
        #expect(s.ironAge)
        #expect(engine.ironWorked("egypt", s))
    }
}

@Suite struct SackTests {
    let engine = try! Engine.bare()

    @Test func takingACapitalCarriesOffHalfItsTreasury() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["egypt", "mesopotamia"])
        s.land["petraea"]!.owner = "mesopotamia"
        s.armies["petraea"] = Army(owner: "mesopotamia", units: UnitCounts(infantry: 40))
        s.armies["egypt"] = Army(owner: "egypt", units: UnitCounts(infantry: 1))
        s.civs["egypt"]!.gold = 40
        let before = s.civs["mesopotamia"]!.gold
        play(&s, as: "mesopotamia")
        let events = try engine.apply(.move(from: "petraea", to: "egypt", units: UnitCounts(infantry: 40)), to: &s)
        #expect(events.contains(.capitalSacked(by: "mesopotamia", from: "egypt", territory: "egypt", gold: 20)))
        #expect(s.civs["mesopotamia"]!.gold == before + 20)
        #expect(s.civs["mesopotamia"]!.sacked == 1)
    }
}

@Suite struct SiegeTests {
    let engine = try! Engine.bare()

    /// Mesopotamia camped in Petraea before walled Egypt.
    func siege(granary: Bool = false) throws -> GameState {
        var s = try engine.newGame(seed: 1, civilizations: ["egypt", "mesopotamia"])
        s.turn = 3
        s.land["egypt"]!.improvements.insert(.walls)
        if granary { s.land["egypt"]!.improvements.insert(.granary) }
        s.armies["egypt"] = Army(owner: "egypt", units: UnitCounts(infantry: 8))
        // Paid and fed, so only the siege thins the garrison.
        s.civs["egypt"]!.gold = 200
        s.civs["egypt"]!.granary = 200
        s.civs["mesopotamia"]!.gold = 200
        s.civs["mesopotamia"]!.granary = 200
        s.land["petraea"]!.owner = "mesopotamia"
        s.armies["petraea"] = Army(owner: "mesopotamia", units: UnitCounts(infantry: 6))
        play(&s, as: "mesopotamia")
        try engine.apply(.besiege(territory: "egypt", from: "petraea"), to: &s)
        return s
    }

    /// Ends Mesopotamia's turn and Egypt's, so Mesopotamia's next turn presses the siege.
    func round(_ s: inout GameState) throws {
        while true {
            try engine.apply(.endTurn, to: &s)
            if s.activePlayer == "mesopotamia" { return }
        }
    }

    @Test func aSiegeStarvesTheGarrisonAndWearsDownTheWalls() throws {
        var s = try siege()
        let walls = engine.fortification(at: "egypt", s)
        try round(&s)
        // The town's own stores hold the first round.
        #expect(s.sieges["egypt"]?.rounds == 1)
        #expect(s.armies["egypt"]!.units.total == 8)
        #expect(engine.fortification(at: "egypt", s) == walls - engine.rules.siege.wallDamagePercent)
        try round(&s)
        #expect(s.armies["egypt"]!.units.total == 7)
    }

    @Test func aGranaryHoldsOffHunger() throws {
        var s = try siege(granary: true)
        for _ in 0..<3 { try round(&s) }
        #expect(s.armies["egypt"]!.units.total == 8)
    }

    @Test func sicknessSpreadsInALongSiegesCamp() throws {
        var s = try siege(granary: true)
        for _ in 0..<engine.rules.siege.campSicknessFrom { try round(&s) }
        #expect(s.armies["petraea"]?.units.total == 5, "camp \(String(describing: s.armies["petraea"]?.units.total)), siege \(String(describing: s.sieges["egypt"]))")
    }

    @Test func aStarvingGarrisonSalliesWhenItHasAChance() throws {
        var s = try siege()
        s.armies["egypt"]!.units = UnitCounts(infantry: 12)
        s.armies["petraea"]!.units = UnitCounts(infantry: 4)
        try round(&s)
        try round(&s)
        // Egypt's turn: the AI goes out to meet the camp.
        s.civs["egypt"]!.isHuman = false
        while s.activePlayer != "egypt" { try engine.apply(.endTurn, to: &s) }
        let turn = AIPlayer(engine: engine, personality: .turtle).play(&s)
        #expect(turn.events.contains { if case let .moved(civ, from, to, _) = $0 { civ == "egypt" && from == "egypt" && to == "petraea" } else { false } })
    }

    @Test func leavingCampLiftsTheSiege() throws {
        var s = try siege()
        s.armies["petraea"] = nil
        try round(&s)
        #expect(s.sieges["egypt"] == nil)
    }

    @Test func onlyWalledTownsAreBesieged() throws {
        var s = try siege()
        s.sieges = [:]
        s.land["egypt"]!.improvements.remove(.walls)
        s.moved = [:]
        #expect(throws: GameError.notWalled("egypt")) {
            try engine.apply(.besiege(territory: "egypt", from: "petraea"), to: &s)
        }
    }
}

@Suite struct AssaultTests {
    let engine = try! Engine.bare()

    /// Egypt holds Egypt and Cyrenaica; Mesopotamia holds Libya between them.
    func world(defenders: Int) throws -> GameState {
        var s = try engine.newGame(seed: 1, civilizations: ["egypt", "mesopotamia"])
        s.land["cyrenaica"]!.owner = "egypt"
        s.land["libya"]!.owner = "mesopotamia"
        s.armies["egypt"] = Army(owner: "egypt", units: UnitCounts(infantry: 10))
        s.armies["cyrenaica"] = Army(owner: "egypt", units: UnitCounts(infantry: 10))
        s.armies["libya"] = Army(owner: "mesopotamia", units: UnitCounts(infantry: defenders))
        play(&s, as: "egypt")
        return s
    }

    @Test func twoArmiesStormTogether() throws {
        var s = try world(defenders: 3)
        try engine.apply(.assault(territory: "libya", groups: [
            AssaultGroup(.land("egypt"), UnitCounts(infantry: 8)),
            AssaultGroup(.land("cyrenaica"), UnitCounts(infantry: 8)),
        ], general: nil), to: &s)
        #expect(s.owner(of: "libya") == "egypt")
        #expect(s.armies["egypt"]!.units.total == 2)
        #expect(s.armies["cyrenaica"]!.units.total == 2)
        #expect((s.armies["libya"]?.units.total ?? 0) > 3)
    }

    @Test func aBeatenHostFallsBackWhereItCameFrom() throws {
        var s = try world(defenders: 40)
        try engine.apply(.assault(territory: "libya", groups: [
            AssaultGroup(.land("egypt"), UnitCounts(infantry: 2)),
            AssaultGroup(.land("cyrenaica"), UnitCounts(infantry: 2)),
        ], general: nil), to: &s)
        #expect(s.owner(of: "libya") == "mesopotamia")
        #expect(s.armies["egypt"]!.units.total <= 10)
        #expect(s.armies["cyrenaica"]!.units.total <= 10)
        #expect(s.armies["egypt"]!.units.total >= 8)
    }

    @Test func troopsLandFromTheSeaAlongsideTheMarch() throws {
        var s = try world(defenders: 3)
        s.fleets.append(Fleet(sea: "eastern_med", owner: "egypt", ships: 3, cargo: UnitCounts(infantry: 6)))
        try engine.apply(.assault(territory: "libya", groups: [
            AssaultGroup(.land("egypt"), UnitCounts(infantry: 6)),
            AssaultGroup(.sea("eastern_med"), UnitCounts(infantry: 6)),
        ], general: nil), to: &s)
        #expect(s.owner(of: "libya") == "egypt")
        #expect(s.fleet(of: "egypt", in: "eastern_med")!.cargo.isEmpty)
    }

    @Test func enemyShipsBarTheLanding() throws {
        var s = try world(defenders: 3)
        s.fleets.append(Fleet(sea: "eastern_med", owner: "egypt", ships: 3, cargo: UnitCounts(infantry: 6)))
        s.fleets.append(Fleet(sea: "eastern_med", owner: "mesopotamia", ships: 1))
        #expect(throws: GameError.blockaded("eastern_med")) {
            try engine.apply(.assault(territory: "libya", groups: [
                AssaultGroup(.sea("eastern_med"), UnitCounts(infantry: 6)),
            ], general: nil), to: &s)
        }
    }
}

@Suite struct PlayOnTests {
    let engine = try! Engine.bare()

    @Test func theGameGoesOnAfterTheAgeEndsAndNobodyWinsAgain() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["egypt", "greece"])
        s.turn = engine.rules.victory.roundLimit
        while s.winner == nil { try engine.apply(.endTurn, to: &s) }
        #expect(s.victory?.kind == .legacy)
        #expect(throws: GameError.gameOver) { try engine.apply(.endTurn, to: &s) }
        try engine.apply(.playOn, to: &s)
        #expect(s.winner == nil)
        #expect(s.turn == engine.rules.victory.roundLimit + 1)
        for _ in 0..<6 { try engine.apply(.endTurn, to: &s) }
        #expect(s.winner == nil)
        #expect(s.turn > engine.rules.victory.roundLimit + 2)
        #expect(s.victory?.kind == .legacy)
    }
}
