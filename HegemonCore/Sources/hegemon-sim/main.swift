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
//   Any mode takes --set KEY=VALUE (repeatable) to override a rules.json number for the run,
//   e.g. --set battle.homeGroundPercent=5, for trying a balance change without rebuilding.
//   hegemon-sim defence [--seeds N]
//       Attacker win rates by army size, terrain and walls: the attacker uses its best formation,
//       the defender the formation that holds best against it.
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

/// The bundled engine with any `--set path.to.key=number` overrides applied to the rules.
func makeEngine() throws -> Engine {
    let bundled = try Engine.bundled()
    let args = CommandLine.arguments
    let sets = args.indices.filter { args[$0] == "--set" && $0 + 1 < args.count }.map { args[$0 + 1] }
    guard !sets.isEmpty else { return bundled }
    var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(bundled.rules)) as! [String: Any]
    func assign(_ path: ArraySlice<String>, _ value: Int, in dict: inout [String: Any]) {
        guard let key = path.first else { return }
        if path.count == 1 {
            guard dict[key] is NSNumber else { print("--set: no number at \(key)"); exit(1) }
            dict[key] = value
        } else {
            guard var inner = dict[key] as? [String: Any] else { print("--set: no section \(key)"); exit(1) }
            assign(path.dropFirst(), value, in: &inner)
            dict[key] = inner
        }
    }
    for s in sets {
        let parts = s.split(separator: "=", maxSplits: 1).map(String.init)
        guard parts.count == 2, let value = Int(parts[1]) else { print("--set wants KEY=NUMBER, got \(s)"); exit(1) }
        assign(ArraySlice(parts[0].split(separator: ".").map(String.init)), value, in: &json)
    }
    let rules = try Rules(json: JSONSerialization.data(withJSONObject: json))
    return Engine(map: bundled.map, rules: rules)
}
let engine = try makeEngine()

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

if CommandLine.arguments.dropFirst().first == "defence" {
    let seeds = Int(option("--seeds") ?? "60") ?? 60
    let sim = BattleSimulator(rules: engine.rules)
    let ids = engine.rules.battle.formations.map(\.id)
    func army(_ n: Int) -> UnitCounts {
        UnitCounts(infantry: n - n / 4 - n / 4, archers: n / 4, cavalry: n / 4)
    }
    func attackerWins(_ a: Int, _ d: Int, _ terrain: Terrain, _ walls: Int, _ approach: Approach = .overland) -> Int {
        // The defender commits to a formation first; the attacker answers it.
        ids.map { df in
            ids.map { af in
                (0..<seeds).filter { seed in
                    sim.resolve(BattleSetup(attacker: BattleArmy(civ: "a", units: army(a), formation: af),
                                            defender: BattleArmy(civ: "d", units: army(d), formation: df),
                                            terrain: terrain, approach: approach, seed: UInt64(seed),
                                            fortification: walls)).winner == .attacker
                }.count
            }.max()!
        }.min()! * 100 / seeds
    }
    let matchups = [(4, 4), (5, 4), (6, 4), (8, 4), (6, 6), (9, 6), (12, 6)]
    let walls = [0, engine.rules.projectEffects.wallsDefensePercent,
                 engine.rules.projectEffects.wallsDefensePercent + engine.rules.knowledge.effects.fortificationPercent]
    print("attacker win %, mixed armies (half infantry, a quarter each archers and cavalry), \(seeds) seeds")
    print("terrain    walls " + matchups.map { pad("\($0.0)v\($0.1)", 6) }.joined())
    print("plains, across a river".padding(toLength: 16, withPad: " ", startingAt: 0)
          + matchups.map { pad("\(attackerWins($0.0, $0.1, .plains, 0, .river))%", 6) }.joined())
    for terrain in Terrain.allCases {
        for w in walls {
            print(terrain.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0) + pad("\(w)%", 6)
                  + matchups.map { pad("\(attackerWins($0.0, $0.1, terrain, w))%", 6) }.joined())
        }
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
    let how = record.finalState.victory.map { " by \($0.grade.rawValue) \($0.kind.rawValue)" } ?? ""
    print("game \(g + 1)/\(games) seed \(seed): winner \(record.winner ?? "none")\(how) after \(record.turns) turns (\(land))")
}
let elapsed = Date().timeIntervalSince(started)

let civs = engine.map.civilizations.map(\.id)
let decided = records.filter { $0.winner != nil }
print("")
print("\(games) games, max \(maxTurns) turns, \(String(format: "%.1f", elapsed))s")
print("decided: \(decided.count)/\(games)"
      + (decided.isEmpty ? "" : ", average length \(decided.map(\.turns).reduce(0, +) / decided.count) turns"))
let endings = Dictionary(grouping: records.compactMap(\.finalState.victory)) { "\($0.grade.rawValue) \($0.kind.rawValue)" }
print("how games end: " + endings.map { ($0.key, $0.value.count) }.sorted { $0.1 > $1.1 }
      .map { "\($0.0) \($0.1)" }.joined(separator: ", "))
print("")
print("civ          personality   wins  elim  collapse  avg land  peak  starving turns  deserted  attrition    attacks won   defences held   vs civs held  rejected")
for civ in civs {
    let rs = records.compactMap { $0.civs[civ] }
    let n = max(1, rs.count)
    let sum = { (f: (CivRecord) -> Int) in rs.map(f).reduce(0, +) }
    let attacks = sum { $0.attacksWon + $0.attacksLost }
    let defences = sum { $0.defencesWon + $0.defencesLost }
    let civDefences = sum { $0.defencesVsCivsWon + $0.defencesVsCivsLost }
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
        pad("\(pct(sum(\.defencesVsCivsWon), civDefences)) of \(civDefences)", 15),
        pad(String(sum(\.rejectedCommands)), 10),
    ]
    print(cols.joined())
}

// Who leads, and does the lead last? Rebel factions are pooled as "rebels".
func side(_ civ: CivilizationID?) -> String? {
    guard let civ else { return nil }
    return civs.contains(civ) ? civ : "rebels"
}
let lc = records.map(\.leadChanges)
let earlyLeaderWon = decided.filter { r in side(r.leader(atRound: 10)) == side(r.winner) }.count
print("")
print("lead changes per game: average \(String(format: "%.1f", Double(lc.reduce(0, +)) / Double(max(1, lc.count)))), "
      + "games with none \(pct(lc.filter { $0 == 0 }.count, lc.count)); "
      + "the round-10 leader went on to win \(pct(earlyLeaderWon, decided.count)) of decided games")
print("civ          led at round 10   20   30   wins  rebel wins")
for name in civs + ["rebels"] {
    let cols = [10, 20, 30].map { round in
        pad(pct(records.filter { side($0.leader(atRound: round)) == name }.count, records.count), round == 10 ? 18 : 5)
    }
    print(name.padding(toLength: 13, withPad: " ", startingAt: 0) + cols.joined()
          + pad(pct(records.filter { side($0.winner) == name }.count, records.count), 7)
          + (name == "rebels" ? "" : pad(pct(records.filter { r in
              r.winner.map { r.finalState.civs[$0]?.rebelledFrom == name } ?? false }.count, records.count), 12)))
}

// Government and events, per 100 turns played (games differ a lot in length).
let kinds = EventKind.allCases
print("")
print("per 100 turns")
print("civ          rulers died  civil wars  regencies  coups   "
      + kinds.map { pad(String($0.rawValue.prefix(8)), 9) }.joined())
for civ in civs {
    let rs = records.compactMap { $0.civs[civ] }
    let turnsPlayed = Double(max(1, records.map(\.turns).reduce(0, +)))
    let avg = { (f: (CivRecord) -> Int) in String(format: "%.1f", Double(rs.map(f).reduce(0, +)) * 100 / turnsPlayed) }
    print(civ.padding(toLength: 13, withPad: " ", startingAt: 0)
          + pad(avg(\.rulersDied), 11) + pad(avg(\.civilWars), 12) + pad(avg(\.regencies), 11) + pad(avg(\.coups), 7)
          + "   " + kinds.map { k in pad(avg { $0.events[k] ?? 0 }, 9) }.joined())
}
let rebelFactions = records.map { r in r.finalState.players.filter { r.finalState.civs[$0]?.rebelledFrom != nil }.count }
print("rebel factions per game: \(String(format: "%.1f", Double(rebelFactions.reduce(0, +)) / Double(max(1, records.count))))")

print("")
print("median over civs holding land then")
print("civ          gold in hand at round 10   20   30    units at 10   20   30")
for civ in civs {
    let rs = records.compactMap { $0.civs[civ] }
    func avg(_ f: (CivRecord) -> Int?) -> String {
        let xs = rs.compactMap(f).sorted()
        return xs.isEmpty ? "-" : String(xs[xs.count / 2])
    }
    print(civ.padding(toLength: 13, withPad: " ", startingAt: 0)
          + [10, 20, 30].map { r in pad(avg { $0.goldAt[r] }, r == 10 ? 26 : 5) }.joined()
          + [10, 20, 30].map { r in pad(avg { $0.unitsAt[r] }, r == 10 ? 15 : 5) }.joined())
}

print("")
print("civ          ships built  landings  sea battles won")
for civ in civs {
    let rs = records.compactMap { $0.civs[civ] }
    let n = max(1, rs.count)
    let sum = { (f: (CivRecord) -> Int) in rs.map(f).reduce(0, +) }
    let fights = sum { $0.navalBattlesWon + $0.navalBattlesLost }
    print(civ.padding(toLength: 13, withPad: " ", startingAt: 0)
          + pad(String(format: "%.1f", Double(sum(\.shipsBuilt)) / Double(n)), 11)
          + pad(String(format: "%.1f", Double(sum(\.landings)) / Double(n)), 10)
          + pad("\(pct(sum(\.navalBattlesWon), fights)) of \(fights)", 17))
}

// Knowledge and investment: what each empire learned by round 20, and what it built.
let fields = KnowledgeField.allCases
print("")
print("knowledge at round 20 (average level 0-3), projects per game")
print("civ          " + fields.map { pad(String($0.rawValue.prefix(8)), 9) }.joined() + "    built     lost")
for civ in civs {
    let rs = records.compactMap { $0.civs[civ] }
    let known = rs.compactMap(\.knowledgeAt20)
    let n = Double(max(1, rs.count))
    print(civ.padding(toLength: 13, withPad: " ", startingAt: 0)
          + fields.map { f in pad(known.isEmpty ? "-" : String(format: "%.1f",
              Double(known.map { $0[f] ?? 0 }.reduce(0, +)) / Double(known.count)), 9) }.joined()
          + pad(String(format: "%.1f", Double(rs.map(\.projectsBuilt).reduce(0, +)) / n), 9)
          + pad(String(format: "%.1f", Double(rs.map(\.projectsDestroyed).reduce(0, +)) / n), 9))
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

var odds = OddsTally()
for r in records {
    for i in odds.battles.indices {
        odds.battles[i] += r.civBattles.battles[i]
        odds.attackerWins[i] += r.civBattles.attackerWins[i]
    }
}
let labels = ["< 1.25x", "1.25-1.5x", "1.5-2x", "2-3x", ">= 3x"]
print("")
print("civ against civ land battles, by attacker:defender troops")
print("odds         " + labels.map { pad($0, 11) }.joined())
print("battles      " + odds.battles.map { pad(String($0), 11) }.joined())
print("attacker won " + odds.battles.indices.map { pad(pct(odds.attackerWins[$0], odds.battles[$0]), 11) }.joined())

