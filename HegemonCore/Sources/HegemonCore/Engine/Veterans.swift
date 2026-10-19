/// Veterans (Josh: "armies should also get a veteran status and improve as they survive
/// battles"). Each army carries its soldiers' average number of battles survived. It rises by
/// one for everyone who comes through a battle and is diluted when green recruits join. Rank
/// follows from it (Green, Blooded, Veteran, Elite), and each rank fights harder and holds
/// longer.

public struct VeteranRules: Codable, Sendable, Equatable {
    /// Battles survived to reach Blooded, Veteran and Elite.
    public let rankAt: [Int]
    /// Per rank: extra strength (percent) for every unit type, and extra morale.
    public let strengthPercentPerRank: Int
    public let moralePerRank: Int
    /// Battle honours stop counting here.
    public let maxBattles: Int
}

public enum VeteranRank: Int, Codable, Sendable, Comparable, CaseIterable {
    case green, blooded, veteran, elite
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    public var name: String {
        switch self {
        case .green: "Green"
        case .blooded: "Blooded"
        case .veteran: "Veteran"
        case .elite: "Elite"
        }
    }
}

extension Engine {
    public func rank(battles: Int) -> VeteranRank {
        let n = rules.veterans.rankAt.filter { battles >= $0 }.count
        return VeteranRank(rawValue: min(n, VeteranRank.elite.rawValue)) ?? .green
    }

    public func rank(of army: Army) -> VeteranRank { rank(battles: army.battles ?? 0) }

    /// Battle honours after `joining` soldiers with `theirs` merge into `units` with `ours`:
    /// the average, rounded to nearest.
    func mergedBattles(_ ours: Int, _ units: Int, _ theirs: Int, _ joining: Int) -> Int {
        let total = units + joining
        guard total > 0 else { return 0 }
        return (2 * (ours * units + theirs * joining) + total) / (2 * total)
    }

    /// Adds units to a territory's army (creating it), merging their battle honours.
    func join(_ units: UnitCounts, battles: Int, to t: TerritoryID, owner: CivilizationID, _ state: inout GameState) {
        guard !units.isEmpty else { return }
        var army = state.armies[t] ?? Army(owner: owner, units: .zero)
        let b = mergedBattles(army.battles ?? 0, army.units.total, battles, units.total)
        army.units += units
        army.battles = b > 0 ? b : nil
        state.armies[t] = army
    }

    /// A rank's edge in battle.
    func applyVeterancy(_ army: inout BattleArmy, battles: Int) {
        let r = rank(battles: battles).rawValue
        guard r > 0 else { return }
        for type in UnitType.allCases {
            army.unitPercent[type, default: 0] += r * rules.veterans.strengthPercentPerRank
        }
        army.morale += r * rules.veterans.moralePerRank
    }

    func seasoned(_ battles: Int) -> Int { min(rules.veterans.maxBattles, battles + 1) }
}
