import HegemonCore
import SwiftUI

/// An order the player has started on the map and is finishing in the panel.
enum PendingOrder: Hashable {
    case march(from: TerritoryID, to: TerritoryID)
    case embark(from: TerritoryID, sea: SeaZoneID)
    case land(sea: SeaZoneID, to: TerritoryID)
}

/// The game: the board on the left, the player's panel on the right.
struct GameScreen: View {
    @Bindable var session: GameSession
    @State private var selected: MapPick?
    @State private var pending: PendingOrder?
    @State private var tab = PanelTab.orders
    @State private var layer = MapLayer.armies

    enum PanelTab: String, CaseIterable {
        case orders = "Orders", empire = "Empire", log = "Chronicle"
    }

    private var engine: Engine { session.engine }
    private var state: GameState { session.state }

    var body: some View {
        HStack(spacing: 0) {
            MapView(state: state, map: engine.map, engine: engine, layer: layer, focus: session.human,
                    selected: selected, targets: targets, onTap: tapped)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 0.12, green: 0.10, blue: 0.08))
                .overlay(alignment: .top) {
                    Picker("Map", selection: $layer) {
                        ForEach(MapLayer.allCases.filter { session.human != nil || $0 != .supply }, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 360)
                    .padding(.top, 8)
                }
                .overlay(alignment: .bottom) { legend.padding(.bottom, 8) }
            VStack(alignment: .leading, spacing: 10) {
                header
                if let message = session.message {
                    Text(message).font(.caption).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Picker("Panel", selection: $tab) {
                    ForEach(PanelTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                ScrollView {
                    switch tab {
                    case .orders: orders
                    case .empire: EmpireView(session: session)
                    case .log: ChronicleView(session: session)
                    }
                }
            }
            .padding(10)
            .frame(width: 290)
            .background(Color(.systemBackground))
        }
        .sheet(item: $session.replay) { entry in
            NavigationStack {
                BattleReplayView(entry: entry, state: state, map: engine.map, autoplay: true)
                    .id(entry.id)
                    .toolbar { Button("Done") { session.replay = nil } }
            }
        }
        .sheet(isPresented: .constant(session.crisis != nil && session.replay == nil)) {
            CrisisView(session: session).interactiveDismissDisabled()
        }
        .onChange(of: session.state.turn) { _, _ in pending = nil }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let human = session.human {
                    Circle().fill(Palette.color(human, state)).frame(width: 10, height: 10)
                    Text(Palette.name(human, state)).font(.headline)
                } else {
                    Text("Watching").font(.headline)
                }
                Spacer()
                Text("Round \(state.turn)/\(engine.rules.victory.roundLimit)")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Menu {
                    Button("New game") { session.quit() }
                } label: { Image(systemName: "ellipsis.circle") }
            }
            if let human = session.human, let cs = state.civs[human] {
                if let econ = session.economy {
                    HStack(spacing: 10) {
                        stat("Gold", "\(cs.gold)", change: econ.income, color: .orange)
                        stat("Grain", "\(econ.granary)", change: econ.grainBalance, color: .green)
                        stat("Legitimacy", "\(cs.legitimacy)", change: nil, color: .purple)
                    }
                }
                HStack(spacing: 10) {
                    if let econ = session.economy, !econ.cutOff.isEmpty {
                        Label("\(econ.cutOff.count) cut off", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                    Spacer()
                    if session.busy {
                        ProgressView().controlSize(.small)
                        Text("Rivals move…").font(.caption).foregroundStyle(.secondary)
                    } else if session.isHumanTurn {
                        Button("End turn") {
                            selected = nil
                            pending = nil
                            session.endTurn()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .font(.caption.monospacedDigit())
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
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder private var legend: some View {
        let text: String? = switch layer {
        case .armies: nil
        case .supply: "Supply lines from your capital ♛ · orange/red: distance costs extra grain · red land: cut off"
        case .trade: "Trade routes between empires at peace · dots: sea straits, colored by holder"
        case .resources: "🌾 grain · Cu copper · Sn tin · 🐎 horses · 🪵 timber · 🪙 gold · copper + tin make bronze"
        }
        if let text {
            Text(text).font(.caption2).foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.black.opacity(0.6), in: Capsule())
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
                    if let done { selected = done }
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
            return
        }
        pending = nil
        selected = pick == selected ? nil : pick
        if pick != nil { tab = .orders }
    }
}
