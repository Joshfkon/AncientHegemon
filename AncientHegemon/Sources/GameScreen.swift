import HegemonCore
import SwiftUI

/// An order the player has started on the map and is finishing in the panel.
enum PendingOrder: Hashable {
    case march(from: TerritoryID, to: TerritoryID)
    case embark(from: TerritoryID, sea: SeaZoneID)
    case land(sea: SeaZoneID, to: TerritoryID)
    /// Board the ships off this coast, sail if need be, and land across the water: one order.
    case seaAssault(from: TerritoryID, to: TerritoryID, route: SeaRouteKey)
}

/// A sea route as a hashable value for the pending order.
struct SeaRouteKey: Hashable {
    let board: SeaZoneID
    let land: SeaZoneID
    let room: Int
    init(_ r: SeaRoute) { board = r.board; land = r.land; room = r.room }
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
    /// For a two-step road march being composed: the land it passes through.
    @State private var roadVia: TerritoryID?
    /// The army's menu rather than the land's: the cube was tapped.
    @State private var armyFocus = false
    @State private var tab = PanelTab.orders
    @State private var panelOpen = false
    @State private var showKnowledge = false
    @State private var showCodex = false
    @State private var showWalkthrough = false
    @State private var showThrone = false
    @State private var showStandings = false
    @State private var showTrade = false
    @State private var cityShown: CityPick?

    struct CityPick: Identifiable { let id: TerritoryID }
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

    var body: some View { watching(screen) }

    private var screen: some View {
        ZStack {
            MapView(state: state, map: engine.map, engine: engine, layer: layer, focus: session.human,
                    selected: selected, targets: targets, onTap: tapped, onCubeTap: { armyFocus = $0 },
                    onLongPress: { pick in
                        if case .territory(let t)? = pick { quickLook = t; Feedback.select() }
                    },
                    marks: session.marks, markTimes: session.markTimes, planned: planned, idle: session.isHumanTurn ? Set(idleArmies) : [],
                    trailingInset: panelOpen ? Self.panelWidth : 0,
                    bottomInset: selected != nil && pending == nil && session.human != nil ? 190 : 0, center: mapCenter,
                    spotlight: spotlightTerritories, flashes: session.flashes, sight: session.sight)
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
            if session.crisis != nil, session.replay == nil, session.muster == nil, session.moments.isEmpty {
                ZStack {
                    Color.black.opacity(0.45).ignoresSafeArea()
                    CrisisView(session: session)
                }
                .transition(.opacity)
            }
            if let human = session.human, let kind = state.civs[human]?.decision, session.isHumanTurn,
               session.moments.isEmpty, !session.showReport {
                DecisionCard(session: session, kind: kind)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
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
        .fullScreenCover(item: $session.audience) { a in
            AudienceView(session: session, audience: a) { session.audience = nil }
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
        .sheet(isPresented: $showKnowledge) {
            if let human = session.human {
                NavigationStack {
                    TechTreeView(civ: human, state: state, engine: engine, session: session)
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
                EndScreen(session: session, victory: victory, close: {
                    endDismissed = true
                    session.quit()
                }, playOn: {
                    endDismissed = true
                    session.playOn()
                })
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
        .fullScreenCover(item: $cityShown) { pick in
            CityView(session: session, territory: pick.id) { cityShown = nil }
        }
        .sheet(isPresented: $showTrade) {
            NavigationStack {
                TradeView(session: session) { _ in }.toolbar { Button("Done") { showTrade = false } }
            }
        }
        .sheet(isPresented: $showStandings) {
            NavigationStack {
                StandingsView(session: session).toolbar { Button("Done") { showStandings = false } }
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
            if UserDefaults.standard.bool(forKey: "demoCrisis") { session.demoCrisis() }
            if UserDefaults.standard.bool(forKey: "demoHost") { session.demoHost() }
            if UserDefaults.standard.bool(forKey: "demoSiege") { session.demoSiege() }
            if UserDefaults.standard.bool(forKey: "demoRebellion"), let human = session.human,
               let seat = engine.seat(of: human, in: state) {
                session.moments = [Moment(kind: .rebellion(general: "Horemheb", lands: [seat], rebel: human, bribed: true))]
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
    }

    /// Reactions to the game moving on: following rivals, offering tips, releasing gains.
    private func watching<V: View>(_ view: V) -> some View {
        view
        .onChange(of: focusTerritory) { _, t in
            guard let t, panelOpen else { return }
            mapCenter = MapCenter(territory: t, id: (mapCenter?.id ?? 0) + 1)
        }
        .onChange(of: session.marks.count) { _, _ in
            // Follow the rivals around the map as they move.
            guard session.busy, !session.skipping, let mark = session.marks.last, session.inSight(mark) else { return }
            let place: TerritoryID? = switch mark {
            case let .march(_, _, to, _), let .landing(_, _, to, _): to
            case let .battle(at, _, _): at
            case let .captured(t, _), let .event(t, _), let .raised(t, _, _, _): t
            case .gain: nil
            }
            if let place { mapCenter = MapCenter(territory: place, id: (mapCenter?.id ?? 0) + 1) }
        }
        .onChange(of: panelOpen) { _, open in
            guard open, let t = focusTerritory else { return }
            mapCenter = MapCenter(territory: t, id: (mapCenter?.id ?? 0) + 1)
        }
        .onChange(of: session.showReport) { _, shown in if shown { offer(.rivals) } }
        .onChange(of: !session.showReport && courtSettled) { _, clear in if clear { session.releaseGains() } }
        .onChange(of: readyForAudience) { _, ready in if ready { session.nextAudience() } }
        .onChange(of: session.audience == nil) { _, gone in if gone, readyForAudience { session.nextAudience() } }
        .onChange(of: session.gainsAt?.id) { _, _ in lookAtGains() }
        .onChange(of: pending) { _, p in
            if case let .march(_, to)? = p, state.armies[to].map({ $0.owner != session.human }) ?? false { offer(.battle) }
            if p == nil { session.plannedOdds = nil }
        }
        .onChange(of: selected) { _, pick in
            // Keep what's selected in view, above the command bar.
            if case .territory(let t)? = pick { mapCenter = MapCenter(territory: t, id: (mapCenter?.id ?? 0) + 1) }
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
                if !panelOpen {
                    VStack(spacing: 6) {
                        layerPicker
                        if session.human != nil { StandingsBar(session: session) { showStandings = true } }
                    }
                }
                Spacer(minLength: 8)
                toolbar
            }
            if let toast = session.toast {
                Label(toast.text, systemImage: toast.bad ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .font(.system(.callout, design: .serif).weight(.bold))
                    .foregroundStyle(toast.bad ? Color(red: 1, green: 0.55, blue: 0.45) : Color(red: 0.6, green: 0.95, blue: 0.6))
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .woodPanel(Capsule())
                    .id(toast.id)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: toast.id) {
                        do { try await Task.sleep(for: .seconds(2.6)) } catch { return }
                        withAnimation { if session.toast?.id == toast.id { session.toast = nil } }
                    }
            }
            if let message = session.message {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .foregroundStyle(Color(red: 1, green: 0.6, blue: 0.5))
                    .woodPanel(Capsule())
                    .onTapGesture { session.message = nil }
                    .transition(.opacity)
            }
            if !session.showReport, tip != .map, session.isHumanTurn, session.moments.isEmpty, selected == nil, pending == nil {
                HStack(spacing: 8) {
                    if let human = session.human, let call = state.warRequests.first(where: { $0.to == human }) {
                        notice("📯 \(Palette.name(call.from, state)) calls you to arms", "Answer") { open(.diplomacy) }
                    }
                    if let human = session.human, let offer = state.allianceOffers.first(where: { $0.to == human }) {
                        notice("🛡️ \(Palette.name(offer.from, state)) proposes an alliance", "View") { open(.diplomacy) }
                    }
                    if let human = session.human {
                        // Each offer answered right here; more than two wait on the Rivals tab.
                        let offers = state.peaceOffers.filter { $0.to == human }.map(\.from).sorted()
                        ForEach(offers.prefix(2), id: \.self) { from in peaceNotice(from) }
                        if offers.count > 2 { notice("🕊️ +\(offers.count - 2) more", "View") { open(.diplomacy) } }
                    }
                    if !session.report.isEmpty, !session.report.contains(where: { $0.mine == true }) {
                        notice("📜 \(session.report.count) events elsewhere", "Read") { session.showReport = true }
                    }
                }
            }
            Spacer(minLength: 0)
            if let selected, pending == nil, session.human != nil {
                HStack(alignment: .bottom, spacing: 10) {
                    CommandBar(session: session, pick: selected, close: { self.selected = nil },
                               enter: { cityShown = CityPick(id: $0) },
                               armyView: armyFocus, switchView: { armyFocus = $0 })
                        .id("\(String(describing: selected))-\(armyFocus)")
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
            if session.isHumanTurn, !session.busy { NextTurnLine(session: session) }
            turnButton
        }
    }

    private func circleButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.callout.weight(.semibold))
                .foregroundStyle(Bronze.gradient)
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

    /// "Greece offers peace": accept or decline without leaving the map.
    private func peaceNotice(_ from: CivilizationID) -> some View {
        HStack(spacing: 8) {
            Text("🕊️ \(Palette.name(from, state)) offers peace").font(.callout).foregroundStyle(.white)
            Button("Decline") {
                if session.order(.declinePeace(from: from)) { Feedback.select() }
            }
            .font(.callout.bold()).foregroundStyle(.white.opacity(0.8))
            Button("Accept") {
                if session.order(.acceptPeace(from: from)) { SoundBoard.shared.play(.horn, volume: 0.4) }
            }
            .font(.callout.bold()).foregroundStyle(Bronze.gradient)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .woodPanel(Capsule())
        .shadow(radius: 3)
    }

    private var offerCount: Int {
        guard let human = session.human else { return 0 }
        return state.peaceOffers.filter { $0.to == human }.count
    }

    /// Where the player is looking: the order's target, else the selected territory.
    private var focusTerritory: TerritoryID? {
        switch pending {
        case let .march(_, to)?, let .land(_, to)?, let .seaAssault(_, to, _)?: return to
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
        case .ally(_, let joined): SoundBoard.shared.play(joined ? .horn : .defeat, volume: 0.5); Feedback.outcome(joined)
        case .allyJoins: SoundBoard.shared.play(.roar, volume: 0.6); Feedback.outcome(true)
        case .callToArms: SoundBoard.shared.play(.wardrums, volume: 0.5); Feedback.impact(0.7)
        case let .seaBattle(_, won, _): SoundBoard.shared.play(won ? .victory : .defeat, volume: 0.5); Feedback.outcome(won)
        case let .monument(_, civ):
            let ours = civ == session.human
            SoundBoard.shared.play(ours ? .victory : .horn, volume: 0.5); Feedback.outcome(ours)
        case .monumentLost: SoundBoard.shared.play(.defeat, volume: 0.5); Feedback.outcome(false)
        case .rebellion: SoundBoard.shared.play(.wardrums, volume: 0.7); Feedback.impact(1)
        case let .besieged(_, by): SoundBoard.shared.play(.wardrums, volume: 0.6); Feedback.impact(by == session.human ? 0.5 : 1)
        case let .sacked(_, by, _): SoundBoard.shared.play(by == session.human ? .victory : .defeat, volume: 0.6); Feedback.outcome(by == session.human)
        case let .splendour(began): SoundBoard.shared.play(began ? .horn : .click, volume: 0.5); Feedback.outcome(began)
        case .ironAge: SoundBoard.shared.play(.clash, volume: 0.6); Feedback.impact(0.8)
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
        if case let .rebellion(_, lands, _, _) = moment.kind, let t = lands.first {
            mapCenter = MapCenter(territory: t, id: (mapCenter?.id ?? 0) + 1)
        }
        // A cancelled sleep throws: only the moment that's still showing may dismiss itself.
        // Discoveries stay up longer: there's something to read.
        let linger = switch moment.kind { case .discovery, .monument, .rebellion, .splendour, .ironAge, .sacked: 4200; default: 1900 }
        do { try await Task.sleep(for: .milliseconds(linger)) } catch { return }
        guard session.moments.first?.id == moment.id else { return }
        withAnimation(.easeInOut(duration: 0.3)) { session.dismissMoment() }
    }

    private func lookAtGains() {
        if let t = session.gainsAt?.territory { mapCenter = MapCenter(territory: t, id: (mapCenter?.id ?? 0) + 1) }
    }

    /// The player's turn, with nothing else on screen: rulers may be received.
    private var readyForAudience: Bool {
        session.isHumanTurn && !session.busy && !session.showReport && session.moments.isEmpty && courtSettled
            && session.replay == nil && session.muster == nil
    }

    /// No dilemma or succession crisis waits for an answer.
    private var courtSettled: Bool {
        guard let human = session.human else { return true }
        return state.civs[human]?.decision == nil && session.crisis == nil
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
        armyFocus = true
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
                Text((state.playingOn == true ? "Round \(state.turn) · playing on" : "Round \(state.turn)/\(engine.rules.victory.roundLimit)")
                     + (state.ironAge ? " · Iron Age" : ""))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            if let human = session.human, let left = state.civs[human]?.splendour, left > 0 {
                Label("Age of splendour · \(left) round\(left == 1 ? "" : "s") left", systemImage: "sun.max.fill")
                    .font(.caption.bold()).foregroundStyle(Bronze.gradient)
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
                toolButton("Trade", "arrow.left.arrow.right") { showTrade = true }
                toolButton("Diplomacy", "person.2.fill", badge: offerCount) { open(.diplomacy) }
                toolButton("Knowledge", "books.vertical.fill", hint: session.human.map { state.civs[$0]?.patronage == nil } ?? false) {
                    showKnowledge = true
                }
            }
            toolButton("Chronicle", "scroll.fill", badge: unreadLog) { open(.log); seenLog = session.log.first?.id ?? 0 }
            Menu {
                Button("How to play", systemImage: "book") { showWalkthrough = true }
                Button("Rules reference", systemImage: "text.book.closed") { showCodex = true }
                Button("Show tips again", systemImage: "lightbulb") { Tip.seen = [] }
                Button("New game", role: .destructive) { session.quit() }
            } label: {
                Image(systemName: "ellipsis").foregroundStyle(Bronze.gradient).frame(width: 34, height: 34)
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

    /// `hint` puts a small bronze dot on the button: something there is waiting for a choice.
    private func toolButton(_ title: String, _ symbol: String, badge: Int = 0, hint: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(Bronze.gradient)
                .frame(width: 34, height: 34)
                .overlay(alignment: .topTrailing) {
                    if badge == 0, hint {
                        Circle().fill(Bronze.gradient).frame(width: 9, height: 9)
                            .overlay(Circle().stroke(.black.opacity(0.6), lineWidth: 1))
                            .offset(x: 3, y: -1)
                    }
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
                        Button(session.fastRivals ? "2×" : "1×") { session.fastRivals.toggle() }
                            .font(.callout.bold().monospacedDigit())
                            .foregroundStyle(session.fastRivals ? AnyShapeStyle(Bronze.gradient) : AnyShapeStyle(.white.opacity(0.75)))
                            .accessibilityLabel(session.fastRivals ? "Double speed" : "Normal speed")
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
        case .resources: nil
        }
        if layer == .resources {
            ([Resource.grain] + ResourcesView.order).reduce(Text("")) { t, r in t + MapView.icon(r) + Text(" \(r.rawValue)   ") }
                .font(.caption2).foregroundStyle(.white)
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
                OrderComposer(session: session, order: pending, via: roadVia) { done in
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
            if let victory = state.victory, state.winner != nil {
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

    /// Coasts the selected army can sail to this turn with the ships offshore.
    /// Land the selected army can reach in one order by marching along a road: the first step
    /// to a neighbour with a road (ours, no one to fight), then one more step anywhere. Keyed by
    /// destination, with the land passed through.
    private var roadTargets: [TerritoryID: TerritoryID] {
        guard session.isHumanTurn, let human = session.human, case .territory(let from)? = selected,
              let army = state.armies[from], army.owner == human else { return [:] }
        let fresh = army.units - (state.moved[from] ?? .zero) - (state.roadMoved[from] ?? .zero)
        guard fresh.total > 0 else { return [:] }
        let near = Set(engine.map.landNeighbors(of: from))
        var result: [TerritoryID: TerritoryID] = [:]
        for via in near.sorted() where engine.roadLinks(from, via, for: human, in: state) {
            for to in engine.map.landNeighbors(of: via).sorted() where to != from && !near.contains(to) && result[to] == nil {
                if let owner = state.owner(of: to), owner != human, state.atPeace(human, owner) { continue }
                result[to] = via
            }
        }
        return result
    }

    private var seaRoutes: [TerritoryID: SeaRoute] {
        guard session.isHumanTurn, let human = session.human, case .territory(let from)? = selected,
              let army = state.armies[from], army.owner == human,
              (army.units - (state.moved[from] ?? .zero)).total > 0 else { return [:] }
        return engine.seaRoutes(from: from, for: human, in: state)
    }

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
            // Coasts across the water that the ships offshore can carry this army to.
            picks.formUnion(seaRoutes.keys.map(MapPick.territory))
            // Land two steps away along a road, in one order.
            picks.formUnion(roadTargets.keys.map(MapPick.territory))
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
            case let (.territory(a), .territory(b)):
                roadVia = nil
                if !engine.map.areLandAdjacent(a, b), let via = roadTargets[b] {
                    roadVia = via
                    pending = .march(from: a, to: b)
                } else if !engine.map.areLandAdjacent(a, b), let route = seaRoutes[b] {
                    pending = .seaAssault(from: a, to: b, route: SeaRouteKey(route))
                } else {
                    pending = .march(from: a, to: b)
                }
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
