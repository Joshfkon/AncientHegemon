/// Knowledge that grows out of experience (Late Bronze Age redesign).
///
/// Each turn a civilization earns knowledge from its population and wealth. It flows into the
/// fields it has recent experience in, in proportion: sailors learn seafaring, horse peoples learn
/// horsemanship. Neighbors and trade partners that are further ahead pass part of their lead along.
extension Engine {
    /// A civilization's level (0–3) in a field.
    public func level(_ field: KnowledgeField, of civ: CivilizationID?, in state: GameState) -> Int {
        guard let civ, let progress = state.civs[civ]?.knowledge[field] else { return 0 }
        return rules.knowledge.levels.filter { progress >= $0 }.count
    }

    /// Fields a civilization has any experience or knowledge of: the visible part of its tree.
    public func revealedFields(of civ: CivilizationID, in state: GameState) -> [KnowledgeField] {
        guard let cs = state.civs[civ] else { return [] }
        return KnowledgeField.allCases.filter { (cs.knowledge[$0] ?? 0) > 0 || (cs.experience[$0] ?? 0) > 0 }
    }

    /// The name of a field's level, e.g. "Ironworking" for metallurgy 2.
    public func levelName(_ field: KnowledgeField, _ level: Int) -> String? {
        guard level >= 1, let names = rules.knowledge.fields[field], level <= names.count else { return nil }
        return names[level - 1]
    }

    func addExperience(_ civ: CivilizationID, _ field: KnowledgeField, _ amount: Int, _ state: inout GameState) {
        guard amount > 0, state.civs[civ] != nil else { return }
        state.civs[civ]!.experience[field, default: 0] += amount
    }

    /// Civilizations in contact: a shared land border or a trade route.
    func contacts(of civ: CivilizationID, _ routes: [TradeRoute], _ state: GameState) -> [(CivilizationID, trade: Bool)] {
        let partners = Set(routes.filter { $0.involves(civ) }.map { $0.partner(of: civ) })
        var neighbors: Set<CivilizationID> = []
        for t in state.territories(of: civ) {
            for n in map.landNeighbors(of: t) {
                if let owner = state.owner(of: n), owner != civ, state.civs[owner] != nil { neighbors.insert(owner) }
            }
        }
        return partners.union(neighbors).sorted().map { ($0, partners.contains($0)) }
    }

    /// The yearly lesson: experience from what the civilization did this turn, then new knowledge
    /// split by experience, then diffusion from contacts, then fading experience.
    func learn(_ civ: CivilizationID, production: Int, bronze: Int, income: Int, routes: [TradeRoute],
               _ state: inout GameState) -> [GameEvent] {
        let k = rules.knowledge
        let home = homeNetwork(of: civ, in: state)
        let civRoutes = routes.filter { $0.involves(civ) }
        let seaRoutes = civRoutes.filter { $0.path.contains { if case .sea = $0 { true } else { false } } }.count
        let ships = state.fleets(of: civ).reduce(0) { $0 + $1.ships }

        // Everyday life teaches a little; what sets an empire apart teaches more.
        addExperience(civ, .agriculture, production / 8, &state)
        addExperience(civ, .metallurgy, bronze + 2 * yield(of: .iron, in: home, state), &state)
        addExperience(civ, .horsemanship, 2 * yield(of: .horses, in: home, state), &state)
        addExperience(civ, .seafaring, ships + 2 * seaRoutes, &state)
        addExperience(civ, .construction, yield(of: .stone, in: home, state), &state)
        addExperience(civ, .administration, civRoutes.count + state.territories(of: civ).count / 6 + income / 10, &state)

        let before = Dictionary(uniqueKeysWithValues: KnowledgeField.allCases.map { ($0, level($0, of: civ, in: state)) })

        // New knowledge, split by experience (largest shares first, leftovers to the most practiced).
        let population = state.totalPopulation(of: civ)
        var points = 10 * max(1, population / max(1, k.populationPerPoint) + income / max(1, k.goldPerPoint))
        if holds("library", civ, in: state) { points = points * 125 / 100 }
        let experience = state.civs[civ]!.experience
        let total = experience.values.reduce(0, +)
        if total > 0 {
            var given = 0
            let ranked = KnowledgeField.allCases.sorted { ((experience[$0] ?? 0), $1.rawValue) > ((experience[$1] ?? 0), $0.rawValue) }
            for field in ranked {
                let share = points * (experience[field] ?? 0) / total
                state.civs[civ]!.knowledge[field, default: 0] += share
                given += share
            }
            if let top = ranked.first, given < points { state.civs[civ]!.knowledge[top, default: 0] += points - given }
        }

        // Contact passes knowledge along: the best teacher in each field counts.
        for field in KnowledgeField.allCases {
            let mine = state.civs[civ]!.knowledge[field] ?? 0
            let gain = contacts(of: civ, routes, state).map { other, trade -> Int in
                let gap = (state.civs[other]?.knowledge[field] ?? 0) - mine
                guard gap > 0 else { return 0 }
                return max(1, gap * (trade ? k.tradeDiffusionPercent : k.contactDiffusionPercent) / 100)
            }.max() ?? 0
            if gain > 0 { state.civs[civ]!.knowledge[field, default: 0] += gain }
        }

        // Experience fades, so the direction follows recent practice.
        for field in KnowledgeField.allCases {
            let e = state.civs[civ]!.experience[field] ?? 0
            state.civs[civ]!.experience[field] = e - (e * k.experienceDecayPercent + 99) / 100
        }

        return KnowledgeField.allCases.compactMap { field in
            let now = level(field, of: civ, in: state)
            return now > before[field]! ? .discovery(civ: civ, field: field, level: now) : nil
        }
    }

    // MARK: Effects used across the engine

    func granaryTurns(_ civ: CivilizationID, _ state: GameState) -> Int {
        (level(.agriculture, of: civ, in: state) >= 2 ? rules.knowledge.effects.granaryTurns : rules.economy.granaryCapTurns)
            + (holds("ziggurat", civ, in: state) ? 1 : 0)
    }

    public func shipCapacity(_ civ: CivilizationID, _ state: GameState) -> Int {
        rules.ships.capacity + (level(.seafaring, of: civ, in: state) >= 1 ? rules.knowledge.effects.galleysCapacity : 0)
            + (holds("lighthouse", civ, in: state) ? 1 : 0)
    }

    func navalPercent(_ civ: CivilizationID, _ state: GameState) -> Int {
        let e = rules.knowledge.effects
        let lv = level(.seafaring, of: civ, in: state)
        return 100 + (lv >= 2 ? e.navigationPercent : 0) + (lv >= 3 ? e.triremesPercent : 0)
    }

    /// Recruits a turn a point of a resource allows (horse breeding doubles cavalry).
    func recruitsPerPoint(_ unit: UnitType, _ civ: CivilizationID, _ state: GameState) -> Int {
        unit == .cavalry && level(.horsemanship, of: civ, in: state) >= 2 ? rules.knowledge.effects.breedingMultiplier : 1
    }

    /// Project cost and time after Masonry and Engineering.
    public func projectCost(_ kind: ProjectKind, for civ: CivilizationID, _ state: GameState) -> ProjectCost {
        let base = rules.projects[kind]!
        let e = rules.knowledge.effects
        let lv = level(.construction, of: civ, in: state)
        let off = lv >= 3 ? e.engineeringDiscount : 0
        return ProjectCost(gold: base.gold, stone: max(0, base.stone - off), timber: max(0, base.timber - off),
                           turns: max(1, base.turns - (lv >= 1 ? e.masonryTurns : 0)))
    }

    /// A civilization's army as it fights: its knowledge sharpens units and steadies morale.
    public func battleArmy(_ civ: CivilizationID, _ units: UnitCounts, formation: FormationID?, general: General?,
                           _ state: GameState) -> BattleArmy {
        battleArmy(civ, units, plan: BattlePlan(formation: formation), general: general, state)
    }

    /// The army as it fights with a plan, after dropping anything it can't actually use.
    public func battleArmy(_ civ: CivilizationID, _ units: UnitCounts, plan: BattlePlan, general: General?,
                           battles: Int = 0, _ state: GameState) -> BattleArmy {
        let plan = effectivePlan(plan, civ, units, general: general, state)
        let e = rules.knowledge.effects
        var percent: [UnitType: Int] = [:]
        let horse = level(.horsemanship, of: civ, in: state)
        percent[.cavalry] = (horse >= 1 ? e.chariotsPercent : 0) + (horse >= 3 ? e.horseArchersPercent : 0)
        let war = level(.warfare, of: civ, in: state)
        percent[.infantry] = war >= 1 ? e.drillPercent : 0
        percent[.archers] = war >= 2 ? e.bowsPercent : 0
        var army = BattleArmy(civ: civ, units: units, formation: plan.formation ?? rules.battle.defaultFormation,
                          general: general, bronzePercent: bronzePercent(civ, state),
                          unitPercent: percent, morale: war >= 3 ? e.tacticsMorale : 0,
                          depth: plan.depth, stratagem: plan.stratagem)
        army.pursue = plan.pursue
        applyVeterancy(&army, battles: battles)
        if holds("lionGate", civ, in: state) { army.morale += 5 }
        return army
    }

    /// Experience from a land battle: fighting teaches warfare, cavalry teaches horsemanship.
    func battleExperience(_ army: BattleArmy, _ state: inout GameState) {
        addExperience(army.civ, .warfare, 3 + (army.units.infantry + army.units.archers) / 3, &state)
        addExperience(army.civ, .horsemanship, 2 * army.units.cavalry, &state)
    }
}
