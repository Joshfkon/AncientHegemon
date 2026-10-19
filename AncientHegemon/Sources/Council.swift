import HegemonCore
import SwiftUI

/// The ruler's council: four advisors, each reading the realm and saying the one thing that
/// matters most in their field right now. Their advice points at a place on the map, or a tab.
struct Advisor: Identifiable {
    enum Role: String, CaseIterable { case general, steward, envoy, priest }
    enum Mood { case calm, warning, alarm }
    enum Target: Equatable { case territory(TerritoryID), diplomacy, realm }

    let role: Role
    let name: String
    let advice: String
    let mood: Mood
    let target: Target?
    var id: Role { role }

    var title: String {
        switch role {
        case .general: "General"
        case .steward: "Steward"
        case .envoy: "Envoy"
        case .priest: "High priest"
        }
    }

    var symbol: String {
        switch role {
        case .general: "shield.lefthalf.filled"
        case .steward: "scroll.fill"
        case .envoy: "person.2.wave.2.fill"
        case .priest: "sun.max.fill"
        }
    }

    static func names(_ civ: CivilizationID) -> [Role: String] {
        switch civ {
        case "egypt": [.general: "Horemheb", .steward: "Vizier Paser", .envoy: "Amenemope", .priest: "Wennefer"]
        case "greece": [.general: "Diomedes", .steward: "Eumaeus", .envoy: "Nestor", .priest: "Kassandra"]
        case "italia": [.general: "Turnus", .steward: "Lars", .envoy: "Latinus", .priest: "Tages the augur"]
        case "mesopotamia": [.general: "Ninurta-apil", .steward: "Belshunu", .envoy: "Ili-pada", .priest: "Enlil-nadin"]
        default: [.general: "The general", .steward: "The steward", .envoy: "The envoy", .priest: "The priest"]
        }
    }
}

enum Council {
    /// `quick` skips the general's battle odds, for the toolbar badge that only counts alarms.
    @MainActor static func advice(_ session: GameSession, quick: Bool = false) -> [Advisor] {
        guard let civ = session.human, let cs = session.state.civs[civ] else { return [] }
        let engine = session.engine, state = session.state, map = engine.map
        let names = Advisor.names(civ)
        func place(_ t: TerritoryID) -> String { map.territory(t)?.name ?? t }
        func who(_ c: CivilizationID) -> String { Palette.name(c, state) }
        var council: [Advisor] = []

        // The general: the gravest threat to our land, else the best fight on offer.
        do {
            let threats = ThreatMap(for: civ, in: state, map: map, engine: engine)
            let danger = threats.threat.map { (t: $0.key, n: $0.value, g: threats.garrison[$0.key] ?? 0) }
                .filter { $0.n > $0.g }
                .max { ($0.n - $0.g, $1.t) < ($1.n - $1.g, $0.t) }
            if let d = danger {
                let raiders = map.landNeighbors(of: d.t).contains { state.armies[$0]?.owner == barbariansID }
                council.append(Advisor(role: .general, name: names[.general]!,
                    advice: "\(d.n) \(raiders ? "raiders" : "enemy troops") could strike \(place(d.t)), held by \(d.g). Reinforce it, or wall it.",
                    mood: .alarm, target: .territory(d.t)))
            } else if !quick, let best = bestAttack(civ, engine, state) {
                council.append(Advisor(role: .general, name: names[.general]!,
                    advice: "The army in \(place(best.from)) could take \(place(best.to))\(best.owner.map { " from \(who($0))" } ?? ""). Our scouts like our chances.",
                    mood: .calm, target: .territory(best.from)))
            } else {
                council.append(Advisor(role: .general, name: names[.general]!,
                    advice: "The borders are quiet. A larger army would let us strike when the moment comes.",
                    mood: .calm, target: engine.seat(of: civ, in: state).map(Advisor.Target.territory)))
            }
        }

        // The steward: food first, then money.
        if let e = session.economy {
            if e.grainBalance < 0 {
                let turns = max(1, e.granary / max(1, -e.grainBalance) + 1)
                council.append(Advisor(role: .steward, name: names[.steward]!,
                    advice: "We eat \(-e.grainBalance) more grain than we grow. The granary lasts \(turns) turn\(turns == 1 ? "" : "s"); then people starve. Farms, or fewer mouths.",
                    mood: turns <= 2 ? .alarm : .warning, target: .realm))
            } else if e.netIncome < 0 {
                council.append(Advisor(role: .steward, name: names[.steward]!,
                    advice: "The army's pay (\(e.pay) gold) outruns our income. When the treasury is empty, the unpaid go home.",
                    mood: .warning, target: .realm))
            } else if let cut = e.cutOff.first {
                council.append(Advisor(role: .steward, name: names[.steward]!,
                    advice: "\(place(cut)) is cut off from the capital: no taxes, no recruits, and its garrison wastes away. Reopen the road.",
                    mood: .warning, target: .territory(cut)))
            } else if cs.gold >= 40 {
                council.append(Advisor(role: .steward, name: names[.steward]!,
                    advice: "The treasury holds \(cs.gold) gold doing nothing. Build, raise troops, or adorn this hall.",
                    mood: .calm, target: .realm))
            } else {
                council.append(Advisor(role: .steward, name: names[.steward]!,
                    advice: "We grow \(e.grainBalance) grain more than we eat and gain \(e.netIncome) gold a turn. The storehouses are in order.",
                    mood: .calm, target: .realm))
            }
        }

        // The envoy: offers waiting, tribes to win, peace worth making.
        do {
            let offers = state.peaceOffers.filter { $0.to == civ }.map(\.from).sorted()
            let tribes = state.territories(of: civ).flatMap { map.landNeighbors(of: $0) }
                .filter { engine.tribe(at: $0, for: civ, in: state) != nil && !state.parleyed.contains($0) }
            let likely = Set(tribes).sorted().max { a, b in
                (engine.giftChance(at: a, for: civ, in: state), b) < (engine.giftChance(at: b, for: civ, in: state), a)
            }
            if let from = offers.first {
                council.append(Advisor(role: .envoy, name: names[.envoy]!,
                    advice: "\(who(from)) offers peace\(offers.count > 1 ? ", and \(offers.count - 1) more besides" : ""). Peace opens trade.",
                    mood: .warning, target: .diplomacy))
            } else if let t = likely, engine.giftChance(at: t, for: civ, in: state) >= 55 {
                let cost = engine.giftCost(at: t, in: state)
                council.append(Advisor(role: .envoy, name: names[.envoy]!,
                    advice: "The tribe in \(place(t)) would likely take our gifts (\(cost) gold) and swear to us. Cheaper than a war.",
                    mood: .calm, target: .territory(t)))
            } else if let lacking = [Resource.tin, .horses, .timber].first(where: { (session.economy?.resources[$0] ?? 0) == 0 }),
                      let source = engine.sources(of: lacking, for: civ, in: state).first(where: { $0.owner.map { state.atWar(civ, $0) } ?? false }),
                      let owner = source.owner {
                council.append(Advisor(role: .envoy, name: names[.envoy]!,
                    advice: "We have no \(lacking.rawValue), and \(who(owner)) holds it in \(place(source.territory)). Make peace and it will come by trade.",
                    mood: .calm, target: .diplomacy))
            } else {
                council.append(Advisor(role: .envoy, name: names[.envoy]!,
                    advice: "Our neighbours keep their counsel. Trade flows wherever we are at peace.",
                    mood: .calm, target: .diplomacy))
            }
        }

        // The priest: omens, the gods' mood, the throne's future.
        do {
            let g = engine.rules.government
            if cs.omen {
                council.append(Advisor(role: .priest, name: names[.priest]!,
                    advice: "The omens are dark. No army of ours may attack this turn.", mood: .alarm, target: nil))
            } else if cs.legitimacy < 40 {
                council.append(Advisor(role: .priest, name: names[.priest]!,
                    advice: "The people mutter against the throne (legitimacy \(cs.legitimacy)). Lower taxes, bring luxuries, or win a battle.",
                    mood: .warning, target: .realm))
            } else if cs.government == .monarchy, cs.ruler.age >= 55,
                      cs.heir.map({ $0.age < g.adultAge }) ?? true || cs.legitimacy + engine.successionEase(of: civ, in: state) < g.minSmoothLegitimacy {
                council.append(Advisor(role: .priest, name: names[.priest]!,
                    advice: "\(cs.ruler.name) is \(cs.ruler.age). If the gods call him now, the succession will be contested. A splendid court steadies a new king.",
                    mood: .warning, target: nil))
            } else if engine.collapsePressure(state) > 0 {
                council.append(Advisor(role: .priest, name: names[.priest]!,
                    advice: "I have seen burning cities in the smoke. Sea Peoples and droughts will come; wall the coasts and fill the granaries.",
                    mood: .warning, target: nil))
            } else {
                council.append(Advisor(role: .priest, name: names[.priest]!,
                    advice: "The gods smile on \(who(civ)). Their favour will not last forever; the age is ending.",
                    mood: .calm, target: nil))
            }
        }
        return council
    }

    /// The likeliest win for one of our armies against a neighbour we may attack.
    @MainActor private static func bestAttack(_ civ: CivilizationID, _ engine: Engine,
                                              _ state: GameState) -> (from: TerritoryID, to: TerritoryID, owner: CivilizationID?)? {
        var best: (TerritoryID, TerritoryID, CivilizationID?, Double)?
        for (from, units) in state.armies(of: civ) where units.total > 1 {
            for to in engine.map.landNeighbors(of: from) {
                if let owner = state.owner(of: to), owner == civ || state.atPeace(civ, owner) { continue }
                guard engine.defenders(of: to, against: civ, state) != nil else { continue }
                let p = engine.attackOdds(civ, units: units, into: to, from: from, samples: 6, in: state) ?? 0
                if p >= 0.7, best.map({ p > $0.3 }) ?? true { best = (from, to, state.owner(of: to), p) }
            }
        }
        return best.map { ($0.0, $0.1, $0.2) }
    }
}
