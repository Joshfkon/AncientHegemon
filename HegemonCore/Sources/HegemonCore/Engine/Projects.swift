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

    /// How high a territory's walls stand: 0 without walls, then 1 up to `maxWallLevel`.
    public func wallLevel(at territory: TerritoryID, _ state: GameState) -> Int {
        guard let land = state.land[territory], land.improvements.contains(.walls) else { return 0 }
        return land.wallLevel ?? 1
    }

    /// Whether a territory's walls can be raised a level now (the top level needs Construction).
    func canRaiseWalls(_ territory: TerritoryID, _ state: GameState) -> Bool {
        let lv = wallLevel(at: territory, state)
        let fx = rules.projectEffects
        guard lv >= 1, lv < fx.maxWallLevel else { return false }
        return lv + 1 < fx.maxWallLevel || level(.construction, of: state.owner(of: territory), in: state) >= fx.topWallConstruction
    }

    /// Whether a project can be built in a territory at all (ignoring costs). Walls already
    /// standing can be raised a level.
    public func canBuild(_ project: ProjectKind, in territory: TerritoryID, _ state: GameState) -> Bool {
        guard let t = map.territory(territory), let land = state.land[territory], land.construction == nil else { return false }
        if project == .walls, land.improvements.contains(.walls) { return canRaiseWalls(territory, state) }
        guard !land.improvements.contains(project) else { return false }
        switch project {
        case .mine: return [.copper, .tin, .iron, .gold, .stone].contains { (t.resources[$0] ?? 0) > 0 }
        case .harbor: return t.isCoastal
        case .road, .walls, .farm, .granary, .drains: return true
        case .levee: return t.has(.riverValley)
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
        // An overlord may lay a road through its vassal's land.
        let throughVassal = project == .road && canBuildRoad(through: territory, for: civ, state)
        if !throughVassal {
            guard state.owner(of: territory) == civ else { throw GameError.notOwner(territory) }
            guard homeNetwork(of: civ, in: state).contains(territory) else { throw GameError.outOfSupply(territory) }
            guard canBuild(project, in: territory, state) else { throw GameError.projectUnavailable(territory, project) }
        }
        let cost = projectCost(project, for: civ, state, at: territory)
        let cs = state.civs[civ]!
        guard cs.gold >= cost.gold else { throw GameError.insufficientGold(needed: cost.gold, available: cs.gold) }
        for (resource, needed) in [(Resource.stone, cost.stone), (.timber, cost.timber)] where needed > 0 {
            let have = cs.stock[resource] ?? 0
            guard have >= needed else { throw GameError.insufficientStock(resource, needed: needed, available: have) }
        }
        state.civs[civ]!.gold -= cost.gold
        state.civs[civ]!.stock[.stone, default: 0] -= cost.stone
        state.civs[civ]!.stock[.timber, default: 0] -= cost.timber
        state.land[territory]!.construction = Construction(kind: project, turnsLeft: cost.turns, builder: throughVassal ? civ : nil)
        return [.projectStarted(civ: civ, territory: territory, project: project)]
    }

    /// Whether `civ` may lay a road through `territory`: the land of a vassal of its (a kingdom
    /// or an empire), with no road and no building site yet, next to land of its own.
    public func canBuildRoad(through territory: TerritoryID, for civ: CivilizationID, _ state: GameState) -> Bool {
        guard let land = state.land[territory], !land.improvements.contains(.road), land.construction == nil else { return false }
        guard vassalLord(of: territory, state) == civ else { return false }
        let home = Set(homeNetwork(of: civ, in: state))
        return map.landNeighbors(of: territory).contains { home.contains($0) || canReachByRoad($0, civ, state) }
    }

    /// Vassal land of `civ`'s that already has a road (roads may run on from one to the next).
    private func canReachByRoad(_ t: TerritoryID, _ civ: CivilizationID, _ state: GameState) -> Bool {
        state.land[t]?.improvements.contains(.road) == true && vassalLord(of: t, state) == civ
    }

    /// The overlord of whoever holds a territory: a vassal empire's liege, or a vassal kingdom's.
    func vassalLord(of t: TerritoryID, _ state: GameState) -> CivilizationID? {
        state.owner(of: t).flatMap { liege(of: $0, in: state) } ?? overlord(of: t, in: state)
    }

    /// Advances a civilization's building sites by a turn, finishing what's due.
    func progressConstruction(_ civ: CivilizationID, _ state: inout GameState) -> [GameEvent] {
        var events: [GameEvent] = []
        // An age of splendour builds twice as fast.
        let pace = state.civs[civ]!.splendour > 0 ? 2 : 1
        // Its own land, and roads it is laying through its vassals' land.
        let elsewhere = state.land.filter { $0.value.construction?.builder == civ && $0.value.owner != civ }.keys.sorted()
        for t in state.territories(of: civ) + elsewhere {
            defer { if state.owner(of: t) == civ { events += startQueued(civ, t, &state) } }
            guard var site = state.land[t]!.construction else { continue }
            // Someone else's site on our land (our overlord's road) is theirs to advance.
            if let builder = site.builder, builder != civ { continue }
            // A road through land that is no longer our vassal's is abandoned.
            if state.owner(of: t) != civ, vassalLord(of: t, state) != civ {
                state.land[t]!.construction = nil
                continue
            }
            site.turnsLeft -= pace
            if site.turnsLeft <= 0 {
                if site.kind == .walls, state.land[t]!.improvements.contains(.walls) {
                    state.land[t]!.wallLevel = wallLevel(at: t, state) + 1
                }
                state.land[t]!.improvements.insert(site.kind)
                state.land[t]!.construction = nil
                addExperience(civ, .construction, 4, &state)
                adjustLegitimacy(civ, rules.realm.buildingLegitimacy, &state)
                if site.kind == .farm { addExperience(civ, .agriculture, 3, &state) }
                if site.kind == .mine { addExperience(civ, .metallurgy, 2, &state) }
                events.append(.projectCompleted(civ: civ, territory: t, project: site.kind))
            } else {
                state.land[t]!.construction = site
            }
        }
        return events
    }

    /// Whether a project could be added to a territory's queue: it isn't built, under way or
    /// queued already, and the land suits it.
    public func canQueue(_ project: ProjectKind, in territory: TerritoryID, _ state: GameState) -> Bool {
        guard let land = state.land[territory], !land.improvements.contains(project) || project == .walls,
              land.construction?.kind != project, !land.queue.contains(project),
              land.queue.count < rules.economy.queueLength else { return false }
        var bare = state
        bare.land[territory]!.construction = nil
        return canBuild(project, in: territory, bare)
    }

    func queueProject(_ project: ProjectKind, in territory: TerritoryID, _ state: inout GameState) throws -> [GameEvent] {
        let civ = state.activePlayer
        guard state.owner(of: territory) == civ else { throw GameError.notOwner(territory) }
        guard canQueue(project, in: territory, state) else { throw GameError.alreadyQueued(territory) }
        // With nothing under way, queueing simply starts it if it can be paid for.
        if state.land[territory]!.construction == nil, let started = try? build(project, in: territory, &state) {
            return started
        }
        state.land[territory]!.queue.append(project)
        return [.projectQueued(civ: civ, territory: territory, project: project)]
    }

    func clearQueue(_ territory: TerritoryID, _ state: inout GameState) throws -> [GameEvent] {
        guard state.owner(of: territory) == state.activePlayer else { throw GameError.notOwner(territory) }
        state.land[territory]!.queue = []
        return []
    }

    /// Starts the next queued project once the site is free, if it can be paid for; one that no
    /// longer fits is dropped.
    private func startQueued(_ civ: CivilizationID, _ t: TerritoryID, _ state: inout GameState) -> [GameEvent] {
        while state.land[t]?.construction == nil, let next = state.land[t]?.queue.first {
            guard canBuild(next, in: t, state), homeNetwork(of: civ, in: state).contains(t) else {
                state.land[t]!.queue.removeFirst()
                continue
            }
            let cost = projectCost(next, for: civ, state, at: t)
            let cs = state.civs[civ]!
            guard cs.gold >= cost.gold, (cs.stock[.stone] ?? 0) >= cost.stone, (cs.stock[.timber] ?? 0) >= cost.timber else { break }
            state.civs[civ]!.gold -= cost.gold
            state.civs[civ]!.stock[.stone, default: 0] -= cost.stone
            state.civs[civ]!.stock[.timber, default: 0] -= cost.timber
            state.land[t]!.construction = Construction(kind: next, turnsLeft: cost.turns)
            state.land[t]!.queue.removeFirst()
            return [.projectStarted(civ: civ, territory: t, project: next)]
        }
        return []
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
        let splendour = state.civs[civ]!.splendour > 0 ? rules.splendour.growthPercent : 0
        guard rate > e.defaultTax else { return 100 + splendour }
        return max(0, (100 - rate) * 100 / max(1, 100 - e.defaultTax)) * (100 + splendour) / 100
    }
}
