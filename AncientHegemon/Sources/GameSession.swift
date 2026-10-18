import Foundation
import HegemonCore
import Observation

struct LogLine: Identifiable, Codable {
    let id: Int
    let round: Int
    let civ: CivilizationID?
    let text: String
    /// Where it happened, to jump the map there.
    var territory: TerritoryID?
}

struct BattleEntry: Identifiable, Codable {
    let id: Int
    let round: Int
    let territory: TerritoryID
    let report: BattleReport
}

/// One game: a person playing one civilization against the AI (or just watching the AIs).
/// Applies the player's orders, runs the AI empires' turns off the main thread one at a time so
/// their moves can be watched, and keeps a readable chronicle.
@MainActor @Observable
final class GameSession {
    let engine: Engine
    private(set) var state: GameState {
        didSet { refreshEconomy() }
    }
    /// The player's economy as it stands (grain, gold, trade, resources), kept current.
    private(set) var economy: EconomyReport?
    private(set) var log: [LogLine] = []
    private(set) var battles: [BattleEntry] = []
    /// The civilization the person plays; nil when watching the AIs play each other.
    private(set) var human: CivilizationID?
    /// Whether a game is under way (false shows the civilization picker).
    private(set) var started = false
    /// AI empires are taking their turns.
    private(set) var busy = false
    private(set) var seed: UInt64
    /// The latest refusal from the engine, in words, for the order panel.
    var message: String?
    /// A battle the player fought, waiting to be watched.
    var replay: BattleEntry?
    /// Spectating: AI rounds keep playing until paused.
    var playing = false {
        didSet { if playing { startPlaying() } }
    }
    /// Seconds between AI turns, so their moves can be followed on the map.
    var pace = 0.35
    private var nextID = 0
    /// A game that can be continued, offered on the picker.
    private(set) var saved: SavedGame?
    /// What the rivals did since the player's last turn, marked on the map until it ends again.
    private(set) var marks: [MapMark] = []
    /// The chronicle lines since the player last ended a turn, shown as a summary card.
    private(set) var report: [LogLine] = []
    var showReport = false
    /// Skip the step-by-step reveal of the rivals' moves.
    var skipping = false
    /// The odds of the attack being planned, for the arrow on the map.
    var plannedOdds: Double?
    /// States to step back to within the turn. Anything left to chance (a battle, an event)
    /// clears it, so undo can't re-roll fate.
    private var undoStack: [(state: GameState, log: [LogLine], battles: [BattleEntry], nextID: Int)] = []
    var canUndo: Bool { isHumanTurn && !undoStack.isEmpty }
    private var reportFrom = 0

    init() {
        let engine = try! Engine.bundled()
        let seed = UInt64.random(in: 1...99_999)
        self.engine = engine
        self.seed = seed
        state = try! engine.newGame(seed: seed, civilizations: Self.order(engine, seed))
        saved = SaveStore.load(for: engine)
    }

    private static func order(_ engine: Engine, _ seed: UInt64) -> [CivilizationID] {
        shuffledTurnOrder(engine.map.civilizations.map(\.id), seed: seed)
    }

    /// Starts a game as `civ`, or as a spectator when nil.
    func start(as civ: CivilizationID?) {
        playing = false
        seed = UInt64.random(in: 1...99_999)
        state = try! engine.newGame(seed: seed, civilizations: Self.order(engine, seed))
        human = civ
        if let civ { state.civs[civ]!.isHuman = true }
        refreshEconomy()
        log = []
        battles = []
        message = nil
        replay = nil
        started = true
        SaveStore.delete()
        saved = nil
        if civ != nil {
            autosave()
            Task { await runAITurns() }
        }
    }

    /// Picks up the saved game where it left off.
    func resume() {
        guard let game = saved else { return }
        playing = false
        seed = game.seed
        human = game.human
        state = game.state
        log = game.log
        battles = game.battles
        nextID = (game.log.map(\.id) + game.battles.map(\.id)).max() ?? 0
        message = nil
        replay = nil
        started = true
        // If the app closed while the rivals were moving, let them finish.
        if state.activePlayer != human { Task { await runAITurns() } }
    }

    /// Saves the player's game (spectating isn't saved); a finished game clears the save.
    func autosave() {
        guard let human, started else { return }
        if isOver {
            SaveStore.delete()
            saved = nil
            return
        }
        let game = SavedGame(human: human, seed: seed, state: state, log: Array(log.prefix(150)),
                             battles: Array(battles.prefix(30)), savedAt: .now)
        SaveStore.save(game)
        saved = game
    }

    private func refreshEconomy() {
        economy = human.map { engine.economy(of: $0, in: state) }
    }

    func quit() {
        autosave()
        playing = false
        started = false
        human = nil
    }

    var isOver: Bool { state.winner != nil }
    var isHumanTurn: Bool { human != nil && state.activePlayer == human && !isOver && !busy }
    var crisis: SuccessionCrisis? { human.flatMap { state.civs[$0]?.crisis } }

    // MARK: Orders

    /// Applies one of the player's orders. Returns false (and sets `message`) if the engine refuses.
    @discardableResult
    func order(_ command: Command) -> Bool {
        guard isHumanTurn else { return false }
        let before = state
        let snapshot = (state: state, log: log, battles: battles, nextID: nextID)
        do {
            var s = state
            let events = try engine.apply(command, to: &s)
            message = nil
            if case .endTurn = command {
                undoStack = []
                marks = []
                showReport = false
                skipping = false
                reportFrom = nextID
            }
            record(events, round: before.turn, before: before, after: s)
            state = s
            if case .endTurn = command {
            } else if s.rng != before.rng || events.contains(where: { if case .battle = $0 { true } else { false } }) {
                undoStack = []  // chance has spoken
            } else {
                undoStack.append(snapshot)
            }
            autosave()
            if case .endTurn = command { Task { await runAITurns() } }
            return true
        } catch {
            message = Self.describe(error, engine: engine)
            return false
        }
    }

    func endTurn() { order(.endTurn) }

    /// Steps back one order this turn.
    func undo() {
        guard canUndo, let last = undoStack.popLast() else { return }
        state = last.state
        log = last.log
        battles = last.battles
        nextID = last.nextID
        message = nil
        autosave()
    }

    /// Plays AI turns until it is the person's turn again (or the game ends).
    private func runAITurns() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        while !isOver, state.activePlayer != human {
            await playOneAITurn()
            if !skipping { try? await Task.sleep(for: .seconds(pace)) }
        }
        // Back to the player: sum up what happened since they ended their turn.
        report = log.filter { $0.id > reportFrom }.sorted { $0.id < $1.id }
        showReport = human != nil && !report.isEmpty && !isOver
        autosave()
    }

    private func playOneAITurn() async {
        let engine = self.engine
        let start = state
        let (after, events) = await Task.detached(priority: .userInitiated) { () -> (GameState, [GameEvent]) in
            var s = start
            let ai = AIPlayer(engine: engine, personality: .default(for: s.activePlayer))
            let turn = ai.playTurn(&s)
            return (s, turn.events)
        }.value
        record(events, round: start.turn, before: start, after: after)
        state = after
        // Reveal this rival's moves one at a time, so they can be followed on the map.
        for mark in MapMark.from(events, before: start, after: after) {
            marks.append(mark)
            if human != nil, !skipping { try? await Task.sleep(for: .milliseconds(220)) }
        }
    }

    // MARK: Spectating

    /// Plays every civ's turn once (spectator mode).
    func playRound() async {
        guard human == nil, !busy, !isOver else { return }
        busy = true
        defer { busy = false }
        let round = state.turn
        repeat {
            await playOneAITurn()
        } while !isOver && state.turn == round
    }

    private func startPlaying() {
        Task {
            while playing, !isOver {
                await playRound()
                try? await Task.sleep(for: .seconds(0.4))
            }
            playing = false
        }
    }

    /// The engine's refusals, in words.
    static func describe(_ error: Error, engine: Engine) -> String {
        func place(_ t: String) -> String { engine.map.territory(t)?.name ?? engine.map.sea(t)?.name ?? t }
        guard let e = error as? GameError else { return "That can't be done." }
        switch e {
        case .insufficientGold(let needed, let available): return "Not enough gold: \(needed) needed, \(available) in the treasury."
        case .insufficientPopulation(let t): return "\(place(t)) has too few people left to raise troops."
        case .resourceLimit(let r): return "Not enough \(r.rawValue) this turn."
        case .notAdjacent(let a, let b): return "\(place(a)) and \(place(b)) don't border each other."
        case .insufficientUnits(let t): return "Not enough troops ready in \(place(t)) (each unit moves once a turn)."
        case .atPeace(let t): return "You are at peace with the owner of \(place(t)). Declare war first."
        case .outOfSupply(let t): return "\(place(t)) is cut off from your capital's supply."
        case .contested(let t): return "Another army holds \(place(t))."
        case .badOmen: return "The omens forbid attacking this turn."
        case .tooManyGenerals: return "Your realm can't support another general yet."
        case .crisisPending: return "Settle the succession first."
        case .chokepointClosed: return "An enemy holds the strait."
        case .overCapacity: return "The ships can't carry that many."
        case .blockaded(let s): return "An enemy fleet controls \(place(s))."
        case .noGeneral: return "No general is ready to march from there."
        case .notCoastal(let t, let s): return "\(place(t)) has no coast on \(place(s))."
        case .insufficientShips: return "Not enough ships ready to sail."
        case .planLocked: return "Your army hasn't learned that yet."
        case .invalidTaxRate: return "Taxes go from 0 to 100% in steps of 10."
        case .projectUnavailable(let t, let p): return "Can't build \(projectName(p).lowercased()) in \(place(t))."
        case .insufficientStock(let r, let needed, let available): return "Not enough \(r.rawValue): \(needed) needed, \(available) in store."
        default: return "That can't be done (\(e))."
        }
    }

    // MARK: Chronicle

    private func record(_ events: [GameEvent], round: Int, before: GameState, after: GameState) {
        var lines: [LogLine] = []
        var target: TerritoryID?
        func name(_ civ: CivilizationID?) -> String { civ.map { Palette.name($0, after) } ?? "nobody" }
        func place(_ t: TerritoryID?) -> String { t.flatMap { engine.map.territory($0)?.name } ?? "?" }
        func add(_ civ: CivilizationID?, _ text: String, at territory: TerritoryID? = nil) {
            nextID += 1
            lines.append(LogLine(id: nextID, round: round, civ: civ, text: text, territory: territory))
        }

        for event in events {
            switch event {
            case let .moved(_, _, to, _): target = to
            case let .landed(civ, _, t, units):
                target = t
                add(civ, "\(name(civ)) lands \(units.total) troops on \(place(t))", at: t)
            case let .battle(report):
                let a = report.setup.attacker, d = report.setup.defender
                let won = report.winner == .attacker
                add(won ? a.civ : d.civ,
                    "Battle of \(place(target)): \(name(a.civ)) (\(a.units.total)) \(won ? "beat" : "repulsed by") "
                    + "\(name(d.civ)) (\(d.units.total + d.levy)) in \(report.rounds) rounds", at: target)
                if let t = target {
                    nextID += 1
                    let entry = BattleEntry(id: nextID, round: round, territory: t, report: report)
                    battles.insert(entry, at: 0)
                    if let human, a.civ == human || d.civ == human { replay = entry }
                }
            case let .captured(civ, t, from) where before.isPlayer(from) || after.isPlayer(civ) && from != nil:
                let verb = after.isPlayer(civ) ? "takes" : "seize"
                add(civ, "\(name(civ)) \(verb) \(place(t)) from \(name(from))", at: t)
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
                case .claimantCrowned: "is crowned to keep the peace"
                }
                add(civ, "\(ruler) \(how) in \(name(civ))")
            case let .event(r):
                let text = switch r.kind {
                case .famine: "Famine in \(place(r.territory))"
                case .flood: "Floods in \(place(r.territory))" + (r.amount > 0 ? " (−\(r.amount) people)" : "")
                case .goodHarvest: "Bumper harvest in \(place(r.territory))"
                case .plague: "Plague in \(name(r.civ))" + (r.amount > 0 ? " (−\(r.amount) people)" : "")
                case .goldDiscovered: "Gold found in \(place(r.territory))"
                case .badOmen: "Bad omens in \(name(r.civ)): the sacred chickens refuse to eat"
                case .barbarians: "A barbarian horde of \(r.amount) falls on \(place(r.territory))"
                case .revolt: "\(place(r.territory)) revolts against \(name(r.civ))"
                case .seaPeoples: "Sea Peoples, \(r.amount) strong, land in \(place(r.territory))"
                case .drought: "Drought in \(name(r.civ)): \(r.amount) harvests wither"
                case .earthquake: "An earthquake shakes \(place(r.territory))"
                case .tradeDisrupted: "Trade between \(name(r.civ)) and \(name(r.partner)) breaks down for \(r.amount) rounds"
                }
                if [.revolt, .barbarians, .seaPeoples].contains(r.kind) { target = r.territory }
                add(r.civ, text, at: r.territory)
            case let .successionCrisis(civ, claimants):
                add(civ, "The throne of \(name(civ)) is contested by \(claimants.count) general\(claimants.count == 1 ? "" : "s")")
            case let .peaceOffered(from, to):
                if to == human || from == human { add(from, "\(name(from)) offers peace to \(name(to))") }
            case let .recruited(civ, t, unit, count) where civ == human:
                add(civ, "Raised \(count) \(unit.rawValue) in \(place(t))", at: t)
            case let .peaceMade(pair): add(nil, "Peace between \(name(pair.a)) and \(name(pair.b))")
            case let .warDeclared(by, on): add(by, "\(name(by)) declares war on \(name(on))")
            case let .navalBattle(sea, r):
                let winner = r.winner == .attacker ? r.attacker : r.defender
                add(winner, "Sea battle in the \(engine.map.sea(sea)?.name ?? sea): \(name(winner)) wins")
            case let .generalKilled(id):
                if let g = after.generals[id] { add(g.owner, "General \(g.name) of \(name(g.owner)) falls") }
            case let .discovery(civ, field, level):
                if civ == human || level >= 2 {
                    add(civ, "\(name(civ)) discover\(civ == human ? "" : "s") \(engine.levelName(field, level) ?? field.rawValue)"
                        + (civ == human ? ": \(KnowledgeView.effect(field, level))" : ""))
                }
            case let .projectStarted(civ, t, kind) where civ == human:
                add(civ, "Work begins on \(projectName(kind).lowercased()) in \(place(t))")
            case let .projectCompleted(civ, t, kind) where civ == human:
                add(civ, "\(projectName(kind)) finished in \(place(t))", at: t)
            case let .projectDestroyed(t, kind) where before.owner(of: t) == human:
                add(human, "\(projectName(kind)) in \(place(t)) destroyed", at: t)
            case let .taxRateSet(civ, rate) where civ == human:
                add(civ, "Taxes set to \(rate)%")
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
