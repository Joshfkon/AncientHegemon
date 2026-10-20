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
    /// A march two steps along a road: the land it passes through on the way.
    var via: TerritoryID?
    /// Called when the order is sent (with what to select next) or cancelled (nil).
    let done: (MapPick?) -> Void

    @State private var units = UnitCounts.zero
    @State private var withGeneral = false
    @State private var plan = BattlePlan()
    /// Chance of victory with each formation, recomputed when the force or plan changes.
    @State private var oddsByFormation: [FormationID: Double] = [:]
    /// Other armies and fleets sent to join this attack (all their ready troops).
    @State private var joined: Set<AssaultGroup.Source> = []

    private var engine: Engine { session.engine }
    private var state: GameState { session.state }
    private var human: CivilizationID { session.human! }

    private var available: UnitCounts {
        switch order {
        case let .march(from, _), let .embark(from, _), let .seaAssault(from, _, _):
            guard let army = state.armies[from], army.owner == human else { return .zero }
            // Through a road, only troops that haven't already taken a road step can go on.
            let ready = army.units - (state.moved[from] ?? .zero) - (via != nil ? state.roadMoved[from] ?? .zero : .zero)
            return UnitCounts(infantry: max(0, ready.infantry), archers: max(0, ready.archers),
                              cavalry: max(0, ready.cavalry))
        case let .land(sea, _):
            return state.fleet(of: human, in: sea)?.cargo ?? .zero
        }
    }

    private var destination: TerritoryID? {
        switch order {
        case let .march(_, to), let .land(_, to), let .seaAssault(_, to, _): to
        case .embark: nil
        }
    }

    /// The sea troops come ashore from, for landings and sea assaults.
    private var landingSea: SeaZoneID? {
        switch order {
        case let .land(sea, _): sea
        case let .seaAssault(_, _, route): route.land
        default: nil
        }
    }

    /// Troops the ships can carry on a sea assault.
    private var seaRoom: Int? {
        if case let .seaAssault(_, _, route) = order { return route.room }
        return nil
    }

    /// Who could join a land attack: other armies of ours next to the target with troops ready,
    /// and our fleets with troops aboard in its seas (where no enemy ships bar the way).
    private var helpers: [AssaultGroup] {
        guard case let .march(from, to) = order, isBattle, let t = engine.map.territory(to) else { return [] }
        var result: [AssaultGroup] = []
        for n in engine.map.landNeighbors(of: to).sorted() where n != from {
            guard let army = state.armies[n], army.owner == human else { continue }
            let ready = army.units - (state.moved[n] ?? .zero)
            let free = UnitCounts(infantry: max(0, ready.infantry), archers: max(0, ready.archers), cavalry: max(0, ready.cavalry))
            if !free.isEmpty { result.append(AssaultGroup(.land(n), free)) }
        }
        for sea in t.seas.sorted() {
            guard let fleet = state.fleet(of: human, in: sea), !fleet.cargo.isEmpty,
                  !state.fleets.contains(where: { $0.sea == sea && $0.ships > 0 && state.atWar(human, $0.owner) }) else { continue }
            result.append(AssaultGroup(.sea(sea), fleet.cargo))
        }
        return result
    }

    private var joining: [AssaultGroup] { helpers.filter { joined.contains($0.source) } }

    /// The whole host: this army and everyone joining it.
    private var host: UnitCounts { joining.reduce(units) { $0 + $1.units } }

    /// The camp a siege would be laid from, if the target is a walled town we could besiege.
    private var siegeCamp: TerritoryID? {
        guard case let .march(from, to) = order, engine.canBesiege(to, from: from, by: human, state) else { return nil }
        return from
    }

    private var isBattle: Bool {
        destination.map { engine.defenders(of: $0, against: human, state) != nil } ?? false
    }

    /// Three or more to one: no need for the battlefield (it's still a tap away).
    private var overwhelming: Bool {
        guard case let .march(_, to) = order, isBattle, let d = engine.defenders(of: to, against: human, state) else { return false }
        return host.total >= 3 * max(1, d.army.units.total + d.levy)
    }

    private var general: General? {
        guard case let .march(from, _) = order, let g = state.general(of: human, at: from),
              !state.generalsMoved.contains(g.id) else { return nil }
        return g
    }

    private var title: String {
        func place(_ t: String) -> String { engine.map.territory(t)?.name ?? engine.map.sea(t)?.name ?? t }
        switch order {
        case let .march(from, to):
            if let via { return "\(isBattle ? "Attack" : "March to") \(place(to)) by road through \(place(via))" }
            if !engine.map.areLandAdjacent(from, to), let human = session.human,
               let vassal = engine.vassalPassage(from, to, for: human, in: state) {
                return "\(isBattle ? "Attack" : "March to") \(place(to)) through your vassal \(place(vassal))"
            }
            return "\(isBattle ? "Attack" : "March to") \(place(to)) from \(place(from))"
        case let .embark(from, sea): return "Board ships in the \(place(sea)) from \(place(from))"
        case let .land(sea, to): return "\(isBattle ? "Land and attack" : "Land in") \(place(to)) from the \(place(sea))"
        case let .seaAssault(from, to, _): return "\(isBattle ? "Sail and attack" : "Sail to") \(place(to)) from \(place(from))"
        }
    }

    var body: some View {
        // The choices scroll; Cancel and the order itself stay put at the bottom.
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(title).font(.headline)
                    if let to = destination { destinationSummary(to) }
                    if case let .seaAssault(_, _, route) = order {
                        let water = route.board == route.land
                            ? "Your ships in the \(engine.map.sea(route.board)?.name ?? route.board) carry them straight across."
                            : "Your ships board in the \(engine.map.sea(route.board)?.name ?? route.board), sail into the \(engine.map.sea(route.land)?.name ?? route.land), and land."
                        Label(water + " Room for \(route.room).", systemImage: "sailboat.fill")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    UnitPicker(available: available, units: $units)
                    if let room = seaRoom, units.total > room {
                        Label("Only \(room) fit aboard.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    if let general {
                        Toggle("\(general.name) leads (\(traitName(general.trait)))", isOn: $withGeneral).font(.callout)
                    }
                    if !helpers.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Join the attack").font(.subheadline.bold())
                            ForEach(helpers, id: \.source) { g in
                                Toggle(isOn: Binding(get: { joined.contains(g.source) },
                                                     set: { if $0 { joined.insert(g.source) } else { joined.remove(g.source) } })) {
                                    HStack(spacing: 6) {
                                        Image(systemName: { if case .sea = g.source { "sailboat.fill" } else { "figure.walk" } }())
                                        Text(sourceName(g.source)).font(.callout)
                                        UnitRow(units: g.units, size: 11).font(.caption)
                                    }
                                }
                            }
                            Text("They strike together as one host; if beaten, each falls back where it came from.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    if siegeCamp != nil {
                        Label("Walled. You can lay siege instead: the town is cut off, starves, and its walls weaken every round you stay. Storm it when it's ready.",
                              systemImage: "shield.lefthalf.filled.slash")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if isBattle, destination != nil {
                        odds
                    }
                    if let sea = landingSea,
                       let enemy = state.fleets.first(where: { $0.sea == sea && $0.ships > 0 && state.atWar(human, $0.owner) }) {
                        Label("\(Palette.name(enemy.owner, state))'s \(enemy.ships) ship\(enemy.ships == 1 ? "" : "s") guard these waters: your fleet must beat them at sea before anyone lands.",
                              systemImage: "sailboat.fill")
                            .font(.caption).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let warning = garrisonWarning {
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if isBattle, case .march = order {
                        Label(overwhelming ? "You outnumber them three to one or more: attack at once, or plan it on the battlefield."
                                           : "You'll choose your battle plan on the field.", systemImage: "flag.2.crossed")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.trailing, 4)
            }
            HStack {
                Button("Cancel") { done(nil) }.buttonStyle(.bordered)
                Spacer()
                if let camp = siegeCamp {
                    Button("Lay siege") {
                        guard case let .march(_, to) = order else { return }
                        if session.order(.besiege(territory: to, from: camp)) {
                            SoundBoard.shared.play(.wardrums, volume: 0.5)
                            done(.territory(to))
                        }
                    }
                    .buttonStyle(.bordered)
                }
                if overwhelming {
                    Button("Battlefield") { send() }.buttonStyle(.bordered)
                    Button("Attack") { quickAttack() }
                        .buttonStyle(.borderedProminent).tint(.red)
                        .disabled(units.isEmpty)
                } else {
                    Button(confirmLabel) { send() }
                        .buttonStyle(.borderedProminent)
                        .tint(isBattle ? .red : .accentColor)
                        .disabled(units.isEmpty || units.total > (seaRoom ?? .max))
                }
            }
            .padding(.top, 4)
        }
        .onAppear {
            setDefaults()
            updateOdds()
        }
        .onChange(of: units) { _, _ in updateOdds() }
        .onChange(of: joined) { _, _ in updateOdds() }
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
        let amphibious = { switch order { case .land, .seaAssault: true; default: false } }()
        let chosen = plan.formation ?? engine.rules.battle.defaultFormation
        let leader = withGeneral ? general : nil
        let ids = from == nil ? [chosen] : engine.rules.battle.formations.map(\.id).filter {
            engine.formationAvailable($0, human, general: leader, in: state)
        }
        var odds: [FormationID: Double] = [:]
        for id in ids {
            odds[id] = engine.attackOdds(human, units: host, into: to, from: from, formation: id,
                                         depth: from == nil ? .deep : plan.depth,
                                         stratagem: from == nil ? nil : plan.stratagem,
                                         general: leader, amphibious: amphibious, in: state) ?? 0
        }
        oddsByFormation = odds
        session.plannedOdds = odds[chosen]
    }

    private var confirmLabel: String {
        switch order {
        case .march: isBattle ? "To the battlefield" : "March"
        case .embark: "Board"
        case .land: isBattle ? "Land and attack" : "Land"
        case .seaAssault: isBattle ? "Sail and attack" : "Sail"
        }
    }

    @ViewBuilder private func destinationSummary(_ to: TerritoryID) -> some View {
        let t = engine.map.territory(to)!
        let crossing: String = switch order {
        case let .march(from, _): engine.map.crossing(between: from, and: to).map { " · across a \($0.rawValue)" } ?? ""
        case .land, .seaAssault: " · from the sea"
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
        guard let to = destination else { return [] }
        let from: TerritoryID? = if case let .march(f, _) = order { f } else { nil }
        return Scouts.report(engine: engine, state: state, civ: human, units: units, plan: plan,
                             general: withGeneral ? general : nil, to: to, from: from)
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
        case .seaAssault(_, _, let route):
            // As many as fit, foot first.
            var left = route.room
            units = .zero
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

    /// Straight in, with the army's standing battle plan.
    private func quickAttack() {
        guard case let .march(start, to) = order, let from = firstLeg(start) else { return }
        SoundBoard.shared.play(.roar, volume: 0.6)
        let sent = joining.isEmpty
            ? session.order(.move(from: from, to: to, units: units, general: withGeneral))
            : session.order(.assault(territory: to, groups: [AssaultGroup(.land(from), units)] + joining,
                                     general: withGeneral ? from : nil))
        if sent { done(.territory(to)) }
    }

    private func sourceName(_ source: AssaultGroup.Source) -> String {
        switch source {
        case .land(let t): "From " + (engine.map.territory(t)?.name ?? t)
        case .sea(let s): "Landing from the " + (engine.map.sea(s)?.name ?? s)
        }
    }

    /// For a road march, takes the first step to `via` and returns where the army now stands.
    private func firstLeg(_ from: TerritoryID) -> TerritoryID? {
        guard let via else { return from }
        return session.order(.move(from: from, to: via, units: units, general: withGeneral)) ? via : nil
    }

    private func send() {
        switch order {
        case let .march(start, to):
            guard let from = firstLeg(start) else { return }
            // Partway along the road: if the last step can't be taken, the army stays where it got to.
            defer { if via != nil, session.message != nil { done(.territory(from)) } }
            if isBattle {
                // The plan is made on the battlefield, with both armies in view.
                Feedback.select()
                session.muster = Muster(from: from, to: to, units: units, general: withGeneral, joining: joining)
                done(.territory(to))
                return
            }
            if session.order(.move(from: from, to: to, units: units, general: withGeneral)) {
                done(.territory(to))
            }
        case let .embark(from, sea):
            if session.order(.embark(territory: from, sea: sea, units: units)) { done(.sea(sea)) }
        case let .land(sea, to):
            if session.order(.land(sea: sea, territory: to, units: units)) { done(.territory(to)) }
        case let .seaAssault(from, to, route):
            // Board, sail if the target is a sea further, then land. Each step is a normal order,
            // so a sea battle on the way can stop it.
            guard session.order(.embark(territory: from, sea: route.board, units: units)) else { return }
            if route.board != route.land, let fleet = state.fleet(of: human, in: route.board) {
                let ready = fleet.ships - fleet.movedShips
                guard session.order(.moveFleet(from: route.board, to: route.land, ships: ready, cargo: fleet.cargo)) else { return }
                guard state.fleet(of: human, in: route.land) != nil else {
                    done(.sea(route.board))  // beaten at sea: the fleet fell back
                    return
                }
            }
            let aboard = state.fleet(of: human, in: route.land)?.cargo ?? .zero
            var landing = units
            for type in UnitType.allCases { landing[type] = min(landing[type], aboard[type]) }
            guard !landing.isEmpty else { done(.sea(route.land)); return }
            if session.order(.land(sea: route.land, territory: to, units: landing)) { done(.territory(to)) }
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
    @State private var disbanding = false
    @State private var toDisband = UnitCounts.zero

    private var engine: Engine { session.engine }
    private var state: GameState { session.state }

    var body: some View {
        let human = session.human
        let mine = human != nil && state.owner(of: territory) == human
        VStack(alignment: .leading, spacing: 10) {
            TerritoryCard(id: territory, state: state, map: engine.map, engine: engine) {}
            if mine, session.isHumanTurn, let human {
                actions(human)
            }
            if state.owner(of: territory) == nil, session.isHumanTurn, let human {
                TribeTalks(session: session, territory: territory, civ: human)
            }
        }
    }

    /// Troops the player has raised here since their turn began (the map's "+1" marks).
    private func raisedThisTurn(_ human: CivilizationID) -> UnitCounts {
        var units = UnitCounts.zero
        for mark in session.marks {
            if case let .raised(t, civ, unit, count) = mark, t == territory, civ == human { units[unit] += count }
        }
        return units
    }

    @ViewBuilder private func actions(_ human: CivilizationID) -> some View {
        let t = engine.map.territory(territory)!
        let army = state.armies[territory].flatMap { $0.owner == human ? $0 : nil }
        let home = engine.homeNetwork(of: human, in: state).contains(territory)
        if home, let steps = engine.supplySteps(of: human, to: territory, in: state) {
            let haul = engine.haul(of: human, to: territory, in: state)
            let extra = haul?.extraGrain ?? 0
            Text(steps == 0 ? "Your capital." : "In supply · \(steps) step\(steps == 1 ? "" : "s") from the capital"
                 + (extra > 0 ? " · grain is carted \(haul!.steps) steps overland, so each unit here eats \(extra) extra (roads or a sea route would carry it free)" : ""))
                .font(.caption).foregroundStyle(extra > 0 ? .orange : .secondary)
        }
        if let army {
            let ready = army.units - (state.moved[territory] ?? .zero)
            Text(ready.total > 0 ? "Tap a highlighted territory to march \(ready.total) ready units, or a sea with your ships to board."
                                 : "These troops have moved this turn.")
                .font(.caption).foregroundStyle(.secondary)
            // Upkeep: grain for every soldier, and pay for every few.
            let grain = engine.rules.upkeep(of: army.units)
                + army.units.total * (engine.haul(of: human, to: territory, in: state)?.extraGrain ?? 0)
            let per = engine.rules.economy.soldiersPerGold
            Text("Upkeep: \(grain) 🌾 a turn, and 1 gold a turn for every \(per) soldiers in your realm (your army costs \(engine.armyPay(of: human, in: state)) gold a turn in all).")
                .font(.caption).foregroundStyle(.secondary)
        }
        if home {
            HStack {
                Text("Recruit").font(.subheadline.bold())
                Spacer()
                let raised = raisedThisTurn(human)
                if raised.total > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Raised this turn:")
                        UnitRow(units: raised, size: 12)
                    }
                    .font(.caption.bold())
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.green.opacity(0.15)))
                    .id(raised.total)
                    .transition(.scale(scale: 1.6).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.35, bounce: 0.5), value: raisedThisTurn(human).total)
            Text("Each soldier costs gold and one of this land's people (👥 \(state.population(of: territory)) here), then eats 1 🌾 grain a turn. Cavalry also need a horse: each horse you have lets you raise one cavalry a turn.")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 6) {
                ForEach(UnitType.allCases, id: \.self) { type in
                    let stats = engine.rules.stats(type)
                    let allowance = engine.recruitAllowance(type, for: human, in: state)
                    let blocked = (allowance?.left ?? 1) == 0
                    Button {
                        if blocked, let r = stats.requires {
                            NotificationCenter.default.post(name: .showResource, object: r)
                        } else {
                            session.order(.recruit(territory: territory, unit: type, count: 1))
                        }
                    } label: {
                        HStack(spacing: 8) {
                            UnitIcon(type: type).frame(width: 20, height: 20)
                            VStack(alignment: .leading, spacing: 0) {
                                Text("Raise \(type.rawValue)").font(.callout.bold())
                                if let allowance, let r = stats.requires {
                                    (blocked ? Text("No \(r.rawValue): tap to see where")
                                             : Text("\(MapView.icon(r)) \(allowance.left) left this turn"))
                                        .font(.caption2)
                                        .multilineTextAlignment(.leading)
                                        .foregroundStyle(blocked ? .orange : .secondary)
                                }
                            }
                            Spacer(minLength: 4)
                            (Text("\(stats.cost) gold · 1 👥") + (stats.requires.map { Text(" · 1 \(MapView.icon($0))") } ?? Text(""))
                             + Text(" · 🌾\(stats.upkeep)/turn"))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .opacity(blocked ? 0.7 : 1)
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
            if !t.seas.isEmpty { SeaCrossing(session: session, territory: territory, civ: human) }
            projects(human)
        } else {
            Text("Cut off from your capital: no recruiting here.").font(.caption).foregroundStyle(.orange)
        }
        if let army { disbandControls(army, human) }
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
    /// Sending soldiers home: pick how many, see what it saves, confirm.
    @ViewBuilder func disbandControls(_ army: Army, _ human: CivilizationID) -> some View {
        if disbanding {
            VStack(alignment: .leading, spacing: 6) {
                Text("Disband").font(.subheadline.bold())
                UnitPicker(available: army.units, units: $toDisband)
                let own = state.owner(of: territory) == human
                let upkeep = engine.rules.upkeep(of: toDisband)
                Text((own ? "They go home and farm: up to \(toDisband.total) people return here. " : "Far from home, they simply scatter. ")
                     + "Saves \(upkeep) grain a turn. No gold comes back.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Cancel") { disbanding = false }.buttonStyle(.bordered)
                    Spacer()
                    Button("Disband \(toDisband.total)") {
                        if session.order(.disband(territory: territory, units: toDisband)) { disbanding = false }
                    }
                    .buttonStyle(.borderedProminent).tint(.orange)
                    .disabled(toDisband.isEmpty)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.1)))
        } else {
            Button {
                toDisband = .zero
                disbanding = true
            } label: {
                Label("Disband troops", systemImage: "person.fill.xmark")
            }
            .buttonStyle(.bordered)
            .font(.caption)
        }
    }

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
                let cost = engine.projectCost(kind, for: human, state, at: territory)
                let affordable = cs.gold >= cost.gold && (cs.stock[.stone] ?? 0) >= cost.stone
                    && (cs.stock[.timber] ?? 0) >= cost.timber
                Button {
                    session.order(.build(territory: territory, project: kind))
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(projectName(kind, at: territory, engine, state)).font(.caption.bold())
                            Text(projectPurpose(kind, at: territory, engine, state)).font(.caption2).foregroundStyle(.secondary)
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

/// Unclaimed land: talk to the tribe living there. Gifts may win them over (they swear to you,
/// and some of their warriors take service); a demand works only with an overwhelming army next
/// door; or march in and fight.
struct TribeTalks: View {
    let session: GameSession
    let territory: TerritoryID
    let civ: CivilizationID

    private var engine: Engine { session.engine }
    private var state: GameState { session.state }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Diplomacy").font(.subheadline.bold())
            let warriors = state.armies[territory].flatMap { $0.owner == nativesID ? $0.units.total : nil } ?? 0
            if warriors == 0 {
                note("Nobody lives here to treat with. March a single unit in to claim it.")
            } else if engine.tribe(at: territory, for: civ, in: state) == nil {
                note("A tribe of \(warriors) warriors holds this land. Your land must border theirs before you can send envoys.")
            } else if state.parleyed.contains(territory) {
                note("Your envoys have spoken with them this turn. Try again next turn, or march in.")
            } else {
                talks(warriors)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func talks(_ warriors: Int) -> some View {
        let cost = engine.giftCost(at: territory, in: state)
        let chance = engine.giftChance(at: territory, for: civ, in: state)
        let gold = state.civs[civ]?.gold ?? 0
        let next = engine.troopsNextTo(territory, for: civ, in: state)
        let bows = engine.demandWorks(at: territory, for: civ, in: state)
        let join = warriors * engine.rules.tribes.warriorsJoinPercent / 100
        note("A tribe of \(warriors) warriors. Tribes don't trade or sign treaties, but they can be brought under your rule: they become your land, and \(join == 0 ? "their warriors go home" : "\(join) of their warriors join your army").")
        Button {
            if session.order(.parley(territory: territory, .gifts)) { SoundBoard.shared.play(.coins, volume: 0.6) }
        } label: {
            option("gift.fill", "Win them over with gifts",
                   (gold < cost ? "\(cost) gold (you have \(gold))" : "\(cost) gold") + " · \(Self.likelihood(chance)). More of your troops next door makes them keener.")
        }
        .disabled(gold < cost)
        Button {
            session.order(.parley(territory: territory, .demand))
        } label: {
            option("crown.fill", "Demand they submit",
                   bows ? "With \(next) troops at their border, they will bow." :
                   "Free, but they bow only to \(engine.rules.tribes.demandRatio)× their numbers at the border (you have \(next)). Refused, it costs you standing and stiffens them.")
        }
        option("flag.2.crossed.fill", "Or take it by force",
               "Select one of your armies next door and tap this land to attack.")
            .foregroundStyle(.secondary)
    }

    private func option(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.bold())
                Text(detail).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    /// Words, not numbers, like the scouts.
    static func likelihood(_ p: Int) -> String {
        switch p {
        case 75...: "they will very likely accept"
        case 55..<75: "they will probably accept"
        case 40..<55: "they may accept"
        case 25..<40: "they will probably refuse"
        default: "they will very likely refuse"
        }
    }
}

/// Crossing the sea, as three steps with where the player stands on each: ships in a sea off this
/// coast (building one needs gold and timber), boarding by tapping that sea with the army
/// selected, then landing by selecting the ships and tapping the far coast.
struct SeaCrossing: View {
    let session: GameSession
    let territory: TerritoryID
    let civ: CivilizationID

    private var engine: Engine { session.engine }
    private var state: GameState { session.state }

    var body: some View {
        let seas = engine.map.territory(territory)?.seas ?? []
        let capacity = engine.rules.ships.capacity
        let fleets = seas.compactMap { state.fleet(of: civ, in: $0) }
        let ships = fleets.reduce(0) { $0 + $1.ships }
        let aboard = fleets.reduce(0) { $0 + $1.cargo.total }
        let army = state.armies[territory].flatMap { $0.owner == civ ? $0.units.total : nil } ?? 0
        let allowance = engine.shipAllowance(for: civ, in: state)
        let gold = state.civs[civ]?.gold ?? 0
        VStack(alignment: .leading, spacing: 8) {
            Label("Crossing the sea", systemImage: "sailboat.fill").font(.subheadline.bold())
            step(1, done: ships > 0, ships > 0
                 ? "You have \(ships) ship\(ships == 1 ? "" : "s") off this coast (each carries \(capacity))."
                 : "Build a ship in a sea off this coast. Each costs \(engine.rules.ships.cost) gold and a timber "
                   + "(🪵 \(allowance.left) left this turn), carries \(capacity) troops, and its crew eats \(engine.rules.ships.upkeep) 🌾 a turn.")
            ForEach(seas, id: \.self) { sea in
                Button {
                    if session.order(.buildShips(territory: territory, sea: sea, count: 1)) {
                        SoundBoard.shared.play(.coins, volume: 0.6)
                    }
                } label: {
                    HStack {
                        Image(systemName: "hammer.fill")
                        Text("Build a ship in the \(engine.map.sea(sea)?.name ?? sea)")
                        Spacer(minLength: 4)
                        Text("\(engine.rules.ships.cost) gold · 1 ") + MapView.icon(.timber)
                    }
                    .font(.caption.bold())
                }
                .buttonStyle(.bordered)
                .disabled(allowance.left == 0 || gold < engine.rules.ships.cost)
            }
            if allowance.perTurn == 0 {
                Button {
                    NotificationCenter.default.post(name: .showResource, object: Resource.timber)
                } label: {
                    Text("You have no timber: tap to see where to get it.").font(.caption2.bold())
                }
                .foregroundStyle(.orange)
            }
            step(2, done: aboard > 0, aboard > 0
                 ? "\(aboard) troops are aboard."
                 : army > 0 ? "With this army selected, tap the sea (it glows) and choose who boards."
                            : "Bring an army here, select it, then tap the sea to board.")
            step(3, done: false, "Tap your ships' sea, then a glowing coast to land. Landing on held land means a fight from the boats.")
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
    }

    private func step(_ n: Int, done: Bool, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : "\(n).circle")
                .foregroundStyle(done ? .green : .secondary)
            Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
        }
    }
}
