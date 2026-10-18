import Foundation
import Testing
@testable import HegemonCore

@Suite struct BattlePlanTests {
    let engine = try! Engine.calm()
    var sim: BattleSimulator { BattleSimulator(rules: engine.rules) }

    func army(_ civ: CivilizationID, _ units: UnitCounts, _ formation: FormationID = "phalanx",
              depth: LineDepth = .deep, stratagem: Stratagem? = nil) -> BattleArmy {
        BattleArmy(civ: civ, units: units, formation: formation, depth: depth, stratagem: stratagem)
    }

    func battle(_ a: BattleArmy, _ d: BattleArmy, seed: UInt64 = 1, terrain: Terrain = .plains) -> BattleReport {
        sim.resolve(BattleSetup(attacker: a, defender: d, terrain: terrain, seed: seed))
    }

    // MARK: Unlocking

    @Test func advancedPlansNeedKnowledgeOrTheRightGeneral() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["greece"])  // Miltiades, a tactician
        let miltiades = s.general(of: "greece", at: "greece")
        #expect(engine.formationAvailable("phalanx", "greece", general: nil, in: s))
        #expect(!engine.formationAvailable("hammer_and_anvil", "greece", general: miltiades, in: s))
        #expect(engine.formationAvailable("refused_flank", "greece", general: miltiades, in: s))
        #expect(!engine.formationAvailable("refused_flank", "greece", general: nil, in: s))
        #expect(engine.stratagemAvailable(.standFast, "greece", general: nil, in: s))
        #expect(!engine.stratagemAvailable(.feignedRetreat, "greece", general: miltiades, in: s))

        s.civs["greece"]!.knowledge[.horsemanship] = engine.rules.knowledge.levels[0]
        #expect(engine.formationAvailable("hammer_and_anvil", "greece", general: nil, in: s))
        s.civs["greece"]!.knowledge[.horsemanship] = engine.rules.knowledge.levels[1]
        #expect(engine.stratagemAvailable(.feignedRetreat, "greece", general: nil, in: s))
    }

    @Test func lockedPlansAreRefused() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["greece"])
        #expect(throws: GameError.planLocked) {
            try engine.apply(.setBattlePlan(territory: "greece", plan: BattlePlan(formation: "hammer_and_anvil")), to: &s)
        }
        try engine.apply(.setBattlePlan(territory: "greece",
                                        plan: BattlePlan(formation: "refused_flank", depth: .wide, stratagem: .standFast)), to: &s)
        #expect(s.armies["greece"]!.plan == BattlePlan(formation: "refused_flank", depth: .wide, stratagem: .standFast))
    }

    @Test func planFallsBackWithoutItsGeneral() throws {
        let s = try engine.newGame(seed: 1, civilizations: ["greece"])
        let plan = BattlePlan(formation: "refused_flank", stratagem: .feignedRetreat)
        let without = engine.battleArmy("greece", UnitCounts(infantry: 3), plan: plan, general: nil, s)
        #expect(without.formation == engine.rules.battle.defaultFormation)
        #expect(without.stratagem == nil)
    }

    // MARK: Line depth

    @Test func wideLinePutsEveryoneInTheFrontRank() {
        let units = UnitCounts(infantry: 3, archers: 2)
        let deep = battle(army("a", units), army("d", UnitCounts(infantry: 1))).frames[0].blocks
        let wide = battle(army("a", units, depth: .wide), army("d", UnitCounts(infantry: 1))).frames[0].blocks
        // The attacker's front rank is row 1, its rear row 0.
        #expect(deep.filter { $0.side == .attacker }.contains { $0.position.row == 0 })
        #expect(wide.filter { $0.side == .attacker }.allSatisfy { $0.position.row == 1 })
    }

    // MARK: Stratagems

    @Test func standingFastNobodyAdvances() {
        let infantry = UnitCounts(infantry: 4)
        let report = battle(army("a", infantry, stratagem: .standFast), army("d", infantry, stratagem: .standFast))
        #expect(report.frames.allSatisfy { $0.strikes.isEmpty })
        #expect(report.winner == .defender)  // nothing happens, so the defender holds
    }

    @Test func feignedRetreatFallsBackThenPunishesPursuers() {
        let raiders = UnitCounts(infantry: 2, cavalry: 4)
        let line = UnitCounts(infantry: 6)
        let report = battle(army("a", raiders, "hammer_and_anvil", stratagem: .feignedRetreat), army("d", line))
        let start = Dictionary(uniqueKeysWithValues: report.frames[0].blocks.map { ($0.id, $0.position.row) })
        let cavalry = report.frames[1].blocks.filter { $0.side == .attacker && $0.type == .cavalry }
        #expect(!cavalry.isEmpty)
        #expect(cavalry.allSatisfy { $0.position.row <= start[$0.id]! })

        func wins(_ stratagem: Stratagem?) -> Int {
            (0..<60).filter { seed in
                battle(army("a", raiders, "hammer_and_anvil", stratagem: stratagem), army("d", line), seed: UInt64(seed))
                    .winner == .attacker
            }.count
        }
        #expect(wins(.feignedRetreat) > wins(nil))
    }

    @Test func shieldWallBlunsArrows() {
        func arrowDamage(_ stratagem: Stratagem?) -> Int {
            (0..<30).reduce(0) { total, seed in
                let report = battle(army("a", UnitCounts(archers: 4), "skirmish_screen"),
                                    army("d", UnitCounts(infantry: 4), stratagem: stratagem), seed: UInt64(seed))
                return total + report.frames.flatMap(\.strikes).filter(\.ranged).reduce(0) { $0 + $1.damage }
                    / max(1, report.frames.flatMap(\.strikes).filter(\.ranged).count)
            }
        }
        #expect(arrowDamage(.shieldWall) < arrowDamage(nil))
    }

    @Test func flankingMarchPushesTheWingsForward() {
        let units = UnitCounts(infantry: 3, cavalry: 2)  // phalanx puts the cavalry on the wings
        let plain = battle(army("a", units), army("d", UnitCounts(infantry: 1))).frames[0].blocks
        let march = battle(army("a", units, stratagem: .flankingMarch), army("d", UnitCounts(infantry: 1))).frames[0].blocks
        func wingRows(_ blocks: [BlockSnapshot]) -> [Int] {
            blocks.filter { $0.side == .attacker && $0.type == .cavalry }.map(\.position.row).sorted()
        }
        #expect(wingRows(march).reduce(0, +) > wingRows(plain).reduce(0, +))
    }
}
