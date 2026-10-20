/// Diplomacy with the native tribes holding unclaimed land: win them over with gifts (gold, and
/// a chance they refuse) or demand their submission (free, but only an overwhelming army next
/// door makes them bow; a refused demand costs face and stiffens them).
public enum Parley: String, Codable, Sendable, CaseIterable {
    /// Win them over with gold; demand they submit; or offer them your protection as vassals.
    case gifts, demand, vassalage
}

public struct TribeRules: Codable, Sendable, Equatable {
    /// Gifts cost this much gold, plus `giftGoldPerWarrior` for each warrior.
    public let giftGoldBase: Int
    public let giftGoldPerWarrior: Int
    /// Chance (percent) that gifts work: this base…
    public let giftChanceBase: Int
    /// …plus this much for each of your troops next door beyond their warriors…
    public let giftChancePerTroop: Int
    /// …clamped to this range.
    public let giftChanceMin: Int
    public let giftChanceMax: Int
    /// A demand works when your troops next door outnumber their warriors this many times.
    public let demandRatio: Int
    /// Legitimacy lost when a demand is refused; the tribe also gains a warrior.
    public let demandRefusedLegitimacy: Int
    /// Share of the tribe's warriors who join your army when they come over.
    public let warriorsJoinPercent: Int
}

extension Engine {
    /// The tribe holding a territory, if it is native land the civ could talk to: unclaimed, held
    /// by natives, next to the civ's land, and nobody's vassal.
    public func tribe(at territory: TerritoryID, for civ: CivilizationID, in state: GameState) -> Army? {
        guard state.owner(of: territory) == nil, let army = state.armies[territory], army.owner == nativesID,
              overlord(of: territory, in: state) == nil,
              map.landNeighbors(of: territory).contains(where: { state.owner(of: $0) == civ }) else { return nil }
        return army
    }

    /// The civ's troops in land bordering the territory.
    public func troopsNextTo(_ territory: TerritoryID, for civ: CivilizationID, in state: GameState) -> Int {
        map.landNeighbors(of: territory).reduce(0) { total, n in
            guard let a = state.armies[n], a.owner == civ else { return total }
            return total + a.units.total
        }
    }

    public func giftCost(at territory: TerritoryID, in state: GameState) -> Int {
        let r = rules.tribes
        return r.giftGoldBase + r.giftGoldPerWarrior * (state.armies[territory]?.units.total ?? 0)
    }

    /// Percent chance that gifts win the tribe over.
    public func giftChance(at territory: TerritoryID, for civ: CivilizationID, in state: GameState) -> Int {
        let r = rules.tribes
        let warriors = state.armies[territory]?.units.total ?? 0
        let legitimacy = (state.civs[civ]?.legitimacy ?? 50) - 50
        let writing = level(.administration, of: civ, in: state) >= 1 ? 10 : 0
        let p = r.giftChanceBase + r.giftChancePerTroop * (troopsNextTo(territory, for: civ, in: state) - warriors)
            + legitimacy / 2 + writing
            + magnificence(of: civ, in: state) / max(1, rules.throneRoom.magnificencePerGiftPercent)
            + (people(at: territory, in: state) != nil ? attitude(of: territory, toward: civ, in: state) / 2 : 0)
        return min(r.giftChanceMax, max(r.giftChanceMin, p))
    }

    public func demandWorks(at territory: TerritoryID, for civ: CivilizationID, in state: GameState) -> Bool {
        let warriors = state.armies[territory]?.units.total ?? 0
        return troopsNextTo(territory, for: civ, in: state) >= rules.tribes.demandRatio * max(1, warriors)
    }

    func parley(_ territory: TerritoryID, _ kind: Parley, _ state: inout GameState) throws -> [GameEvent] {
        let civ = state.activePlayer
        guard let tribe = tribe(at: territory, for: civ, in: state) else { throw GameError.noTribe(territory) }
        guard !state.parleyed.contains(territory) else { throw GameError.alreadyParleyed(territory) }
        let r = rules.tribes
        state.parleyed.insert(territory)
        let joins: Bool
        switch kind {
        case .gifts:
            let cost = giftCost(at: territory, in: state)
            let gold = state.civs[civ]!.gold
            guard gold >= cost else { throw GameError.insufficientGold(needed: cost, available: gold) }
            state.civs[civ]!.gold -= cost
            joins = Int(state.rng.next() % 100) < giftChance(at: territory, for: civ, in: state)
            // Refused gifts are still remembered kindly.
            if !joins { changeAttitude(of: territory, toward: civ, by: rules.minors.giftAttitude, &state) }
        case .demand:
            joins = demandWorks(at: territory, for: civ, in: state)
            if !joins {
                adjustLegitimacy(civ, -r.demandRefusedLegitimacy, &state)
                state.armies[territory]!.units.infantry += 1
                changeAttitude(of: territory, toward: civ, by: rules.minors.demandRefusedAttitude, &state)
            }
        case .vassalage:
            // Only a kingdom can swear fealty; a tribe without a name just joins or doesn't.
            guard people(at: territory, in: state) != nil else { throw GameError.noTribe(territory) }
            guard wouldSwear(territory, to: civ, in: state) else {
                changeAttitude(of: territory, toward: civ, by: rules.minors.vassalRefusedAttitude, &state)
                return [.tribeRefused(civ: civ, territory: territory, parley: kind)]
            }
            return swear(territory, to: civ, &state)
        }
        guard joins else { return [.tribeRefused(civ: civ, territory: territory, parley: kind)] }
        state.minors[territory] = nil
        // The land is theirs to give; some of the warriors take service.
        let warriors = tribe.units.total * r.warriorsJoinPercent / 100
        state.armies[territory] = warriors > 0 ? Army(owner: civ, units: UnitCounts(infantry: warriors)) : nil
        state.land[territory]!.owner = civ
        taken(territory, &state)
        var events: [GameEvent] = [.tribeJoined(civ: civ, territory: territory, parley: kind, warriors: warriors)]
        if state.winner == nil,
           state.territories(of: civ).count * 100 >= map.territories.count * rules.victory.territoryPercent {
            events += declareVictory(civ, .domination, &state)
        }
        return events
    }
}
