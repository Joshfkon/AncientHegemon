import HegemonCore
import SwiftUI

/// Something that happened this round, marked on the map until the player's next turn ends:
/// marches, landings, battles, captures and events.
enum MapMark: Hashable {
    case march(civ: CivilizationID, from: TerritoryID, to: TerritoryID, units: Int)
    case landing(civ: CivilizationID, sea: SeaZoneID, to: TerritoryID, units: Int)
    case battle(at: TerritoryID, winner: CivilizationID, loser: CivilizationID)
    case captured(TerritoryID, by: CivilizationID)
    case event(TerritoryID, EventKind)

    /// Marks for one turn's events, in the order they happened.
    static func from(_ events: [GameEvent], before: GameState, after: GameState) -> [MapMark] {
        var marks: [MapMark] = []
        var target: TerritoryID?
        for event in events {
            switch event {
            case let .moved(civ, from, to, units):
                target = to
                marks.append(.march(civ: civ, from: from, to: to, units: units.total))
            case let .landed(civ, sea, t, units):
                target = t
                marks.append(.landing(civ: civ, sea: sea, to: t, units: units.total))
            case let .battle(report):
                guard let t = target else { continue }
                let won = report.winner == .attacker
                marks.append(.battle(at: t, winner: won ? report.setup.attacker.civ : report.setup.defender.civ,
                                     loser: won ? report.setup.defender.civ : report.setup.attacker.civ))
            case let .captured(civ, t, _):
                marks.append(.captured(t, by: civ))
            case let .event(r):
                if let t = r.territory, [.famine, .flood, .plague, .barbarians, .revolt, .seaPeoples, .drought, .earthquake].contains(r.kind) {
                    target = t
                    marks.append(.event(t, r.kind))
                }
            default:
                break
            }
        }
        return marks
    }

    static func glyph(_ kind: EventKind) -> String {
        switch kind {
        case .famine, .drought: "🥀"
        case .flood: "🌊"
        case .plague: "☠️"
        case .barbarians: "🪓"
        case .revolt: "✊"
        case .seaPeoples: "⛵"
        case .earthquake: "💥"
        default: "❗"
        }
    }
}

/// How dangerous each of a civ's territories is next turn: hostile troops that could reach it by
/// land or from the sea, against the garrison.
struct ThreatMap {
    let threat: [TerritoryID: Int]
    let garrison: [TerritoryID: Int]

    init(for civ: CivilizationID, in state: GameState, map: GameMap) {
        var threat: [TerritoryID: Int] = [:]
        var garrison: [TerritoryID: Int] = [:]
        func hostile(_ other: CivilizationID) -> Bool {
            other != civ && (!state.isPlayer(other) ? other == barbariansID : state.atWar(civ, other))
        }
        for t in state.territories(of: civ) {
            garrison[t] = state.armies[t].map { $0.owner == civ ? $0.units.total : 0 } ?? 0
            var n = 0
            for neighbor in map.landNeighbors(of: t) {
                if let a = state.armies[neighbor], hostile(a.owner) { n += a.units.total }
            }
            for sea in map.seas(bordering: t) {
                n += state.fleets.filter { $0.sea == sea && hostile($0.owner) }.reduce(0) { $0 + $1.cargo.total }
            }
            if n > 0 { threat[t] = n }
        }
        self.threat = threat
        self.garrison = garrison
    }
}
