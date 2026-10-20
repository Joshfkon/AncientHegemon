/// Ships: building, sailing, transport and naval battles (auto-resolve only).
extension Engine {
    /// A sea is blockaded for `travelers` when a fleet at war with any of them is there and none
    /// of theirs is.
    public func blockaded(_ sea: SeaZoneID, for travelers: [CivilizationID], in state: GameState) -> Bool {
        let here = state.fleets.filter { $0.sea == sea && $0.ships > 0 }
        guard !here.contains(where: { travelers.contains($0.owner) }) else { return false }
        return here.contains { f in travelers.contains { state.atWar(f.owner, $0) } }
    }

    /// The shortest way for `civ`'s ships from one sea to another within a turn's sailing,
    /// through open lanes, never through waters an enemy fleet holds (only into them, to fight).
    /// The path excludes the starting sea.
    public func fleetPath(from: SeaZoneID, to: SeaZoneID, for civ: CivilizationID, in state: GameState) -> [SeaZoneID]? {
        fleetPaths(from: from, for: civ, in: state)[to]
    }

    /// Every sea `civ`'s ships in `from` can reach this turn, each with its path.
    public func fleetPaths(from: SeaZoneID, for civ: CivilizationID, in state: GameState) -> [SeaZoneID: [SeaZoneID]] {
        var paths: [SeaZoneID: [SeaZoneID]] = [from: []]
        var frontier = [from]
        for _ in 0..<max(1, rules.ships.moves) {
            var next: [SeaZoneID] = []
            for s in frontier {
                // Enemy waters end the voyage: ships sail in to fight, not through.
                if s != from, state.fleets.contains(where: { $0.sea == s && $0.ships > 0 && state.atWar(civ, $0.owner) }) { continue }
                for n in map.seaNeighbors(of: s).sorted() where paths[n] == nil && seaLinkOpen(s, n, for: [civ], in: state) {
                    paths[n] = paths[s]! + [n]
                    next.append(n)
                }
            }
            frontier = next
        }
        paths[from] = nil
        return paths
    }

    func fleetIndex(_ civ: CivilizationID, _ sea: SeaZoneID, _ state: GameState) -> Int? {
        state.fleets.firstIndex { $0.owner == civ && $0.sea == sea }
    }

    /// Adds ships (and cargo) to a civilization's fleet in a sea, creating it if needed.
    private func addToFleet(_ civ: CivilizationID, _ sea: SeaZoneID, ships: Int, moved: Int,
                            cargo: UnitCounts, _ state: inout GameState) {
        guard ships > 0 else { return }
        if let i = fleetIndex(civ, sea, state) {
            state.fleets[i].ships += ships
            state.fleets[i].movedShips += moved
            state.fleets[i].cargo += cargo
        } else {
            state.fleets.append(Fleet(sea: sea, owner: civ, ships: ships, movedShips: moved, cargo: cargo))
            state.fleets.sort { ($0.sea, $0.owner) < ($1.sea, $1.owner) }
        }
    }

    /// Drowns cargo that no longer fits after ship losses, most numerous type first.
    func drownExcess(_ cargo: inout UnitCounts, ships: Int, capacity: Int) -> UnitCounts {
        var lost = UnitCounts.zero
        while cargo.total > ships * capacity {
            let type = UnitType.allCases.max { cargo[$0] < cargo[$1] }!
            cargo[type] -= 1
            lost[type] += 1
        }
        return lost
    }

    // MARK: Commands

    func buildShips(_ territory: TerritoryID, _ sea: SeaZoneID, _ count: Int,
                    _ state: inout GameState) throws -> [GameEvent] {
        let civ = state.activePlayer
        guard count > 0 else { throw GameError.invalidCount }
        guard let t = map.territory(territory) else { throw GameError.unknownTerritory(territory) }
        guard map.sea(sea) != nil else { throw GameError.unknownSea(sea) }
        guard state.owner(of: territory) == civ else { throw GameError.notOwner(territory) }
        guard t.seas.contains(sea) else { throw GameError.notCoastal(territory, sea) }
        guard homeNetwork(of: civ, in: state).contains(territory) else { throw GameError.outOfSupply(territory) }
        guard !blockaded(sea, for: [civ], in: state) else { throw GameError.blockaded(sea) }
        let discount = state.land[territory]?.improvements.contains(.harbor) == true ? rules.projectEffects.harborShipDiscount : 0
        let cost = max(1, rules.ships.cost - discount) * count
        let gold = state.civs[civ]!.gold
        guard gold >= cost else { throw GameError.insufficientGold(needed: cost, available: gold) }
        let resource = rules.ships.requires
        let used = state.civs[civ]!.resourceUsedThisTurn[resource] ?? 0
        guard used + count <= effectiveYield(of: resource, for: civ, in: state) else {
            throw GameError.resourceLimit(resource)
        }

        state.civs[civ]!.resourceUsedThisTurn[resource] = used + count
        state.civs[civ]!.gold -= cost
        addToFleet(civ, sea, ships: count, moved: count, cargo: .zero, &state)
        return [.shipsBuilt(civ: civ, sea: sea, count: count)]
    }

    func embark(_ territory: TerritoryID, _ sea: SeaZoneID, _ units: UnitCounts,
                _ state: inout GameState) throws -> [GameEvent] {
        let civ = state.activePlayer
        guard units.isNonNegative, !units.isEmpty else { throw GameError.invalidCount }
        guard let t = map.territory(territory) else { throw GameError.unknownTerritory(territory) }
        guard t.seas.contains(sea) else { throw GameError.notCoastal(territory, sea) }
        guard let army = state.armies[territory], army.owner == civ,
              units.fits(in: army.units - (state.moved[territory] ?? .zero)) else {
            throw GameError.insufficientUnits(territory)
        }
        guard let i = fleetIndex(civ, sea, state) else { throw GameError.noFleet(sea) }
        guard state.fleets[i].cargo.total + units.total <= state.fleets[i].ships * shipCapacity(civ, state) else {
            throw GameError.overCapacity(sea)
        }

        let honours = army.battles ?? 0
        state.armies[territory]!.units -= units
        if state.armies[territory]!.units.isEmpty { state.armies[territory] = nil }
        let f = state.fleets[i]
        state.fleets[i].cargoBattles = mergedBattles(f.cargoBattles ?? 0, f.cargo.total, honours, units.total)
        state.fleets[i].cargo += units
        return [.embarked(civ: civ, territory: territory, sea: sea, units: units)]
    }

    func land(_ sea: SeaZoneID, _ territory: TerritoryID, _ units: UnitCounts,
              _ state: inout GameState) throws -> [GameEvent] {
        let civ = state.activePlayer
        guard units.isNonNegative, !units.isEmpty else { throw GameError.invalidCount }
        guard let t = map.territory(territory) else { throw GameError.unknownTerritory(territory) }
        guard t.seas.contains(sea) else { throw GameError.notCoastal(territory, sea) }
        guard let i = fleetIndex(civ, sea, state) else { throw GameError.noFleet(sea) }
        guard units.fits(in: state.fleets[i].cargo) else { throw GameError.insufficientUnits(territory) }
        if let owner = state.owner(of: territory), state.atPeace(civ, owner) { throw GameError.atPeace(territory) }
        if shielded(territory, from: civ, in: state) { throw GameError.shielded(territory) }
        try checkOmen(civ, attacking: territory, state)

        // Enemy ships in these waters must be beaten before anyone goes ashore.
        var events: [GameEvent] = []
        var units = units
        let enemies = state.fleets.filter { $0.sea == sea && $0.ships > 0 && state.atWar(civ, $0.owner) }.map(\.owner).sorted()
        if !enemies.isEmpty {
            var fleet = state.fleets.remove(at: i)
            for enemy in enemies where state.fleets.contains(where: { $0.owner == enemy && $0.sea == sea }) {
                let result = navalBattle(civ, ships: fleet.ships, cargo: fleet.cargo, from: sea, against: enemy, in: sea,
                                         plan: fleet.plan, &state)
                events += result.events
                fleet.ships = result.ships
                fleet.cargo = result.cargo
                guard result.won, fleet.ships > 0 else {
                    if fleet.ships > 0 {
                        addToFleet(civ, sea, ships: fleet.ships, moved: fleet.ships, cargo: fleet.cargo, &state)
                        if let j = fleetIndex(civ, sea, state) { state.fleets[j].cargoBattles = fleet.cargoBattles }
                    }
                    return events
                }
            }
            fleet.movedShips = fleet.ships
            state.fleets.append(fleet)
            state.fleets.sort { ($0.sea, $0.owner) < ($1.sea, $1.owner) }
            guard let k = fleetIndex(civ, sea, state) else { return events }
            // Troops drowned in the fight can't land.
            for type in UnitType.allCases { units[type] = min(units[type], state.fleets[k].cargo[type]) }
            guard !units.isEmpty else { return events }
        }
        guard let i = fleetIndex(civ, sea, state) else { return events }
        let honours = state.fleets[i].cargoBattles ?? 0
        state.fleets[i].cargo -= units
        if state.fleets[i].cargo.isEmpty { state.fleets[i].cargoBattles = nil }
        events.append(.landed(civ: civ, sea: sea, territory: territory, units: units))
        return events + advance(civ, units, general: nil, plan: BattlePlan(), battles: honours, into: territory,
                                from: .sea(sea), approach: .amphibious, &state)
    }

    /// Ships broken up or laid up ashore: no gold comes back, but no more upkeep is owed.
    func disbandShips(_ sea: SeaZoneID, _ ships: Int, _ state: inout GameState) throws -> [GameEvent] {
        let civ = state.activePlayer
        guard ships > 0 else { throw GameError.invalidCount }
        guard let i = fleetIndex(civ, sea, state) else { throw GameError.noFleet(sea) }
        let fleet = state.fleets[i]
        guard ships <= fleet.ships else { throw GameError.insufficientShips(sea) }
        guard fleet.cargo.total <= (fleet.ships - ships) * shipCapacity(civ, state) else {
            throw GameError.overCapacity(sea)
        }
        state.fleets[i].ships -= ships
        state.fleets[i].movedShips = min(state.fleets[i].movedShips, state.fleets[i].ships)
        if state.fleets[i].ships == 0 { state.fleets.remove(at: i) }
        return [.shipsDisbanded(civ: civ, sea: sea, count: ships)]
    }

    func moveFleet(_ from: SeaZoneID, _ to: SeaZoneID, _ ships: Int, _ cargo: UnitCounts,
                   _ state: inout GameState) throws -> [GameEvent] {
        let civ = state.activePlayer
        guard ships > 0, cargo.isNonNegative else { throw GameError.invalidCount }
        guard map.sea(to) != nil else { throw GameError.unknownSea(to) }
        guard let i = fleetIndex(civ, from, state) else { throw GameError.noFleet(from) }
        let fleet = state.fleets[i]
        guard ships <= fleet.ships - fleet.movedShips else { throw GameError.insufficientShips(from) }
        guard cargo.fits(in: fleet.cargo) else { throw GameError.insufficientUnits(from) }
        let cap = shipCapacity(civ, state)
        guard cargo.total <= ships * cap, (fleet.cargo - cargo).total <= (fleet.ships - ships) * cap else {
            throw GameError.overCapacity(from)
        }
        guard let path = fleetPath(from: from, to: to, for: civ, in: state) else {
            if map.seaNeighbors(of: from).contains(to) { throw GameError.chokepointClosed(from, to) }
            throw GameError.notAdjacent(from, to)
        }
        // The last sea before the destination: where a beaten squadron falls back to.
        let lastLeg = path.count > 1 ? path[path.count - 2] : from

        let plan = fleet.plan
        let honours = fleet.cargoBattles ?? 0
        state.fleets[i].ships -= ships
        state.fleets[i].cargo -= cargo
        if state.fleets[i].ships == 0 { state.fleets.remove(at: i) }

        var events: [GameEvent] = [.fleetMoved(civ: civ, from: from, to: to, ships: ships, cargo: cargo)]
        var ships = ships
        var cargo = cargo
        let enemies = state.fleets.filter { $0.sea == to && state.atWar(civ, $0.owner) }.map(\.owner).sorted()
        for enemy in enemies {
            let result = navalBattle(civ, ships: ships, cargo: cargo, from: lastLeg, against: enemy, in: to, plan: plan, &state)
            events += result.events
            (ships, cargo) = (result.ships, result.cargo)
            guard result.won else {
                addToFleet(civ, lastLeg, ships: ships, moved: ships, cargo: cargo, &state)
                return events
            }
        }
        let existed = fleetIndex(civ, to, state) != nil
        let before = existed ? state.fleets[fleetIndex(civ, to, state)!] : nil
        addToFleet(civ, to, ships: ships, moved: ships, cargo: cargo, &state)
        if let j = fleetIndex(civ, to, state) {
            // The squadron's plan and its troops' honours sail with it.
            if !existed {
                state.fleets[j].formation = plan.formation
                state.fleets[j].depth = plan.depth
                state.fleets[j].stratagem = plan.stratagem
                state.fleets[j].holdBack = plan.pursue ? nil : true
            }
            state.fleets[j].cargoBattles = mergedBattles(before?.cargoBattles ?? 0, before?.cargo.total ?? 0,
                                                         honours, cargo.total)
        }
        return events
    }

    /// A sea battle as fought on the grid: each ship a unit, on open water, crews as good as
    /// their seafaring.
    public func navalSetup(_ civ: CivilizationID, ships: Int, plan: BattlePlan,
                           against enemy: CivilizationID, ships enemyShips: Int, plan enemyPlan: BattlePlan,
                           seed: UInt64 = 0, _ state: GameState) -> BattleSetup {
        func side(_ c: CivilizationID, _ n: Int, _ p: BattlePlan) -> BattleArmy {
            var army = battleArmy(c, UnitCounts(infantry: n), plan: p, general: nil, state)
            army.unitPercent = [.infantry: navalPercent(c, state) - 100]
            army.morale = 0
            return army
        }
        var setup = BattleSetup(attacker: side(civ, ships, plan), defender: side(enemy, enemyShips, enemyPlan),
                                terrain: .plains, approach: .overland, seed: seed)
        setup.naval = true
        return setup
    }

    /// The first enemy fleet a squadron sailing into `sea` would have to fight, and the battle.
    public func fleetAttackSetup(_ civ: CivilizationID, ships: Int, into sea: SeaZoneID, plan: BattlePlan,
                                 in state: GameState) -> BattleSetup? {
        guard let enemy = state.fleets.filter({ $0.sea == sea && $0.ships > 0 && state.atWar(civ, $0.owner) })
            .sorted(by: { $0.owner < $1.owner }).first else { return nil }
        return navalSetup(civ, ships: ships, plan: plan, against: enemy.owner, ships: enemy.ships, plan: enemy.plan, state)
    }

    /// Chance a squadron wins that battle, from a few trial runs (the game's RNG is untouched).
    public func fleetAttackOdds(_ civ: CivilizationID, ships: Int, into sea: SeaZoneID, plan: BattlePlan,
                                samples: Int = 12, in state: GameState) -> Double? {
        guard let setup = fleetAttackSetup(civ, ships: ships, into: sea, plan: plan, in: state) else { return nil }
        var rng = SeededRNG(seed: state.seed ^ (UInt64(state.turn) &* 0x9E37_79B9_7F4A_7C15) ^ UInt64(sea.utf8.count))
        let sim = BattleSimulator(rules: rules)
        var wins = 0
        for _ in 0..<samples {
            var trial = setup
            trial.seed = rng.next()
            if sim.resolve(trial).winner == .attacker { wins += 1 }
        }
        return Double(wins) / Double(samples)
    }

    /// Fights the enemy fleet in `sea`. Returns whether the attacker won and what it has left.
    private func navalBattle(_ civ: CivilizationID, ships: Int, cargo: UnitCounts, from: SeaZoneID,
                             against enemy: CivilizationID, in sea: SeaZoneID, plan attackerPlan: BattlePlan = BattlePlan(),
                             _ state: inout GameState)
        -> (won: Bool, ships: Int, cargo: UnitCounts, events: [GameEvent]) {
        let d = fleetIndex(enemy, sea, state)!
        let setup = navalSetup(civ, ships: ships, plan: attackerPlan,
                               against: enemy, ships: state.fleets[d].ships, plan: state.fleets[d].plan,
                               seed: state.rng.next(), state)
        let grid = BattleSimulator(rules: rules).resolve(setup)
        var report = NavalReport(attacker: civ, defender: enemy, attackerShips: ships,
                                 defenderShips: state.fleets[d].ships, winner: grid.winner, rounds: grid.rounds,
                                 attackerShipsLeft: grid.attackerSurvivors.total, defenderShipsLeft: grid.defenderSurvivors.total)
        report.battle = grid
        var events: [GameEvent] = [.navalBattle(sea: sea, report: report)]
        addExperience(civ, .seafaring, 5, &state)
        addExperience(enemy, .seafaring, 5, &state)

        var cargo = cargo
        let attackerDrowned = drownExcess(&cargo, ships: report.attackerShipsLeft, capacity: shipCapacity(civ, state))
        let attackerSunk = ships - report.attackerShipsLeft
        if attackerSunk > 0 || !attackerDrowned.isEmpty {
            events.append(.destroyed(civ: civ, units: attackerDrowned, ships: attackerSunk))
        }

        var defender = state.fleets.remove(at: d)
        let defenderDrowned = drownExcess(&defender.cargo, ships: report.defenderShipsLeft, capacity: shipCapacity(enemy, state))
        let defenderSunk = defender.ships - report.defenderShipsLeft
        defender.ships = report.defenderShipsLeft
        defender.movedShips = min(defender.movedShips, defender.ships)
        if defenderSunk > 0 || !defenderDrowned.isEmpty {
            events.append(.destroyed(civ: enemy, units: defenderDrowned, ships: defenderSunk))
        }

        var lost = defenderSunk
        let won = report.winner == .attacker
        if !won {
            if defender.ships > 0 {
                addToFleet(enemy, sea, ships: defender.ships, moved: defender.movedShips,
                           cargo: defender.cargo, &state)
            }
        } else if defender.ships > 0 {
            // The beaten fleet withdraws to a neighboring sea it can reach and isn't blockaded in.
            let refuge = map.seaNeighbors(of: sea).first { s in
                s != from && seaLinkOpen(sea, s, for: [enemy], in: state) && !blockaded(s, for: [enemy], in: state)
            }
            if let refuge {
                addToFleet(enemy, refuge, ships: defender.ships, moved: defender.movedShips,
                           cargo: defender.cargo, &state)
                events.append(.fleetRetreated(civ: enemy, from: sea, to: refuge, ships: defender.ships))
            } else {
                events.append(.destroyed(civ: enemy, units: defender.cargo, ships: defender.ships))
                lost += defender.ships
            }
        }
        // The coasts pay well for every pirate ship sent to the bottom.
        if enemy == piratesID, lost > 0, state.civs[civ] != nil {
            let bounty = lost * rules.pirates.bountyPerShip
            state.civs[civ]!.gold += bounty
            events.append(.bountyPaid(civ: civ, gold: bounty))
        }
        events += checkElimination(enemy, &state)
        return (won, report.attackerShipsLeft, cargo, events)
    }
}
