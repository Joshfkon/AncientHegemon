/// The perils of the sea: storms that wreck ships far from a harbour of their own, and pirates
/// who prowl the waters, plunder coasts nobody guards and close the lanes they sit on.
extension Engine {
    // MARK: Storms

    /// A sea where `civ`'s ships ride out storms: one of its own coasts there has a harbour.
    public func sheltered(_ sea: SeaZoneID, for civ: CivilizationID, in state: GameState) -> Bool {
        map.coastalTerritories(of: sea).contains { t in
            state.owner(of: t) == civ && state.land[t]?.improvements.contains(.harbor) == true
        }
    }

    /// Chance a storm catches one of `civ`'s fleets this turn on open water (half that off a
    /// coast of its own, none off a harbour of its own).
    public func stormChance(for civ: CivilizationID, in state: GameState) -> Int {
        let s = rules.ships
        guard s.stormPercent > 0 else { return 0 }
        let chance = max(s.stormMinPercent, s.stormPercent - level(.seafaring, of: civ, in: state) * s.stormSeafaringRelief)
        // The great lighthouse guides ships to shelter before the weather breaks.
        return holds("lighthouse", civ, in: state) ? chance / 2 : chance
    }

    /// At the start of `civ`'s turn, storms may sink some of each fleet at sea away from shelter,
    /// and drown the troops that no longer fit aboard.
    func storms(_ civ: CivilizationID, _ state: inout GameState) -> [GameEvent] {
        let chance = stormChance(for: civ, in: state)
        guard chance > 0 else { return [] }
        var events: [GameEvent] = []
        for sea in state.fleets(of: civ).map(\.sea).sorted() {
            // Off a coast of their own, ships can run for a beach: half the danger.
            let inshore = map.coastalTerritories(of: sea).contains { state.owner(of: $0) == civ }
            guard !sheltered(sea, for: civ, in: state), Int(state.rng.next() % 100) < (inshore ? chance / 2 : chance),
                  let i = fleetIndex(civ, sea, state) else { continue }
            let ships = state.fleets[i].ships
            let sunk = min(ships, max(1, ships * rules.ships.stormLossPercent / 100))
            var cargo = state.fleets[i].cargo
            let drowned = drownExcess(&cargo, ships: ships - sunk, capacity: shipCapacity(civ, state))
            state.fleets[i].ships -= sunk
            state.fleets[i].cargo = cargo
            state.fleets[i].movedShips = min(state.fleets[i].movedShips, state.fleets[i].ships)
            if state.fleets[i].ships == 0 { state.fleets.remove(at: i) }
            events.append(.storm(civ: civ, sea: sea, ships: sunk, drowned: drowned))
        }
        return events
    }

    // MARK: Pirates

    public func pirateFleets(in state: GameState) -> [Fleet] {
        state.fleets.filter { $0.owner == piratesID }
    }

    /// Waters a navy patrols: a fleet of `patrolShips` or more rides here or next door.
    public func patrolled(_ sea: SeaZoneID, in state: GameState) -> Bool {
        let near = Set([sea] + map.seaNeighbors(of: sea))
        return state.fleets.contains { $0.owner != piratesID && near.contains($0.sea) && $0.ships >= rules.pirates.patrolShips }
    }

    /// Coasts of `sea` that pirates there could plunder: a player's, unwalled, with none of the
    /// owner's ships in these waters or the next.
    func plunderable(_ sea: SeaZoneID, _ state: GameState) -> [TerritoryID] {
        let near = Set([sea] + map.seaNeighbors(of: sea))
        return map.coastalTerritories(of: sea).filter { t in
            guard let owner = state.owner(of: t), state.isPlayer(owner),
                  state.land[t]?.improvements.contains(.walls) != true else { return false }
            return !state.fleets.contains { $0.owner == owner && near.contains($0.sea) }
        }
    }

    /// Once a round: each pirate band may break up (likelier where a navy patrols); the rest slip
    /// to unpatrolled waters with easy pickings and plunder a coast there. Now and then a new
    /// band puts to sea, never in patrolled waters.
    func piratesRound(_ state: inout GameState) -> [GameEvent] {
        let p = rules.pirates
        guard state.turn >= p.fromRound else { return [] }
        var events: [GameEvent] = []
        for band in pirateFleets(in: state).map(\.sea).sorted() {
            // Bands don't last: sooner or later they break up and sail home with their loot,
            // sooner with warships about.
            let scatter = patrolled(band, in: state) ? p.patrolScatterPercent : p.scatterPercent
            if Int(state.rng.next() % 100) < scatter, let i = fleetIndex(piratesID, band, state) {
                state.fleets.remove(at: i)
                events.append(.piratesScattered(sea: band))
                continue
            }
            // Wander: stay or slip next door, never into waters where ships ride or navies patrol.
            let away = map.seaNeighbors(of: band).sorted().filter { s in
                !state.fleets.contains { $0.sea == s } && !patrolled(s, in: state)
            }
            let options = (patrolled(band, in: state) && !away.isEmpty ? [] : [band]) + away
            let weights = options.map { 1 + 3 * plunderable($0, state).count }
            var pick = Int(state.rng.next() % UInt64(weights.reduce(0, +)))
            var to = band
            for (s, w) in zip(options, weights) {
                if pick < w { to = s; break }
                pick -= w
            }
            if to != band, let i = fleetIndex(piratesID, band, state) {
                state.fleets[i].sea = to
                state.fleets.sort { ($0.sea, $0.owner) < ($1.sea, $1.owner) }
            }
            // Plunder the richest coast they can reach.
            let victims = plunderable(to, state).compactMap { t in state.owner(of: t).map { (t, $0) } }
            guard let (t, owner) = victims.max(by: { a, b in
                let ga = state.civs[a.1]!.gold, gb = state.civs[b.1]!.gold
                return ga != gb ? ga < gb : a.0 > b.0
            }) else { continue }
            let gold = min(state.civs[owner]!.gold, p.plunderGold)
            state.civs[owner]!.gold -= gold
            events.append(.piratesPlundered(civ: owner, territory: t, gold: gold))
        }
        // A new band, in waters where no ships ride and no navy patrols.
        if pirateFleets(in: state).count < p.maxFleets, Int(state.rng.next() % 100) < p.spawnPercent {
            let empty = map.seas.map(\.id).sorted().filter { s in
                !state.fleets.contains { $0.sea == s } && !patrolled(s, in: state)
            }
            if !empty.isEmpty {
                let sea = empty[Int(state.rng.next() % UInt64(empty.count))]
                let ships = p.baseShips + state.turn / max(1, p.roundsPerExtraShip)
                state.fleets.append(Fleet(sea: sea, owner: piratesID, ships: ships))
                state.fleets.sort { ($0.sea, $0.owner) < ($1.sea, $1.owner) }
                events.append(.piratesAppeared(sea: sea, ships: ships))
            }
        }
        return events
    }
}
