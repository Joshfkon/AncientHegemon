import Foundation
import HegemonCore
import Observation

struct LogLine: Identifiable {
    let id: Int
    let round: Int
    let civ: CivilizationID?
    let text: String
}

struct BattleEntry: Identifiable {
    let id: Int
    let round: Int
    let territory: TerritoryID
    let report: BattleReport
}

/// Runs an AI-vs-AI game a round at a time, off the main thread, and keeps a readable chronicle.
@MainActor @Observable
final class GameSession {
    let engine: Engine
    private(set) var state: GameState
    private(set) var log: [LogLine] = []
    private(set) var battles: [BattleEntry] = []
    private(set) var busy = false
    private(set) var seed: UInt64
    var playing = false {
        didSet { if playing { startPlaying() } }
    }
    /// Seconds between rounds while playing.
    var delay = 0.6
    private var nextID = 0

    init() {
        let engine = try! Engine.bundled()
        let seed = UInt64.random(in: 1...99_999)
        self.engine = engine
        self.seed = seed
        state = try! engine.newGame(seed: seed, civilizations: Self.order(engine, seed))
    }

    private static func order(_ engine: Engine, _ seed: UInt64) -> [CivilizationID] {
        shuffledTurnOrder(engine.map.civilizations.map(\.id), seed: seed)
    }

    func newGame() {
        playing = false
        seed = UInt64.random(in: 1...99_999)
        state = try! engine.newGame(seed: seed, civilizations: Self.order(engine, seed))
        log = []
        battles = []
    }

    var isOver: Bool { state.winner != nil }

    /// Plays every civ's turn once.
    func playRound() async {
        guard !busy, !isOver else { return }
        busy = true
        defer { busy = false }
        let engine = self.engine
        let start = state
        let round = start.turn
        let (after, events) = await Task.detached(priority: .userInitiated) { () -> (GameState, [GameEvent]) in
            var s = start
            var events: [GameEvent] = []
            repeat {
                let civ = s.activePlayer
                let ai = AIPlayer(engine: engine, personality: .default(for: civ))
                events += ai.playTurn(&s).events
            } while s.winner == nil && s.activePlayerIndex != 0
            return (s, events)
        }.value
        record(events, round: round, before: start, after: after)
        state = after
    }

    private func startPlaying() {
        Task {
            while playing, !isOver {
                await playRound()
                try? await Task.sleep(for: .seconds(delay))
            }
            playing = false
        }
    }

    // MARK: Chronicle

    private func record(_ events: [GameEvent], round: Int, before: GameState, after: GameState) {
        var lines: [LogLine] = []
        var target: TerritoryID?
        func name(_ civ: CivilizationID?) -> String { civ.map { Palette.name($0, after) } ?? "nobody" }
        func place(_ t: TerritoryID?) -> String { t.flatMap { engine.map.territory($0)?.name } ?? "?" }
        func add(_ civ: CivilizationID?, _ text: String) {
            nextID += 1
            lines.append(LogLine(id: nextID, round: round, civ: civ, text: text))
        }

        for event in events {
            switch event {
            case let .moved(_, _, to, _): target = to
            case let .landed(civ, _, t, units):
                target = t
                add(civ, "\(name(civ)) lands \(units.total) troops on \(place(t))")
            case let .battle(report):
                let a = report.setup.attacker, d = report.setup.defender
                let won = report.winner == .attacker
                add(won ? a.civ : d.civ,
                    "Battle of \(place(target)): \(name(a.civ)) (\(a.units.total)) \(won ? "beat" : "repulsed by") "
                    + "\(name(d.civ)) (\(d.units.total)) in \(report.rounds) rounds")
                if let t = target {
                    nextID += 1
                    battles.insert(BattleEntry(id: nextID, round: round, territory: t, report: report), at: 0)
                }
            case let .captured(civ, t, from) where before.isPlayer(from) || after.isPlayer(civ) && from != nil:
                let verb = after.isPlayer(civ) ? "takes" : "seize"
                add(civ, "\(name(civ)) \(verb) \(place(t)) from \(name(from))")
            case let .civilWar(civ, rebel, _, territories):
                add(rebel, "CIVIL WAR in \(name(civ)): \(name(rebel)) seize \(territories.map { place($0) }.joined(separator: ", "))")
            case let .rulerDied(civ, ruler, age, cause):
                add(civ, "\(ruler) of \(name(civ)) dies \(cause == .plague ? "of plague" : "of old age") at \(age)")
            case let .succession(civ, ruler, outcome):
                let how = switch outcome {
                case .smooth: "succeeds"
                case .regency: "takes the throne under a regency"
                case .bribed: "takes the throne after buying off rivals"
                case .civilWar: "is crowned as rivals take up arms"
                case .coup: "seizes power and ends the republic"
                }
                add(civ, "\(ruler) \(how) in \(name(civ))")
            case let .event(r):
                let text = switch r.kind {
                case .famine: "Famine in \(place(r.territory))"
                case .flood: "Floods in \(place(r.territory))" + (r.amount > 0 ? " (−\(r.amount) people)" : "")
                case .goodHarvest: "Bumper harvest in \(place(r.territory))"
                case .plague: "Plague in \(name(r.civ)) (−\(r.amount) people)"
                case .goldDiscovered: "Gold found in \(place(r.territory))"
                case .badOmen: "Bad omens in \(name(r.civ)): the sacred chickens refuse to eat"
                case .barbarians: "A barbarian horde of \(r.amount) falls on \(place(r.territory))"
                case .revolt: "\(place(r.territory)) revolts against \(name(r.civ))"
                }
                if r.kind == .revolt || r.kind == .barbarians { target = r.territory }
                add(r.civ, text)
            case let .peaceMade(pair): add(nil, "Peace between \(name(pair.a)) and \(name(pair.b))")
            case let .warDeclared(by, on): add(by, "\(name(by)) declares war on \(name(on))")
            case let .navalBattle(sea, r):
                let winner = r.winner == .attacker ? r.attacker : r.defender
                add(winner, "Sea battle in the \(engine.map.sea(sea)?.name ?? sea): \(name(winner)) wins")
            case let .generalKilled(id):
                if let g = after.generals[id] { add(g.owner, "General \(g.name) of \(name(g.owner)) falls") }
            case let .eliminated(civ): add(civ, "\(name(civ)) is destroyed")
            case let .victory(civ): add(civ, "\(name(civ)) dominates the known world")
            default: break
            }
        }
        log.insert(contentsOf: lines.reversed(), at: 0)
        if log.count > 300 { log.removeLast(log.count - 300) }
        if battles.count > 100 { battles.removeLast(battles.count - 100) }
    }
}
