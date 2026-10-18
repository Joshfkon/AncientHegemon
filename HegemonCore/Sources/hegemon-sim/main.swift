import Foundation
import HegemonCore

// The balance tool: runs AI-vs-AI games and reports how empires fare.
//
//   hegemon-sim [--games N] [--turns T] [--seed S] [--personality NAME] [--fixed-order]
//       N games (default 20) of at most T turns (default 150), seeds S, S+1, ...
//       --personality gives every civ the same temperament, so differences come from the map.
//       Turn order is shuffled per game (seeded) unless --fixed-order.
//   hegemon-sim --trace [--seed S] [--turns T]
//       One game, printing every civ's land, units, population, gold and grain each round.
//   hegemon-sim formations [--seeds N]
//       Win rates for every formation pairing, mixed armies on open ground.
//
// Build with `swift run -c release hegemon-sim ...`; debug builds are much slower.

func option(_ name: String) -> String? {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

func pct(_ n: Int, _ d: Int) -> String {
    d == 0 ? "  -" : String(format: "%3d%%", n * 100 / d)
}

func pad(_ s: String, _ w: Int) -> String {
    s.count >= w ? s : String(repeating: " ", count: w - s.count) + s
}

let engine = try Engine.bundled()

if CommandLine.arguments.dropFirst().first == "formations" {
    let seeds = Int(option("--seeds") ?? "100") ?? 100
    let sim = BattleSimulator(rules: engine.rules)
    let ids = engine.rules.battle.formations.map(\.id)
    let army = UnitCounts(infantry: 4, archers: 2, cavalry: 2)
    print("attacker win % (rows attack, columns defend), 4 inf / 2 arc / 2 cav each, plains, \(seeds) seeds")
    print(pad("", 18) + ids.map { pad(String($0.prefix(9)), 10) }.joined())
    for a in ids {
        let row = ids.map { d -> String in
            let wins = (0..<seeds).filter { seed in
                sim.resolve(BattleSetup(attacker: BattleArmy(civ: "a", units: army, formation: a),
                                        defender: BattleArmy(civ: "d", units: army, formation: d),
                                        terrain: .plains, seed: UInt64(seed))).winner == .attacker
            }.count
            return pad(pct(wins, seeds), 10)
        }
        print(a.padding(toLength: 18, withPad: " ", startingAt: 0) + row.joined())
    }
    exit(0)
}

let games = Int(option("--games") ?? "20") ?? 20
let maxTurns = Int(option("--turns") ?? "150") ?? 150
let firstSeed = UInt64(option("--seed") ?? "1") ?? 1
var personalities: [CivilizationID: Personality] = [:]
if let name = option("--personality") {
    guard let p = Personality.named(name) else {
        print("unknown personality '\(name)'; choose from \(Personality.all.map(\.name).joined(separator: ", "))")
        exit(1)
    }
    for civ in engine.map.civilizations.map(\.id) { personalities[civ] = p }
}

if CommandLine.arguments.contains("--trace") {
    print("round  " + engine.map.civilizations.map { $0.id.padding(toLength: 28, withPad: " ", startingAt: 0) }.joined())
    print("       " + engine.map.civilizations.map { _ in "land units  pop gold granary ".padding(toLength: 28, withPad: " ", startingAt: 0) }.joined())
    let record = try playAIMatch(engine: engine, seed: firstSeed, personalities: personalities, maxTurns: maxTurns) { s in
        let cols = engine.map.civilizations.map { c -> String in
            let civ = c.id
            guard let cs = s.civs[civ], !cs.eliminated else { return "out".padding(toLength: 28, withPad: " ", startingAt: 0) }
            let units = s.totalUnits(of: civ).total
            return (pad(String(s.territories(of: civ).count), 4) + pad(String(units), 6) + pad(String(s.totalPopulation(of: civ)), 5)
                    + pad(String(cs.gold), 5) + pad(String(cs.granary), 8)).padding(toLength: 28, withPad: " ", startingAt: 0)
        }
        print(pad(String(s.turn), 5) + "  " + cols.joined())
    }
    print("winner: \(record.winner ?? "none") after \(record.turns) turns")
    exit(0)
}

let started = Date()
var records: [MatchRecord] = []
for g in 0..<games {
    let seed = firstSeed + UInt64(g)
    let civsInOrder = engine.map.civilizations.map(\.id)
    let order = CommandLine.arguments.contains("--fixed-order") ? civsInOrder : shuffledTurnOrder(civsInOrder, seed: seed)
    let record = try playAIMatch(engine: engine, seed: seed, personalities: personalities,
                                 civilizations: order, maxTurns: maxTurns)
    records.append(record)
    let land = record.finalState.players
        .map { "\($0) \(record.finalState.territories(of: $0).count)" }.joined(separator: ", ")
    print("game \(g + 1)/\(games) seed \(seed): winner \(record.winner ?? "none") after \(record.turns) turns (\(land))")
}
let elapsed = Date().timeIntervalSince(started)

let civs = engine.map.civilizations.map(\.id)
let decided = records.filter { $0.winner != nil }
print("")
print("\(games) games, max \(maxTurns) turns, \(String(format: "%.1f", elapsed))s")
print("decided: \(decided.count)/\(games)"
      + (decided.isEmpty ? "" : ", average length \(decided.map(\.turns).reduce(0, +) / decided.count) turns"))
print("")
print("civ          personality   wins  elim  collapse  avg land  peak  starving turns  deserted  attrition    attacks won   defences held  rejected")
for civ in civs {
    let rs = records.compactMap { $0.civs[civ] }
    let n = max(1, rs.count)
    let sum = { (f: (CivRecord) -> Int) in rs.map(f).reduce(0, +) }
    let attacks = sum { $0.attacksWon + $0.attacksLost }
    let defences = sum { $0.defencesWon + $0.defencesLost }
    let cols = [
        civ.padding(toLength: 13, withPad: " ", startingAt: 0)
            + (rs.first?.personality ?? "").padding(toLength: 12, withPad: " ", startingAt: 0),
        pad(pct(records.filter { $0.winner == civ }.count, rs.count), 6),
        pad(pct(rs.filter { $0.eliminatedOnTurn != nil }.count, rs.count), 6),
        pad(pct(rs.filter(\.collapsed).count, rs.count), 10),
        pad(String(format: "%.1f", Double(sum(\.finalTerritories)) / Double(n)), 10),
        pad(String(format: "%.1f", Double(sum(\.peakTerritories)) / Double(n)), 6),
        pad(String(format: "%.1f", Double(sum(\.turnsStarving)) / Double(n)), 16),
        pad(String(sum(\.unitsDeserted) / n), 10),
        pad(String(sum(\.unitsLostToAttrition) / n), 11),
        pad("\(pct(sum(\.attacksWon), attacks)) of \(attacks)", 15),
        pad("\(pct(sum(\.defencesWon), defences)) of \(defences)", 16),
        pad(String(sum(\.rejectedCommands)), 10),
    ]
    print(cols.joined())
}

var formations: [FormationID: FormationRecord] = [:]
for r in records {
    for (f, rec) in r.formations {
        formations[f, default: FormationRecord()].attacks += rec.attacks
        formations[f, default: FormationRecord()].attackWins += rec.attackWins
        formations[f, default: FormationRecord()].defences += rec.defences
        formations[f, default: FormationRecord()].defenceWins += rec.defenceWins
    }
}
print("")
print("formation         attacks (won)    defences (held)")
for f in engine.rules.battle.formations.map(\.id) {
    let r = formations[f] ?? FormationRecord()
    print(f.padding(toLength: 18, withPad: " ", startingAt: 0)
          + pad("\(r.attacks) (\(pct(r.attackWins, r.attacks)))", 14)
          + pad("\(r.defences) (\(pct(r.defenceWins, r.defences)))", 18))
}
