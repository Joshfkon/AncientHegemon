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

    @Test func tiesGoToTheDefender() {
        // As in Risk: an even fight on open ground favors the side on its home ground, and a
        // quarter more troops is enough to overcome it.
        #expect(arena.attackerWinRate(inf, inf, on: .plains) <= 25)
        let more = UnitCounts(infantry: inf.infantry + (inf.infantry + 3) / 4)
        #expect(arena.attackerWinRate(more, inf, on: .plains) >= 75)
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
        #expect(arena.attackerWinRate(UnitCounts(infantry: 10), inf, on: .plains) >= 95)
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
        let events = try engine.apply(
            .move(from: "mesopotamia", to: "persia", units: UnitCounts(infantry: 12)), to: &s)
        #expect(events.contains { if case .battle = $0 { true } else { false } })
        #expect(s.owner(of: "persia") == "mesopotamia")
        // Persia's only other neighbor is Media, which Greece doesn't hold: nowhere to run.
        #expect(events.contains { if case .destroyed(civ: "greece", _, 0) = $0 { true } else { false } })
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
