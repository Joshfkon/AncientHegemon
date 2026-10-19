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
extension Notification.Name {
    /// Open the resources sheet at a resource (the notification's object).
    static let showResource = Notification.Name("showResource")
}

struct GameScreen: View {
    @Bindable var session: GameSession
    @State private var selected: MapPick?
    @State private var pending: PendingOrder?
    @State private var tab = PanelTab.orders
    @State private var panelOpen = false
    @State private var showKnowledge = false
    @State private var showCodex = false
    @State private var showWalkthrough = false
    @State private var showThrone = false
    @State private var layer = MapLayer.armies
    @State private var quickLook: TerritoryID?
    @State private var explain: StatTopic?
    @State private var tip: Tip?
    /// Tips waiting their turn, shown one at a time in the order of `Tip.allCases`.
    @State private var tipQueue: [Tip] = []
    /// The last chronicle line the player has seen, for the Chronicle badge.
    @State private var seenLog = 0
    @State private var idleIndex = 0
    @State private var mapCenter: MapCenter?
    /// The resources sheet, opened at a given resource.
    @State private var resourcesAt: Resource?
    @State private var showResources = false
    /// A resource whose sources are spotlit on the map.
    @State private var spotlit: Resource?
    @State private var shake: CGFloat = 0
    @State private var endDismissed = false
    @State private var tint: Color?

    enum PanelTab: String, CaseIterable {
        case orders = "Orders", empire = "Realm", diplomacy = "Rivals", log = "Chronicle"
    }

    private var engine: Engine { session.engine }
    private var state: GameState { session.state }
    static let panelWidth: CGFloat = 320

    var body: some View {
        ZStack {
            MapView(state: state, map: engine.map, engine: engine, layer: layer, focus: session.human,
                    selected: selected, targets: targets, onTap: tapped,
                    onLongPress: { pick in
                        if case .territory(let t)? = pick { quickLook = t; Feedback.select() }
                    },
                    marks: session.marks, markTimes: session.markTimes, planned: planned, idle: session.isHumanTurn ? Set(idleArmies) : [],
                    trailingInset: panelOpen ? Self.panelWidth : 0, center: mapCenter,
                    spotlight: spotlightTerritories, flashes: session.flashes)
                .background(Color(red: 0.12, green: 0.10, blue: 0.08))
                .modifier(Shake(animatableData: shake))
                .overlay { if let tint { tint.opacity(0.35).allowsHitTesting(false).transition(.opacity) } }
                .ignoresSafeArea()
            overlays
                .padding(.trailing, panelOpen ? Self.panelWidth : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            // One interruption at a time: the very first tip, then the news.
            if let moment = session.moments.first {
                VStack {
                    MomentBanner(moment: moment, session: session)
                        .id(moment.id)
                        .padding(.top, 70)
                        .onTapGesture { session.dismissMoment() }
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: moment.id) { await play(moment) }
            }
            if session.showReport, session.isHumanTurn, tip != .map, session.moments.isEmpty {
                TurnReportCard(session: session) { t in
                    selected = .territory(t)
                    session.showReport = false
                }
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
            if panelOpen {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    panel
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: panelOpen)
        .fullScreenCover(item: $session.muster) { muster in
            BattlefieldView(session: session, muster: muster)
        }
        // Battles fought from the battlefield play there; this is for the rest (landings, defences).
        .sheet(item: Binding(get: { session.muster == nil ? session.replay : nil },
                             set: { session.replay = $0 })) { entry in
            NavigationStack {
                BattleReplayView(entry: entry, state: state, map: engine.map, autoplay: true, perspective: session.human) {
                    session.replay = nil
                }
                .id(entry.id)
            }
        }
        .sheet(isPresented: .constant(session.crisis != nil && session.replay == nil && session.muster == nil)) {
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
        .sheet(isPresented: $showResources) {
            NavigationStack {
                ResourcesView(session: session, show: { r in
                    showResources = false
                    spotlit = r
                    layer = .resources
                    if let first = session.human.flatMap({ engine.sources(of: r, for: $0, in: state).first }) {
                        mapCenter = MapCenter(territory: first.territory, onlyIfHidden: false, id: (mapCenter?.id ?? 0) + 1)
                    }
                }, focus: resourcesAt)
                .toolbar { Button("Done") { showResources = false } }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showResource)) { note in
            resourcesAt = note.object as? Resource
            showResources = true
        }
        .fullScreenCover(isPresented: Binding(get: { state.victory != nil && session.replay == nil && !endDismissed },
                                              set: { if !$0 { endDismissed = true } })) {
            if let victory = state.victory {
                EndScreen(session: session, victory: victory) {
                    endDismissed = true
                    session.quit()
                }
            }
        }
        .fullScreenCover(isPresented: $showThrone) {
            ThroneRoomView(session: session) { target in
                showThrone = false
                switch target {
                case let .territory(t)?:
                    selected = .territory(t)
                    if tab == .orders { panelOpen = false }
                    mapCenter = MapCenter(territory: t, id: (mapCenter?.id ?? 0) + 1)
                case .diplomacy?: open(.diplomacy)
                case .realm?: open(.empire)
                case nil: break
                }
            }
        }
        .fullScreenCover(isPresented: $showWalkthrough) {
            WalkthroughView { showWalkthrough = false }
        }
        .sheet(isPresented: $showCodex) {
            NavigationStack {
                CodexView().toolbar { Button("Done") { showCodex = false } }
            }
        }
        .onChange(of: session.state.turn) { _, _ in pending = nil }
        .onAppear {
            #if DEBUG
            // Launch with DEMO_MOMENTS=1 to see one of each moment.
            if UserDefaults.standard.bool(forKey: "demoMoments"), let human = session.human,
               let seat = engine.seat(of: human, in: state) {
                session.moments = [Moment(kind: .captured(seat)), Moment(kind: .discovery(.metallurgy, 2)),
                                   Moment(kind: .war(state.players.first { $0 != human } ?? human)),
                                   Moment(kind: .disaster(.earthquake, seat))]
                session.demoFlash(seat)
            }
            if UserDefaults.standard.bool(forKey: "demoSeaBattle") { session.muster = session.demoSeaBattle() }
            // Launch with -demoBattle YES to draw the capital's army up against a neighbouring tribe.
            if UserDefaults.standard.bool(forKey: "demoBattle"), let human = session.human,
               let seat = engine.seat(of: human, in: state), let army = state.armies[seat],
               let target = engine.map.landNeighbors(of: seat).first(where: { engine.defenders(of: $0, against: human, state) != nil }) {
                session.muster = Muster(from: seat, to: target, units: army.units, general: state.general(of: human, at: seat) != nil)
            }
            #endif
            // Start close in on the player's own land.
            if let human = session.human, let seat = engine.seat(of: human, in: state) {
                mapCenter = MapCenter(territory: seat, minZoom: 1.7, onlyIfHidden: false, id: 1)
            }
            offer(.map)
        }
        .onChange(of: focusTerritory) { _, t in
            guard let t, panelOpen else { return }
            mapCenter = MapCenter(territory: t, id: (mapCenter?.id ?? 0) + 1)
        }
        .onChange(of: session.marks.count) { _, _ in
            // Follow the rivals around the map as they move.
            guard session.busy, !session.skipping, let mark = session.marks.last else { return }
            let place: TerritoryID? = switch mark {
            case let .march(_, _, to, _), let .landing(_, _, to, _): to
            case let .battle(at, _, _): at
            case let .captured(t, _), let .event(t, _), let .raised(t, _, _, _): t
            }
            if let place { mapCenter = MapCenter(territory: place, id: (mapCenter?.id ?? 0) + 1) }
        }
        .onChange(of: panelOpen) { _, open in
            guard open, let t = focusTerritory else { return }
            mapCenter = MapCenter(territory: t, id: (mapCenter?.id ?? 0) + 1)
        }
        .onChange(of: session.showReport) { _, shown in if shown { offer(.rivals) } }
        .onChange(of: pending) { _, p in
            if case let .march(_, to)? = p, state.armies[to].map({ $0.owner != session.human }) ?? false { offer(.battle) }
            if p == nil { session.plannedOdds = nil }
        }
        .onChange(of: selected) { _, pick in
            if case .territory(let t)? = pick, state.armies[t]?.owner == session.human, session.human != nil { offer(.orders) }
        }
        .onChange(of: engine.collapsePressure(state) > 0) { _, on in if on { offer(.collapse) } }
        .onChange(of: knowledgeLevels) { old, new in if new > old { offer(.knowledge) } }
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
            if let toast = session.toast {
                Label(toast.text, systemImage: toast.bad ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .font(.callout.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background((toast.bad ? Color(red: 0.6, green: 0.15, blue: 0.12) : Color(red: 0.15, green: 0.5, blue: 0.3)).opacity(0.95), in: Capsule())
                    .shadow(radius: 4)
                    .id(toast.id)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: toast.id) {
                        do { try await Task.sleep(for: .seconds(2.6)) } catch { return }
                        withAnimation { if session.toast?.id == toast.id { session.toast = nil } }
                    }
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
            if !session.showReport, tip != .map, session.isHumanTurn, session.moments.isEmpty {
                HStack(spacing: 8) {
                    if offerCount > 0 {
                        notice("🕊️ \(offerCount) peace offer\(offerCount == 1 ? "" : "s")", "View") { open(.diplomacy) }
                    }
                    if !session.report.isEmpty, !session.report.contains(where: { $0.mine == true }) {
                        notice("📜 \(session.report.count) events elsewhere", "Read") { session.showReport = true }
                    }
                }
            }
            Spacer(minLength: 0)
            if let selected, pending == nil, session.human != nil {
                HStack(alignment: .bottom, spacing: 10) {
                    CommandBar(session: session, pick: selected) { self.selected = nil }
                        .id(selected)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    turnControls
                }
            } else {
            HStack(alignment: .bottom) {
                if let quickLook {
                    QuickLookCard(id: quickLook, session: session) { self.quickLook = nil }
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                Spacer()
                if let tip, !session.showReport || tip == .map {
                    TipBanner(tip: tip) {
                        tip.markSeen()
                        self.tip = nil
                        showNextTip()
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    legend
                }
                Spacer()
                turnControls
            }
            }
        }
        .padding(10)
        .animation(.spring(duration: 0.3), value: selected)
        .animation(.easeInOut(duration: 0.25), value: tip)
        .animation(.spring(duration: 0.3), value: session.toast?.id)
        .animation(.easeInOut(duration: 0.25), value: session.showReport)
        .animation(.easeInOut(duration: 0.25), value: quickLook)
    }

    /// Undo, next idle army, and End turn.
    private var turnControls: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if session.isHumanTurn {
                HStack(spacing: 8) {
                    if session.canUndo {
                        circleButton("arrow.uturn.backward", "Undo") {
                            pending = nil
                            session.undo()
                        }
                    }
                    if !idleArmies.isEmpty {
                        circleButton("figure.walk", "Next army that can move") { nextIdle() }
                    }
                }
            }
            turnButton
        }
    }

    private func circleButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.callout.weight(.semibold))
                .frame(width: 40, height: 40)
                .woodPanel(Circle())
        }
        .accessibilityLabel(label)
    }

    /// A small, dismissable pill for news that can wait.
    private func notice(_ text: String, _ action: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            HStack(spacing: 6) {
                Text(text).foregroundStyle(.primary)
                Text(action).bold()
            }
            .font(.callout)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .woodPanel(Capsule())
            .shadow(radius: 3)
        }
        .buttonStyle(.plain)
    }

    private var offerCount: Int {
        guard let human = session.human else { return 0 }
        return state.peaceOffers.filter { $0.to == human }.count
    }

    /// Where the player is looking: the order's target, else the selected territory.
    private var focusTerritory: TerritoryID? {
        switch pending {
        case let .march(_, to)?, let .land(_, to)?: return to
        case let .embark(from, _)?: return from
        case nil: break
        }
        if case .territory(let t)? = selected { return t }
        return nil
    }

    /// A moment's sound, jolt and screen effect, then it clears itself.
    private func play(_ moment: Moment) async {
        switch moment.kind {
        case .captured, .peace: SoundBoard.shared.play(.victory, volume: 0.5); Feedback.outcome(true)
        case .discovery: SoundBoard.shared.play(.horn, volume: 0.45); Feedback.outcome(true)
        case .lost, .war: SoundBoard.shared.play(.defeat, volume: 0.5); Feedback.outcome(false)
        case .disaster: SoundBoard.shared.play(.clash, volume: 0.6); Feedback.impact(1)
        case .unpaid: SoundBoard.shared.play(.coins, volume: 0.6); Feedback.outcome(false)
        case .attacked: SoundBoard.shared.play(.horn, volume: 0.7); Feedback.impact(1)
        case let .seaBattle(_, won, _): SoundBoard.shared.play(won ? .victory : .defeat, volume: 0.5); Feedback.outcome(won)
        }
        let fx = MomentBanner.effect(moment.kind)
        if fx.shake { withAnimation(.linear(duration: 0.5)) { shake += 1 } }
        if let color = fx.tint {
            withAnimation(.easeOut(duration: 0.2)) { tint = color }
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(.easeIn(duration: 0.8)) { tint = nil }
            if Task.isCancelled { return }
        }
        if case let .captured(t) = moment.kind {
            mapCenter = MapCenter(territory: t, id: (mapCenter?.id ?? 0) + 1)
        }
        // A cancelled sleep throws: only the moment that's still showing may dismiss itself.
        // Discoveries stay up longer: there's something to read.
        let linger = if case .discovery = moment.kind { 4200 } else { 1900 }
        do { try await Task.sleep(for: .milliseconds(linger)) } catch { return }
        guard session.moments.first?.id == moment.id else { return }
        withAnimation(.easeInOut(duration: 0.3)) { session.dismissMoment() }
    }

    // MARK: Guidance

    private func offer(_ t: Tip) {
        guard session.human != nil, t.isNew, tip != t, !tipQueue.contains(t) else { return }
        tipQueue.append(t)
        if tip == nil { showNextTip() }
    }

    /// The earliest waiting tip comes next, so the basics always come first.
    private func showNextTip() {
        tipQueue.sort { Tip.allCases.firstIndex(of: $0)! < Tip.allCases.firstIndex(of: $1)! }
        while let next = tipQueue.first {
            tipQueue.removeFirst()
            if next.isNew { tip = next; return }
        }
    }

    /// A famine, drought or flood struck the player's harvest at the start of this turn.
    private var harvestHit: Bool {
        guard let human = session.human else { return false }
        return session.report.contains { $0.mine == true && $0.civ == human
            && ($0.text.hasPrefix("Famine") || $0.text.hasPrefix("Drought") || $0.text.hasPrefix("Floods")) }
    }

    /// Total knowledge levels, to notice a discovery.
    private var knowledgeLevels: Int {
        guard let human = session.human else { return 0 }
        return KnowledgeField.allCases.reduce(0) { $0 + engine.level($1, of: human, in: state) }
    }


    /// The player's armies that still have troops ready to move and somewhere new to go: next to
    /// land that isn't theirs, or on a coast where their own ships wait.
    private var idleArmies: [TerritoryID] {
        guard let human = session.human, session.isHumanTurn else { return [] }
        return state.armies(of: human).filter { t, units in
            let ready = units - (state.moved[t] ?? .zero)
            guard ready.total > 0 else { return false }
            let frontier = engine.map.landNeighbors(of: t).contains { n in
                guard let owner = state.owner(of: n) else { return true }
                return owner != human && !state.atPeace(human, owner)
            }
            return frontier
        }.map(\.territory).sorted()
    }

    private func nextIdle() {
        let list = idleArmies
        guard !list.isEmpty else { return }
        idleIndex = (idleIndex + 1) % list.count
        pending = nil
        selected = .territory(list[idleIndex])
        if tab == .orders { panelOpen = false }
    }

    /// A gentle reminder before ending the turn: armies that could act, gold piling up.
    private var nudge: String? {
        guard let human = session.human, let cs = state.civs[human] else { return nil }
        var parts: [String] = []
        let idle = idleArmies.count
        if idle > 0 { parts.append("\(idle) arm\(idle == 1 ? "y" : "ies") can still move") }
        if cs.gold >= 3 * engine.rules.stats(.infantry).cost + 10 { parts.append("\(cs.gold) gold unspent") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The attack being composed, as an arrow on the map with its odds.
    private var planned: (from: TerritoryID, to: TerritoryID, label: String?)? {
        guard case let .march(from, to)? = pending else { return nil }
        let label = session.plannedOdds.map { Outlook($0).word }
        return (from, to, label)
    }

    private var layerPicker: some View {
        Picker("Map", selection: $layer) {
            ForEach(MapLayer.allCases.filter { session.human != nil || $0 != .supply }, id: \.self) {
                Text($0.rawValue).tag($0)
            }
        }
        .pickerStyle(.segmented)
        .frame(minWidth: 300, maxWidth: 340)
        .layoutPriority(1)
        .padding(4)
        .woodPanel(RoundedRectangle(cornerRadius: 10))
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
                    Button { explain = .gold } label: { stat("Gold", "\(cs.gold)", change: econ.netIncome, color: .orange) }
                    Button { explain = .grain } label: {
                        stat(harvestHit ? "Grain ⚠" : "Grain", "\(econ.granary)", change: econ.grainBalance, color: .green)
                    }
                    Button { explain = .people } label: { stat("People", "\(state.totalPopulation(of: human))", change: nil, color: .teal) }
                    Button { explain = .legitimacy } label: { stat("Legitimacy", "\(cs.legitimacy)", change: nil, color: .purple) }
                }
                .buttonStyle(.plain)
                .popover(item: $explain) { topic in
                    StatExplainer(topic: topic, session: session)
                        .presentationCompactAdaptation(.popover)
                }
                // The resources that limit what you can raise and build, at a glance.
                Button {
                    resourcesAt = nil
                    showResources = true
                } label: {
                    HStack(spacing: 7) {
                        ForEach([Resource.horses, .timber, .copper, .tin, .stone], id: \.self) { r in
                            let n = econ.resources[r] ?? 0
                            HStack(spacing: 1) {
                                MapView.icon(r).font(.body)
                                Text("\(n)").font(.subheadline.bold().monospacedDigit())
                            }
                            .foregroundStyle(n == 0 ? Color.red.opacity(0.8) : Color.primary)
                        }
                        Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Resources")
                if !econ.cutOff.isEmpty {
                    Label("\(econ.cutOff.count) cut off", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.red)
                }
            }
        }
        .padding(10)
        .fixedSize()
        .woodPanel(RoundedRectangle(cornerRadius: 12))
    }

    private var toolbar: some View {
        HStack(spacing: 4) {
            if session.human != nil {
                toolButton("Throne room", "crown.fill", badge: councilAlarms) { showThrone = true }
                toolButton("Empire", "building.columns.fill") { open(.empire) }
                toolButton("Diplomacy", "person.2.fill", badge: offerCount) { open(.diplomacy) }
                toolButton("Knowledge", "books.vertical.fill") { showKnowledge = true }
            }
            toolButton("Chronicle", "scroll.fill", badge: unreadLog) { open(.log); seenLog = session.log.first?.id ?? 0 }
            Menu {
                Button("How to play", systemImage: "book") { showWalkthrough = true }
                Button("Rules reference", systemImage: "text.book.closed") { showCodex = true }
                Button("Show tips again", systemImage: "lightbulb") { Tip.seen = [] }
                Button("New game", role: .destructive) { session.quit() }
            } label: {
                Image(systemName: "ellipsis").frame(width: 34, height: 34)
            }
        }
        .padding(4)
        .woodPanel(RoundedRectangle(cornerRadius: 12))
    }

    /// Advisors with something urgent to say.
    private var councilAlarms: Int {
        guard session.isHumanTurn else { return 0 }
        return Council.advice(session, quick: true).filter { $0.mood == .alarm }.count
    }

    private func toolButton(_ title: String, _ symbol: String, badge: Int = 0, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 34, height: 34)
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        Text(badge > 9 ? "9+" : "\(badge)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(.red, in: Capsule())
                            .offset(x: 4, y: -2)
                    }
                }
        }
        .accessibilityLabel(badge > 0 ? "\(title), \(badge) new" : title)
    }

    /// Chronicle lines the player hasn't opened the Chronicle to see.
    private var unreadLog: Int {
        session.log.filter { $0.id > seenLog && $0.mine == true }.count
    }

    @ViewBuilder private var turnButton: some View {
        if session.human != nil {
            if session.busy {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Rivals move…").font(.callout)
                    if !session.skipping {
                        Button("Skip") { session.skipping = true }.font(.callout.bold())
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .woodPanel(Capsule())
            } else if session.isHumanTurn {
                Button {
                    selected = nil
                    pending = nil
                    panelOpen = false
                    SoundBoard.shared.play(.drum, volume: 0.7)
                    Feedback.impact(0.8)
                    session.endTurn()
                } label: {
                    VStack(spacing: 0) {
                        Label("End turn", systemImage: "hourglass")
                            .font(.system(.callout, design: .serif).weight(.bold))
                        if let nudge {
                            Text(nudge).font(.caption2).opacity(0.8)
                        }
                    }
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(.black)
                    .padding(.horizontal, 18).padding(.vertical, 9)
                    .background(Bronze.gradient, in: Capsule())
                    .overlay(Capsule().stroke(Color(red: 0.4, green: 0.25, blue: 0.1), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .shadow(color: .black.opacity(0.4), radius: 5, y: 2)
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
            .woodPanel(Capsule())
        }
    }

    private var spotlightTerritories: Set<TerritoryID> {
        guard let r = spotlit else { return [] }
        return Set(engine.map.territories.filter { engine.territoryYield(r, $0.id, state) > 0 }.map(\.id))
    }

    @ViewBuilder private var legend: some View {
        if let r = spotlit {
            Button {
                spotlit = nil
            } label: {
                HStack(spacing: 6) {
                    Text("\(MapView.icon(r)) Where to find \(r.rawValue)")
                    Image(systemName: "xmark.circle.fill")
                }
                .font(.callout.bold())
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.yellow.opacity(0.9), in: Capsule())
                .foregroundStyle(.black)
            }
        } else {
            layerLegend
        }
    }

    @ViewBuilder private var layerLegend: some View {
        let text: String? = switch layer {
        case .armies: nil
        case .threats: "Red: more hostile troops can reach it next turn than defend it · orange: threatened but held · ⚔︎ attackers vs garrison"
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
            if tab == .orders, let pending, session.isHumanTurn {
                // The order composer scrolls its own choices and keeps its buttons in view.
                OrderComposer(session: session, order: pending) { done in
                    self.pending = nil
                    if let done { selected = done }
                    panelOpen = false
                }
                .id(pending)
            } else {
                ScrollView {
                    Group {
                    switch tab {
                    case .orders: orders
                    case .empire: EmpireView(session: session)
                    case .diplomacy: DiplomacyView(session: session)
                    case .log: ChronicleView(session: session)
                    }
                    }
                    .padding(.trailing, 4)
                }
            }
        }
        .padding(12)
        .frame(width: Self.panelWidth)
        .frame(maxHeight: .infinity)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 16)
                .fill(Wood.gradient)
                .overlay(UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 16).stroke(Bronze.gradient, lineWidth: 2))
                .shadow(color: .black.opacity(0.4), radius: 10)
                .ignoresSafeArea()
        }
        .environment(\.colorScheme, .dark)
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
            if case .territory(let id)? = selected {
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
                    // Enemy ships there: draw up for a sea battle first.
                    if state.fleets.contains(where: { $0.sea == t && $0.ships > 0 && state.atWar(session.human!, $0.owner) }) {
                        session.muster = Muster(from: s, to: t, units: .zero, general: false, ships: ready, cargo: cargo)
                        tab = .orders
                        panelOpen = true
                        return
                    }
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
        if pick != nil { SoundBoard.shared.play(.click, volume: 0.35) }
        // Selections show along the bottom; the side panel is for orders being composed and tabs.
        if tab == .orders { panelOpen = false }
    }
}
