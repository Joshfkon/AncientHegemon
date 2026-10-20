/// Ages of splendour, the coming of iron, and the sack of capitals.

/// A realm at the height of its power (a secure throne, among the most prestigious) enters a
/// few rounds of splendour: it builds twice as fast, grows faster and gathers more gold. Then
/// it must wait before another.
public struct SplendourRules: Codable, Sendable, Equatable {
    public let legitimacy: Int
    /// Among this many most prestigious empires.
    public let topRanks: Int
    public let minRound: Int
    public let rounds: Int
    public let rest: Int
    public let goldPercent: Int
    public let growthPercent: Int
}

/// When the collapse is far enough along, iron (which needs no tin) is within everyone's reach.
public struct IronAgeRules: Codable, Sendable, Equatable {
    public let pressure: Int
}

/// Taking a rival's capital seizes part of its treasury and is remembered.
public struct SackRules: Codable, Sendable, Equatable {
    public let goldPercent: Int
    public let prestige: Int
}

extension Engine {
    /// Whether a civ can use iron: it knows ironworking, or the Iron Age has come.
    public func ironWorked(_ civ: CivilizationID, _ state: GameState) -> Bool {
        state.ironAge || level(.metallurgy, of: civ, in: state) >= 2
    }

    /// Begins, counts down and ends a civ's age of splendour, at the start of its turn.
    func updateSplendour(_ civ: CivilizationID, _ state: inout GameState) -> [GameEvent] {
        let r = rules.splendour
        let cs = state.civs[civ]!
        if cs.splendour > 0 {
            state.civs[civ]!.splendour -= 1
            guard state.civs[civ]!.splendour == 0 else { return [] }
            state.civs[civ]!.splendourRest = r.rest
            return [.splendourEnded(civ: civ)]
        }
        if cs.splendourRest > 0 {
            state.civs[civ]!.splendourRest -= 1
            return []
        }
        let leaders = standings(in: state).filter { state.isPlayer($0) && !(state.civs[$0]?.eliminated ?? true) }.prefix(r.topRanks)
        guard state.turn >= r.minRound, cs.legitimacy >= r.legitimacy, leaders.contains(civ) else { return [] }
        state.civs[civ]!.splendour = r.rounds
        return [.splendourBegan(civ: civ)]
    }

    /// The Iron Age dawns once, when the collapse reaches its height.
    func dawnOfIron(_ state: inout GameState) -> [GameEvent] {
        guard !state.ironAge, collapsePressure(state) >= rules.ironAge.pressure else { return [] }
        state.ironAge = true
        return [.ironAgeBegan]
    }

    /// The fall of a capital: the victor carries off part of the treasury.
    func sack(_ capital: TerritoryID, of victim: CivilizationID, by civ: CivilizationID,
              _ state: inout GameState) -> [GameEvent] {
        guard state.isPlayer(victim), state.isPlayer(civ), let vs = state.civs[victim] else { return [] }
        let gold = vs.gold * rules.sack.goldPercent / 100
        state.civs[victim]!.gold -= gold
        state.civs[civ]!.gold += gold
        state.civs[civ]!.sacked += 1
        return [.capitalSacked(by: civ, from: victim, territory: capital, gold: gold)]
    }
}
