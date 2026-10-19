import HegemonCore
import SwiftUI

/// What can be done with the selected territory or sea, along the bottom of the screen in the
/// title screen's style: dark wood, bronze rules and serif capitals, with every action a card in a
/// row you slide through. Nothing to scroll down to.
struct CommandBar: View {
    let session: GameSession
    let pick: MapPick
    let close: () -> Void
    /// Go into one of your own territories.
    var enter: ((TerritoryID) -> Void)?

    @State private var showPlan = false
    @State private var showDisband = false
    @State private var toDisband = UnitCounts.zero

    private var engine: Engine { session.engine }
    private var state: GameState { session.state }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            header
                .frame(width: 210, alignment: .leading)
            Rectangle().fill(Bronze.gradient).frame(width: 1.5).padding(.vertical, 2)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) { sections }
                    .padding(.trailing, 8)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(height: 150)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(LinearGradient(colors: [Color(red: 0.2, green: 0.15, blue: 0.11), Color(red: 0.12, green: 0.09, blue: 0.07)],
                                     startPoint: .top, endPoint: .bottom))
        )
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Bronze.gradient, lineWidth: 2))
        .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 4) {
            Group {
                switch pick {
                case .territory(let id): territoryHeader(id)
                case .sea(let sea): seaHeader(sea)
                }
            }
            Spacer(minLength: 0)
            Button(action: close) {
                Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.white.opacity(0.5))
            }
            .accessibilityLabel("Close")
        }
    }

    private func territoryHeader(_ id: TerritoryID) -> some View {
        let t = engine.map.territory(id)!
        let owner = state.owner(of: id)
        let army = state.armies[id]
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if let owner {
                    Circle().fill(Palette.color(owner, state)).frame(width: 10, height: 10)
                        .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 1))
                }
                Text(t.name.uppercased())
                    .font(.system(.title3, design: .serif).weight(.bold)).tracking(1.5)
                    .foregroundStyle(Bronze.gradient)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            Text("\(owner.map { Palette.name($0, state) } ?? "Unclaimed") · \(t.terrain.rawValue)")
                .font(.caption).foregroundStyle(.white.opacity(0.7))
            HStack(spacing: 8) {
                Label("\(state.population(of: id))", systemImage: "person.2.fill")
                Text("🌾\(engine.territoryYield(.grain, id, state))")
                if let army, army.units.total > 0 {
                    UnitRow(units: army.units, size: 12)
                }
            }
            .font(.caption.bold())
            .foregroundStyle(.white)
            if let army, army.units.total > 0, engine.rank(of: army) > .green {
                VeteranBadge(rank: engine.rank(of: army))
            }
            Text(hint(id)).font(.caption2).foregroundStyle(.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(3)
            if let enter, owner != nil, owner == session.human {
                Button { enter(id) } label: {
                    Label("Enter \(engine.seat(of: owner!, in: state) == id ? "the capital" : "the town")", systemImage: "building.2.fill")
                        .font(.caption.bold())
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Bronze.gradient, in: Capsule())
                        .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func seaHeader(_ sea: SeaZoneID) -> some View {
        let fleets = state.fleets.filter { $0.sea == sea }
        return VStack(alignment: .leading, spacing: 4) {
            Text((engine.map.sea(sea)?.name ?? sea).uppercased())
                .font(.system(.title3, design: .serif).weight(.bold)).tracking(1.5)
                .foregroundStyle(Bronze.gradient)
                .lineLimit(1).minimumScaleFactor(0.6)
            if fleets.isEmpty { Text("Open water").font(.caption).foregroundStyle(.white.opacity(0.7)) }
            ForEach(fleets, id: \.owner) { f in
                HStack(spacing: 5) {
                    Circle().fill(Palette.color(f.owner, state)).frame(width: 8, height: 8)
                    Text("\(Palette.name(f.owner, state)): ⛵\(f.ships)" + (f.cargo.total > 0 ? " · \(f.cargo.total) aboard" : ""))
                }
                .font(.caption.bold()).foregroundStyle(.white)
            }
            if let human = session.human, let mine = state.fleet(of: human, in: sea), session.isHumanTurn {
                let ready = mine.ships - mine.movedShips
                Text(ready > 0 ? "Tap a glowing sea to sail\(mine.cargo.total > 0 ? ", or a glowing coast to land" : "")."
                     : mine.cargo.total > 0 ? "The ships have sailed; the troops can still land." : "These ships have sailed this turn.")
                    .font(.caption2).foregroundStyle(.white.opacity(0.65))
            }
        }
    }

    private func hint(_ id: TerritoryID) -> String {
        guard let human = session.human, session.isHumanTurn else { return "" }
        if let army = state.armies[id], army.owner == human {
            let ready = army.units - (state.moved[id] ?? .zero)
            if let haul = engine.haul(of: human, to: id, in: state), haul.extraGrain > 0 {
                return "Grain is carted \(haul.steps) steps here: each soldier eats \(haul.extraGrain) extra. Roads or ships carry it free."
            }
            guard ready.total > 0 else { return "These troops have moved this turn." }
            let coastal = !(engine.map.territory(id)?.seas.isEmpty ?? true)
            let routes = engine.seaRoutes(from: id, for: human, in: state)
            if !routes.isEmpty { return "Tap white land to march, or a blue coast ⛵ to sail there and attack in one go." }
            if coastal { return "Tap a glowing territory to march. To cross the sea, build a ship (Ships, below) first." }
            return "Tap a glowing territory to march."
        }
        if state.owner(of: id) == human { return engine.homeNetwork(of: human, in: state).contains(id) ? "" : "Cut off from your capital: no recruiting here." }
        return "Select one of your armies next door and tap here to attack."
    }

    // MARK: Sections

    @ViewBuilder private var sections: some View {
        if let human = session.human, session.isHumanTurn {
            switch pick {
            case .territory(let id):
                if state.owner(of: id) == human {
                    ownSections(id, human)
                } else if state.owner(of: id) == nil {
                    tribeSection(id, human)
                }
            case .sea(let sea):
                if state.fleet(of: human, in: sea) != nil { fleetSection(sea, human) }
            }
        } else {
            Text(session.human == nil ? "" : "The other empires are taking their turns.")
                .font(.callout).foregroundStyle(.white.opacity(0.7)).padding(.top, 30)
        }
    }

    @ViewBuilder private func ownSections(_ id: TerritoryID, _ human: CivilizationID) -> some View {
        let home = engine.homeNetwork(of: human, in: state).contains(id)
        let army = state.armies[id].flatMap { $0.owner == human ? $0 : nil }
        let cs = state.civs[human]!
        if let army { supplyCard(army, id, human) }
        if home {
            section("Recruit") {
                ForEach(UnitType.allCases, id: \.self) { type in recruitTile(type, id, human) }
            }
            let land = state.land[id]!
            let buildable = ProjectKind.allCases.filter { engine.canBuild($0, in: id, state) }
            if land.construction != nil || !buildable.isEmpty {
                section("Build") {
                    if let site = land.construction {
                        Tile(symbol: "hammer.fill", title: projectName(site.kind), detail: "Under way",
                             cost: Text("\(site.turnsLeft) turn\(site.turnsLeft == 1 ? "" : "s") left"), enabled: false) {}
                    } else {
                        ForEach(buildable, id: \.self) { kind in
                            let c = engine.projectCost(kind, for: human, state)
                            let ok = cs.gold >= c.gold && (cs.stock[.stone] ?? 0) >= c.stone && (cs.stock[.timber] ?? 0) >= c.timber
                            Tile(symbol: Self.projectSymbol(kind), title: projectName(kind), detail: projectPurpose(kind),
                                 cost: Self.cost(gold: c.gold, stone: c.stone, timber: c.timber, turns: c.turns), enabled: ok) {
                                if session.order(.build(territory: id, project: kind)) { SoundBoard.shared.play(.coins, volume: 0.6) }
                            }
                        }
                    }
                }
            }
            let seas = engine.map.territory(id)!.seas
            if !seas.isEmpty {
                section("Ships") {
                    let allowance = engine.shipAllowance(for: human, in: state)
                    ForEach(seas, id: \.self) { sea in
                        let mine = state.fleet(of: human, in: sea)?.ships ?? 0
                        Tile(symbol: "sailboat.fill", title: "Ship",
                             detail: "In the \(engine.map.sea(sea)?.name ?? sea)" + (mine > 0 ? " (\(mine) there)" : ""),
                             cost: Text("\(engine.rules.ships.cost) gold · 1 ") + MapView.icon(.timber),
                             enabled: allowance.left > 0 && cs.gold >= engine.rules.ships.cost) {
                            if session.order(.buildShips(territory: id, sea: sea, count: 1)) { SoundBoard.shared.play(.coins, volume: 0.6) }
                        }
                    }
                }
            }
        }
        if let army {
            section("Command") {
                if home, state.general(of: human, at: id) == nil {
                    Tile(symbol: "star.fill", title: "General", detail: "Appoint one to lead this army",
                         cost: Text("\(engine.rules.government.appointCost) gold"), enabled: cs.gold >= engine.rules.government.appointCost) {
                        session.order(.appointGeneral(territory: id))
                    }
                }
                let f = engine.rules.battle.formation(army.formation ?? engine.rules.battle.defaultFormation)?.name ?? ""
                Tile(symbol: "shield.lefthalf.filled", title: "Defence", detail: "If attacked here: \(f.lowercased())",
                     cost: Text("Change plan"), enabled: true) { showPlan = true }
                    .popover(isPresented: $showPlan) {
                        ScrollView {
                            BattlePlanEditor(engine: engine, civ: human, state: state, units: army.units,
                                             general: state.general(of: human, at: id), plan: Binding(
                                get: { state.armies[id]?.plan ?? army.plan },
                                set: { session.order(.setBattlePlan(territory: id, plan: $0)) }))
                                .padding()
                        }
                        .frame(width: 420, height: 320)
                        .presentationCompactAdaptation(.popover)
                    }
                Tile(symbol: "person.fill.xmark", title: "Disband", detail: "Send soldiers home to farm",
                     cost: Text("Saves grain and pay"), enabled: true) {
                    toDisband = .zero
                    showDisband = true
                }
                .popover(isPresented: $showDisband) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Disband").font(.headline)
                        UnitPicker(available: army.units, units: $toDisband)
                        Text("Saves \(engine.rules.upkeep(of: toDisband)) grain a turn. No gold comes back.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Disband \(toDisband.total)") {
                            if session.order(.disband(territory: id, units: toDisband)) { showDisband = false }
                        }
                        .buttonStyle(.borderedProminent).tint(.orange).disabled(toDisband.isEmpty)
                    }
                    .padding()
                    .frame(width: 300)
                    .presentationCompactAdaptation(.popover)
                }
            }
        }
    }

    @ViewBuilder private func tribeSection(_ id: TerritoryID, _ human: CivilizationID) -> some View {
        let warriors = state.armies[id].flatMap { $0.owner == nativesID ? $0.units.total : nil } ?? 0
        section("Diplomacy") {
            if warriors == 0 {
                Tile(symbol: "flag.fill", title: "Empty land", detail: "March a single unit in to claim it", cost: Text(""), enabled: false) {}
            } else if engine.tribe(at: id, for: human, in: state) == nil {
                Tile(symbol: "person.3.fill", title: "\(warriors) warriors", detail: "Your land must border theirs to send envoys",
                     cost: Text(""), enabled: false) {}
            } else if state.parleyed.contains(id) {
                Tile(symbol: "hourglass", title: "Spoken with", detail: "Try again next turn, or attack", cost: Text(""), enabled: false) {}
            } else {
                let cost = engine.giftCost(at: id, in: state)
                let chance = engine.giftChance(at: id, for: human, in: state)
                let bows = engine.demandWorks(at: id, for: human, in: state)
                Tile(symbol: "gift.fill", title: "Gifts", detail: TribeTalks.likelihood(chance).capitalizedFirst,
                     cost: Text("\(cost) gold"), enabled: (state.civs[human]?.gold ?? 0) >= cost) {
                    if session.order(.parley(territory: id, .gifts)) { SoundBoard.shared.play(.coins, volume: 0.6) }
                }
                Tile(symbol: "crown.fill", title: "Demand", detail: bows ? "They will bow to your army" : "They'd refuse: you need \(engine.rules.tribes.demandRatio)× their warriors nearby",
                     cost: Text(bows ? "Free" : "Costs standing if refused"), enabled: true) {
                    session.order(.parley(territory: id, .demand))
                }
            }
        }
    }

    @ViewBuilder private func fleetSection(_ sea: SeaZoneID, _ human: CivilizationID) -> some View {
        let fleet = state.fleet(of: human, in: sea)!
        section("Fleet") {
            let f = engine.rules.battle.formation(fleet.formation ?? engine.rules.battle.defaultFormation)?.name ?? ""
            Tile(symbol: "sailboat.fill", title: "Battle plan", detail: "At sea: \(f.lowercased())", cost: Text("Change plan"), enabled: true) {
                showPlan = true
            }
            .popover(isPresented: $showPlan) {
                ScrollView {
                    BattlePlanEditor(engine: engine, civ: human, state: state, units: UnitCounts(infantry: fleet.ships),
                                     general: nil, plan: Binding(
                        get: { state.fleet(of: human, in: sea)?.plan ?? fleet.plan },
                        set: { session.order(.setFleetPlan(sea: sea, plan: $0)) }), naval: true)
                        .padding()
                }
                .frame(width: 420, height: 320)
                .presentationCompactAdaptation(.popover)
            }
        }
    }

    /// What keeping this army in the field costs, and how its supply gets there.
    private func supplyCard(_ army: Army, _ id: TerritoryID, _ human: CivilizationID) -> some View {
        let men = army.units.total
        let haul = engine.haul(of: human, to: id, in: state)
        let steps = engine.supplySteps(of: human, to: id, in: state)
        let base = engine.rules.upkeep(of: army.units)
        let extra = men * (haul?.extraGrain ?? 0)
        let per = engine.rules.economy.soldiersPerGold
        let pay = Double(men) / Double(per)
        let (status, color): (String, Color) = switch (steps, extra) {
        case (nil, _): ("Cut off", .red)
        case (_, 0): ("Well supplied", .green)
        case (_, ..<4): ("Long haul", .orange)
        default: ("Strained", .red)
        }
        return section("Supply") {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Circle().fill(color).frame(width: 9, height: 9)
                    Text(status).font(.system(.subheadline, design: .serif).weight(.bold))
                    Spacer()
                    Text("\(men) soldiers").font(.caption2)
                }
                Text("🌾 \(base + extra) grain a turn" + (extra > 0 ? " (\(base) + \(extra) carted)" : ""))
                    .font(.caption.bold())
                Text("🪙 about \(pay.formatted(.number.precision(.fractionLength(0...1)))) gold a turn in pay")
                    .font(.caption.bold())
                Group {
                    if steps == nil {
                        Text("No road home to the capital: no supply, and it loses a soldier a turn. Retake the land between.")
                    } else if let haul, haul.extraGrain > 0 {
                        Text("Grain is carted \(haul.steps) steps overland. A road, or your ships in the sea between, would carry it free.")
                    } else if steps == 0 {
                        Text("At the capital: fed straight from the granary.")
                    } else {
                        Text("\(steps!) steps from the capital, by road or sea: no carting costs.")
                    }
                }
                .font(.caption2).foregroundStyle(Color(red: 0.3, green: 0.24, blue: 0.16))
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(8)
            .frame(width: 210, height: 96, alignment: .topLeading)
            .foregroundStyle(Color(red: 0.2, green: 0.14, blue: 0.08))
            .background(RoundedRectangle(cornerRadius: 10).fill(LinearGradient(
                colors: [Color(red: 0.96, green: 0.91, blue: 0.79), Color(red: 0.86, green: 0.78, blue: 0.62)],
                startPoint: .top, endPoint: .bottom)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(color, lineWidth: 2))
        }
    }

    // MARK: Pieces

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(.caption, design: .serif).weight(.bold)).tracking(2)
                .foregroundStyle(Bronze.gradient)
            HStack(alignment: .top, spacing: 8) { content() }
        }
    }

    private func recruitTile(_ type: UnitType, _ id: TerritoryID, _ human: CivilizationID) -> some View {
        let stats = engine.rules.stats(type)
        let allowance = engine.recruitAllowance(type, for: human, in: state)
        let blocked = (allowance?.left ?? 1) == 0
        let cs = state.civs[human]!
        let raised = session.marks.reduce(0) { n, m in
            if case let .raised(t, civ, unit, count) = m, t == id, civ == human, unit == type { return n + count }
            return n
        }
        var cost = Text("\(stats.cost) gold · 1 👥")
        if let r = stats.requires { cost = cost + Text(" · 1 ") + MapView.icon(r) }
        let detail: String = if let allowance, let r = stats.requires {
            blocked ? "No \(r.rawValue): tap to see where" : "\(allowance.left) more this turn"
        } else { "Eats 1 grain a turn" }
        return Tile(unit: type, title: type.rawValue.capitalized, detail: detail, cost: cost,
                    enabled: blocked || (cs.gold >= stats.cost && state.population(of: id) > engine.rules.economy.minPopulation),
                    badge: raised > 0 ? "+\(raised)" : nil) {
            if blocked, let r = stats.requires {
                NotificationCenter.default.post(name: .showResource, object: r)
            } else {
                session.order(.recruit(territory: id, unit: type, count: 1))
            }
        }
    }

    static func cost(gold: Int, stone: Int, timber: Int, turns: Int) -> Text {
        var t = Text("\(gold) gold")
        if stone > 0 { t = t + Text(" · \(stone) ") + MapView.icon(.stone) }
        if timber > 0 { t = t + Text(" · \(timber) ") + MapView.icon(.timber) }
        return t + Text(" · \(turns)t")
    }

    static func projectSymbol(_ kind: ProjectKind) -> String {
        switch kind {
        case .road: "road.lanes"
        case .walls: "building.columns.fill"
        case .farm: "leaf.fill"
        case .mine: "hammer.fill"
        case .harbor: "ferry.fill"
        }
    }
}

/// One action: a parchment card with an icon, a name, what it does and what it costs.
private struct Tile: View {
    var symbol: String?
    var unit: UnitType?
    let title: String
    let detail: String
    let cost: Text
    let enabled: Bool
    var badge: String?
    let action: () -> Void

    init(symbol: String, title: String, detail: String, cost: Text, enabled: Bool, badge: String? = nil, action: @escaping () -> Void) {
        self.symbol = symbol
        self.title = title
        self.detail = detail
        self.cost = cost
        self.enabled = enabled
        self.badge = badge
        self.action = action
    }

    init(unit: UnitType, title: String, detail: String, cost: Text, enabled: Bool, badge: String? = nil, action: @escaping () -> Void) {
        self.unit = unit
        self.title = title
        self.detail = detail
        self.cost = cost
        self.enabled = enabled
        self.badge = badge
        self.action = action
    }

    var body: some View {
        Button {
            // Unavailable cards stay readable (no system dimming); a tap just doesn't act.
            if enabled { action() } else { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Group {
                        if let unit { UnitIcon(type: unit, color: Color(red: 0.3, green: 0.2, blue: 0.1)) }
                        else if let symbol { Image(systemName: symbol).resizable().scaledToFit() }
                    }
                    .frame(width: 20, height: 20)
                    .foregroundStyle(Color(red: 0.45, green: 0.3, blue: 0.12))
                    Text(title).font(.system(.subheadline, design: .serif).weight(.bold))
                        .foregroundStyle(Color(red: 0.2, green: 0.14, blue: 0.08))
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Text(detail).font(.caption2).foregroundStyle(Color(red: 0.3, green: 0.24, blue: 0.16))
                    .lineLimit(2).multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                cost.font(.caption2.bold().monospacedDigit())
                    .foregroundStyle(enabled ? Color(red: 0.45, green: 0.3, blue: 0.12) : Color(red: 0.65, green: 0.15, blue: 0.1))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(8)
            .frame(width: 128, height: 96, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: enabled
                                         ? [Color(red: 0.96, green: 0.91, blue: 0.79), Color(red: 0.86, green: 0.78, blue: 0.62)]
                                         : [Color(red: 0.78, green: 0.75, blue: 0.69), Color(red: 0.66, green: 0.63, blue: 0.57)],
                                         startPoint: .top, endPoint: .bottom))
            )
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Bronze.gradient, lineWidth: 1.5))
            .overlay(alignment: .topTrailing) {
                if let badge {
                    Text(badge).font(.caption2.bold()).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(.green))
                        .offset(x: 4, y: -6)
                        .transition(.scale.combined(with: .opacity))
                }
            }

        }
        .buttonStyle(.plain)
        .animation(.spring(duration: 0.3, bounce: 0.5), value: badge)
    }
}

/// The title screen's look for the game's controls: dark wood with a bronze edge, light text.
enum Wood {
    static let gradient = LinearGradient(colors: [Color(red: 0.2, green: 0.15, blue: 0.11), Color(red: 0.12, green: 0.09, blue: 0.07)],
                                         startPoint: .top, endPoint: .bottom)
}

extension View {
    func woodPanel<S: InsettableShape>(_ shape: S, border: CGFloat = 1.5) -> some View {
        self
            .background(shape.fill(Wood.gradient).shadow(color: .black.opacity(0.35), radius: 6, y: 2))
            .overlay(shape.strokeBorder(Bronze.gradient, lineWidth: border))
            .environment(\.colorScheme, .dark)
    }
}
