/// Battle plans: which formations and stratagems an army can use. The basics are open to
/// everyone; the rest are unlocked by knowledge (for every army the civilization has) or by the
/// trait of the general leading the army.
extension Engine {
    public func requirement(for formation: FormationID) -> PlanRequirement? {
        rules.battle.plans.formationRequires[formation]
    }

    public func requirement(for stratagem: Stratagem) -> PlanRequirement? {
        rules.battle.plans.stratagemRequires[stratagem]
    }

    /// Whether a civilization meets a requirement, with `general` leading.
    public func meets(_ requirement: PlanRequirement?, _ civ: CivilizationID, general: General?,
                      in state: GameState) -> Bool {
        guard let r = requirement, r.field != nil || r.trait != nil else { return true }
        if let field = r.field, level(field, of: civ, in: state) >= (r.level ?? 1) { return true }
        if let trait = r.trait, general?.trait == trait { return true }
        return false
    }

    public func formationAvailable(_ formation: FormationID, _ civ: CivilizationID, general: General?,
                                   in state: GameState) -> Bool {
        rules.battle.formation(formation) != nil && meets(requirement(for: formation), civ, general: general, in: state)
    }

    public func stratagemAvailable(_ stratagem: Stratagem, _ civ: CivilizationID, general: General?,
                                   in state: GameState) -> Bool {
        meets(requirement(for: stratagem), civ, general: general, in: state)
    }

    /// The plan as it can actually be fought: anything no longer unlocked (the general who knew
    /// the trick stayed behind, or died) falls back to the basics, and a feigned retreat needs
    /// cavalry to feign with.
    func effectivePlan(_ plan: BattlePlan, _ civ: CivilizationID, _ units: UnitCounts, general: General?,
                       _ state: GameState) -> BattlePlan {
        var plan = plan
        if let f = plan.formation, !formationAvailable(f, civ, general: general, in: state) { plan.formation = nil }
        if let s = plan.stratagem {
            if !stratagemAvailable(s, civ, general: general, in: state) || (s == .feignedRetreat && units.cavalry == 0) {
                plan.stratagem = nil
            }
        }
        return plan
    }

    func setBattlePlan(_ territory: TerritoryID, _ plan: BattlePlan, _ state: inout GameState) throws -> [GameEvent] {
        let civ = state.activePlayer
        guard let army = state.armies[territory], army.owner == civ else { throw GameError.insufficientUnits(territory) }
        let general = state.general(of: civ, at: territory)
        if let f = plan.formation {
            guard rules.battle.formation(f) != nil else { throw GameError.unknownFormation(f) }
            guard formationAvailable(f, civ, general: general, in: state) else { throw GameError.planLocked }
        }
        if let s = plan.stratagem, !stratagemAvailable(s, civ, general: general, in: state) { throw GameError.planLocked }
        state.armies[territory]!.formation = plan.formation
        state.armies[territory]!.depth = plan.depth
        state.armies[territory]!.stratagem = plan.stratagem
        state.armies[territory]!.holdBack = plan.pursue ? nil : true
        return [.battlePlanSet(civ: civ, territory: territory, plan: plan)]
    }
}
