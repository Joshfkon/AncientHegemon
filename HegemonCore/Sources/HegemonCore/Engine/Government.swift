/// Rulers, succession, legitimacy, generals' loyalty and civil war (DESIGN §7).
///
/// Runs at the start of each civilization's turn, after the harvest. The core tension: great
/// generals win wars, but renown and distance erode their loyalty, and disloyal generals with
/// armies are what tear empires apart, above all when a ruler dies.
extension Engine {
    func adjustLegitimacy(_ civ: CivilizationID?, _ delta: Int, _ state: inout GameState) {
        guard let civ, state.civs[civ] != nil else { return }
        state.civs[civ]!.legitimacy = max(0, min(100, state.civs[civ]!.legitimacy + delta))
    }

    private func percentRoll(_ chance: Int, _ state: inout GameState) -> Bool {
        Int(state.rng.next() % 100) < chance
    }

    private func names(for civ: CivilizationID, _ state: GameState) -> NameLists? {
        rules.names[civ] ?? state.civs[civ]?.rebelledFrom.flatMap { rules.names[$0] }
    }

    func livingGenerals(of civ: CivilizationID, _ state: GameState) -> [General] {
        state.generals.values.filter { $0.owner == civ && $0.isAlive }.sorted { $0.id < $1.id }
    }

    public func maxGenerals(of civ: CivilizationID, in state: GameState) -> Int {
        1 + state.territories(of: civ).count / rules.government.territoriesPerGeneral
    }

    // MARK: Turn

    func governmentPhase(_ civ: CivilizationID, _ state: inout GameState) -> [GameEvent] {
        let g = rules.government
        var events: [GameEvent] = []

        // Aging, heirs and natural death.
        state.civs[civ]!.ruler.age += 1
        state.civs[civ]!.heir?.age += 1
        if state.civs[civ]!.government == .monarchy, state.civs[civ]!.heir == nil,
           state.civs[civ]!.ruler.age >= 18, percentRoll(g.heirBirthChance, &state) {
            let name = GameState.pickName(names(for: civ, state)?.rulers, &state.rng)
            state.civs[civ]!.heir = Heir(name: name, age: 0)
            events.append(.heirBorn(civ: civ, name: name))
        }
        let age = state.civs[civ]!.ruler.age
        if percentRoll(g.baseDeathChance + max(0, age - g.deathAge) * g.deathChancePerYear, &state) {
            events += rulerDies(civ, cause: .oldAge, &state)
        }

        // Legitimacy drifts back toward 50; some rulers push it.
        let cs = state.civs[civ]!
        let drift = cs.legitimacy < 50 ? min(g.legitimacyDrift, 50 - cs.legitimacy)
            : -min(g.legitimacyDrift, cs.legitimacy - 50)
        adjustLegitimacy(civ, drift + (rules.rulerTraits[cs.ruler.trait]?.legitimacyPerTurn ?? 0), &state)

        // Generals are paid, and their loyalty moves toward what the throne commands.
        let distances = supplyDistances(of: civ, in: state)
        let traitShift = rules.rulerTraits[state.civs[civ]!.ruler.trait]?.loyaltyTarget ?? 0
        var unpaid = 0
        for general in livingGenerals(of: civ, state) {
            var loyalty = general.loyalty
            if state.civs[civ]!.gold >= g.generalPay {
                state.civs[civ]!.gold -= g.generalPay
            } else {
                loyalty += g.unpaidLoyalty
                unpaid += 1
            }
            let steps = general.location.flatMap { distances[$0] } ?? 10
            let target = state.civs[civ]!.legitimacy - general.renown * g.loyaltyPerRenown
                - steps * g.loyaltyPerStep + traitShift
            let gap = target - loyalty
            loyalty += gap == 0 ? 0 : (gap / g.loyaltyDriftDivisor == 0 ? gap.signum() : gap / g.loyaltyDriftDivisor)
            state.generals[general.id]!.loyalty = max(0, min(100, loyalty))
        }
        if unpaid > 0 { events.append(.generalsUnpaid(civ: civ, count: unpaid)) }

        // Disloyal generals far from the capital may rise up.
        for general in livingGenerals(of: civ, state) where general.loyalty < g.rebellionLoyalty {
            guard canRebel(general, civ, state),
                  percentRoll((g.rebellionLoyalty - general.loyalty) * g.rebellionChancePerPoint, &state) else { continue }
            events += civilWar(civ, general.id, &state)
        }
        return events
    }

    /// A general can rebel if he leads an army of his own civ, big enough, away from the seat.
    private func canRebel(_ general: General, _ civ: CivilizationID, _ state: GameState) -> Bool {
        guard general.owner == civ, let at = general.location, at != seat(of: civ, in: state),
              let army = state.armies[at], army.owner == civ else { return false }
        return army.units.total >= rules.government.minRebelArmy
    }

    // MARK: Succession

    func rulerDies(_ civ: CivilizationID, cause: DeathCause, _ state: inout GameState) -> [GameEvent] {
        let g = rules.government
        let l = g.legitimacy
        let old = state.civs[civ]!.ruler
        var events: [GameEvent] = [.rulerDied(civ: civ, name: old.name, age: old.age, cause: cause)]
        let trait = RulerTrait.allCases.randomElement(using: &state.rng)!

        switch state.civs[civ]!.government {
        case .monarchy:
            let claimants = livingGenerals(of: civ, state).filter {
                $0.renown >= 1 && $0.loyalty < g.claimantLoyalty && canRebel($0, civ, state)
            }
            let heir = state.civs[civ]!.heir
            if let heir, heir.age >= g.adultAge, state.civs[civ]!.legitimacy >= g.minSmoothLegitimacy,
               claimants.isEmpty {
                state.civs[civ]!.ruler = Ruler(name: heir.name, age: heir.age, trait: trait)
                state.civs[civ]!.heir = nil
                adjustLegitimacy(civ, l.succession, &state)
                events.append(.succession(civ: civ, ruler: heir.name, outcome: .smooth))
            } else {
                // A child, no heir, or rivals: a regent rules and the realm wavers.
                let name = heir?.name ?? GameState.pickName(names(for: civ, state)?.rulers, &state.rng)
                state.civs[civ]!.ruler = Ruler(name: name, age: heir?.age ?? GameState.roll(g.electedAge, &state.rng),
                                               trait: trait)
                state.civs[civ]!.heir = nil
                adjustLegitimacy(civ, l.regency, &state)
                if claimants.isEmpty {
                    events.append(.succession(civ: civ, ruler: name, outcome: .regency))
                } else if state.civs[civ]!.isHuman {
                    // A person decides: the realm waits on them.
                    let ranked = claimants.sorted { ($0.renown, $1.id) > ($1.renown, $0.id) }.map(\.id)
                    state.civs[civ]!.crisis = SuccessionCrisis(claimants: ranked,
                                                               bribeCost: g.bribePerClaimant * claimants.count,
                                                               ruler: name)
                    events.append(.successionCrisis(civ: civ, claimants: ranked))
                } else if state.civs[civ]!.gold >= g.bribePerClaimant * claimants.count {
                    state.civs[civ]!.gold -= g.bribePerClaimant * claimants.count
                    adjustLegitimacy(civ, l.bribe, &state)
                    for c in claimants { state.generals[c.id]!.loyalty = g.claimantLoyalty }
                    events.append(.succession(civ: civ, ruler: name, outcome: .bribed))
                } else {
                    events.append(.succession(civ: civ, ruler: name, outcome: .civilWar))
                    for c in claimants { events += civilWar(civ, c.id, &state) }
                }
            }

        case .republic:
            let usurper = livingGenerals(of: civ, state)
                .filter { $0.renown >= g.coupRenown && $0.loyalty < g.coupLoyalty }
                .max { ($0.renown, $1.id) < ($1.renown, $0.id) }
            if let usurper {
                // Caesar crosses the Rubicon: the republic becomes his monarchy.
                state.civs[civ]!.government = .monarchy
                state.civs[civ]!.ruler = Ruler(name: usurper.name, age: GameState.roll(g.electedAge, &state.rng),
                                               trait: trait)
                state.civs[civ]!.heir = nil
                state.civs[civ]!.legitimacy = 40
                state.generals[usurper.id]!.location = nil
                events.append(.succession(civ: civ, ruler: usurper.name, outcome: .coup))
            } else {
                let name = GameState.pickName(names(for: civ, state)?.rulers, &state.rng)
                state.civs[civ]!.ruler = Ruler(name: name, age: GameState.roll(g.electedAge, &state.rng), trait: trait)
                adjustLegitimacy(civ, l.succession, &state)
                events.append(.succession(civ: civ, ruler: name, outcome: .smooth))
            }
        }

        // Whatever the outcome, generals who were already disloyal seize the moment.
        for general in livingGenerals(of: civ, state)
        where general.loyalty < g.successionDisloyalty && canRebel(general, civ, state) {
            events += civilWar(civ, general.id, &state)
        }
        return events
    }

    // MARK: Civil war

    /// Land steps from `start` over a civilization's own territories.
    private func landSteps(from start: TerritoryID, within owned: Set<TerritoryID>) -> [TerritoryID: Int] {
        var dist = [start: 0]
        var queue = [start]
        var i = 0
        while i < queue.count {
            let t = queue[i]
            i += 1
            for n in map.landNeighbors(of: t) where owned.contains(n) && dist[n] == nil {
                dist[n] = dist[t]! + 1
                queue.append(n)
            }
        }
        return dist
    }

    /// The general breaks away with his army and every territory closer to him than to the seat.
    /// His faction becomes a new civilization, at war with the old one.
    func civilWar(_ civ: CivilizationID, _ generalID: GeneralID, _ state: inout GameState) -> [GameEvent] {
        guard let general = state.generals[generalID], general.owner == civ, let at = general.location,
              state.owner(of: at) == civ, let seat = seat(of: civ, in: state), at != seat else { return [] }
        state.rebellions += 1
        let rebel = "\(civ)-rebels-\(state.rebellions)"
        let owned = Set(state.territories(of: civ))
        let fromSeat = landSteps(from: seat, within: owned)
        let fromRebel = landSteps(from: at, within: owned)
        let region = owned.filter { t in
            t == at || (t != seat && (fromRebel[t] ?? .max) < (fromSeat[t] ?? .max))
        }.sorted()

        for t in region {
            state.land[t]!.owner = rebel
            if state.armies[t]?.owner == civ { state.armies[t]!.owner = rebel }
        }
        for g in livingGenerals(of: civ, state) where g.location.map(region.contains) ?? false {
            state.generals[g.id]!.owner = rebel
            state.generals[g.id]!.loyalty = 100
        }
        var cs = CivState(gold: 0, granary: 0)
        cs.government = .monarchy
        cs.ruler = Ruler(name: general.name, age: GameState.roll(rules.government.electedAge, &state.rng),
                         trait: RulerTrait.allCases.randomElement(using: &state.rng)!)
        cs.legitimacy = 40
        cs.rebelledFrom = civ
        cs.displayName = "\(general.name)'s rebels"
        state.civs[rebel] = cs
        state.players.append(rebel)
        return [.civilWar(civ: civ, rebel: rebel, general: generalID, territories: region)]
    }

    // MARK: Commands

    func resolveCrisis(_ choice: CrisisChoice, _ state: inout GameState) throws -> [GameEvent] {
        let civ = state.activePlayer
        guard let crisis = state.civs[civ]!.crisis else { throw GameError.noCrisis }
        let g = rules.government
        let claimants = crisis.claimants.filter { state.generals[$0]?.owner == civ && state.generals[$0]!.isAlive }
        var events: [GameEvent] = []
        switch choice {
        case .payOff:
            let gold = state.civs[civ]!.gold
            guard gold >= crisis.bribeCost else {
                throw GameError.insufficientGold(needed: crisis.bribeCost, available: gold)
            }
            state.civs[civ]!.gold -= crisis.bribeCost
            adjustLegitimacy(civ, g.legitimacy.bribe, &state)
            for id in claimants { state.generals[id]!.loyalty = g.claimantLoyalty }
            events.append(.succession(civ: civ, ruler: crisis.ruler, outcome: .bribed))
        case .crownClaimant:
            guard let winner = claimants.first.flatMap({ state.generals[$0] }) else {
                events.append(.succession(civ: civ, ruler: crisis.ruler, outcome: .regency))
                break
            }
            state.civs[civ]!.ruler = Ruler(name: winner.name, age: GameState.roll(g.electedAge, &state.rng),
                                           trait: RulerTrait.allCases.randomElement(using: &state.rng)!)
            state.civs[civ]!.heir = nil
            state.generals[winner.id]!.location = nil  // he leaves the army for the throne
            adjustLegitimacy(civ, g.legitimacy.bribe, &state)
            for id in claimants.dropFirst() { state.generals[id]!.loyalty = g.claimantLoyalty }
            events.append(.succession(civ: civ, ruler: winner.name, outcome: .claimantCrowned))
        case .standFirm:
            events.append(.succession(civ: civ, ruler: crisis.ruler, outcome: .civilWar))
            for id in claimants { events += civilWar(civ, id, &state) }
        }
        state.civs[civ]!.crisis = nil
        return events
    }

    func appointGeneral(_ territory: TerritoryID, _ state: inout GameState) throws -> [GameEvent] {
        let civ = state.activePlayer
        guard state.owner(of: territory) == civ else { throw GameError.notOwner(territory) }
        guard state.armies[territory]?.owner == civ else { throw GameError.insufficientUnits(territory) }
        guard homeNetwork(of: civ, in: state).contains(territory) else { throw GameError.outOfSupply(territory) }
        guard livingGenerals(of: civ, state).count < maxGenerals(of: civ, in: state) else {
            throw GameError.tooManyGenerals
        }
        let cost = rules.government.appointCost
        let gold = state.civs[civ]!.gold
        guard gold >= cost else { throw GameError.insufficientGold(needed: cost, available: gold) }

        state.civs[civ]!.gold -= cost
        let number = state.generals.keys.filter { $0.hasPrefix("\(civ)-") && !$0.dropFirst(civ.count + 1).contains("-") }.count + 1
        let id = "\(civ)-\(number)"
        state.generals[id] = General(id: id, name: GameState.pickName(names(for: civ, state)?.generals, &state.rng),
                                     owner: civ, trait: GeneralTrait.allCases.randomElement(using: &state.rng)!,
                                     renown: 0, location: territory, loyalty: rules.government.startLoyalty)
        return [.generalAppointed(civ: civ, general: id)]
    }

    func honorGeneral(_ id: GeneralID, _ state: inout GameState) throws -> [GameEvent] {
        let civ = state.activePlayer
        guard let general = state.generals[id], general.owner == civ, general.isAlive else {
            throw GameError.unknownGeneral(id)
        }
        let cost = rules.government.honorCost * (1 + general.renown)
        let gold = state.civs[civ]!.gold
        guard gold >= cost else { throw GameError.insufficientGold(needed: cost, available: gold) }
        state.civs[civ]!.gold -= cost
        state.generals[id]!.loyalty = min(100, general.loyalty + rules.government.honorLoyalty)
        return [.generalHonored(id)]
    }
}
