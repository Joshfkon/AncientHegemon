import HegemonCore
import SwiftUI

/// Picks how many of each unit type to send, within what's available.
struct UnitPicker: View {
    let available: UnitCounts
    @Binding var units: UnitCounts

    var body: some View {
        VStack(spacing: 2) {
            ForEach(UnitType.allCases, id: \.self) { type in
                if available[type] > 0 {
                    Stepper(value: Binding(get: { units[type] }, set: { units[type] = $0 }),
                            in: 0...available[type]) {
                        HStack(spacing: 6) {
                            UnitIcon(type: type).frame(width: 18, height: 18)
                            Text("\(type.rawValue.capitalized) \(units[type]) of \(available[type])")
                                .font(.callout.monospacedDigit())
                        }
                    }
                }
            }
        }
    }
}

/// Finishes an order started on the map: how many troops, which formation, whether the general
/// goes, and the odds if it means a battle.
struct OrderComposer: View {
    let session: GameSession
    let order: PendingOrder
    /// Called when the order is sent (with what to select next) or cancelled (nil).
    let done: (MapPick?) -> Void

    @State private var units = UnitCounts.zero
    @State private var withGeneral = false
    @State private var plan = BattlePlan()
    @State private var showPlan = false
    /// Chance of victory with each formation, recomputed when the force or plan changes.
    @State private var oddsByFormation: [FormationID: Double] = [:]

    private var engine: Engine { session.engine }
    private var state: GameState { session.state }
    private var human: CivilizationID { session.human! }

    private var available: UnitCounts {
        switch order {
        case let .march(from, _), let .embark(from, _):
            guard let army = state.armies[from], army.owner == human else { return .zero }
            let ready = army.units - (state.moved[from] ?? .zero)
            return UnitCounts(infantry: max(0, ready.infantry), archers: max(0, ready.archers),
                              cavalry: max(0, ready.cavalry))
        case let .land(sea, _):
            return state.fleet(of: human, in: sea)?.cargo ?? .zero
        }
    }

    private var destination: TerritoryID? {
        switch order {
        case let .march(_, to), let .land(_, to): to
        case .embark: nil
        }
    }

    private var isBattle: Bool {
        destination.map { engine.defenders(of: $0, against: human, state) != nil } ?? false
    }

    private var general: General? {
        guard case let .march(from, _) = order, let g = state.general(of: human, at: from),
              !state.generalsMoved.contains(g.id) else { return nil }
        return g
    }

    private var title: String {
        func place(_ t: String) -> String { engine.map.territory(t)?.name ?? engine.map.sea(t)?.name ?? t }
        switch order {
        case let .march(from, to): return "\(isBattle ? "Attack" : "March to") \(place(to)) from \(place(from))"
        case let .embark(from, sea): return "Board ships in the \(place(sea)) from \(place(from))"
        case let .land(sea, to): return "\(isBattle ? "Land and attack" : "Land in") \(place(to)) from the \(place(sea))"
        }
    }

    var body: some View {
        // The choices scroll; Cancel and the order itself stay put at the bottom.
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(title).font(.headline)
                    if let to = destination { destinationSummary(to) }
                    UnitPicker(available: available, units: $units)
                    if let general {
                        Toggle("\(general.name) leads (\(traitName(general.trait)))", isOn: $withGeneral).font(.callout)
                    }
                    if isBattle, destination != nil {
                        odds
                    }
                    if let warning = garrisonWarning {
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if isBattle, case .march = order {
                        DisclosureGroup(isExpanded: $showPlan) {
                            BattlePlanEditor(engine: engine, civ: human, state: state, units: units,
                                             general: withGeneral ? general : nil, plan: $plan, odds: oddsByFormation)
                                .padding(.top, 6)
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Battle plan").font(.subheadline.bold())
                                Text(planSummary).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.trailing, 4)
            }
            HStack {
                Button("Cancel") { done(nil) }.buttonStyle(.bordered)
                Spacer()
                Button(confirmLabel) { send() }
                    .buttonStyle(.borderedProminent)
                    .tint(isBattle ? .red : .accentColor)
                    .disabled(units.isEmpty)
            }
            .padding(.top, 4)
        }
        .onAppear {
            setDefaults()
            updateOdds()
        }
        .onChange(of: units) { _, _ in updateOdds() }
        .onChange(of: withGeneral) { _, _ in
            // Options the general brought leave with them.
            let leader = withGeneral ? general : nil
            if let f = plan.formation, !engine.formationAvailable(f, human, general: leader, in: state) { plan.formation = nil }
            if let st = plan.stratagem, !engine.stratagemAvailable(st, human, general: leader, in: state) { plan.stratagem = nil }
            updateOdds()
        }
        .onChange(of: plan.depth) { _, _ in updateOdds() }
        .onChange(of: plan.formation) { _, f in
            session.plannedOdds = oddsByFormation[f ?? engine.rules.battle.defaultFormation]
        }
        .onChange(of: plan.stratagem) { _, _ in updateOdds() }
    }

    /// Odds for every formation (landings fight in the army's standing formation).
    private func updateOdds() {
        guard isBattle, let to = destination else { oddsByFormation = [:]; return }
        let from: TerritoryID? = if case let .march(f, _) = order { f } else { nil }
        let amphibious = { if case .land = order { true } else { false } }()
        let chosen = plan.formation ?? engine.rules.battle.defaultFormation
        let leader = withGeneral ? general : nil
        let ids = from == nil ? [chosen] : engine.rules.battle.formations.map(\.id).filter {
            engine.formationAvailable($0, human, general: leader, in: state)
        }
        var odds: [FormationID: Double] = [:]
        for id in ids {
            odds[id] = engine.attackOdds(human, units: units, into: to, from: from, formation: id,
                                         depth: from == nil ? .deep : plan.depth,
                                         stratagem: from == nil ? nil : plan.stratagem,
                                         general: leader, amphibious: amphibious, in: state) ?? 0
        }
        oddsByFormation = odds
        session.plannedOdds = odds[chosen]
    }

    private var confirmLabel: String {
        switch order {
        case .march: isBattle ? "Attack" : "March"
        case .embark: "Board"
        case .land: isBattle ? "Land and attack" : "Land"
        }
    }

    @ViewBuilder private func destinationSummary(_ to: TerritoryID) -> some View {
        let t = engine.map.territory(to)!
        let crossing: String = switch order {
        case let .march(from, _): engine.map.crossing(between: from, and: to).map { " · across a \($0.rawValue)" } ?? ""
        case .land: " · from the sea"
        case .embark: ""
        }
        VStack(alignment: .leading, spacing: 2) {
            Text("\(t.terrain.rawValue.capitalized)\(crossing)").font(.caption).foregroundStyle(.secondary)
            if let d = engine.defenders(of: to, against: human, state) {
                HStack(spacing: 6) {
                    Text("Defended by \(Palette.name(d.owner, state)):")
                    if d.army.units.total > 0 { UnitRow(units: d.army.units, size: 12) }
                    if d.levy > 0 { Text("+ \(d.levy) militia") }
                    if let f = d.army.formation, f != engine.rules.battle.defaultFormation {
                        Text("in \(engine.rules.battle.formation(f)?.name ?? "")")
                    }
                }
                .font(.caption)
            }
        }
    }

    /// "Phalanx · Deep line · Straight fight".
    private var planSummary: String {
        let f = engine.rules.battle.formation(plan.formation ?? engine.rules.battle.defaultFormation)?.name ?? ""
        return [f, plan.depth == .deep ? "deep line" : "wide line", BattlePlanEditor.name(plan.stratagem).lowercased()]
            .joined(separator: " · ")
    }

    /// Marching everyone out leaves the land to its levy.
    private var garrisonWarning: String? {
        guard case let .march(from, _) = order, let army = state.armies[from], units.total > 0,
              units.total >= army.units.total else { return nil }
        let name = engine.map.territory(from)?.name ?? from
        let levy = engine.levy(at: from, state)
        let capital = engine.seat(of: human, in: state) == from
        return "This leaves \(name)\(capital ? ", your capital," : "") with no garrison"
            + (levy > 0 ? " (its people would raise \(levy) militia)." : ".")
    }

    /// The scouts' report: how the numbers compare, what favours the defender, and the officers'
    /// feeling about it. Deliberately no percentages.
    private var odds: some View {
        let p = oddsByFormation[plan.formation ?? engine.rules.battle.defaultFormation] ?? oddsByFormation.values.first ?? 0
        let outlook = Outlook(p)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Scouts' report").font(.subheadline.bold())
                Spacer()
                Text(outlook.word).font(.title3.bold()).foregroundStyle(outlook.color)
            }
            ForEach(scouting, id: \.self) { line in
                Text("• " + line).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var scouting: [String] {
        guard let to = destination, let d = engine.defenders(of: to, against: human, state) else { return [] }
        let defender = d.army
        var lines: [String] = []
        // Militia count for half: they're many but they're farmers.
        let ours = Double(max(1, units.total)), theirs = Double(max(1, defender.units.total)) + Double(d.levy) / 2
        let ratio = ours / theirs
        let numbers = switch ratio {
        case ..<0.5: "They greatly outnumber us."
        case 0.5..<0.8: "They outnumber us."
        case 0.8...1.25: "Their numbers are roughly the same as ours."
        case 1.25..<2: "We outnumber them."
        default: "We greatly outnumber them."
        }
        lines.append(numbers)
        if ratio < 1.6 { lines.append("Defenders hold the edge in an even fight.") }
        // How the two armies compare as they would actually fight.
        let leader = withGeneral ? general : nil
        let ourArmy = engine.battleArmy(human, units, plan: plan, general: leader, state)
        if let theirArmy = engine.defendingArmy(of: to, against: human, state) {
            if theirArmy.bronzePercent >= ourArmy.bronzePercent + 30 { lines.append("Their troops are better armed with bronze.") }
            if ourArmy.bronzePercent >= theirArmy.bronzePercent + 30 { lines.append("Our bronze gives us the edge.") }
            let ourDrill = ourArmy.unitPercent.values.reduce(0, +) + ourArmy.morale
            let theirDrill = theirArmy.unitPercent.values.reduce(0, +) + theirArmy.morale
            if theirDrill > ourDrill + 10 { lines.append("Their soldiers are better trained.") }
            if ourDrill > theirDrill + 10 { lines.append("Our soldiers are better trained.") }
            if theirArmy.units.archers > 0, units.cavalry == 0 { lines.append("Their archers will thin our ranks, and we have no cavalry.") }
            if theirArmy.general != nil, leader == nil { lines.append("A general leads them; none leads us.") }
            if leader != nil, theirArmy.general == nil { lines.append("Our general leads; they have none.") }
        }
        if d.levy > 0 {
            lines.append(defender.units.total == 0 ? "No soldiers, but the people will take up arms." : "The people will take up arms beside them.")
        }
        let walls = engine.fortification(at: to, state)
        if walls > 0 { lines.append("They are behind walls.") }
        let terrain = engine.map.territory(to)!.terrain
        if (engine.rules.battle.terrain[terrain]?.defensePercent ?? 0) > 0 {
            lines.append("The \(terrain.rawValue) favour the defender.")
        }
        switch order {
        case let .march(from, _):
            if let crossing = engine.map.crossing(between: from, and: to) { lines.append("We must cross a \(crossing.rawValue).") }
        case .land: lines.append("We must fight our way ashore.")
        case .embark: break
        }
        return lines
    }

    private func setDefaults() {
        if case let .march(from, _) = order, let army = state.armies[from] {
            plan = army.plan
            // A defensive stratagem is no way to attack.
            if plan.stratagem == .standFast { plan.stratagem = nil }
        }
        withGeneral = isBattle && general != nil
        switch order {
        case .embark(_, let sea):
            let fleet = state.fleet(of: human, in: sea)
            let room = fleet.map { $0.ships * engine.rules.ships.capacity - $0.cargo.total } ?? 0
            var left = room
            for type in [UnitType.infantry, .cavalry, .archers] {
                units[type] = min(left, available[type])
                left -= units[type]
            }
        case .march(_, let to) where !isBattle && state.owner(of: to) != human:
            // Claiming empty land takes one unit.
            let type = UnitType.allCases.first { available[$0] > 0 } ?? .infantry
            units = .zero
            units[type] = min(1, available[type])
        default:
            units = available
        }
    }

    private func send() {
        switch order {
        case let .march(from, to):
            if isBattle, state.armies[from]?.plan != plan {
                session.order(.setBattlePlan(territory: from, plan: plan))
            }
            if session.order(.move(from: from, to: to, units: units, general: withGeneral)) {
                done(.territory(to))
            }
        case let .embark(from, sea):
            if session.order(.embark(territory: from, sea: sea, units: units)) { done(.sea(sea)) }
        case let .land(sea, to):
            if session.order(.land(sea: sea, territory: to, units: units)) { done(.territory(to)) }
        }
    }
}

func traitName(_ trait: GeneralTrait) -> String {
    switch trait {
    case .tactician: "Tactician"
    case .cavalryCommander: "Cavalry Commander"
    case .cautious: "Cautious"
    case .reckless: "Reckless"
    }
}

/// A selected territory: what it holds, and what can be done there.
struct TerritoryPanel: View {
    let session: GameSession
    let territory: TerritoryID

    private var engine: Engine { session.engine }
    private var state: GameState { session.state }

    var body: some View {
        let human = session.human
        let mine = human != nil && state.owner(of: territory) == human
        VStack(alignment: .leading, spacing: 10) {
            TerritoryCard(id: territory, state: state, map: engine.map) {}
            if mine, session.isHumanTurn, let human {
                actions(human)
            }
        }
    }

    @ViewBuilder private func actions(_ human: CivilizationID) -> some View {
        let t = engine.map.territory(territory)!
        let army = state.armies[territory].flatMap { $0.owner == human ? $0 : nil }
        let home = engine.homeNetwork(of: human, in: state).contains(territory)
        if home, let strain = engine.supplyStrain(of: human, at: territory, in: state) {
            Text(strain.steps == 0 ? "Your capital." :
                 "In supply · \(strain.steps) steps from the capital"
                 + (strain.extraGrain > 0 ? " · each unit here eats \(strain.extraGrain) extra grain" : ""))
                .font(.caption).foregroundStyle(strain.extraGrain > 0 ? .orange : .secondary)
        }
        if let army {
            let ready = army.units - (state.moved[territory] ?? .zero)
            Text(ready.total > 0 ? "Tap a highlighted territory to march \(ready.total) ready units, or a sea with your ships to board."
                                 : "These troops have moved this turn.")
                .font(.caption).foregroundStyle(.secondary)
        }
        if home {
            Text("Recruit").font(.subheadline.bold())
            HStack {
                ForEach(UnitType.allCases, id: \.self) { type in
                    Button {
                        session.order(.recruit(territory: territory, unit: type, count: 1))
                    } label: {
                        VStack(spacing: 0) {
                            HStack(spacing: 3) {
                                UnitIcon(type: type).frame(width: 14, height: 14)
                                Text("+ \(type.rawValue.capitalized)").font(.caption.bold())
                            }
                            Text("\(engine.rules.stats(type).cost) gold").font(.caption2)
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
            if army != nil, state.general(of: human, at: territory) == nil {
                Button("Appoint a general (\(engine.rules.government.appointCost) gold)") {
                    session.order(.appointGeneral(territory: territory))
                }
                .buttonStyle(.bordered)
            }
            ForEach(t.seas, id: \.self) { sea in
                Button("Build a ship in the \(engine.map.sea(sea)?.name ?? sea) (\(engine.rules.ships.cost) gold)") {
                    session.order(.buildShips(territory: territory, sea: sea, count: 1))
                }
                .buttonStyle(.bordered)
                .font(.caption)
            }
            projects(human)
        } else {
            Text("Cut off from your capital: no recruiting here.").font(.caption).foregroundStyle(.orange)
        }
        if let army {
            // Rarely changed, so tucked away at the bottom.
            DisclosureGroup {
                BattlePlanEditor(engine: engine, civ: human, state: state, units: army.units,
                                 general: state.general(of: human, at: territory), plan: Binding(
                    get: { army.plan },
                    set: { session.order(.setBattlePlan(territory: territory, plan: $0)) }))
                    .padding(.top, 6)
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Defensive plan").font(.subheadline.bold())
                    let f = engine.rules.battle.formation(army.formation ?? engine.rules.battle.defaultFormation)?.name ?? ""
                    Text([f, army.plan.depth == .deep ? "deep line" : "wide line",
                          BattlePlanEditor.name(army.plan.stratagem).lowercased()].joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

extension TerritoryPanel {
    /// Projects: what's built, what's underway, and what can be started here.
    @ViewBuilder func projects(_ human: CivilizationID) -> some View {
        let land = state.land[territory]!
        let cs = state.civs[human]!
        Text("Build").font(.subheadline.bold())
        Text("In store: \(cs.gold) gold · \(cs.stock[.stone] ?? 0) stone · \(cs.stock[.timber] ?? 0) timber"
             + " (stone and timber pile up each harvest from your land and trade)")
            .font(.caption2).foregroundStyle(.secondary)
        if let site = land.construction {
            Text("\(projectName(site.kind)) under construction: \(site.turnsLeft) turn\(site.turnsLeft == 1 ? "" : "s") left.")
                .font(.caption)
        } else {
            ForEach(ProjectKind.allCases.filter { engine.canBuild($0, in: territory, state) }, id: \.self) { kind in
                let cost = engine.projectCost(kind, for: human, state)
                let affordable = cs.gold >= cost.gold && (cs.stock[.stone] ?? 0) >= cost.stone
                    && (cs.stock[.timber] ?? 0) >= cost.timber
                Button {
                    session.order(.build(territory: territory, project: kind))
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(projectName(kind)).font(.caption.bold())
                            Text(projectPurpose(kind)).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(([("\(cost.gold) gold", cost.gold), ("\(cost.stone) stone", cost.stone),
                               ("\(cost.timber) timber", cost.timber)].filter { $0.1 > 0 }.map(\.0)
                              + ["\(cost.turns) turns"]).joined(separator: " · "))
                            .font(.caption2.monospacedDigit())
                    }
                }
                .buttonStyle(.bordered)
                .disabled(!affordable)
            }
            if ProjectKind.allCases.allSatisfy({ !engine.canBuild($0, in: territory, state) }) {
                Text("Nothing more to build here.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// A selected sea: the fleets there, and how to use the player's.
struct FleetPanel: View {
    let session: GameSession
    let sea: SeaZoneID

    var body: some View {
        let state = session.state
        let name = session.engine.map.sea(sea)?.name ?? sea
        VStack(alignment: .leading, spacing: 6) {
            Text(name).font(.headline)
            let fleets = state.fleets.filter { $0.sea == sea }
            if fleets.isEmpty { Text("No ships here.").font(.caption).foregroundStyle(.secondary) }
            ForEach(fleets, id: \.owner) { fleet in
                HStack(spacing: 6) {
                    Circle().fill(Palette.color(fleet.owner, state)).frame(width: 8, height: 8)
                    Text("\(Palette.name(fleet.owner, state)): \(fleet.ships) ships, \(fleet.cargo.total) troops aboard")
                        .font(.caption)
                }
            }
            if let human = session.human, let mine = state.fleet(of: human, in: sea), session.isHumanTurn {
                let ready = mine.ships - mine.movedShips
                Text(ready > 0 ? "Tap a highlighted sea to sail \(ready) ships there\(mine.cargo.total > 0 ? ", or a coast to land the troops" : "")."
                               : mine.cargo.total > 0 ? "The ships have sailed this turn; the troops can still land on a highlighted coast."
                                                      : "These ships have sailed this turn.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
