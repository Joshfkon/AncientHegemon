/// Taxes and projects: how a civilization invests rather than spends.
extension Engine {
    // MARK: Yields

    /// What a territory yields of a resource, counting its farm or mine.
    public func territoryYield(_ resource: Resource, _ territory: TerritoryID, _ state: GameState) -> Int {
        guard let t = map.territory(territory) else { return 0 }
        let built = state.land[territory]?.improvements ?? []
        let fx = rules.projectEffects
        if resource == .grain {
            let owner = state.owner(of: territory)
            let farming = level(.agriculture, of: owner, in: state)
            let kx = rules.knowledge.effects
            var grain = t.grain
            if t.has(.riverValley), farming >= 1 { grain += kx.irrigationRiverGrain }
            if built.contains(.farm) {
                grain += t.has(.riverValley) ? fx.farmRiverValleyGrain : fx.farmGrain
                if farming >= 3 { grain += kx.cropRotationFarmGrain }
            }
            return grain
        }
        let base = t.resources[resource] ?? 0
        let mineable: Set<Resource> = [.copper, .tin, .iron, .gold, .stone]
        if base > 0, built.contains(.mine), mineable.contains(resource) { return base + fx.mineBonus }
        return base
    }

    /// Whether a project can be built in a territory at all (ignoring costs).
    public func canBuild(_ project: ProjectKind, in territory: TerritoryID, _ state: GameState) -> Bool {
        guard let t = map.territory(territory), let land = state.land[territory],
              !land.improvements.contains(project), land.construction == nil else { return false }
        switch project {
        case .mine: return [.copper, .tin, .iron, .gold, .stone].contains { (t.resources[$0] ?? 0) > 0 }
        case .harbor: return t.isCoastal
        case .road, .walls, .farm, .granary: return true
        }
    }

    // MARK: Commands

    func setTaxRate(_ rate: Int, _ state: inout GameState) throws -> [GameEvent] {
        guard (0...100).contains(rate), rate % 10 == 0 else { throw GameError.invalidTaxRate }
        let civ = state.activePlayer
        state.civs[civ]!.taxRate = rate
        return [.taxRateSet(civ: civ, rate: rate)]
    }

    func build(_ project: ProjectKind, in territory: TerritoryID, _ state: inout GameState) throws -> [GameEvent] {
        let civ = state.activePlayer
        guard state.owner(of: territory) == civ else { throw GameError.notOwner(territory) }
        guard homeNetwork(of: civ, in: state).contains(territory) else { throw GameError.outOfSupply(territory) }
        guard canBuild(project, in: territory, state) else { throw GameError.projectUnavailable(territory, project) }
        let cost = projectCost(project, for: civ, state)
        let cs = state.civs[civ]!
        guard cs.gold >= cost.gold else { throw GameError.insufficientGold(needed: cost.gold, available: cs.gold) }
        for (resource, needed) in [(Resource.stone, cost.stone), (.timber, cost.timber)] where needed > 0 {
            let have = cs.stock[resource] ?? 0
            guard have >= needed else { throw GameError.insufficientStock(resource, needed: needed, available: have) }
        }
        state.civs[civ]!.gold -= cost.gold
        state.civs[civ]!.stock[.stone, default: 0] -= cost.stone
        state.civs[civ]!.stock[.timber, default: 0] -= cost.timber
        state.land[territory]!.construction = Construction(kind: project, turnsLeft: cost.turns)
        return [.projectStarted(civ: civ, territory: territory, project: project)]
    }

    /// Advances a civilization's building sites by a turn, finishing what's due.
    func progressConstruction(_ civ: CivilizationID, _ state: inout GameState) -> [GameEvent] {
        var events: [GameEvent] = []
        for t in state.territories(of: civ) {
            guard var site = state.land[t]!.construction else { continue }
            site.turnsLeft -= 1
            if site.turnsLeft <= 0 {
                state.land[t]!.improvements.insert(site.kind)
                state.land[t]!.construction = nil
                addExperience(civ, .construction, 4, &state)
                if site.kind == .farm { addExperience(civ, .agriculture, 3, &state) }
                if site.kind == .mine { addExperience(civ, .metallurgy, 2, &state) }
                events.append(.projectCompleted(civ: civ, territory: t, project: site.kind))
            } else {
                state.land[t]!.construction = site
            }
        }
        return events
    }

    /// Stone, timber and iron pile up from the home network (and trade access), up to a cap.
    func stockpile(_ civ: CivilizationID, _ routes: [TradeRoute], _ state: inout GameState) {
        for resource in Resource.stockpiled {
            let gained = effectiveYield(of: resource, for: civ, in: state, routes: routes)
            let have = state.civs[civ]!.stock[resource] ?? 0
            state.civs[civ]!.stock[resource] = min(rules.economy.stockCap, have + gained)
        }
    }

    /// Gold from wine and oil: each unit sells, and each unit shipped to a partner who has none
    /// sells again (up to a cap per route).
    func wineGold(_ civ: CivilizationID, _ home: [TerritoryID], _ routes: [TradeRoute], _ state: GameState) -> Int {
        let wine = yield(of: .wine, in: home, state)
        guard wine > 0 else { return 0 }
        let exports = routes.filter { $0.involves(civ) }.reduce(0) { total, route in
            let partner = route.partner(of: civ)
            let theirs = yield(of: .wine, in: homeNetwork(of: partner, in: state), state)
            return total + (theirs == 0 ? min(wine, rules.economy.wineExportCap) : 0)
        }
        return (wine + exports) * rules.economy.winePerGold
    }

    /// Harbors pay when there's trade to handle.
    func harborGold(_ civ: CivilizationID, _ home: [TerritoryID], _ routes: [TradeRoute], _ state: GameState) -> Int {
        guard routes.contains(where: { $0.involves(civ) }) else { return 0 }
        return home.filter { state.land[$0]?.improvements.contains(.harbor) ?? false }.count * rules.projectEffects.harborGold
    }

    /// Legitimacy a turn from taxes (below the default raises it, above lowers it) and luxuries.
    func taxAndLuxuryLegitimacy(_ civ: CivilizationID, _ state: GameState) -> Int {
        let e = rules.economy
        let taxes = (e.defaultTax - state.civs[civ]!.taxRate) / max(1, e.taxLegitimacyStep)
        let luxuries = effectiveYield(of: .luxuries, for: civ, in: state)
        return taxes + min(e.luxuryLegitimacyCap, luxuries / max(1, e.luxuriesPerLegitimacy))
            + courtLegitimacy(of: civ, in: state)
            + (holds("pyramid", civ, in: state) ? 1 : 0)
    }

    /// Share of surplus grain that goes into population growth: less when taxes are high.
    func growthPercent(_ civ: CivilizationID, _ state: GameState) -> Int {
        let e = rules.economy
        let rate = state.civs[civ]!.taxRate
        guard rate > e.defaultTax else { return 100 }
        return max(0, (100 - rate) * 100 / max(1, 100 - e.defaultTax))
    }
}
