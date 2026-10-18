import HegemonCore
import SwiftUI

/// An order the player has started on the map and is finishing in the panel.
enum PendingOrder: Hashable {
    case march(from: TerritoryID, to: TerritoryID)
    case embark(from: TerritoryID, sea: SeaZoneID)
    case land(sea: SeaZoneID, to: TerritoryID)
}

/// The game: the board fills the screen, with the player's status and controls floating over it.
/// The panel slides in from the right when there's something to do there (a selection, an order,
/// the empire or the chronicle) and gets out of the way otherwise.
struct GameScreen: View {
    @Bindable var session: GameSession
    @State private var selected: MapPick?
    @State private var pending: PendingOrder?
    @State private var tab = PanelTab.orders
    @State private var panelOpen = false
    @State private var showKnowledge = false
    @State private var layer = MapLayer.armies

    enum PanelTab: String, CaseIterable {
        case orders = "Orders", empire = "Empire", log = "Chronicle"
    }

    private var engine: Engine { session.engine }
    private var state: GameState { session.state }
    static let panelWidth: CGFloat = 320

    var body: some View {
        ZStack {
            MapView(state: state, map: engine.map, engine: engine, layer: layer, focus: session.human,
                    selected: selected, targets: targets, onTap: tapped)
                .background(Color(red: 0.12, green: 0.10, blue: 0.08))
                .ignoresSafeArea()
            overlays
                .padding(.trailing, panelOpen ? Self.panelWidth : 0)
            if panelOpen {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    panel
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: panelOpen)
        .sheet(item: $session.replay) { entry in
            NavigationStack {
                BattleReplayView(entry: entry, state: state, map: engine.map, autoplay: true, perspective: session.human)
                    .id(entry.id)
                    .toolbar { Button("Done") { session.replay = nil } }
            }
        }
        .sheet(isPresented: .constant(session.crisis != nil && session.replay == nil)) {
            CrisisView(session: session).interactiveDismissDisabled()
        }
        .sheet(isPresented: $showKnowledge) {
            if let human = session.human {
                NavigationStack {
                    TechTreeView(civ: human, state: state, engine: engine)
                        .toolbar { Button("Done") { showKnowledge = false } }
                }
            }
        }
        .onChange(of: session.state.turn) { _, _ in pending = nil }
        .onChange(of: state.victory != nil) { _, over in
            if over { tab = .orders; panelOpen = true }
        }
    }

    // MARK: Floating controls

    private var overlays: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                status
                Spacer(minLength: 8)
                if !panelOpen { layerPicker }
                Spacer(minLength: 8)
                toolbar
            }
            if let message = session.message {
                Text(message)
                    .font(.callout)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(.red.opacity(0.9), in: Capsule())
                    .foregroundStyle(.white)
                    .onTapGesture { session.message = nil }
                    .transition(.opacity)
            }
            Spacer()
            HStack(alignment: .bottom) {
                Spacer()
                legend
                Spacer()
                turnButton
            }
        }
        .padding(10)
    }

    private var layerPicker: some View {
        Picker("Map", selection: $layer) {
            ForEach(MapLayer.allCases.filter { session.human != nil || $0 != .supply }, id: \.self) {
                Text($0.rawValue).tag($0)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 320)
        .padding(4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    /// The player's empire at a glance: who, when, and the three numbers that matter.
    private var status: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                if let human = session.human {
                    Circle().fill(Palette.color(human, state)).frame(width: 10, height: 10)
                    Text(Palette.name(human, state)).font(.headline)
                } else {
                    Text("Watching").font(.headline)
                }
                Text("Round \(state.turn)/\(engine.rules.victory.roundLimit)")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            if let human = session.human, let cs = state.civs[human], let econ = session.economy {
                HStack(spacing: 12) {
                    stat("Gold", "\(cs.gold)", change: econ.income, color: .orange)
                    stat("Grain", "\(econ.granary)", change: econ.grainBalance, color: .green)
                    stat("Legitimacy", "\(cs.legitimacy)", change: nil, color: .purple)
                }
                if !econ.cutOff.isEmpty {
                    Label("\(econ.cutOff.count) cut off", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.red)
                }
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var toolbar: some View {
        HStack(spacing: 4) {
            if session.human != nil {
                toolButton("Empire", "building.columns.fill") { open(.empire) }
                toolButton("Knowledge", "books.vertical.fill") { showKnowledge = true }
            }
            toolButton("Chronicle", "scroll.fill") { open(.log) }
            Menu {
                Button("New game", role: .destructive) { session.quit() }
            } label: {
                Image(systemName: "ellipsis").frame(width: 34, height: 34)
            }
        }
        .padding(4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func toolButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 34, height: 34)
        }
        .accessibilityLabel(title)
    }

    @ViewBuilder private var turnButton: some View {
        if session.human != nil {
            if session.busy {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Rivals move…").font(.callout)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
            } else if session.isHumanTurn {
                Button {
                    selected = nil
                    pending = nil
                    panelOpen = false
                    session.endTurn()
                } label: {
                    Label("End turn", systemImage: "hourglass")
                        .font(.headline)
                        .padding(.horizontal, 6).padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .shadow(radius: 4)
            }
        } else {
            HStack {
                Button { session.playing.toggle() } label: {
                    Image(systemName: session.playing ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(session.isOver)
                Button { Task { await session.playRound() } } label: { Image(systemName: "forward.frame.fill") }
                    .buttonStyle(.bordered)
                    .disabled(session.busy || session.playing || session.isOver)
            }
            .padding(6)
            .background(.ultraThinMaterial, in: Capsule())
        }
    }

    @ViewBuilder private var legend: some View {
        let text: String? = switch layer {
        case .armies: nil
        case .supply: "Supply lines from your capital ♛ · orange/red: distance costs extra grain · red land: cut off"
        case .trade: "Trade routes between empires at peace · ▸ goods each partner receives · dots: sea straits, colored by holder"
        case .resources: "🌾 grain · Cu copper · Sn tin · Fe iron · 🐎 horses · 🪵 timber · 🪨 stone · 🪙 gold · 🍷 wine · 💎 luxuries"
            + " · built: 🛤 road 🧱 walls 🌱 farm ⛏ mine ⚓ harbor 🏗 underway"
        }
        if let text {
            Text(text).font(.caption2).foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.black.opacity(0.6), in: Capsule())
        }
    }

    // MARK: Panel

    private func open(_ tab: PanelTab) {
        if panelOpen && self.tab == tab && selected == nil && pending == nil {
            panelOpen = false
        } else {
            self.tab = tab
            panelOpen = true
        }
    }

    private func closePanel() {
        panelOpen = false
        selected = nil
        pending = nil
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("Panel", selection: $tab) {
                    ForEach(PanelTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Button(action: closePanel) {
                    Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary)
                }
                .accessibilityLabel("Close")
            }
            ScrollView {
                Group {
                switch tab {
                case .orders: orders
                case .empire: EmpireView(session: session)
                case .log: ChronicleView(session: session)
                }
                }
                .padding(.trailing, 4)
            }
        }
        .padding(12)
        .frame(width: Self.panelWidth)
        .frame(maxHeight: .infinity)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 16)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.25), radius: 10)
                .ignoresSafeArea()
        }
    }

    /// A labeled number with its change per turn, red when falling.
    private func stat(_ name: String, _ value: String, change: Int?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(name).font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: 3) {
                Text(value).font(.callout.bold().monospacedDigit()).foregroundStyle(color)
                if let change {
                    Text(change >= 0 ? "+\(change)" : "\(change)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(change < 0 ? .red : .secondary)
                }
            }
        }
    }

    // MARK: Orders

    @ViewBuilder private var orders: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let victory = state.victory {
                VictoryBanner(victory: victory, state: state, engine: engine)
                Button("New game") { session.quit() }.buttonStyle(.borderedProminent)
            }
            if let pending, session.isHumanTurn {
                OrderComposer(session: session, order: pending) { done in
                    self.pending = nil
                    if let done { selected = done } else if selected == nil { panelOpen = false }
                }
                .id(pending)
            } else if case .territory(let id)? = selected {
                TerritoryPanel(session: session, territory: id)
            } else if case .sea(let sea)? = selected {
                FleetPanel(session: session, sea: sea)
            } else if session.human != nil, !session.isOver {
                Text(session.isHumanTurn
                     ? "Tap one of your territories to give its army orders, or to recruit and build there."
                     : "The other empires are taking their turns.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if session.human == nil {
                EmpireTable(state: state, engine: engine)
            }
        }
    }

    // MARK: Map interaction

    /// Where the selected army or fleet can go this turn.
    private var targets: Set<MapPick> {
        guard session.isHumanTurn, let human = session.human, pending == nil else { return [] }
        switch selected {
        case .territory(let from)?:
            guard let army = state.armies[from], army.owner == human,
                  (army.units - (state.moved[from] ?? .zero)).total > 0 else { return [] }
            var picks = Set(engine.map.landNeighbors(of: from).filter { to in
                !(state.owner(of: to).map { $0 != human && state.atPeace(human, $0) } ?? false)
            }.map(MapPick.territory))
            for sea in engine.map.seas(bordering: from) {
                if let fleet = state.fleet(of: human, in: sea),
                   fleet.cargo.total < fleet.ships * engine.rules.ships.capacity {
                    picks.insert(.sea(sea))
                }
            }
            return picks
        case .sea(let sea)?:
            guard let fleet = state.fleet(of: human, in: sea) else { return [] }
            var picks: Set<MapPick> = []
            if fleet.ships > fleet.movedShips {
                picks.formUnion(engine.map.seaNeighbors(of: sea).map(MapPick.sea))
            }
            if fleet.cargo.total > 0 {
                picks.formUnion(engine.map.coastalTerritories(of: sea).filter { to in
                    !(state.owner(of: to).map { $0 != human && state.atPeace(human, $0) } ?? false)
                }.map(MapPick.territory))
            }
            return picks
        case nil:
            return []
        }
    }

    private func tapped(_ pick: MapPick?) {
        session.message = nil
        if let pick, targets.contains(pick), let from = selected {
            switch (from, pick) {
            case let (.territory(a), .territory(b)): pending = .march(from: a, to: b)
            case let (.territory(a), .sea(s)): pending = .embark(from: a, sea: s)
            case let (.sea(s), .territory(t)): pending = .land(sea: s, to: t)
            case let (.sea(s), .sea(t)):
                // Sailing needs no choices: every ready ship goes, with all the cargo that fits.
                if let fleet = state.fleet(of: session.human!, in: s) {
                    let ready = fleet.ships - fleet.movedShips
                    let cargo = fleet.cargo.total <= ready * engine.rules.ships.capacity ? fleet.cargo : .zero
                    if session.order(.moveFleet(from: s, to: t, ships: ready, cargo: cargo)) {
                        selected = state.fleet(of: session.human!, in: t) != nil ? .sea(t) : nil
                    }
                }
            }
            tab = .orders
            panelOpen = true
            return
        }
        pending = nil
        selected = pick == selected ? nil : pick
        if selected != nil {
            tab = .orders
            panelOpen = true
        } else if tab == .orders {
            panelOpen = false
        }
    }
}
