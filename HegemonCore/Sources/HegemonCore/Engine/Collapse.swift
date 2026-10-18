/// The Late Bronze Age collapse: from round 12 the world gets steadily worse. Sea Peoples raid
/// the coasts, droughts spread beyond the river valleys, earthquakes bring down walls and
/// palaces, and trade routes break. Bronze wears out unless tin keeps flowing; iron doesn't.
extension Engine {
    /// How far the collapse has gone, 0–100.
    public func collapsePressure(_ state: GameState) -> Int {
        let c = rules.collapse
        guard state.turn > c.startRound else { return 0 }
        return min(100, (state.turn - c.startRound) * 100 / max(1, c.peakRound - c.startRound))
    }

    func collapseWeights(_ civ: CivilizationID, _ state: GameState) -> [(EventKind, Int)] {
        let pressure = collapsePressure(state)
        guard pressure > 0 else { return [] }
        let w = rules.collapse.weights
        let owned = state.territories(of: civ)
        let coasts = owned.filter { map.territory($0)!.isCoastal }.count
        let dry = !owned.contains { map.territory($0)!.has(.riverValley) }
        let rugged = owned.filter { [.hills, .mountains].contains(map.territory($0)!.terrain) }.count
        let routes = tradeRoutes(in: state).filter { $0.involves(civ) }.count
        let full: [(EventKind, Int)] = [
            (.seaPeoples, coasts * w.seaPeoplesPerCoast),
            (.drought, w.drought + (dry ? w.droughtNoRiver : 0)),
            (.earthquake, w.earthquake + rugged * w.earthquakePerRugged),
            (.tradeDisrupted, routes * w.tradeDisruptionPerRoute),
        ]
        return full.map { kind, weight in (kind, weight * pressure / 100) }
    }

    func strikeCollapse(_ kind: EventKind, _ civ: CivilizationID, _ state: inout GameState) -> [GameEvent] {
        let c = rules.collapse
        let owned = state.territories(of: civ)
        func pick<T>(_ items: [T]) -> T? {
            items.isEmpty ? nil : items[Int(state.rng.next() % UInt64(items.count))]
        }
        func report(_ t: TerritoryID?, _ amount: Int, partner: CivilizationID? = nil) -> GameEvent {
            .event(EventReport(kind: kind, civ: civ, territory: t, amount: amount, partner: partner))
        }

        switch kind {
        case .seaPeoples:
            // They come from the sea, burn what they take, and sail off if beaten.
            guard let target = pick(owned.filter { map.territory($0)!.isCoastal }) else { return [] }
            let size = c.seaPeoplesBase + collapsePressure(state) / max(1, c.seaPeoplesPressurePerExtra)
            let raiders = UnitCounts(infantry: size - size / 3, archers: size / 3)
            var events = [report(target, size)]
            events += raid(barbariansID, raiders, into: target, fallback: nil, approach: .amphibious, &state)
            if state.owner(of: target) == nil {
                events += state.land[target]!.improvements.sorted { $0.rawValue < $1.rawValue }.map {
                    .projectDestroyed(territory: target, project: $0)
                }
                state.land[target]!.improvements = []
            }
            return events

        case .drought:
            // The best farmland outside the river valleys withers first; the rivers hold out longest.
            let ranked = owned.sorted { a, b in
                let (ta, tb) = (map.territory(a)!, map.territory(b)!)
                return (ta.has(.riverValley) ? 1 : 0, -ta.grain, a) < (tb.has(.riverValley) ? 1 : 0, -tb.grain, b)
            }
            let struck = ranked.prefix(c.droughtTerritories)
            guard let first = struck.first else { return [] }
            for t in struck { state.harvestPercent[t] = min(state.harvestPercent[t] ?? 100, c.droughtGrainPercent) }
            return [report(first, struck.count)]

        case .earthquake:
            // Rugged land shakes hardest; the most built-up place there takes the blow.
            let rugged = owned.filter { [.hills, .mountains].contains(map.territory($0)!.terrain) }
            guard let target = pick(rugged.isEmpty ? owned : rugged) else { return [] }
            var events = [report(target, c.earthquakePopulation)]
            let lost = min(c.earthquakePopulation, state.population(of: target) - rules.economy.minPopulation)
            state.land[target]!.population -= max(0, lost)
            if let site = state.land[target]!.construction {
                state.land[target]!.construction = nil
                events.append(.projectDestroyed(territory: target, project: site.kind))
            } else if let built = pick(state.land[target]!.improvements.sorted { $0.rawValue < $1.rawValue }) {
                state.land[target]!.improvements.remove(built)
                events.append(.projectDestroyed(territory: target, project: built))
            }
            return events

        case .tradeDisrupted:
            guard let route = pick(tradeRoutes(in: state).filter { $0.involves(civ) }) else { return [] }
            state.disruptedRoutes[route.partners] = state.turn + c.disruptionRounds - 1
            return [report(nil, c.disruptionRounds, partner: route.partner(of: civ))]

        default:
            return []
        }
    }

    /// Bronze dulls and breaks: a share is lost every harvest.
    func wearBronze(_ civ: CivilizationID, _ state: inout GameState) {
        let bronze = state.civs[civ]!.bronze
        state.civs[civ]!.bronze -= min(bronze, (bronze * rules.collapse.bronzeWearPercent + 99) / 100)
    }
}
