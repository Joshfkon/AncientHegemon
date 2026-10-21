/// One attack from several places at once: neighbouring armies and troops landing from fleets
/// in the town's seas, fighting as one host.

public struct AssaultGroup: Codable, Sendable, Equatable {
    public enum Source: Codable, Sendable, Equatable, Hashable {
        case land(TerritoryID)
        case sea(SeaZoneID)
    }
    public let source: Source
    public let units: UnitCounts

    public init(_ source: Source, _ units: UnitCounts) {
        self.source = source
        self.units = units
    }
}

extension Engine {
    func assault(_ target: TerritoryID, _ groups: [AssaultGroup], general generalFrom: TerritoryID?,
                 _ state: inout GameState) throws -> [GameEvent] {
        let civ = state.activePlayer
        guard let t = map.territory(target) else { throw GameError.unknownTerritory(target) }
        guard !groups.isEmpty, groups.allSatisfy({ $0.units.isNonNegative && !$0.units.isEmpty }),
              Set(groups.map(\.source)).count == groups.count else { throw GameError.invalidCount }
        if let owner = state.owner(of: target), state.atPeace(civ, owner) { throw GameError.atPeace(target) }
        try checkEntry(civ, into: target, state)
        if shielded(target, from: civ, in: state) { throw GameError.shielded(target) }
        try checkOmen(civ, attacking: target, state)
        for g in groups {
            switch g.source {
            case .land(let from):
                guard let army = state.armies[from], army.owner == civ,
                      g.units.fits(in: army.units - (state.moved[from] ?? .zero)) else { throw GameError.insufficientUnits(from) }
                guard map.areLandAdjacent(from, target) || vassalPassage(from, target, for: civ, in: state) != nil else {
                    throw GameError.notAdjacent(from, target)
                }
            case .sea(let sea):
                guard t.seas.contains(sea) else { throw GameError.notCoastal(target, sea) }
                guard let i = fleetIndex(civ, sea, state), g.units.fits(in: state.fleets[i].cargo) else { throw GameError.noFleet(sea) }
                // Enemy ships must be beaten first, in a landing of its own.
                if state.fleets.contains(where: { $0.sea == sea && $0.ships > 0 && state.atWar(civ, $0.owner) }) {
                    throw GameError.blockaded(sea)
                }
            }
        }
        var general: General?
        if let from = generalFrom {
            guard groups.contains(where: { $0.source == .land(from) }),
                  let g = state.general(of: civ, at: from), !state.generalsMoved.contains(g.id) else { throw GameError.noGeneral(from) }
            general = g
            state.generalsMoved.insert(g.id)
        }

        // The first land group (the army that called the others) sets the plan and the approach.
        let lead = groups.first { if case .land = $0.source { true } else { false } }
        var plan = BattlePlan()
        var approach: Approach = .amphibious
        if let lead, case .land(let from) = lead.source {
            plan = state.armies[from]!.plan
            let last = map.areLandAdjacent(from, target) ? from : vassalPassage(from, target, for: civ, in: state) ?? from
            approach = switch map.crossing(between: last, and: target) {
            case .river: .river
            case .strait: .strait
            case nil: .overland
            }
        }

        var events: [GameEvent] = []
        var origins: [(Origin, UnitCounts)] = []
        var total = UnitCounts.zero
        var honours = 0
        for g in groups {
            switch g.source {
            case .land(let from):
                let battles = state.armies[from]!.battles ?? 0
                honours = mergedBattles(honours, total.total, battles, g.units.total)
                state.armies[from]!.units -= g.units
                if state.armies[from]!.units.isEmpty { state.armies[from] = nil }
                origins.append((.territory(from), g.units))
                events.append(.moved(civ: civ, from: from, to: target, units: g.units))
            case .sea(let sea):
                let i = fleetIndex(civ, sea, state)!
                honours = mergedBattles(honours, total.total, state.fleets[i].cargoBattles ?? 0, g.units.total)
                state.fleets[i].cargo -= g.units
                if state.fleets[i].cargo.isEmpty { state.fleets[i].cargoBattles = nil }
                origins.append((.sea(sea), g.units))
                events.append(.landed(civ: civ, sea: sea, territory: target, units: g.units))
            }
            total += g.units
        }
        return events + advance(civ, total, general: general, plan: plan, battles: honours, into: target,
                                from: origins, approach: approach, &state)
    }
}
