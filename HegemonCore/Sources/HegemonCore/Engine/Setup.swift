/// Difficulty and scenarios: how a game is set up before the first turn.

public enum Difficulty: String, Codable, Sendable, CaseIterable, CodingKeyRepresentable {
    case easy, medium, hard, god

    public var name: String {
        switch self {
        case .easy: "Easy"
        case .medium: "Medium"
        case .hard: "Hard"
        case .god: "God"
        }
    }
}

/// What a difficulty does: the rival courts' income, their starting armies and appetite for war,
/// and a head start for the player.
public struct DifficultyLevel: Codable, Sendable, Equatable {
    public let aiIncomePercent: Int
    public let aiStartUnits: Int
    public let aiAggressionPercent: Int
    public let playerStartGold: Int
    public let playerStartUnits: Int
    public let blurb: String
}

public typealias ScenarioID = String

/// A moment from the age, set up and played out over a few rounds. Whoever has the most
/// prestige when it ends wins; the places it was fought over are worth extra to whoever holds them.
public struct Scenario: Sendable, Identifiable {
    public let id: ScenarioID
    public let name: String
    public let year: String
    public let blurb: String
    /// Civs it suits best to play (the first is suggested).
    public let suggested: [CivilizationID]
    public let rounds: Int
    /// Places worth extra prestige to whoever holds them at the end.
    public let objectives: [TerritoryID: Int]
    let setup: @Sendable (Engine, inout GameState) -> Void

    public static let all: [Scenario] = [kadesh, troy, collapse]

    public static func named(_ id: ScenarioID) -> Scenario? { all.first { $0.id == id } }

    /// Egypt and the north meet at Kadesh, in Syria: two great hosts, one prize.
    static let kadesh = Scenario(
        id: "kadesh", name: "Kadesh", year: "1274 BC",
        blurb: "Pharaoh's chariots march north to meet the great king's host in Syria. Whoever holds Syria when the dust settles holds the Levant.",
        suggested: ["egypt", "mesopotamia"], rounds: 15, objectives: ["syria": 30]) { engine, s in
        own(&s, "egypt", ["petraea", "cyprus"])
        own(&s, "mesopotamia", ["syria", "taurus", "anatolia", "armenia"])
        s.armies["petraea"] = Army(owner: "egypt", units: UnitCounts(infantry: 6, archers: 3, cavalry: 5))
        s.armies["syria"] = Army(owner: "mesopotamia", units: UnitCounts(infantry: 7, archers: 3, cavalry: 3))
        s.land["syria"]!.improvements.insert(.walls)
        s.land["syria"]!.wallLevel = 2
        moveGeneral(&s, "egypt", to: "petraea")
        moveGeneral(&s, "mesopotamia", to: "syria")
        for c in ["egypt", "mesopotamia"] { s.civs[c]!.gold += 20 }
    }

    /// The Greeks sail for Troy: a walled city on the far shore of the Aegean.
    static let troy = Scenario(
        id: "troy", name: "The Siege of Troy", year: "c. 1190 BC",
        blurb: "A thousand ships cross the Aegean to a walled city on the Anatolian shore. Take Troy, or hold it.",
        suggested: ["greece", "mesopotamia"], rounds: 20, objectives: ["anatolia": 40]) { engine, s in
        own(&s, "greece", ["macedonia", "crete", "thrace"])
        own(&s, "mesopotamia", ["anatolia", "taurus", "syria"])
        s.land["anatolia"]!.improvements.formUnion([.walls, .granary])
        // The walls of Troy: the highest of the age.
        s.land["anatolia"]!.wallLevel = 3
        s.armies["anatolia"] = Army(owner: "mesopotamia", units: UnitCounts(infantry: 6, archers: 3))
        s.armies["thrace"] = Army(owner: "greece", units: UnitCounts(infantry: 6, archers: 2))
        s.fleets.removeAll { $0.owner == "greece" }
        s.fleets.append(Fleet(sea: "aegean", owner: "greece", ships: 5, cargo: UnitCounts(infantry: 8, archers: 2)))
        moveGeneral(&s, "greece", to: "thrace")
        moveGeneral(&s, "mesopotamia", to: "anatolia")
        s.civs["greece"]!.gold += 15
    }

    /// The great collapse at its height: Sea Peoples, droughts, burning cities. Endure.
    static let collapse = Scenario(
        id: "collapse", name: "The Collapse", year: "1177 BC",
        blurb: "The world is ending. Sea Peoples raid every coast, the rains fail and the old kingdoms burn. Fifteen rounds to keep your realm alive and great.",
        suggested: ["egypt", "greece", "italia", "mesopotamia"], rounds: 15, objectives: [:]) { engine, s in
        // Each realm grown over a generation: its capital's neighbours, peopled and garrisoned.
        for civ in s.players {
            guard let capital = engine.map.civilization(civ)?.capital else { continue }
            let near = engine.map.landNeighbors(of: capital).filter { s.owner(of: $0) == nil }.sorted().prefix(3)
            own(&s, civ, Array(near))
            for t in [capital] + near {
                s.land[t]!.population = max(s.population(of: t), engine.populationCap(of: t, in: s) * 2 / 3)
            }
            s.armies[capital] = Army(owner: civ, units: UnitCounts(infantry: 5, archers: 2, cavalry: 1))
            s.civs[civ]!.gold += 25
        }
        // The collapse is far along.
        s.turn = engine.rules.collapse.peakRound - 10
    }

    private static func own(_ s: inout GameState, _ civ: CivilizationID, _ lands: [TerritoryID]) {
        for t in lands {
            s.land[t]!.owner = civ
            if let a = s.armies[t], a.owner != civ { s.armies[t] = nil }
            s.land[t]!.population = max(s.population(of: t), 2)
        }
    }

    private static func moveGeneral(_ s: inout GameState, _ civ: CivilizationID, to t: TerritoryID) {
        if let g = s.generals.values.first(where: { $0.owner == civ && $0.isAlive }) { s.generals[g.id]!.location = t }
    }
}

extension Engine {
    /// Sets up a new game for a person playing `human` (nil: watching), at a difficulty, from a scenario.
    /// Rounds of a guided start in which the world leaves the player alone.
    public static let quietRounds = 5

    /// Whether `civ` is still in a guided start's quiet opening: nobody attacks its land, no
    /// raider or pirate falls on it, no storm or disaster strikes it.
    public func inQuietOpening(_ civ: CivilizationID?, _ state: GameState) -> Bool {
        guard let civ, let until = state.quietUntil, state.civs[civ]?.isHuman == true else { return false }
        return state.turn <= until
    }

    /// Whether an army of someone else's would leave `t` alone in a quiet opening: the land, or
    /// the army standing on it, belongs to a player still being guided.
    public func spared(_ t: TerritoryID, _ state: GameState) -> Bool {
        inQuietOpening(state.owner(of: t), state) || inQuietOpening(state.armies[t]?.owner, state)
    }

    public func prepare(_ state: inout GameState, human: CivilizationID?, difficulty: Difficulty, scenario: Scenario?,
                        guided: Bool = false) {
        if guided, human != nil { state.quietUntil = state.turn - 1 + Self.quietRounds }
        if let scenario {
            scenario.setup(self, &state)
            state.scenario = scenario.id
            state.roundLimit = state.turn - 1 + scenario.rounds
            state.objectives = scenario.objectives.isEmpty ? nil : scenario.objectives
            // A scenario is a war already under way: everyone starts it at war.
            state.peace = []
            state.peaceOffers = []
        }
        state.difficulty = difficulty
        let level = rules.difficulty[difficulty] ?? rules.difficulty[.medium]!
        for civ in state.players {
            guard let seat = seat(of: civ, in: state) else { continue }
            let extra = civ == human ? level.playerStartUnits : (human == nil ? 0 : level.aiStartUnits)
            if extra > 0 {
                if let a = state.armies[seat], a.owner == civ { state.armies[seat]!.units.infantry += extra }
                else if state.armies[seat] == nil { state.armies[seat] = Army(owner: civ, units: UnitCounts(infantry: extra)) }
            }
            if civ == human { state.civs[civ]!.gold += level.playerStartGold }
        }
    }

    /// The round the age (or scenario) ends.
    public func roundLimit(_ state: GameState) -> Int { state.roundLimit ?? rules.victory.roundLimit }

    /// The rival courts' income at this difficulty, in percent.
    func aiIncomePercent(_ civ: CivilizationID, _ state: GameState) -> Int {
        guard let d = state.difficulty, state.civs[civ]?.isHuman == false,
              state.players.contains(where: { state.civs[$0]?.isHuman == true }) else { return 100 }
        return rules.difficulty[d]?.aiIncomePercent ?? 100
    }

    /// Prestige from the places a scenario was fought over.
    func objectivePrestige(of civ: CivilizationID, in state: GameState) -> Int {
        (state.objectives ?? [:]).reduce(0) { $0 + (state.owner(of: $1.key) == civ ? $1.value : 0) }
    }
}

extension Personality {
    /// The same temperament, more or less eager for war.
    public func withAggression(percent: Int) -> Personality {
        Personality(name: name, aggression: aggression * Double(percent) / 100, caution: caution,
                    trade: trade, opportunism: opportunism)
    }
}
