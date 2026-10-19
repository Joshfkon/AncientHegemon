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
    /// It touches the player: their land, armies, ruler, diplomacy or discoveries.
    var mine: Bool?
}

/// One empire's numbers at the start of a round.
struct RoundStats: Codable, Equatable {
    var prestige: Int
    var land: Int
    var people: Int
    var gold: Int
    var army: Int
    var ships: Int
    var granary: Int
    var knowledge: Int
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
        didSet {
            refreshEconomy()
            // Borders and prestige are recorded once a round, whoever's move began it.
            if started, state.turn != recordedTurn || (state.winner != nil && oldValue.winner == nil) {
                recordedTurn = state.turn
                snapshotBorders()
            }
        }
    }
    /// The round last recorded in `history`.
    private var recordedTurn = 0
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
    /// An attack drawn up on the battlefield, waiting for the player's plan and the charge.
    var muster: Muster?
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
    /// When each mark appeared, so new ones can animate in.
    private(set) var markTimes: [Date] = []
    /// Who held each territory at the start of each round, for the end-of-game replay.
    private(set) var history: [[TerritoryID: CivilizationID]] = []
    /// Each empire's prestige, land, people, gold, army and more at the start of each round,
    /// for the graphs.
    private(set) var statsHistory: [[CivilizationID: RoundStats]] = []
    /// The chronicle lines since the player last ended a turn, shown as a summary card.
    private(set) var report: [LogLine] = []
    var showReport = false
    /// Skip the step-by-step reveal of the rivals' moves.
    var skipping = false
    /// The odds of the attack being planned, for the arrow on the map.
    var plannedOdds: Double?
    /// A short confirmation of the player's last order ("Raised 1 infantry in Egypt").
    var toast: (text: String, id: Int, bad: Bool)?
    /// A rival's answer to the player's latest proposal, shown on its diplomacy card for the turn.
    var answers: [CivilizationID: (round: Int, text: String, good: Bool)] = [:]
    /// Big moments waiting to be shown, one at a time.
    var moments: [Moment] = []
    /// Territories that just changed hands, with when, for a colour sweep on the map.
    private(set) var flashes: [TerritoryID: Date] = [:]
    /// States to step back to within the turn. Anything left to chance (a battle, an event)
    /// clears it, so undo can't re-roll fate.
    private var undoStack: [(state: GameState, log: [LogLine], battles: [BattleEntry], nextID: Int, marks: Int)] = []
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
        history = []
        statsHistory = []
        recordedTurn = state.turn
        snapshotBorders()
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
        history = game.history ?? []
        statsHistory = game.statsHistory ?? []
        recordedTurn = state.turn
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
                             battles: Array(battles.prefix(30)), savedAt: .now, history: history, statsHistory: statsHistory)
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
        let snapshot = (state: state, log: log, battles: battles, nextID: nextID, marks: marks.count)
        do {
            var s = state
            let events = try engine.apply(command, to: &s)
            message = nil
            if case .endTurn = command {
                undoStack = []
                marks = []
                markTimes = []
                showReport = false
                skipping = false
                reportFrom = nextID
            }
            record(events, round: before.turn, before: before, after: s)
            state = s
            // The player's own marches glide too.
            if case .endTurn = command {} else {
                for mark in MapMark.from(events, before: before, after: s) {
                    marks.append(mark)
                    markTimes.append(.now)
                }
            }
            if case .endTurn = command {
            } else if s.rng != before.rng || events.contains(where: { if case .battle = $0 { true } else { false } }) {
                undoStack = []  // chance has spoken
            } else {
                undoStack.append(snapshot)
            }
            autosave()
            switch command {
            case .recruit, .buildShips, .build, .appointGeneral, .honorGeneral: SoundBoard.shared.play(.coins, volume: 0.6)
            default: break
            }
            if let text = Self.confirmation(command, engine: engine) {
                toast = (text, (toast?.id ?? 0) + 1, false)
                Feedback.select()
            }
            // The tribe's answer.
            for event in events {
                switch event {
                case let .tribeJoined(_, t, _, warriors):
                    let name = engine.map.territory(t)?.name ?? t
                    toast = ("\(name) is yours" + (warriors > 0 ? " · \(warriors) warriors join" : ""), (toast?.id ?? 0) + 1, false)
                    Feedback.outcome(true)
                case let .tribeRefused(_, t, _):
                    toast = ("\(engine.map.territory(t)?.name ?? t) refuses", (toast?.id ?? 0) + 1, true)
                    Feedback.outcome(false)
                // A rival court's answer to the player's proposal.
                case let .allianceRefused(by, _):
                    let why = Self.allianceRefusal(by, state: before, engine: engine)
                    answers[by] = (state.turn, "They declined: \(why)", false)
                    toast = ("\(Palette.name(by, state)) declines your alliance", (toast?.id ?? 0) + 1, true)
                    SoundBoard.shared.play(.defeat, volume: 0.4)
                    Feedback.outcome(false)
                case let .allianceMade(pair) where pair.a == human || pair.b == human:
                    let other = pair.a == human ? pair.b : pair.a
                    answers[other] = (state.turn, "They accepted: you are allies.", true)
                case let .warRefused(by, ally, against) where ally == human:
                    answers[by] = (state.turn, "They won't fight \(Palette.name(against, state)): it's more than twice their strength. The alliance stands.", false)
                    toast = ("\(Palette.name(by, state)) won't join your war", (toast?.id ?? 0) + 1, true)
                    Feedback.outcome(false)
                case let .joinedWar(civ, against, ally) where ally == human:
                    answers[civ] = (state.turn, "They marched to war against \(Palette.name(against, state)) for you.", true)
                default: break
                }
            }
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
        marks = Array(marks.prefix(last.marks))
        markTimes = Array(markTimes.prefix(last.marks))
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
        // Only interrupt for news that touches the player; the rest waits behind the News button.
        showReport = human != nil && report.contains { $0.mine == true } && !isOver
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
            markTimes.append(.now)
            if human != nil, !skipping {
                let pause = if case .battle = mark { 700 } else if case .march = mark { 650 } else { 300 }
                try? await Task.sleep(for: .milliseconds(pause))
            }
        }
    }

    // MARK: Spectating

    /// Plays every civ's turn once (spectator mode).
    func playRound() async {
        guard human == nil, !busy, !isOver else { return }
        busy = true
        defer { busy = false }
        let round = state.turn
        // Watching: each round's moves replace the last round's on the map.
        marks = []
        markTimes = []
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

    /// What an order did, in words, for the confirmation toast.
    static func confirmation(_ command: Command, engine: Engine) -> String? {
        func place(_ t: String) -> String { engine.map.territory(t)?.name ?? engine.map.sea(t)?.name ?? t }
        switch command {
        case let .recruit(t, unit, count): return "Raised \(count) \(unit.rawValue) in \(place(t))"
        case let .buildShips(_, sea, count): return "\(count) ship\(count == 1 ? "" : "s") built in the \(place(sea))"
        case let .build(t, project): return "Work begins on \(projectName(project).lowercased()) in \(place(t))"
        case let .appointGeneral(t): return "A general takes command in \(place(t))"
        case let .disband(t, units): return "Disbanded \(units.total) in \(place(t))"
        case let .setTaxRate(r): return "Taxes set to \(r)%"
        default: return nil
        }
    }

    /// The engine's refusals, in words.
    /// Why a rival court turned down an alliance, in its own terms.
    static func allianceRefusal(_ civ: CivilizationID, state: GameState, engine: Engine) -> String {
        if engine.allies(of: civ, in: state).count >= engine.rules.alliances.maxAllies {
            return "they already have all the allies they can keep."
        }
        return "no shared enemy worries them. Courts ally against a common foe at least as strong as they are."
    }

    /// The chronicle's line for how the player answered the court's dilemma.
    static func decisionLine(_ kind: DecisionKind, _ accepted: Bool, _ state: GameState, _ engine: Engine) -> String {
        switch kind {
        case let .famine(t, grain):
            let place = engine.map.territory(t)?.name ?? t
            return accepted ? "The granaries open for \(place) (\(grain) grain); the people bless your name"
                            : "The granaries stay shut; \(place) starves and remembers"
        case let .honours(id, gold):
            let g = state.generals[id]?.name ?? "The general"
            return accepted ? "\(g) is honoured with \(gold) gold" : "\(g) is refused honours and sulks"
        case let .mercenaries(warriors, gold):
            return accepted ? "\(warriors) Sea People warriors take your \(gold) gold and your orders" : "The Sea People mercenaries sail away"
        }
    }

    static func describe(_ error: Error, engine: Engine) -> String {
        func place(_ t: String) -> String { engine.map.territory(t)?.name ?? engine.map.sea(t)?.name ?? t }
        guard let e = error as? GameError else { return "That can't be done." }
        switch e {
        case .insufficientGold(let needed, let available): return "Not enough gold: \(needed) needed, \(available) in the treasury."
        case .insufficientPopulation(let t): return "\(place(t)) has too few people left to raise troops."
        case .resourceLimit(let r):
            return "No \(r.rawValue) to spare this turn. Tap Resources (under your gold) to see where to get more."
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
        case .alreadyDecorated: return "That already adorns the hall."
        case .alreadyAllied: return "You are already allies."
        case .notAllied: return "You have no alliance with them."
        case .noAllianceOffer: return "That offer has lapsed."
        case .tooManyAllies: return "Your realm can keep only \(engine.rules.alliances.maxAllies) allies."
        case .notAtWar: return "You are not at war with them."
        case .alreadyAsked: return "You already asked them this turn."
        case .noWarRequest: return "That call to arms has lapsed."
        case .unknownDecoration: return "No such decoration."
        case .unknownMonument: return "No such great work."
        case .monumentUnavailable: return "That great work can't be raised there: it may stand already, or need other ground."
        case .noDecision: return "That matter is already settled."
        case .insufficientGrain(let needed): return "Not enough grain in the granaries: \(needed) needed."
        case .noTribe(let t): return "There is no tribe in \(place(t)) you can treat with: your land must border theirs."
        case .alreadyParleyed(let t): return "Your envoys have already spoken with \(place(t)) this turn."
        default: return "That can't be done (\(e))."
        }
    }

    private func snapshotBorders() {
        var owners: [TerritoryID: CivilizationID] = [:]
        for (t, land) in state.land { if let o = land.owner { owners[t] = o } }
        history.append(owners)
        var stats: [CivilizationID: RoundStats] = [:]
        for civ in state.players where !(state.civs[civ]?.eliminated ?? true) {
            let cs = state.civs[civ]!
            stats[civ] = RoundStats(prestige: engine.prestige(of: civ, in: state),
                                    land: state.territories(of: civ).count,
                                    people: state.totalPopulation(of: civ),
                                    gold: cs.gold,
                                    army: state.totalUnits(of: civ).total + state.fleets(of: civ).reduce(0) { $0 + $1.cargo.total },
                                    ships: state.fleets(of: civ).reduce(0) { $0 + $1.ships },
                                    granary: cs.granary,
                                    knowledge: cs.knowledge.values.reduce(0, +))
        }
        statsHistory.append(stats)
    }

    // MARK: Moments

    private func noteMoments(_ events: [GameEvent], before: GameState, after: GameState) {
        guard let me = human else { return }
        var new: [Moment] = []
        var target: TerritoryID?
        var attackers: Set<CivilizationID> = []
        for event in events {
            switch event {
            case let .moved(_, _, to, _), let .landed(_, _, to, _):
                target = to
            case let .battle(r) where r.setup.defender.civ == me && before.isPlayer(r.setup.attacker.civ)
                && !attackers.contains(r.setup.attacker.civ):
                attackers.insert(r.setup.attacker.civ)
                new.append(Moment(kind: .attacked(r.setup.attacker.civ, target)))
            case let .captured(civ, t, from):
                flashes[t] = .now
                if civ == me { new.append(Moment(kind: .captured(t))) }
                else if from == me { new.append(Moment(kind: .lost(t))) }
            case let .tribeJoined(civ, t, _, _) where civ == me:
                flashes[t] = .now
                new.append(Moment(kind: .captured(t)))
            case let .discovery(civ, field, level) where civ == me:
                new.append(Moment(kind: .discovery(field, level)))
            case let .peaceMade(pair) where pair.a == me || pair.b == me:
                new.append(Moment(kind: .peace(pair.a == me ? pair.b : pair.a)))
            case let .warDeclared(by, on) where by == me || on == me:
                new.append(Moment(kind: .war(by == me ? on : by)))
            case let .navalBattle(sea, r) where r.attacker == me || r.defender == me:
                new.append(Moment(kind: .seaBattle(sea, won: (r.winner == .attacker) == (r.attacker == me),
                                                   against: r.attacker == me ? r.defender : r.attacker)))
            case let .allianceMade(pair) where pair.a == me || pair.b == me:
                new.append(Moment(kind: .ally(pair.a == me ? pair.b : pair.a, joined: true)))
            case let .joinedWar(civ, against, ally) where ally == me:
                new.append(Moment(kind: .allyJoins(civ, against)))
            case let .allianceEnded(pair, by) where (pair.a == me || pair.b == me) && by != me:
                new.append(Moment(kind: .ally(by, joined: false)))
            case let .calledToWar(r) where r.to == me:
                new.append(Moment(kind: .callToArms(r.from, r.against)))
            case let .monumentCompleted(civ, _, id):
                new.append(Moment(kind: .monument(id, civ)))
            case let .monumentLost(civ, _, id) where civ == me:
                new.append(Moment(kind: .monumentLost(id)))
            case let .armyPaid(civ, _, deserted) where civ == me && deserted > 0:
                new.append(Moment(kind: .unpaid(deserted)))
            case let .event(r) where r.civ == me:
                if [.famine, .drought, .flood, .plague, .earthquake, .seaPeoples, .barbarians, .revolt].contains(r.kind) {
                    new.append(Moment(kind: .disaster(r.kind, r.territory)))
                }
            default:
                break
            }
        }
        moments.append(contentsOf: new)
        if moments.count > 4 { moments.removeFirst(moments.count - 4) }
        // Let the sweeps fade, then forget them, so the map stops redrawing.
        if !flashes.isEmpty {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                let now = Date.now
                flashes = flashes.filter { now.timeIntervalSince($0.value) < 1.7 }
            }
        }
    }

    #if DEBUG
    func demoFlash(_ t: TerritoryID) { flashes[t] = .now }

    /// Stages a sea battle: four of our ships beside three enemy ships, at war.
    func demoSeaBattle() -> Muster? {
        guard let human, let enemy = state.players.first(where: { $0 != human }),
              let seat = engine.seat(of: human, in: state), let sea = engine.map.seas(bordering: seat).first,
              let next = engine.map.seaNeighbors(of: sea).sorted().first else { return nil }
        var s = state
        s.fleets.removeAll { $0.owner == human || $0.sea == next }
        s.fleets.append(Fleet(sea: sea, owner: human, ships: 4))
        s.fleets.append(Fleet(sea: next, owner: enemy, ships: 3))
        s.fleets.sort { ($0.sea, $0.owner) < ($1.sea, $1.owner) }
        s.peace.remove(CivPair(human, enemy))
        state = s
        return Muster(from: sea, to: next, units: .zero, general: false, ships: 4, cargo: .zero)
    }
    #endif

    func dismissMoment() {
        if !moments.isEmpty { moments.removeFirst() }
    }

    // MARK: Chronicle

    /// Whether an event touches the player directly.
    private func involvesHuman(_ event: GameEvent, before: GameState, target: TerritoryID?) -> Bool {
        guard let me = human else { return false }
        switch event {
        case let .landed(civ, _, t, _): return civ == me || before.owner(of: t) == me
        case let .battle(report): return report.setup.attacker.civ == me || report.setup.defender.civ == me
        case let .captured(civ, _, from): return civ == me || from == me
        case let .civilWar(civ, _, _, _), let .rulerDied(civ, _, _, _), let .succession(civ, _, _),
             let .successionCrisis(civ, _), let .discovery(civ, _, _), let .recruited(civ, _, _, _),
             let .projectStarted(civ, _, _), let .projectCompleted(civ, _, _), let .taxRateSet(civ, _):
            return civ == me
        case let .event(r): return r.civ == me || r.partner == me || r.territory.map { before.owner(of: $0) == me } ?? false
        case let .peaceOffered(from, to): return from == me || to == me
        case let .peaceMade(pair), let .allianceMade(pair): return pair.a == me || pair.b == me
        case let .allianceEnded(pair, _): return pair.a == me || pair.b == me
        case let .calledToWar(r): return r.from == me || r.to == me || r.against == me
        case let .joinedWar(civ, against, ally): return civ == me || against == me || ally == me
        case let .warRefused(by, ally, _): return by == me || ally == me
        case let .allianceOffered(from, to), let .allianceRefused(from, to): return from == me || to == me
        case let .warDeclared(by, on): return by == me || on == me
        case let .navalBattle(_, r): return r.attacker == me || r.defender == me
        case let .generalKilled(id): return before.generals[id]?.owner == me
        case let .projectDestroyed(t, _): return before.owner(of: t) == me
        case let .eliminated(civ): return civ == me
        case let .monumentStarted(civ, _, _), let .monumentCompleted(civ, _, _), let .monumentLost(civ, _, _),
             let .decided(civ, _, _), let .patronageSet(civ, _):
            return civ == me
        default: return false
        }
    }

    private func record(_ events: [GameEvent], round: Int, before: GameState, after: GameState) {
        var lines: [LogLine] = []
        var target: TerritoryID?
        func name(_ civ: CivilizationID?) -> String { civ.map { Palette.name($0, after) } ?? "nobody" }
        func place(_ t: TerritoryID?) -> String { t.flatMap { engine.map.territory($0)?.name } ?? "?" }
        func monumentName(_ id: MonumentID) -> String { engine.rules.monuments.list.first { $0.id == id }?.name ?? id }
        var mine = false
        func add(_ civ: CivilizationID?, _ text: String, at territory: TerritoryID? = nil) {
            nextID += 1
            lines.append(LogLine(id: nextID, round: round, civ: civ, text: text, territory: territory, mine: mine))
        }

        for event in events {
            mine = involvesHuman(event, before: before, target: target)
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
                case .famine: "Famine in \(place(r.territory))" + (r.civ == human ? ": its harvest this turn was halved" : "")
                case .flood: "Floods in \(place(r.territory))" + (r.amount > 0 ? " (−\(r.amount) people)" : "")
                case .goodHarvest: "Bumper harvest in \(place(r.territory))"
                case .plague: "Plague in \(name(r.civ))" + (r.amount > 0 ? " (−\(r.amount) people)" : "")
                case .goldDiscovered: "Gold found in \(place(r.territory))"
                case .badOmen: "Bad omens in \(name(r.civ)): the sacred chickens refuse to eat"
                case .barbarians: "A barbarian horde of \(r.amount) falls on \(place(r.territory))"
                case .revolt: "\(place(r.territory)) revolts against \(name(r.civ))"
                case .seaPeoples: "Sea Peoples, \(r.amount) strong, land in \(place(r.territory))"
                case .drought: "Drought in \(name(r.civ)): \(r.amount) harvests wither" + (r.civ == human ? " (less grain this turn)" : "")
                case .earthquake: "An earthquake shakes \(place(r.territory))" + (r.civ == human ? ", costing people and buildings" : "")
                case .tradeDisrupted: "Trade between \(name(r.civ)) and \(name(r.partner)) breaks down for \(r.amount) rounds"
                }
                if [.revolt, .barbarians, .seaPeoples].contains(r.kind) { target = r.territory }
                add(r.civ, text, at: r.territory)
            case let .successionCrisis(civ, claimants):
                add(civ, "The throne of \(name(civ)) is contested by \(claimants.count) general\(claimants.count == 1 ? "" : "s")")
            case let .peaceOffered(from, to):
                if to == human || from == human { add(from, "\(name(from)) offers peace to \(name(to))") }
            case let .decorated(civ, d) where civ == human:
                add(civ, "The throne room is adorned with \(engine.rules.throneRoom.decoration(d)?.name.lowercased() ?? d)")
            case let .trophyWon(civ, kind) where civ == human && !{ if case .spoils = kind { true } else { false } }():
                add(civ, "A trophy for the throne room: \(ThroneRoomView.trophyName(kind, engine, after).lowercased())")
            case let .armyPaid(civ, _, deserted) where civ == human && deserted > 0:
                add(civ, "The treasury is empty: \(deserted) unpaid soldier\(deserted == 1 ? "" : "s") went home")
            case let .disbanded(civ, t, units, rejoined) where civ == human:
                add(civ, "Disbanded \(units.total) troops in \(place(t))" + (rejoined > 0 ? "; \(rejoined) went home to farm" : ""), at: t)
            case let .tribeJoined(civ, t, parley, warriors) where civ == human:
                add(civ, "\(place(t)) \(parley == .gifts ? "accepts your gifts" : "bows to your demand") and swears loyalty"
                    + (warriors > 0 ? "; \(warriors) warriors join you" : ""), at: t)
            case let .tribeRefused(civ, t, parley) where civ == human:
                add(civ, "\(place(t)) " + (parley == .gifts ? "takes your gifts but will not bow" : "refuses your demand and sharpens its spears"), at: t)
            case let .recruited(civ, t, unit, count) where civ == human:
                add(civ, "Raised \(count) \(unit.rawValue) in \(place(t))", at: t)
            case let .peaceMade(pair): add(nil, "Peace between \(name(pair.a)) and \(name(pair.b))")
            case let .allianceMade(pair): add(pair.a, "\(name(pair.a)) and \(name(pair.b)) swear an alliance")
            case let .allianceRefused(by, to): add(by, "\(name(by)) declines an alliance with \(name(to))")
            case let .allianceOffered(from, to): add(from, "\(name(from)) proposes an alliance to \(name(to))")
            case let .allianceEnded(pair, by): add(by, "\(name(by)) breaks the alliance with \(name(pair.a == by ? pair.b : pair.a))")
            case let .calledToWar(r): add(r.from, "\(name(r.from)) calls on \(name(r.to)) to fight \(name(r.against))")
            case let .joinedWar(civ, against, ally): add(civ, "\(name(civ)) goes to war on \(name(against)) for its ally \(name(ally))")
            case let .warRefused(by, ally, against): add(by, "\(name(by)) refuses to fight \(name(against)) for \(name(ally))")
            case let .warDeclared(by, on): add(by, "\(name(by)) declares war on \(name(on))")
            case let .navalBattle(sea, r):
                let winner = r.winner == .attacker ? r.attacker : r.defender
                add(winner, "Sea battle in the \(engine.map.sea(sea)?.name ?? sea): \(name(r.attacker)) (\(r.attackerShips) ships) "
                    + "\(r.winner == .attacker ? "beat" : "beaten off by") \(name(r.defender)) (\(r.defenderShips)); "
                    + "\(r.attackerShips - r.attackerShipsLeft + r.defenderShips - r.defenderShipsLeft) ships sunk", at: nil)
                if let grid = r.battle {
                    nextID += 1
                    let entry = BattleEntry(id: nextID, round: round, territory: sea, report: grid)
                    battles.insert(entry, at: 0)
                    if let human, r.attacker == human || r.defender == human { replay = entry }
                }
            case let .generalKilled(id):
                if let g = after.generals[id] { add(g.owner, "General \(g.name) of \(name(g.owner)) falls") }
            case let .discovery(civ, field, level):
                if civ == human || level >= 2 {
                    add(civ, "\(name(civ)) discover\(civ == human ? "" : "s") \(engine.levelName(field, level) ?? field.rawValue)"
                        + (civ == human ? ". \(KnowledgeView.benefit(field, level))" : ""))
                }
            case let .projectStarted(civ, t, kind) where civ == human:
                add(civ, "Work begins on \(projectName(kind).lowercased()) in \(place(t))")
            case let .projectCompleted(civ, t, kind) where civ == human:
                add(civ, "\(projectName(kind)) finished in \(place(t))", at: t)
            case let .projectDestroyed(t, kind) where before.owner(of: t) == human:
                add(human, "\(projectName(kind)) in \(place(t)) destroyed", at: t)
            case let .monumentStarted(civ, t, id):
                add(civ, "\(name(civ)) begin\(civ == human ? "" : "s") the \(monumentName(id)) in \(place(t))", at: t)
            case let .monumentCompleted(civ, t, id):
                add(civ, "The \(monumentName(id)) rises in \(place(t)): a wonder of the age for \(name(civ))", at: t)
            case let .monumentLost(civ, t, id) where civ == human:
                add(civ, "Work on the \(monumentName(id)) in \(place(t)) is abandoned: a rival finished first", at: t)
            case let .patronageSet(civ, field) where civ == human:
                add(civ, field.map { "The court now pays \(PatronagePicker.patrons($0).lowercased())" } ?? "The court ends its patronage")
            case let .decided(civ, kind, accepted) where civ == human:
                add(civ, Self.decisionLine(kind, accepted, after, engine))
            case let .taxRateSet(civ, rate) where civ == human:
                add(civ, "Taxes set to \(rate)%")
            case let .eliminated(civ): add(civ, "\(name(civ)) is destroyed")
            case let .victory(civ): add(civ, "\(name(civ)) dominates the known world")
            default: break
            }
        }
        noteMoments(events, before: before, after: after)
        log.insert(contentsOf: lines.reversed(), at: 0)
        if log.count > 300 { log.removeLast(log.count - 300) }
        if battles.count > 100 { battles.removeLast(battles.count - 100) }
    }
}
