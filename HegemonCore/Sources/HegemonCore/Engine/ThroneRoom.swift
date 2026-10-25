/// The ruler's hall: decorations bought with gold and stockpiled stone and timber, and trophies
/// won in war and diplomacy. Together they make the court's magnificence, which counts toward
/// prestige and steadies successions (a heir crowned in splendour needs less legitimacy).

public typealias DecorationID = String

public struct Decoration: Codable, Sendable, Equatable, Identifiable {
    public let id: DecorationID
    public let name: String
    public let gold: Int
    /// Stockpiled stone or timber it takes.
    public let stock: [Resource: Int]
    public let magnificence: Int
}

public struct ThroneRoomRules: Codable, Sendable, Equatable {
    public let decorations: [Decoration]
    public let trophyMagnificence: Int
    /// Prestige per point of magnificence.
    public let prestigePerMagnificence: Int
    /// Legitimacy a smooth succession needs is lowered by magnificence ÷ this, up to the cap.
    public let magnificencePerSuccessionPoint: Int
    public let successionEaseCap: Int
    /// Spoils of a conquered territory are worth this much, up to `spoilsCap` in all.
    public let spoilsMagnificence: Int
    public let spoilsCap: Int
    /// Raiders' shields hung in the hall count up to this many; beating off the same raiders yet
    /// again adds no new renown.
    public let raiderShieldCap: Int
    /// Legitimacy +1 a turn per this many magnificence, up to the cap: a splendid court awes.
    public let magnificencePerLegitimacy: Int
    public let legitimacyCap: Int
    /// Tribes' chance of taking gifts rises by magnificence ÷ this (percent points).
    public let magnificencePerGiftPercent: Int
    /// Rivals accept peace from a court at least this magnificent even when they'd rather not.
    public let peaceMagnificence: Int

    public func decoration(_ id: DecorationID) -> Decoration? { decorations.first { $0.id == id } }
}

public enum TrophyKind: Codable, Sendable, Hashable {
    /// The standard of a rival whose capital you took.
    case standard(CivilizationID)
    /// A shield taken from raiders (Sea Peoples or barbarians) beaten off your land, or from
    /// pirates beaten at sea.
    case raiderShield
    /// A tribe's totem, given when it swore to you.
    case totem(TerritoryID)
    /// Spoils carried home from a territory taken by force.
    case spoils(TerritoryID)
}

public struct Trophy: Codable, Sendable, Equatable {
    public let kind: TrophyKind
    public let round: Int
}

extension Engine {
    public func magnificence(of civ: CivilizationID, in state: GameState) -> Int {
        guard let cs = state.civs[civ] else { return 0 }
        let r = rules.throneRoom
        let spoils = cs.trophies.filter { if case .spoils = $0.kind { true } else { false } }.count
        let shields = cs.trophies.filter { $0.kind == .raiderShield }.count
        return cs.decorations.reduce(0) { $0 + (r.decoration($1)?.magnificence ?? 0) }
            + (cs.trophies.count - spoils - shields + min(shields, r.raiderShieldCap)) * r.trophyMagnificence
            + min(r.spoilsCap, spoils * r.spoilsMagnificence)
    }

    /// Legitimacy a turn from the court's splendour.
    public func courtLegitimacy(of civ: CivilizationID, in state: GameState) -> Int {
        let r = rules.throneRoom
        return min(r.legitimacyCap, magnificence(of: civ, in: state) / max(1, r.magnificencePerLegitimacy))
    }

    /// How much less legitimacy a smooth succession needs thanks to the court's splendour.
    public func successionEase(of civ: CivilizationID, in state: GameState) -> Int {
        let r = rules.throneRoom
        return min(r.successionEaseCap, magnificence(of: civ, in: state) / max(1, r.magnificencePerSuccessionPoint))
    }

    func decorate(_ id: DecorationID, _ state: inout GameState) throws -> [GameEvent] {
        let civ = state.activePlayer
        guard let d = rules.throneRoom.decoration(id) else { throw GameError.unknownDecoration(id) }
        guard !state.civs[civ]!.decorations.contains(id) else { throw GameError.alreadyDecorated(id) }
        let gold = state.civs[civ]!.gold
        guard gold >= d.gold else { throw GameError.insufficientGold(needed: d.gold, available: gold) }
        for (r, n) in d.stock {
            let have = state.civs[civ]!.stock[r] ?? 0
            guard have >= n else { throw GameError.insufficientStock(r, needed: n, available: have) }
        }
        state.civs[civ]!.gold -= d.gold
        for (r, n) in d.stock { state.civs[civ]!.stock[r, default: 0] -= n }
        state.civs[civ]!.decorations.insert(id)
        return [.decorated(civ: civ, decoration: id)]
    }

    /// Trophies earned by what just happened: a rival's capital taken, raiders beaten off, a
    /// tribe won over. Each kind of standard or totem is won once.
    func awardTrophies(_ events: [GameEvent], _ state: inout GameState) -> [GameEvent] {
        var awarded: [GameEvent] = []
        func give(_ civ: CivilizationID, _ kind: TrophyKind) {
            guard state.isPlayer(civ), let cs = state.civs[civ], !cs.eliminated else { return }
            if kind != .raiderShield, cs.trophies.contains(where: { $0.kind == kind }) { return }
            state.civs[civ]!.trophies.append(Trophy(kind: kind, round: state.turn))
            awarded.append(.trophyWon(civ: civ, trophy: kind))
        }
        for event in events {
            switch event {
            case let .captured(civ, t, from):
                if let from, map.civilization(from)?.capital == t { give(civ, .standard(from)) }
                else { give(civ, .spoils(t)) }
            case let .battle(report):
                let a = report.setup.attacker.civ, d = report.setup.defender.civ
                if a == barbariansID, report.winner == .defender { give(d, .raiderShield) }
            case let .navalBattle(_, report):
                if report.defender == piratesID, report.winner == .attacker { give(report.attacker, .raiderShield) }
            case let .tribeJoined(civ, t, _, _):
                give(civ, .totem(t))
            default:
                break
            }
        }
        return awarded
    }
}
