/// Ships: building, sailing, transport and naval battles (auto-resolve only).
extension Engine {
    /// A sea is blockaded for `travelers` when a fleet at war with any of them is there and none
    /// of theirs is.
    public func blockaded(_ sea: SeaZoneID, for travelers: [CivilizationID], in state: GameState) -> Bool {
        let here = state.fleets.filter { $0.sea == sea && $0.ships > 0 }
        guard !here.contains(where: { travelers.contains($0.owner) }) else { return false }
        return here.contains { f in travelers.contains { state.atWar(f.owner, $0) } }
    }

    private func fleetIndex(_ civ: CivilizationID, _ sea: SeaZoneID, _ state: GameState) -> Int? {
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
    private func drownExcess(_ cargo: inout UnitCounts, ships: Int) -> UnitCounts {
        var lost = UnitCounts.zero
        while cargo.total > ships * rules.ships.capacity {
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
        guard state.fleets[i].cargo.total + units.total <= state.fleets[i].ships * rules.ships.capacity else {
            throw GameError.overCapacity(sea)
        }

        state.armies[territory]!.units -= units
        if state.armies[territory]!.units.isEmpty { state.armies[territory] = nil }
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
        try checkOmen(civ, attacking: territory, state)

        state.fleets[i].cargo -= units
        let events: [GameEvent] = [.landed(civ: civ, sea: sea, territory: territory, units: units)]
        return events + advance(civ, units, general: nil, formation: nil, into: territory,
                                from: .sea(sea), approach: .amphibious, &state)
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
        let cap = rules.ships.capacity
        guard cargo.total <= ships * cap, (fleet.cargo - cargo).total <= (fleet.ships - ships) * cap else {
            throw GameError.overCapacity(from)
        }
        guard map.seaNeighbors(of: from).contains(to) else { throw GameError.notAdjacent(from, to) }
        guard seaLinkOpen(from, to, for: [civ], in: state) else { throw GameError.chokepointClosed(from, to) }

        state.fleets[i].ships -= ships
        state.fleets[i].cargo -= cargo
        if state.fleets[i].ships == 0 { state.fleets.remove(at: i) }

        var events: [GameEvent] = [.fleetMoved(civ: civ, from: from, to: to, ships: ships, cargo: cargo)]
        var ships = ships
        var cargo = cargo
        let enemies = state.fleets.filter { $0.sea == to && state.atWar(civ, $0.owner) }.map(\.owner).sorted()
        for enemy in enemies {
            let result = navalBattle(civ, ships: ships, cargo: cargo, from: from, against: enemy, in: to, &state)
            events += result.events
            (ships, cargo) = (result.ships, result.cargo)
            guard result.won else {
                addToFleet(civ, from, ships: ships, moved: ships, cargo: cargo, &state)
                return events
            }
        }
        addToFleet(civ, to, ships: ships, moved: ships, cargo: cargo, &state)
        return events
    }

    /// Fights the enemy fleet in `sea`. Returns whether the attacker won and what it has left.
    private func navalBattle(_ civ: CivilizationID, ships: Int, cargo: UnitCounts, from: SeaZoneID,
                             against enemy: CivilizationID, in sea: SeaZoneID, _ state: inout GameState)
        -> (won: Bool, ships: Int, cargo: UnitCounts, events: [GameEvent]) {
        let d = fleetIndex(enemy, sea, state)!
        let report = BattleSimulator(rules: rules).resolveNaval(
            attacker: civ, attackerShips: ships, defender: enemy, defenderShips: state.fleets[d].ships,
            seed: state.rng.next())
        var events: [GameEvent] = [.navalBattle(sea: sea, report: report)]

        var cargo = cargo
        let attackerDrowned = drownExcess(&cargo, ships: report.attackerShipsLeft)
        let attackerSunk = ships - report.attackerShipsLeft
        if attackerSunk > 0 || !attackerDrowned.isEmpty {
            events.append(.destroyed(civ: civ, units: attackerDrowned, ships: attackerSunk))
        }

        var defender = state.fleets.remove(at: d)
        let defenderDrowned = drownExcess(&defender.cargo, ships: report.defenderShipsLeft)
        let defenderSunk = defender.ships - report.defenderShipsLeft
        defender.ships = report.defenderShipsLeft
        defender.movedShips = min(defender.movedShips, defender.ships)
        if defenderSunk > 0 || !defenderDrowned.isEmpty {
            events.append(.destroyed(civ: enemy, units: defenderDrowned, ships: defenderSunk))
        }

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
            }
        }
        events += checkElimination(enemy, &state)
        return (won, report.attackerShipsLeft, cargo, events)
    }
}
