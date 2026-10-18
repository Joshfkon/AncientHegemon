/// One civilization's story over an AI-vs-AI game.
public struct CivRecord: Sendable, Equatable {
    public var personality: String
    public var peakTerritories = 1
    public var finalTerritories = 0
    public var eliminatedOnTurn: Int?
    public var turnsStarving = 0
    public var populationStarved = 0
    public var unitsDeserted = 0
    public var unitsLostToAttrition = 0
    public var attacksWon = 0
    public var attacksLost = 0
    public var defencesWon = 0
    public var defencesLost = 0
    /// Of those, defences against another civilization (not natives, barbarians or rebels in revolt).
    public var defencesVsCivsWon = 0
    public var defencesVsCivsLost = 0
    public var rejectedCommands = 0
    public var shipsBuilt = 0
    public var landings = 0
    public var navalBattlesWon = 0
    public var navalBattlesLost = 0
    public var rulersDied = 0
    public var civilWars = 0
    public var regencies = 0
    public var coups = 0
    public var events: [EventKind: Int] = [:]
    public var projectsBuilt = 0
    public var projectsDestroyed = 0
    /// Knowledge levels at the start of round 20, if the civ was alive then.
    public var knowledgeAt20: [KnowledgeField: Int]?
    /// Gold in hand and units under arms at the start of rounds 10, 20 and 30, if it held land then.
    public var goldAt: [Int: Int] = [:]
    public var unitsAt: [Int: Int] = [:]

    /// Lost at least half of a realm that once held 4+ territories.
    public var collapsed: Bool { peakTerritories >= 4 && finalTerritories * 2 <= peakTerritories }
}

/// Wins by formation, as attacker and as defender.
public struct FormationRecord: Sendable, Equatable {
    public var attacks = 0
    public var attackWins = 0
    public var defences = 0
    public var defenceWins = 0

    public init() {}
}

/// Civ-against-civ land battles, by how heavily the attacker outnumbered the defender.
public struct OddsTally: Sendable, Equatable {
    /// Upper bounds (attacker units ÷ defender units) of each bucket; the last is open-ended.
    public static let bounds: [Double] = [1.25, 1.5, 2, 3]
    public var battles = [Int](repeating: 0, count: bounds.count + 1)
    public var attackerWins = [Int](repeating: 0, count: bounds.count + 1)

    public init() {}

    mutating func add(attackers: Int, defenders: Int, attackerWon: Bool) {
        let ratio = Double(attackers) / Double(max(1, defenders))
        let i = Self.bounds.firstIndex { ratio < $0 } ?? Self.bounds.count
        battles[i] += 1
        if attackerWon { attackerWins[i] += 1 }
    }
}

public struct MatchRecord: Sendable {
    public let seed: UInt64
    public let winner: CivilizationID?
    /// Turns played (the turn the game ended on, or the turn limit).
    public let turns: Int
    public let civs: [CivilizationID: CivRecord]
    public let formations: [FormationID: FormationRecord]
    public let civBattles: OddsTally
    /// The civ holding the most territories at the start of each round (nil on a tie), from round 1.
    public let leaders: [CivilizationID?]
    public let finalState: GameState

    public func leader(atRound round: Int) -> CivilizationID? {
        round >= 1 && round <= leaders.count ? leaders[round - 1] : nil
    }

    /// How often the outright leader changed hands (ties don't count as a change).
    public var leadChanges: Int {
        var changes = 0
        var current: CivilizationID?
        for leader in leaders.compactMap({ $0 }) {
            if let c = current, c != leader { changes += 1 }
            current = leader
        }
        return changes
    }
}

/// A seeded shuffle of the turn order, so balance runs aren't skewed by who moves first.
public func shuffledTurnOrder(_ civs: [CivilizationID], seed: UInt64) -> [CivilizationID] {
    var rng = SeededRNG(seed: seed ^ 0x5EA7_0D3E)
    var order = civs
    order.shuffle(using: &rng)
    return order
}

/// Plays a full AI-vs-AI game. Deterministic for a given seed and personalities.
/// `onRound` is called at the start of every round (all civs have moved), for tracing.
public func playAIMatch(engine: Engine, seed: UInt64, personalities: [CivilizationID: Personality],
                        civilizations: [CivilizationID]? = nil, maxTurns: Int,
                        onRound: ((GameState) -> Void)? = nil) throws -> MatchRecord {
    var state = try engine.newGame(seed: seed, civilizations: civilizations)
    var civs: [CivilizationID: CivRecord] = [:]
    var ais: [CivilizationID: AIPlayer] = [:]
    for civ in state.players {
        let p = personalities[civ] ?? .default(for: civ)
        civs[civ] = CivRecord(personality: p.name)
        ais[civ] = AIPlayer(engine: engine, personality: p)
    }
    var formations: [FormationID: FormationRecord] = [:]
    var civBattles = OddsTally()
    var leaders: [CivilizationID?] = []

    while state.winner == nil, state.turn <= maxTurns {
        let civ = state.activePlayer
        if ais[civ] == nil {
            // A faction born in civil war: an opportunist, as rebels are.
            ais[civ] = AIPlayer(engine: engine, personality: personalities[civ] ?? .opportunist)
            civs[civ] = CivRecord(personality: "rebel")
        }
        if state.activePlayerIndex == 0 {
            onRound?(state)
            if state.turn == 20 {
                for c in state.players where civs[c] != nil && !state.civs[c]!.eliminated {
                    civs[c]!.knowledgeAt20 = Dictionary(uniqueKeysWithValues: KnowledgeField.allCases.map {
                        ($0, engine.level($0, of: c, in: state))
                    })
                }
            }
            if [10, 20, 30].contains(state.turn) {
                for c in state.players where civs[c] != nil && !state.territories(of: c).isEmpty {
                    civs[c]!.goldAt[state.turn] = state.civs[c]!.gold
                    civs[c]!.unitsAt[state.turn] = state.totalUnits(of: c).total
                }
            }
            let alive = state.players.filter { !state.civs[$0]!.eliminated }
            let sizes = alive.map { ($0, state.territories(of: $0).count) }
            let top = sizes.map(\.1).max() ?? 0
            let atTop = sizes.filter { $0.1 == top }
            leaders.append(atTop.count == 1 ? atTop[0].0 : nil)
        }
        let turn = ais[civ]!.playTurn(&state)
        civs[civ]?.rejectedCommands += turn.rejected.count
        for event in turn.events {
            switch event {
            case let .starvation(c, pop, units):
                civs[c]?.turnsStarving += 1
                civs[c]?.populationStarved += pop
                civs[c]?.unitsDeserted += units
            case let .rulerDied(c, _, _, _):
                civs[c]?.rulersDied += 1
            case let .civilWar(c, _, _, _):
                civs[c]?.civilWars += 1
            case let .succession(c, _, outcome):
                if outcome == .regency { civs[c]?.regencies += 1 }
                if outcome == .coup { civs[c]?.coups += 1 }
            case let .event(report):
                civs[report.civ]?.events[report.kind, default: 0] += 1
            case let .projectCompleted(c, _, _):
                civs[c]?.projectsBuilt += 1
            case let .projectDestroyed(t, _):
                if let c = state.owner(of: t) ?? turn.events.lazy.compactMap({ e -> CivilizationID? in
                    if case let .event(r) = e, r.territory == t { r.civ } else { nil } }).first {
                    civs[c]?.projectsDestroyed += 1
                }
            case let .shipsBuilt(c, _, count):
                civs[c]?.shipsBuilt += count
            case let .landed(c, _, _, _):
                civs[c]?.landings += 1
            case let .navalBattle(_, report):
                let won = report.winner == .attacker
                civs[report.attacker]?.navalBattlesWon += won ? 1 : 0
                civs[report.attacker]?.navalBattlesLost += won ? 0 : 1
                civs[report.defender]?.navalBattlesWon += won ? 0 : 1
                civs[report.defender]?.navalBattlesLost += won ? 1 : 0
            case let .outOfSupply(c, _, lost):
                civs[c]?.unitsLostToAttrition += lost
            case let .eliminated(c):
                civs[c]?.eliminatedOnTurn = state.turn
            case let .battle(report):
                let a = report.setup.attacker, d = report.setup.defender
                let attackerWon = report.winner == .attacker
                let byCiv = a.civ != nativesID && a.civ != barbariansID
                if attackerWon {
                    civs[a.civ]?.attacksWon += 1
                    civs[d.civ]?.defencesLost += 1
                    if byCiv { civs[d.civ]?.defencesVsCivsLost += 1 }
                } else {
                    civs[a.civ]?.attacksLost += 1
                    civs[d.civ]?.defencesWon += 1
                    if byCiv { civs[d.civ]?.defencesVsCivsWon += 1 }
                }
                if byCiv, d.civ != nativesID, d.civ != barbariansID {
                    civBattles.add(attackers: a.units.total, defenders: d.units.total, attackerWon: attackerWon)
                }
                formations[a.formation, default: FormationRecord()].attacks += 1
                formations[a.formation, default: FormationRecord()].attackWins += attackerWon ? 1 : 0
                formations[d.formation, default: FormationRecord()].defences += 1
                formations[d.formation, default: FormationRecord()].defenceWins += attackerWon ? 0 : 1
            default:
                break
            }
        }
        for c in state.players where civs[c] != nil {
            civs[c]!.peakTerritories = max(civs[c]!.peakTerritories, state.territories(of: c).count)
        }
    }
    for c in state.players where civs[c] != nil { civs[c]!.finalTerritories = state.territories(of: c).count }
    return MatchRecord(seed: seed, winner: state.winner, turns: min(state.turn, maxTurns), civs: civs,
                       formations: formations, civBattles: civBattles, leaders: leaders, finalState: state)
}
