import Foundation
import Testing
@testable import HegemonCore

/// Win rates over many seeds, so tests check tendencies rather than single lucky rolls.
struct Arena {
    let sim = BattleSimulator(rules: try! Rules.bundled())

    func attackerWinRate(_ attacker: UnitCounts, _ defender: UnitCounts, on terrain: Terrain = .desert,
                         approach: Approach = .overland, attackerGeneral: General? = nil,
                         attackerBronze: Int = 0, seeds: Int = 60) -> Int {
        var wins = 0
        for seed in 0..<seeds {
            let report = sim.resolve(BattleSetup(
                attacker: BattleArmy(civ: "a", units: attacker, formation: "phalanx",
                                     general: attackerGeneral, bronzePercent: attackerBronze),
                defender: BattleArmy(civ: "d", units: defender, formation: "phalanx"),
                terrain: terrain, approach: approach, seed: UInt64(seed)))
            if report.winner == .attacker { wins += 1 }
        }
        return wins * 100 / seeds
    }
}

@Suite struct BattleSimulatorTests {

    @Test func defendersFightOnHomeGround() throws {
        let engine = try Engine.calm()
        let flat = try engine.modified { json in
            var battle = json["battle"] as! [String: Any]
            battle["homeGroundPercent"] = 0
            json["battle"] = battle
        }
        let army = UnitCounts(infantry: 4, archers: 2, cavalry: 2)
        func holds(_ e: Engine) -> Int {
            (0..<40).filter { seed in
                BattleSimulator(rules: e.rules).resolve(BattleSetup(
                    attacker: BattleArmy(civ: "a", units: army, formation: "phalanx"),
                    defender: BattleArmy(civ: "d", units: army, formation: "phalanx"),
                    terrain: .plains, seed: UInt64(seed))).winner == .defender
            }.count
        }
        #expect(holds(engine) > holds(flat))
    }
    let arena = Arena()
    let inf = UnitCounts(infantry: 6)
    let arc = UnitCounts(archers: 6)
    let cav = UnitCounts(cavalry: 6)

    @Test func sameSetupSameBattle() {
        let setup = BattleSetup(attacker: BattleArmy(civ: "a", units: UnitCounts(infantry: 4, archers: 2, cavalry: 2), formation: "wedge"),
                                defender: BattleArmy(civ: "d", units: UnitCounts(infantry: 5, archers: 3), formation: "phalanx"),
                                terrain: .hills, seed: 42)
        #expect(arena.sim.resolve(setup) == arena.sim.resolve(setup))
        let outcomes = Set((0..<10).map { seed -> Int in
            var s = setup
            s.seed = UInt64(seed)
            return arena.sim.resolve(s).frames.count
        })
        #expect(outcomes.count > 1, "the seed should matter")
    }

    // Each unit type beats the one it counters, attacking or defending, except that archers
    // attacking infantry only break even: home ground offsets their edge.
    @Test func cavalryBeatsArchers() {
        #expect(arena.attackerWinRate(cav, arc) >= 80)
        #expect(arena.attackerWinRate(arc, cav) <= 20)
    }

    @Test func archersBeatInfantry() {
        #expect(arena.attackerWinRate(arc, inf) >= 40)
        #expect(arena.attackerWinRate(inf, arc) <= 20)
    }

    @Test func infantryBeatsCavalry() {
        #expect(arena.attackerWinRate(inf, cav) >= 80)
        #expect(arena.attackerWinRate(cav, inf) <= 20)
    }

    @Test func tiesLeanToTheDefender() {
        // An even fight on open ground gives the side on its home ground a modest edge; half
        // again as many troops makes the attack a good bet, though never a sure thing.
        #expect((25...45).contains(arena.attackerWinRate(inf, inf, on: .plains, seeds: 200)))
        let half = UnitCounts(infantry: inf.infantry * 3 / 2)
        #expect(arena.attackerWinRate(half, inf, on: .plains, seeds: 200) >= 75)
    }

    @Test func terrainFavorsDefenders() {
        let open = arena.attackerWinRate(UnitCounts(infantry: 8), inf, on: .plains)
        let hills = arena.attackerWinRate(UnitCounts(infantry: 8), inf, on: .hills)
        let mountains = arena.attackerWinRate(UnitCounts(infantry: 8), inf, on: .mountains)
        #expect(open > hills)
        #expect(hills > mountains)
    }

    @Test func crossingsHurtAttackers() {
        let attackers = UnitCounts(infantry: 7)
        let overland = arena.attackerWinRate(attackers, inf, on: .plains)
        #expect(arena.attackerWinRate(attackers, inf, on: .plains, approach: .river) < overland)
        #expect(arena.attackerWinRate(attackers, inf, on: .plains, approach: .amphibious) < overland)
    }

    @Test func biggerArmyWins() {
        #expect(arena.attackerWinRate(UnitCounts(infantry: 10), inf, on: .plains) >= 80)
    }

    @Test func generalsAndBronzeHelp() {
        let base = arena.attackerWinRate(inf, inf, on: .plains)
        let veteran = General(id: "g", name: "G", owner: "a", trait: .tactician, renown: 5, location: "x")
        #expect(arena.attackerWinRate(inf, inf, on: .plains, attackerGeneral: veteran) > base)
        #expect(arena.attackerWinRate(inf, inf, on: .plains, attackerBronze: 100) > base)
    }

    @Test func replayIsWellFormed() {
        let rules = try! Rules.bundled()
        let report = arena.sim.resolve(BattleSetup(
            attacker: BattleArmy(civ: "a", units: UnitCounts(infantry: 9, archers: 5, cavalry: 4), formation: "hammer_and_anvil"),
            defender: BattleArmy(civ: "d", units: UnitCounts(infantry: 6, archers: 2), formation: "skirmish_screen"),
            terrain: .mountains, seed: 9))
        let deployment = report.frames[0]
        #expect(deployment.strikes.isEmpty)
        #expect(deployment.blocks.filter { $0.side == .attacker }.count == rules.battle.maxBlocks)
        #expect(deployment.blocks.filter { $0.side == .attacker }.reduce(0) { $0 + $1.units } == 18)
        #expect(deployment.blocks.filter { $0.side == .defender }.reduce(0) { $0 + $1.units } == 8)
        #expect(report.frames.count == report.rounds + 1)
        let rocks = Set(report.impassable)
        for frame in report.frames {
            let onField = frame.blocks.filter { $0.status == .fighting }.map(\.position)
            #expect(Set(onField).count == onField.count, "two blocks share a square")
            #expect(rocks.isDisjoint(with: onField))
        }
        #expect(report.attackerSurvivors.fits(in: report.setup.attacker.units))
        #expect(report.defenderSurvivors.fits(in: report.setup.defender.units))
    }

    @Test func navalBattlesFavorBiggerFleets() {
        var wins = 0
        for seed in 0..<40 {
            let r = arena.sim.resolveNaval(attacker: "a", attackerShips: 8, defender: "d", defenderShips: 4,
                                           seed: UInt64(seed))
            if r.winner == .attacker { wins += 1 }
            #expect(r == arena.sim.resolveNaval(attacker: "a", attackerShips: 8, defender: "d",
                                                defenderShips: 4, seed: UInt64(seed)))
        }
        #expect(wins >= 36)
    }
}

private func own(_ s: inout GameState, _ civ: CivilizationID, _ territories: TerritoryID...) {
    for t in territories { s.land[t]!.owner = civ }
}

@Suite struct LandWarTests {
    let engine = try! Engine.bare()

    @Test func overwhelmingAttackCapturesAndDestroysTrappedDefender() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["mesopotamia", "greece"])
        own(&s, "greece", "persia")
        s.armies["persia"] = Army(owner: "greece", units: UnitCounts(infantry: 1))
        s.armies["mesopotamia"]!.units.infantry = 12
        let home = s.armies["greece"]!.units
        let events = try engine.apply(
            .move(from: "mesopotamia", to: "persia", units: UnitCounts(infantry: 12)), to: &s)
        #expect(events.contains { if case .battle = $0 { true } else { false } })
        #expect(s.owner(of: "persia") == "mesopotamia")
        // Persia's only other neighbor is Media, which Greece doesn't hold: nowhere to run, so
        // whatever survives the battle is lost too.
        #expect(s.totalUnits(of: "greece") == home)
        #expect(s.armies["persia"]!.owner == "mesopotamia")
        #expect(s.moved["persia"]!.total == s.armies["persia"]!.units.total)
    }

    @Test func beatenDefenderRetreatsToFriendlyLand() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["mesopotamia", "greece"])
        own(&s, "greece", "media", "armenia")
        s.armies["media"] = Army(owner: "greece", units: UnitCounts(infantry: 4))
        s.armies["mesopotamia"]!.units.infantry = 20
        let events = try engine.apply(
            .move(from: "mesopotamia", to: "media", units: UnitCounts(infantry: 20)), to: &s)
        let retreat = events.first { if case .retreated = $0 { true } else { false } }
        guard case let .retreated(civ, from, to, units) = retreat else {
            Issue.record("no retreat in \(events)")
            return
        }
        #expect(civ == "greece" && from == "media" && to == "armenia")
        #expect(s.armies["armenia"]!.units == units)
    }

    @Test func repulsedAttackersFallBackSpent() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["mesopotamia", "greece"])
        own(&s, "greece", "media")
        s.armies["media"] = Army(owner: "greece", units: UnitCounts(infantry: 20))
        s.armies["mesopotamia"]!.units.infantry = 3
        try engine.apply(.move(from: "mesopotamia", to: "media", units: UnitCounts(infantry: 3)), to: &s)
        #expect(s.owner(of: "media") == "greece")
        let back = s.armies["mesopotamia"]?.units ?? .zero
        #expect(back.total <= 3)
        #expect(s.moved["mesopotamia"] == back)
        #expect(throws: GameError.insufficientUnits("mesopotamia")) {
            try engine.apply(.move(from: "mesopotamia", to: "persia", units: UnitCounts(infantry: 1)), to: &s)
        }
    }

    @Test func generalsMarchWinAndGainRenown() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["mesopotamia", "greece"])
        own(&s, "greece", "persia")
        s.armies["persia"] = Army(owner: "greece", units: UnitCounts(infantry: 1))
        s.armies["mesopotamia"]!.units.infantry = 12
        let sargon = s.general(of: "mesopotamia", at: "mesopotamia")!
        #expect(sargon.name == "Sargon")
        let events = try engine.apply(.move(from: "mesopotamia", to: "persia",
                                            units: UnitCounts(infantry: 12), general: true), to: &s)
        guard case let .battle(report)? = events.first(where: { if case .battle = $0 { true } else { false } }) else {
            Issue.record("no battle")
            return
        }
        #expect(report.setup.attacker.general?.id == sargon.id)
        if !report.attackerGeneralKilled {
            #expect(s.generals[sargon.id]!.location == "persia")
            #expect(s.generals[sargon.id]!.renown == 1)
        }
        // A fresh unit could march on, but the general has already moved this turn.
        s.armies["persia"]!.units.infantry += 1
        #expect(throws: GameError.noGeneral("persia")) {
            try engine.apply(.move(from: "persia", to: "media", units: UnitCounts(infantry: 1), general: true), to: &s)
        }
    }

    @Test func loneGeneralIsCaptured() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["mesopotamia", "greece"])
        let miltiades = s.general(of: "greece", at: "greece")!
        s.generals[miltiades.id]!.location = "media"
        own(&s, "greece", "media")
        let events = try engine.apply(.move(from: "mesopotamia", to: "media", units: UnitCounts(infantry: 1)), to: &s)
        #expect(events.contains(.generalKilled(miltiades.id)))
        #expect(!s.generals[miltiades.id]!.isAlive)
    }

    @Test func formationsAreChosenPerArmy() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["mesopotamia", "greece"])
        // Wedge and refused flank are unlocked by warfare.
        s.civs["mesopotamia"]!.knowledge[.warfare] = engine.rules.knowledge.levels[1]
        s.civs["greece"]!.knowledge[.warfare] = engine.rules.knowledge.levels[1]
        try engine.apply(.setFormation(territory: "mesopotamia", formation: "wedge"), to: &s)
        #expect(s.armies["mesopotamia"]!.formation == "wedge")
        #expect(throws: GameError.unknownFormation("tortoise")) {
            try engine.apply(.setFormation(territory: "mesopotamia", formation: "tortoise"), to: &s)
        }
        own(&s, "greece", "persia")
        s.armies["persia"] = Army(owner: "greece", units: UnitCounts(infantry: 1), formation: "refused_flank")
        let events = try engine.apply(.move(from: "mesopotamia", to: "persia", units: UnitCounts(infantry: 2)), to: &s)
        guard case let .battle(report)? = events.first(where: { if case .battle = $0 { true } else { false } }) else {
            Issue.record("no battle")
            return
        }
        #expect(report.setup.attacker.formation == "wedge")
        #expect(report.setup.defender.formation == "refused_flank")
    }

    @Test func riverCrossingIsRecorded() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["mesopotamia", "greece"])
        own(&s, "greece", "armenia")
        s.armies["armenia"] = Army(owner: "greece", units: UnitCounts(infantry: 1))
        let events = try engine.apply(.move(from: "mesopotamia", to: "armenia", units: UnitCounts(infantry: 2)), to: &s)
        guard case let .battle(report)? = events.first(where: { if case .battle = $0 { true } else { false } }) else {
            Issue.record("no battle")
            return
        }
        #expect(report.setup.approach == .river)
        #expect(report.setup.terrain == .hills)
    }
}

@Suite struct NavalTests {
    let engine = try! Engine.bare()

    /// Greece with Macedonia's timber (2) and plenty of gold.
    func greeceWithShipyards() throws -> GameState {
        var s = try engine.newGame(seed: 1, civilizations: ["greece", "egypt"])
        own(&s, "greece", "macedonia")
        s.civs["greece"]!.gold = 100
        s.land["greece"]!.population = 2
        return s
    }

    @Test func buildingShipsNeedsTimberAndCoast() throws {
        var s = try greeceWithShipyards()
        #expect(throws: GameError.notCoastal("greece", "tyrrhenian")) {
            try engine.apply(.buildShips(territory: "greece", sea: "tyrrhenian", count: 1), to: &s)
        }
        try engine.apply(.buildShips(territory: "greece", sea: "aegean", count: 2), to: &s)
        #expect(s.fleet(of: "greece", in: "aegean")?.ships == 2)
        #expect(s.civs["greece"]!.gold == 92)
        #expect(throws: GameError.resourceLimit(.timber)) {
            try engine.apply(.buildShips(territory: "greece", sea: "aegean", count: 1), to: &s)
        }
        // New ships can't sail until next turn.
        #expect(throws: GameError.insufficientShips("aegean")) {
            try engine.apply(.moveFleet(from: "aegean", to: "eastern_med", ships: 1), to: &s)
        }
    }

    @Test func amphibiousInvasionOfAnIsland() throws {
        var s = try greeceWithShipyards()
        try engine.apply(.buildShips(territory: "greece", sea: "aegean", count: 1), to: &s)
        try engine.apply(.embark(territory: "greece", sea: "aegean", units: UnitCounts(infantry: 2)), to: &s)
        #expect(throws: GameError.overCapacity("aegean")) {
            s.armies["greece"] = Army(owner: "greece", units: UnitCounts(infantry: 1))
            try engine.apply(.embark(territory: "greece", sea: "aegean", units: UnitCounts(infantry: 1)), to: &s)
        }
        let events = try engine.apply(.land(sea: "aegean", territory: "crete", units: UnitCounts(infantry: 2)), to: &s)
        #expect(events.contains(.captured(civ: "greece", territory: "crete", from: nil)))
        #expect(s.armies["crete"]!.units.infantry == 2)
        #expect(s.fleet(of: "greece", in: "aegean")!.cargo.isEmpty)
    }

    @Test func shipsCanBeDisbandedButNotFromUnderTheTroops() throws {
        var s = try greeceWithShipyards()
        s.fleets = [Fleet(sea: "aegean", owner: "greece", ships: 3, cargo: UnitCounts(infantry: 3))]
        #expect(throws: GameError.overCapacity("aegean")) {
            try engine.apply(.disbandShips(sea: "aegean", ships: 2), to: &s)
        }
        let events = try engine.apply(.disbandShips(sea: "aegean", ships: 1), to: &s)
        #expect(events == [.shipsDisbanded(civ: "greece", sea: "aegean", count: 1)])
        #expect(s.fleet(of: "greece", in: "aegean")?.ships == 2)
        s.fleets[0].cargo = .zero
        try engine.apply(.disbandShips(sea: "aegean", ships: 2), to: &s)
        #expect(s.fleet(of: "greece", in: "aegean") == nil)
        #expect(throws: GameError.noFleet("aegean")) {
            try engine.apply(.disbandShips(sea: "aegean", ships: 1), to: &s)
        }
    }

    @Test func shipsSailTwoSeasButNotThroughEnemyWaters() throws {
        var s = try greeceWithShipyards()
        s.fleets = [Fleet(sea: "aegean", owner: "greece", ships: 2)]
        let paths = engine.fleetPaths(from: "aegean", for: "greece", in: s)
        let far = try #require(paths.filter { $0.value.count == 2 }.keys.sorted().first)
        #expect(paths.values.allSatisfy { $0.count <= 2 })
        try engine.apply(.moveFleet(from: "aegean", to: far, ships: 2), to: &s)
        #expect(s.fleet(of: "greece", in: far)?.ships == 2)
        // Three seas out is too far for one turn.
        s.fleets = [Fleet(sea: "aegean", owner: "greece", ships: 2)]
        let beyond = map(engine).seaNeighbors(of: far).first { paths[$0] == nil && $0 != "aegean" }
        if let beyond {
            #expect(throws: GameError.notAdjacent("aegean", beyond)) {
                try engine.apply(.moveFleet(from: "aegean", to: beyond, ships: 2), to: &s)
            }
        }
        // Pirates in every sea next door: the ships can sail in to fight, but not past.
        for n in map(engine).seaNeighbors(of: "aegean") { s.fleets.append(Fleet(sea: n, owner: piratesID, ships: 1)) }
        let hemmed = engine.fleetPaths(from: "aegean", for: "greece", in: s)
        #expect(hemmed.values.allSatisfy { $0.count == 1 })
    }

    private func map(_ engine: Engine) -> GameMap { engine.map }

    @Test func stormsSinkShipsAwayFromAHarbour() throws {
        let stormy = try engine.modified { json in
            var ships = json["ships"] as! [String: Any]
            ships["stormPercent"] = 100
            ships["stormMinPercent"] = 100
            json["ships"] = ships
        }
        var s = try greeceWithShipyards()
        s.fleets = [Fleet(sea: "aegean", owner: "greece", ships: 3, cargo: UnitCounts(infantry: 6))]
        let events = stormy.storms("greece", &s)
        #expect(events == [.storm(civ: "greece", sea: "aegean", ships: 1, drowned: UnitCounts(infantry: 2))])
        #expect(s.fleet(of: "greece", in: "aegean")?.ships == 2)
        #expect(s.fleet(of: "greece", in: "aegean")?.cargo.total == 4)
        // A harbour of their own on these waters: the ships ride it out.
        s.land["greece"]!.improvements.insert(.harbor)
        #expect(stormy.storms("greece", &s).isEmpty)
    }

    @Test func piratesAppearAndPlunderUnguardedCoasts() throws {
        let lawless = try engine.modified { json in
            var p = json["pirates"] as! [String: Any]
            p["spawnPercent"] = 100
            p["fromRound"] = 1
            json["pirates"] = p
        }
        var s = try greeceWithShipyards()
        s.turn = 5
        let appeared = lawless.piratesRound(&s)
        #expect(appeared.contains { if case .piratesAppeared = $0 { true } else { false } })
        #expect(lawless.pirateFleets(in: s).count == 1)

        // A band off Greece's coast, hemmed in by single Egyptian ships (too few to patrol): it
        // stays, and plunders Greece.
        s.fleets = [Fleet(sea: "aegean", owner: piratesID, ships: 2)]
        for n in lawless.map.seaNeighbors(of: "aegean") { s.fleets.append(Fleet(sea: n, owner: "egypt", ships: 1)) }
        let gold = s.civs["greece"]!.gold
        let events = lawless.piratesRound(&s)
        #expect(events.contains { if case let .piratesPlundered(civ, _, g) = $0 { civ == "greece" && g == 4 } else { false } })
        #expect(s.civs["greece"]!.gold == gold - 4)
        // Their sea is closed to Greek trade and supply while they hold it.
        #expect(lawless.blockaded("aegean", for: ["greece"], in: s))
    }

    @Test func strongNaviesKeepPiratesAway() throws {
        let lawless = try engine.modified { json in
            var p = json["pirates"] as! [String: Any]
            p["spawnPercent"] = 100
            p["fromRound"] = 1
            p["maxFleets"] = 50
            json["pirates"] = p
        }
        var s = try greeceWithShipyards()
        s.turn = 5
        s.fleets = [Fleet(sea: "aegean", owner: "greece", ships: 3)]
        #expect(lawless.patrolled("aegean", in: s))
        for n in lawless.map.seaNeighbors(of: "aegean") { #expect(lawless.patrolled(n, in: s)) }
        // However many bands put to sea, none appears in the waters the Greek fleet patrols.
        for _ in 0..<30 { _ = lawless.piratesRound(&s) }
        let patrol = Set(["aegean"] + lawless.map.seaNeighbors(of: "aegean"))
        #expect(!lawless.pirateFleets(in: s).isEmpty)
        #expect(lawless.pirateFleets(in: s).allSatisfy { !patrol.contains($0.sea) })
        // Greek ships next door guard Greece's Aegean coast from plunder.
        s.fleets = [Fleet(sea: "aegean", owner: piratesID, ships: 2),
                    Fleet(sea: lawless.map.seaNeighbors(of: "aegean").sorted()[0], owner: "greece", ships: 1)]
        #expect(!lawless.plunderable("aegean", s).contains("greece"))
    }

    @Test func sinkingPiratesPaysABounty() throws {
        var s = try greeceWithShipyards()
        s.fleets = [Fleet(sea: "eastern_med", owner: "greece", ships: 8), Fleet(sea: "aegean", owner: piratesID, ships: 1)]
        // Greek ships in every other sea next door: the pirates have nowhere to run.
        for n in engine.map.seaNeighbors(of: "aegean") where n != "eastern_med" {
            s.fleets.append(Fleet(sea: n, owner: "greece", ships: 1))
        }
        let gold = s.civs["greece"]!.gold
        let events = try engine.apply(.moveFleet(from: "eastern_med", to: "aegean", ships: 8), to: &s)
        #expect(events.contains(.bountyPaid(civ: "greece", gold: 3)))
        #expect(s.civs["greece"]!.gold == gold + 3)
        #expect(engine.pirateFleets(in: s).isEmpty)
        #expect(s.civs["greece"]!.trophies.contains { $0.kind == .raiderShield })
    }

    @Test func fleetsCarryCargoBetweenSeas() throws {
        var s = try greeceWithShipyards()
        s.fleets = [Fleet(sea: "aegean", owner: "greece", ships: 2, cargo: UnitCounts(infantry: 3))]
        #expect(throws: GameError.overCapacity("aegean")) {
            try engine.apply(.moveFleet(from: "aegean", to: "eastern_med", ships: 1, cargo: UnitCounts(infantry: 3)), to: &s)
        }
        try engine.apply(.moveFleet(from: "aegean", to: "eastern_med", ships: 2, cargo: UnitCounts(infantry: 3)), to: &s)
        #expect(s.fleet(of: "greece", in: "eastern_med")?.cargo.infantry == 3)
        #expect(s.fleet(of: "greece", in: "aegean") == nil)
        #expect(throws: GameError.insufficientShips("eastern_med")) {
            try engine.apply(.moveFleet(from: "eastern_med", to: "aegean", ships: 1), to: &s)
        }
    }

    @Test func enemyChokepointBarsTheStrait() throws {
        var s = try greeceWithShipyards()
        own(&s, "egypt", "thrace", "anatolia")
        s.fleets = [Fleet(sea: "aegean", owner: "greece", ships: 2)]
        #expect(throws: GameError.chokepointClosed("aegean", "black_sea")) {
            try engine.apply(.moveFleet(from: "aegean", to: "black_sea", ships: 2), to: &s)
        }
    }

    @Test func navalBattleSinksShipsAndCargo() throws {
        var s = try greeceWithShipyards()
        s.fleets = [Fleet(sea: "aegean", owner: "greece", ships: 10),
                    Fleet(sea: "eastern_med", owner: "egypt", ships: 2, cargo: UnitCounts(infantry: 4))]
        let events = try engine.apply(.moveFleet(from: "aegean", to: "eastern_med", ships: 10), to: &s)
        guard case let .navalBattle(sea, report)? = events.first(where: { if case .navalBattle = $0 { true } else { false } }) else {
            Issue.record("no naval battle")
            return
        }
        #expect(sea == "eastern_med")
        #expect(report.winner == .attacker)
        #expect(s.fleet(of: "greece", in: "eastern_med")?.ships == report.attackerShipsLeft)
        #expect(s.fleet(of: "egypt", in: "eastern_med") == nil)
        let egyptCargo = s.fleets(of: "egypt").reduce(0) { $0 + $1.cargo.total }
        #expect(egyptCargo <= report.defenderShipsLeft * engine.rules.ships.capacity)
    }

    @Test func peacefulFleetsShareASea() throws {
        var s = try greeceWithShipyards()
        s.peace.insert(CivPair("greece", "egypt"))
        s.fleets = [Fleet(sea: "aegean", owner: "greece", ships: 2), Fleet(sea: "eastern_med", owner: "egypt", ships: 2)]
        let events = try engine.apply(.moveFleet(from: "aegean", to: "eastern_med", ships: 2), to: &s)
        #expect(!events.contains { if case .navalBattle = $0 { true } else { false } })
        #expect(s.fleets.filter { $0.sea == "eastern_med" }.count == 2)
    }

    @Test func blockadeCutsSupply() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["greece", "egypt"])
        own(&s, "greece", "dacia")  // reachable only through the Black Sea
        #expect(engine.supplyPockets(of: "greece", in: s).count == 1)
        s.fleets = [Fleet(sea: "black_sea", owner: "egypt", ships: 1)]
        #expect(engine.supplyPockets(of: "greece", in: s) == [["greece"], ["dacia"]])
        s.fleets.append(Fleet(sea: "black_sea", owner: "greece", ships: 1))
        #expect(engine.supplyPockets(of: "greece", in: s).count == 1)
    }

    @Test func crewsEatFromHome() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["mesopotamia"])
        s.fleets = [Fleet(sea: "persian_gulf", owner: "mesopotamia", ships: 2, cargo: UnitCounts(infantry: 1))]
        // Production 9; people 3 + infantry 2 + crews 2 + cargo 1 = 8.
        let events = try engine.apply(.endTurn, to: &s)
        #expect(events.contains { if case .harvest(_, 9, 8, _, _, _) = $0 { true } else { false } })
    }

    @Test func fleetsKeepACivAlive() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["mesopotamia", "greece"])
        s.land["greece"]!.owner = nil
        s.armies["greece"] = nil
        own(&s, "greece", "persia")
        s.fleets = [Fleet(sea: "aegean", owner: "greece", ships: 1)]
        let events = try engine.apply(.move(from: "mesopotamia", to: "persia", units: UnitCounts(infantry: 1)), to: &s)
        #expect(!events.contains(.eliminated(civ: "greece")))
    }
}

@Suite struct BattleOrdersTests {
    let sim = BattleSimulator(rules: try! Rules.bundled())

    func setup(_ attacker: BattleArmy) -> BattleSetup {
        BattleSetup(attacker: attacker, defender: BattleArmy(civ: "d", units: UnitCounts(infantry: 4), formation: "phalanx"),
                    terrain: .plains, seed: 7)
    }

    @Test func blocksGoWhereTheyArePlaced() {
        var army = BattleArmy(civ: "a", units: UnitCounts(infantry: 4), formation: "phalanx")
        army.placements = [0: GridPoint(0, 0)]
        let frame = sim.deployment(setup(army))
        #expect(frame.blocks.first { $0.id == 0 }?.position == GridPoint(0, 0))
        // Into the enemy's ranks is not allowed.
        army.placements = [0: GridPoint(2, 3)]
        #expect(sim.deployment(setup(army)).blocks.first { $0.id == 0 }?.position.row ?? 9 <= 1)
    }

    @Test func aHoldingBlockStandsItsGround() {
        var army = BattleArmy(civ: "a", units: UnitCounts(infantry: 4), formation: "phalanx")
        let start = sim.deployment(setup(army)).blocks.filter { $0.side == .attacker }
        army.orders = Dictionary(uniqueKeysWithValues: start.map { ($0.id, BlockOrder.hold) })
        let report = sim.resolve(setup(army))
        guard report.frames.count > 1 else { return }
        let next = report.frames[1].blocks.filter { $0.side == .attacker }
        for b in start { #expect(next.first { $0.id == b.id }?.position == b.position) }
    }

    @Test func anAdvancingBlockMarchesEvenWhenItsFormationWouldWait() {
        var army = BattleArmy(civ: "a", units: UnitCounts(infantry: 2, archers: 2), formation: "phalanx")
        let start = sim.deployment(setup(army)).blocks.filter { $0.side == .attacker && $0.type == .archers }
        army.orders = Dictionary(uniqueKeysWithValues: start.map { ($0.id, BlockOrder.advance) })
        let report = sim.resolve(setup(army))
        let moved = start.contains { b in report.frames[1].blocks.first { $0.id == b.id }?.position != b.position }
        #expect(moved)
    }
}

@Suite struct PlacementSurvivesTheChargeTests {
    @Test func aPlanSetBeforeTheAttackKeepsItsPlacingsAndOrders() throws {
        let engine = try Engine.bare()
        var s = try engine.newGame(seed: 1, civilizations: ["egypt", "mesopotamia"])
        s.land["petraea"]!.owner = "mesopotamia"
        s.armies["petraea"] = Army(owner: "mesopotamia", units: UnitCounts(infantry: 3))
        s.armies["egypt"] = Army(owner: "egypt", units: UnitCounts(infantry: 6))
        var plan = BattlePlan()
        plan.placements = [0: GridPoint(0, 0)]
        plan.orders = [1: .hold]
        try engine.apply(.setBattlePlan(territory: "egypt", plan: plan), to: &s)
        #expect(s.armies["egypt"]!.plan.placements == plan.placements)
        #expect(s.armies["egypt"]!.plan.orders == plan.orders)
        let events = try engine.apply(.move(from: "egypt", to: "petraea", units: UnitCounts(infantry: 6)), to: &s)
        let report = events.compactMap { if case let .battle(r) = $0 { r } else { nil } }.first
        let start = report?.frames.first?.blocks.first { $0.id == 0 }
        #expect(start?.position == GridPoint(0, 0))
        #expect(report?.frames.first?.blocks.first { $0.id == 1 }?.order == .hold)
    }
}
