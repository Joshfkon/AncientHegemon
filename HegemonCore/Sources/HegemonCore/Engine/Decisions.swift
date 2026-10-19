/// Dilemmas put to a person's court (Josh: "decision events… choices give each game a story").
/// One at a time, offered at the start of the turn, answered before it ends (an unanswered one
/// counts as saying no). AI courts aren't asked: they follow their usual policies.

public enum DecisionKind: Codable, Sendable, Hashable {
    /// Famine struck: feed the hungry from the granary?
    case famine(territory: TerritoryID, grain: Int)
    /// A proud general wants honours (gold), or his loyalty sours.
    case honours(general: GeneralID, gold: Int)
    /// Sea Peoples offer their swords for gold.
    case mercenaries(warriors: Int, gold: Int)
}

public struct DecisionRules: Codable, Sendable, Equatable {
    public let famineLegitimacy: Int
    public let honoursChancePercent: Int
    public let honoursSnubLoyalty: Int
    public let mercenaryChancePercent: Int
    public let mercenaryWarriors: Int
    public let mercenaryGold: Int
}

extension Engine {
    /// Puts at most one dilemma to a person's court at the start of its turn.
    func offerDecision(_ civ: CivilizationID, after events: [GameEvent], _ state: inout GameState) -> [GameEvent] {
        guard state.civs[civ]?.isHuman == true, state.civs[civ]?.decision == nil else { return [] }
        let d = rules.decisions
        // A famine on our land this turn.
        for case let .event(r) in events where r.kind == .famine && r.civ == civ {
            if let t = r.territory {
                let grain = max(1, territoryYield(.grain, t, state) / 2)
                return put(civ, .famine(territory: t, grain: grain), &state)
            }
        }
        // A proud, wavering general.
        let proud = livingGenerals(of: civ, state).filter { $0.renown >= 1 && $0.loyalty < 60 }.sorted { $0.id < $1.id }
        if let g = proud.first, Int(state.rng.next() % 100) < d.honoursChancePercent {
            return put(civ, .honours(general: g.id, gold: rules.government.honorCost * (1 + g.renown)), &state)
        }
        // Sea Peoples' swords for hire, once the age is unsettled.
        let coastal = state.territories(of: civ).contains { map.territory($0)!.isCoastal }
        if collapsePressure(state) > 0, coastal, Int(state.rng.next() % 100) < d.mercenaryChancePercent {
            return put(civ, .mercenaries(warriors: d.mercenaryWarriors, gold: d.mercenaryGold), &state)
        }
        return []
    }

    private func put(_ civ: CivilizationID, _ kind: DecisionKind, _ state: inout GameState) -> [GameEvent] {
        state.civs[civ]!.decision = kind
        return [.decisionOffered(civ: civ, kind)]
    }

    func decide(_ accept: Bool, _ state: inout GameState) throws -> [GameEvent] {
        let civ = state.activePlayer
        guard let kind = state.civs[civ]!.decision else { throw GameError.noDecision }
        let d = rules.decisions
        switch kind {
        case let .famine(t, grain):
            if accept {
                guard state.civs[civ]!.granary >= grain else { throw GameError.insufficientGrain(needed: grain) }
                state.civs[civ]!.granary -= grain
                adjustLegitimacy(civ, d.famineLegitimacy, &state)
            } else {
                adjustLegitimacy(civ, -d.famineLegitimacy, &state)
                if state.owner(of: t) == civ, state.population(of: t) > rules.economy.minPopulation {
                    state.land[t]!.population -= 1
                }
            }
        case let .honours(id, gold):
            if accept {
                guard state.civs[civ]!.gold >= gold else { throw GameError.insufficientGold(needed: gold, available: state.civs[civ]!.gold) }
                state.civs[civ]!.gold -= gold
                if state.generals[id]?.isAlive == true {
                    state.generals[id]!.loyalty = min(100, state.generals[id]!.loyalty + rules.government.honorLoyalty)
                }
            } else if state.generals[id]?.isAlive == true {
                state.generals[id]!.loyalty = max(0, state.generals[id]!.loyalty - d.honoursSnubLoyalty)
            }
        case let .mercenaries(warriors, gold):
            if accept {
                guard state.civs[civ]!.gold >= gold else { throw GameError.insufficientGold(needed: gold, available: state.civs[civ]!.gold) }
                guard let seat = seat(of: civ, in: state) else { throw GameError.noDecision }
                state.civs[civ]!.gold -= gold
                join(UnitCounts(infantry: warriors), battles: 2, to: seat, owner: civ, &state)
            }
        }
        state.civs[civ]!.decision = nil
        return [.decided(civ: civ, kind, accepted: accept)]
    }
}
