import HegemonCore
import SwiftUI

/// Why things happen to the player, in a sentence: read from the state just before an event
/// (what led to it). Every setback should say what caused it, so outcomes feel earned, not random.
struct Why {
    let engine: Engine
    let me: CivilizationID

    private func peopleName(_ k: CivilizationID, _ s: GameState) -> String {
        s.kingdoms[k].map { $0.name } ?? "they"
    }

    /// A vassal rose (or slipped away): the lapsed oath, or what made it restless.
    func vassalFreed(_ homeland: TerritoryID, before: GameState, after: GameState) -> String? {
        let k = kingdomID(homeland)
        if after.civs[me]?.eliminated ?? true { return "Your realm has fallen" }
        if let sworn = engine.lapsedOath(of: k, in: before) {
            let ruler = before.civs[me]?.ruler.name ?? "your new ruler"
            return "They swore to \(sworn), not to \(ruler), and would not renew their oath"
        }
        let odds = engine.revoltOdds(of: k, in: before)
        var parts: [String] = []
        if odds.unwatched > 0 { parts.append("none of your troops were near") }
        if odds.weakThrone > 0 { parts.append("your legitimacy (\(before.civs[me]?.legitimacy ?? 0)) is too low to awe them") }
        if odds.illWill > 0 { parts.append("they resent you (regard \(engine.attitude(of: k, toward: me, in: before)))") }
        guard !parts.isEmpty else { return nil }
        return "They rose because " + Self.join(parts)
    }

    func levyRefused(_ homeland: TerritoryID, before: GameState) -> String {
        let k = kingdomID(homeland)
        let regard = engine.attitude(of: k, toward: me, in: before)
        return "Vassals answer levies as loyally as they feel: regard \(regard), and every levy is resented"
    }

    func starvation(population: Int, units: Int, before: GameState) -> String {
        let lost = [population > 0 ? "\(population) people" : nil, units > 0 ? "\(units) soldiers" : nil].compactMap { $0 }
        return "Hunger: \(Self.join(lost)) lost. Your granary was empty and the harvest fell short of what your people and army eat"
    }

    func outOfSupply(_ t: TerritoryID, units: Int) -> String {
        let place = engine.map.territory(t)?.name ?? t
        return "\(units) soldier\(units == 1 ? "" : "s") lost at \(place): no road home to your capital carries their grain"
    }

    func unpaid(_ deserted: Int) -> String {
        "The treasury couldn't pay \(deserted) soldier\(deserted == 1 ? "" : "s") beyond your standing army, so they went home"
    }

    /// Why a trade with a kingdom lapsed.
    func tradeEnded(_ homeland: TerritoryID, before: GameState, after: GameState) -> String {
        let k = kingdomID(homeland)
        if after.kingdoms[k] == nil { return "The kingdom is gone" }
        if let t = before.kingdomTrades.first(where: { $0.kingdom == k && $0.civ == me }),
           (before.civs[me]?.gold ?? 0) < t.gold { return "Your treasury couldn't pay, and they resent it" }
        return "Their land no longer yields what they promised"
    }

    /// Kingdoms whose open markets closed to us between two states, and why.
    func marketsClosed(before: GameState, after: GameState) -> [(homeland: TerritoryID, why: String)] {
        before.kingdoms.keys.sorted().compactMap { k in
            guard engine.marketOpen(k, to: me, in: before), !engine.marketOpen(k, to: me, in: after),
                  let kingdom = after.kingdoms[k] else { return nil }
            let regard = engine.attitude(of: k, toward: me, in: after)
            let why: String
            if let lord = kingdom.overlord, lord != me {
                why = "They now answer to \(Palette.name(lord, after)), and trade only with their overlord"
            } else if regard < engine.attitude(of: k, toward: me, in: before) - 20 {
                why = "You attacked them, or theirs: regard \(regard)"
            } else {
                why = "They no longer regard you well enough to trade (regard \(regard))"
            }
            return (kingdom.homeland, why)
        }
    }

    // MARK: Warnings

    struct Warning: Identifiable {
        let id: String
        let icon: String
        let text: String
        let territory: TerritoryID?
    }

    /// What may go wrong soon, so a blow, if it comes, was foreseen.
    func warnings(_ s: GameState) -> [Warning] {
        guard let cs = s.civs[me], !cs.eliminated else { return [] }
        var out: [Warning] = []
        let vassals = engine.vassals(of: me, in: s)
        // Vassals restless enough to rise.
        for k in vassals {
            let odds = engine.revoltOdds(of: k, in: s)
            guard odds.total >= 8, let home = s.kingdoms[k]?.homeland else { continue }
            var parts: [String] = []
            if odds.unwatched > 0 { parts.append("no troops of yours nearby") }
            if odds.weakThrone > 0 { parts.append("legitimacy \(cs.legitimacy)") }
            if odds.illWill > 0 { parts.append("they resent you") }
            out.append(Warning(id: "revolt-\(k)", icon: "flame.fill",
                               text: "\(peopleName(k, s).capitalizedFirst) may rise (\(odds.total)% a round): \(Self.join(parts))",
                               territory: home))
        }
        // An old ruler: each vassal must swear again to the next.
        if !vassals.isEmpty, cs.ruler.age >= 60 {
            let doubtful = vassals.filter { engine.renewChance(of: $0, in: s) < 70 }
            let names = doubtful.prefix(3).map { peopleName($0, s) }
            out.append(Warning(id: "succession", icon: "hourglass",
                               text: "\(cs.ruler.name) is \(cs.ruler.age). When a new ruler takes the throne, each vassal must swear again"
                                + (names.isEmpty ? "" : "; \(Self.join(names)) may refuse"),
                               territory: nil))
        }
        // Armies with no road home: they lose a soldier a turn.
        for t in s.territories(of: me).sorted() where engine.supplySteps(of: me, to: t, in: s) == nil {
            guard let army = s.armies[t], army.owner == me, army.units.total > 0 else { continue }
            out.append(Warning(id: "supply-\(t)", icon: "exclamationmark.triangle.fill",
                               text: "Your army at \(engine.map.territory(t)?.name ?? t) has no road home: it loses a soldier each turn",
                               territory: t))
        }
        // Too far ahead: the world bands together.
        if engine.menace(in: s) == me {
            out.append(Warning(id: "feared", icon: "eye.fill",
                               text: "The world fears you: rival courts will make common cause against you, and kingdoms' regard for you sinks (markets may close)",
                               territory: nil))
        }
        // The turning of the age.
        let until = engine.collapseRounds(s).start + 1 - s.turn
        if (1...3).contains(until) {
            out.append(Warning(id: "collapse", icon: "sailboat.fill",
                               text: "The collapse begins in \(until) round\(until == 1 ? "" : "s"). Fill the granaries; keep tin flowing",
                               territory: nil))
        }
        return out
    }

    static func join(_ parts: [String]) -> String {
        switch parts.count {
        case 0: ""
        case 1: parts[0]
        default: parts.dropLast().joined(separator: ", ") + " and " + parts.last!
        }
    }
}
