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
    /// After a disaster, the priests ask for offerings to win back the gods.
    case offerings(gold: Int)
    /// A neighbouring kingdom's harvest failed: it asks for grain.
    case plea(kingdom: CivilizationID, grain: Int)
    /// Raiders gathering on the frontier: pay them to ride elsewhere, or meet them.
    case raiders(homeland: TerritoryID, target: TerritoryID, gold: Int)
}

public struct DecisionRules: Codable, Sendable, Equatable {
    public let famineLegitimacy: Int
    public let honoursChancePercent: Int
    public let honoursSnubLoyalty: Int
    public let mercenaryChancePercent: Int
    public let mercenaryWarriors: Int
    public let mercenaryGold: Int
    public let offeringsGold: Int
    public let offeringsLegitimacy: Int
    public let offeringsRefusedLegitimacy: Int
    public let pleaChancePercent: Int
    public let pleaGrain: Int
    public let pleaAttitude: Int
    public let pleaRefusedAttitude: Int
    public let raidersChancePercent: Int
    public let raidersGoldPerRider: Int
    /// After this many rounds without a dilemma, the chance ones are twice as likely: the
    /// middle of the age shouldn't pass without a choice.
    public let quietRounds: Int
}

extension Engine {
    /// Puts at most one dilemma to a person's court at the start of its turn.
    func offerDecision(_ civ: CivilizationID, after events: [GameEvent], _ state: inout GameState) -> [GameEvent] {
        guard state.civs[civ]?.isHuman == true, state.civs[civ]?.decision == nil,
              !inQuietOpening(civ, state) else { return [] }
        let d = rules.decisions
        let cs = state.civs[civ]!
        // Long without a choice: the chance dilemmas come twice as readily.
        let since = state.turn - (cs.lastDecision ?? 0)
        let boost = since >= d.quietRounds ? 2 : 1
        func roll(_ percent: Int) -> Bool { Int(state.rng.next() % 100) < percent * boost }
        // A famine on our land this turn.
        for case let .event(r) in events where r.kind == .famine && r.civ == civ {
            if let t = r.territory {
                let grain = max(1, territoryYield(.grain, t, state) / 2)
                // Only a realm with the grain to give faces the choice.
                if cs.granary >= grain { return put(civ, .famine(territory: t, grain: grain), &state) }
            }
        }
        // A disaster on our land: the priests want offerings.
        let disasters: Set<EventKind> = [.flood, .plague, .earthquake, .drought, .badOmen]
        if events.contains(where: { if case let .event(r) = $0 { disasters.contains(r.kind) && r.civ == civ } else { false } }),
           cs.gold >= d.offeringsGold {
            return put(civ, .offerings(gold: d.offeringsGold), &state)
        }
        // Raiders massing on the frontier.
        let fronts = barbarianFronts(civ, state)
        if !fronts.isEmpty, roll(d.raidersChancePercent) {
            let (homeland, target) = fronts[Int(state.rng.next() % UInt64(fronts.count))]
            return put(civ, .raiders(homeland: homeland, target: target, gold: raidersPrice(state)), &state)
        }
        // A proud, wavering general.
        let proud = livingGenerals(of: civ, state).filter { $0.renown >= 1 && $0.loyalty < 60 }.sorted { $0.id < $1.id }
        if let g = proud.first, roll(d.honoursChancePercent) {
            return put(civ, .honours(general: g.id, gold: rules.government.honorCost * (1 + g.renown)), &state)
        }
        // A hungry neighbour asks for grain.
        if cs.granary >= d.pleaGrain, let k = neighbourInNeed(of: civ, state), roll(d.pleaChancePercent) {
            return put(civ, .plea(kingdom: k, grain: d.pleaGrain), &state)
        }
        // Sea Peoples' swords for hire, once the age is unsettled.
        let coastal = state.territories(of: civ).contains { map.territory($0)!.isCoastal }
        if collapsePressure(state) > 0, coastal, roll(d.mercenaryChancePercent) {
            return put(civ, .mercenaries(warriors: d.mercenaryWarriors, gold: d.mercenaryGold), &state)
        }
        return []
    }

    /// The raiders' price: their numbers, in gold.
    public func raidersPrice(_ state: GameState) -> Int {
        rules.decisions.raidersGoldPerRider * raidSize(state)
    }

    /// How many ride in a raid from the frontier this round.
    public func raidSize(_ state: GameState) -> Int {
        let e = rules.events
        return e.barbarianBase + state.turn / max(1, e.barbarianTurnsPerExtra)
            + collapsePressure(state) / max(1, rules.collapse.migrationPressurePerExtra)
    }

    /// A kingdom next to our land, not at odds with us, whose people could use our grain.
    private func neighbourInNeed(of civ: CivilizationID, _ state: GameState) -> CivilizationID? {
        let ours = Set(state.territories(of: civ))
        let near = Set(ours.flatMap { map.landNeighbors(of: $0) }).subtracting(ours)
        let candidates = Set(near.compactMap { kingdom(at: $0, in: state) })
            .filter { attitude(of: $0, toward: civ, in: state) >= -20 && attitude(of: $0, toward: civ, in: state) < 60 }
            .sorted()
        guard !candidates.isEmpty else { return nil }
        return candidates[state.turn % candidates.count]
    }

    private func put(_ civ: CivilizationID, _ kind: DecisionKind, _ state: inout GameState) -> [GameEvent] {
        state.civs[civ]!.decision = kind
        state.civs[civ]!.lastDecision = state.turn
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
        case let .offerings(gold):
            if accept {
                guard state.civs[civ]!.gold >= gold else { throw GameError.insufficientGold(needed: gold, available: state.civs[civ]!.gold) }
                state.civs[civ]!.gold -= gold
                adjustLegitimacy(civ, d.offeringsLegitimacy, &state)
            } else {
                adjustLegitimacy(civ, -d.offeringsRefusedLegitimacy, &state)
            }
        case let .plea(k, grain):
            if accept {
                guard state.civs[civ]!.granary >= grain else { throw GameError.insufficientGrain(needed: grain) }
                state.civs[civ]!.granary -= grain
                changeAttitude(of: k, toward: civ, by: d.pleaAttitude, &state)
            } else {
                changeAttitude(of: k, toward: civ, by: -d.pleaRefusedAttitude, &state)
            }
        case let .raiders(homeland, target, gold):
            if accept {
                guard state.civs[civ]!.gold >= gold else { throw GameError.insufficientGold(needed: gold, available: state.civs[civ]!.gold) }
                state.civs[civ]!.gold -= gold
            } else if state.owner(of: target) == civ {
                state.civs[civ]!.decision = nil
                return [.decided(civ: civ, kind, accepted: false)] + barbarianRaid(from: homeland, into: target, &state)
            }
        }
        state.civs[civ]!.decision = nil
        return [.decided(civ: civ, kind, accepted: accept)]
    }
}
