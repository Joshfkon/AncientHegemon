import HegemonCore
import SwiftUI

/// Advisors who step forward at the start of the player's turn: the council of the throne room,
/// speaking up unasked. Each system gets an introduction the first time it matters (once a game),
/// and a reminder later when something needs attention (with a cooldown, so they don't nag).
/// One at a time, in a small card with a button that goes to the right place.
struct AdvisorCall: Identifiable, Equatable {
    enum Go: Equatable {
        case realm, knowledge, diplomacy
        case territory(TerritoryID)
        case city(TerritoryID)
        case sea(SeaZoneID)
    }

    /// What it's about, for memory: "intro.taxes" is said once; the rest come back after `cooldown`.
    let key: String
    let role: Advisor.Role
    let name: String
    let line: String
    let mood: Advisor.Mood
    let go: Go?
    /// Rounds before the same reminder may come again (intros never repeat).
    var cooldown = 5
    var id: String { key }
    var isIntro: Bool { key.hasPrefix("intro.") }

    var title: String {
        switch role {
        case .general: "General"
        case .steward: "Steward"
        case .envoy: "Envoy"
        case .priest: "High priest"
        }
    }

    var goLabel: String {
        switch go {
        case .realm?: "Open the Realm"
        case .knowledge?: "Open the books"
        case .diplomacy?: "Open Rivals"
        case .city?: "Enter the city"
        case .territory?, .sea?: "Show me"
        case nil: ""
        }
    }
}

/// What the advisors have already said this game: each topic's key and the round it was said.
struct AdvisorMemory: Codable {
    var game: String
    var said: [String: Int] = [:]
    /// How many have spoken on `round`; at most two a turn.
    var round = 0
    var spoken = 0

    static let enabledKey = "advisorsOn"
    private static let key = "advisorMemory"

    static func load(game: String) -> AdvisorMemory {
        if let data = UserDefaults.standard.data(forKey: key),
           let m = try? JSONDecoder().decode(AdvisorMemory.self, from: data), m.game == game { return m }
        return AdvisorMemory(game: game)
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    /// An introduction also starts its topic's reminder cooldown ("intro.siege" then "siege").
    mutating func note(_ call: AdvisorCall, round now: Int) {
        said[call.key] = now
        if call.isIntro { said[String(call.key.dropFirst("intro.".count))] = now }
        if round != now { round = now; spoken = 0 }
        spoken += 1
        save()
    }

    func due(_ call: AdvisorCall, round now: Int) -> Bool {
        guard let last = said[call.key] else { return true }
        return !call.isIntro && now - last >= call.cooldown
    }
}

enum Advisors {
    static let perTurn = 2

    /// The one game being played, so a new game starts with fresh introductions.
    @MainActor static func gameKey(_ session: GameSession) -> String {
        "\(session.seed)-\(session.human ?? "")"
    }

    /// The advisor who should speak now, if any: alarms first, then introductions, then reminders.
    @MainActor static func next(_ session: GameSession, memory: AdvisorMemory) -> AdvisorCall? {
        let now = session.state.turn
        if memory.round == now, memory.spoken >= perTurn { return nil }
        let due = calls(session).filter { memory.due($0, round: now) }
        // The second advisor of a turn only for something that matters.
        if memory.round == now, memory.spoken > 0 { return due.first { $0.mood == .alarm || $0.isIntro } }
        return due.first
    }

    /// Everything the council would say about the realm right now, most pressing first.
    @MainActor static func calls(_ session: GameSession) -> [AdvisorCall] {
        guard let civ = session.human, let cs = session.state.civs[civ], let e = session.economy else { return [] }
        let engine = session.engine, state = session.state, map = engine.map
        let names = Advisor.names(civ)
        let news = session.sinceLastTurn
        func place(_ t: String) -> String { map.territory(t)?.name ?? map.sea(t)?.name ?? t }
        func who(_ c: CivilizationID) -> String { Palette.name(c, state) }
        func s(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
        func say(_ key: String, _ role: Advisor.Role, _ mood: Advisor.Mood, _ line: String,
                 go: AdvisorCall.Go? = nil, cooldown: Int = 5) -> AdvisorCall {
            AdvisorCall(key: key, role: role, name: names[role] ?? "", line: line, mood: mood, go: go, cooldown: cooldown)
        }
        var alarms: [AdvisorCall] = [], intros: [AdvisorCall] = [], reminders: [AdvisorCall] = []

        // Food.
        let starved = news.contains { if case let .starvation(c, _, _) = $0 { c == civ } else { false } }
        if e.grainBalance < 0 || starved {
            let turns = e.grainBalance < 0 ? e.granary / max(1, -e.grainBalance) : 0
            if starved || turns <= 2 {
                alarms.append(say("famine", .steward, .alarm, starved
                    ? "People starved in the night: the granary is bare. Build farms, bring grain by trade, or send soldiers home before more die."
                    : "The granary is nearly empty: \(s(e.granary, "measure")) left, and we eat \(-e.grainBalance) more than we grow each turn. Famine is \(turns <= 0 ? "upon us" : "\(s(turns, "turn")) away").",
                    go: .realm, cooldown: 3))
            }
        }

        // Pay.
        let deserted = news.reduce(0) { n, ev in if case let .armyPaid(c, _, d) = ev, c == civ { n + d } else { n } }
        if deserted > 0 {
            alarms.append(say("unpaid", .steward, .alarm,
                "The treasury ran dry and \(s(deserted, "unpaid soldier")) went home. Raise taxes, or keep a smaller army.",
                go: .realm, cooldown: 2))
        } else if e.netIncome < 0, cs.gold + e.netIncome < 0 {
            alarms.append(say("unpaid", .steward, .warning,
                "Next turn the army's pay (\(e.pay) gold) outruns the treasury. Unpaid soldiers will desert. Raise taxes or disband some troops.",
                go: .realm, cooldown: 3))
        }

        // Our towns under siege.
        for (town, siege) in state.sieges.sorted(by: { $0.key < $1.key }) where state.owner(of: town) == civ && siege.civ != civ {
            // The first time, how sieges work; after that, a reminder (memory picks which).
            alarms.append(say("intro.besieged", .general, .alarm,
                "\(who(siege.civ)) has camped outside \(place(town)). A besieged town grows no grain and pays no taxes; its granary holds a few rounds, then the garrison starves, and the walls crumble round by round. Sally out against the camp, or march a relief army at it.",
                go: .territory(town)))
            alarms.append(say("besieged", .general, .alarm,
                "\(place(town)) is still besieged by \(who(siege.civ)), \(s(siege.rounds, "round")) now. Its walls wear down; break the siege before it's stormed.",
                go: .territory(town), cooldown: 2))
            break
        }

        // Armies cut off from supply.
        let cutArmies = state.armies(of: civ).map(\.territory).filter(e.cutOff.contains)
        if let t = cutArmies.first {
            alarms.append(say("cutOff", .general, .alarm,
                "Our army in \(place(t)) is cut off from the capital. No grain reaches it and it wastes away a unit each turn. Fight back to our lines, or reopen the road.",
                go: .territory(t), cooldown: 3))
        }

        // Introductions, each the first time it matters.
        let harvested = news.contains { if case let .harvest(c, _, _, _, _, _) = $0 { c == civ } else { false } }
        if harvested || state.turn >= 2 {
            intros.append(say("intro.taxes", .steward, .calm,
                "The first harvest is counted. At \(e.taxRate)% taxes we take in \(e.taxes) gold a turn, \(e.netIncome >= 0 ? "+\(e.netIncome)" : "\(e.netIncome)") after the army's pay. Higher taxes fill the treasury, but the people grow more slowly and grumble against the throne. You set the rate in the Realm.",
                go: .realm))
        }
        if state.turn >= 2, cs.patronage == nil {
            intros.append(say("intro.knowledge", .priest, .calm,
                "Your people learn by doing: farming teaches farming, war teaches war. But the court may fund the masters of one craft for \(engine.rules.patronage.gold) gold a turn, and that knowledge grows far faster. Open the books and choose.",
                go: .knowledge))
        }
        if let offer = state.peaceOffers.filter({ $0.to == civ }).map(\.from).sorted().first {
            intros.append(say("intro.peace", .envoy, .warning,
                "\(who(offer)) has offered us peace. Peace lets trade flow between us and frees our armies for other fronts, but breaking it later costs legitimacy. Answer on the map, or in Rivals.",
                go: .diplomacy))
            reminders.append(say("peace", .envoy, .calm,
                "\(who(offer))'s envoy still waits for an answer. Peace would open trade with them.", go: .diplomacy, cooldown: 4))
        }
        if let site = buildable(civ, session) {
            let c = site.cost
            let cost = (["\(c.gold) gold"] + (c.stone > 0 ? ["\(c.stone) stone"] : []) + (c.timber > 0 ? ["\(c.timber) timber"] : [])).joined(separator: ", ")
            intros.append(say("intro.building", .steward, .calm,
                "We could build \(projectName(site.kind).lowercased()) in \(place(site.at)) for \(cost). Farms feed more mouths, walls hold sieges, roads speed the army and the grain carts. Every town shows what it can build.",
                go: .city(site.at)))
            if cs.gold >= c.gold * 2 {
                reminders.append(say("building", .steward, .calm,
                    "The treasury holds \(cs.gold) gold. \(projectName(site.kind)) in \(place(site.at)) costs \(cost); gold in a vault builds nothing.",
                    go: .city(site.at), cooldown: 6))
            }
        }
        if let ours = state.sieges.sorted(by: { $0.key < $1.key }).first(where: { $0.value.civ == civ }) {
            let (town, siege) = (ours.key, ours.value)
            intros.append(say("intro.siege", .general, .calm,
                "Our camp has \(place(town)) shut in. Each round its walls wear and its garrison goes hungry; our camp sickens too, if it lingers. Storm the walls when they're weak enough, or starve them out.",
                go: .territory(siege.camp)))
            if siege.rounds >= 2 {
                reminders.append(say("siege", .general, .calm,
                    "\(s(siege.rounds, "round")) outside \(place(town)): the walls are down to +\(engine.fortification(at: town, state))%. The men ask when we storm them.",
                    go: .territory(siege.camp), cooldown: 3))
            }
        }
        let restless = engine.restlessLands(of: civ, in: state)
        if let t = restless.first {
            let line = "\(place(t))\(restless.count > 1 ? " and \(s(restless.count - 1, "other land"))" : "") will not pay taxes and murmur of revolt. Newly won land needs a garrison: a single soldier there would calm it."
            intros.append(say("intro.unrest", .steward, .warning, line, go: .territory(t)))
            reminders.append(say("unrest", .steward, .warning, line, go: .territory(t), cooldown: 4))
        }
        let fleets = state.fleets.filter { $0.owner == civ && $0.ships > 0 }.sorted { $0.sea < $1.sea }
        if let f = fleets.first(where: { !engine.sheltered($0.sea, for: civ, in: state) }) ?? fleets.first {
            intros.append(say("intro.sea", .general, .calm,
                "Our ships are at sea. Storms can sink a third of a fleet on open water; off a harbour of our own they ride it out. A fleet of 3 or more keeps pirates from its sea and the seas beside it.",
                go: .sea(f.sea)))
        }
        let coasts = Set(state.territories(of: civ).flatMap { map.seas(bordering: $0) })
        if let pirates = engine.pirateFleets(in: state).first(where: { coasts.contains($0.sea) }) {
            intros.append(say("intro.pirates", .general, .warning,
                "Pirates prowl the \(place(pirates.sea)). They plunder unwalled coasts with none of our ships nearby, and close the sea to trade. Three ships on patrol scatter them, and sinking them pays a bounty.",
                go: .sea(pirates.sea)))
        }
        // Vassals are kingdoms: each is named for its people, and shown at one of its lands.
        let vassals = engine.vassals(of: civ, in: state).compactMap { k -> (name: String, land: TerritoryID)? in
            guard let land = engine.lands(of: k, in: state).first else { return nil }
            return ((state.kingdoms[k]?.name ?? place(land)).capitalizedFirst, land)
        }
        if let (name, v) = vassals.first {
            intros.append(say("intro.vassals", .envoy, .calm,
                "\(name) are our vassals now. They send tribute each turn and levies every few rounds, and need no garrison. Leave them unwatched too long and they may break free; after years of loyalty, they may be annexed.",
                go: .territory(v)))
        }

        // Reminders.
        if e.taxRate <= 30, e.netIncome <= 1, cs.gold < 20 {
            reminders.append(say("taxLow", .steward, .warning,
                "The treasury is thin (\(cs.gold) gold, \(e.netIncome >= 0 ? "+" : "")\(e.netIncome) a turn) and taxes are only \(e.taxRate)%. The people could bear more.",
                go: .realm, cooldown: 6))
        }
        if e.taxLegitimacy < 0, cs.legitimacy < 45 {
            reminders.append(say("taxHigh", .priest, .warning,
                "Taxes of \(e.taxRate)% weigh on the people, and they blame the throne (legitimacy \(cs.legitimacy)). Lighter taxes would quiet them.",
                go: .realm, cooldown: 6))
        }
        let found = news.compactMap { ev -> (KnowledgeField, Int)? in
            if case let .discovery(c, f, l) = ev, c == civ { (f, l) } else { nil }
        }.first
        if cs.patronage == nil, let (field, _) = found {
            reminders.append(say("discovery", .priest, .calm,
                "The \(Patrons.patrons(field).lowercased()) have learned something new. No craft has a patron yet; fund one and its discoveries come far sooner.",
                go: .knowledge, cooldown: 6))
        } else if cs.patronage == nil, cs.gold >= engine.rules.patronage.gold * 4 {
            reminders.append(say("noPatron", .priest, .calm,
                "The scribes still ask for a patron. \(engine.rules.patronage.gold) gold a turn would speed one field of learning; the treasury can bear it.",
                go: .knowledge, cooldown: 10))
        }
        if let (sea, ships) = news.compactMap({ ev -> (SeaZoneID, Int)? in
            if case let .storm(c, sea, n, _) = ev, c == civ { (sea, n) } else { nil }
        }).first {
            reminders.append(say("storm", .general, .warning,
                "A storm in the \(place(sea)) took \(s(ships, "ship")). Ships off a harbour of our own ride out the weather; build one on that coast, or keep the fleet near it.",
                go: .sea(sea), cooldown: 4))
        }
        if let (t, gold) = news.compactMap({ ev -> (TerritoryID, Int)? in
            if case let .piratesPlundered(c, t, g) = ev, c == civ { (t, g) } else { nil }
        }).first {
            reminders.append(say("plundered", .general, .warning,
                "Pirates plundered \(place(t))\(gold > 0 ? " and took \(gold) gold" : ""). Walls, or our own ships in that sea, would keep them off.",
                go: .territory(t), cooldown: 4))
        }
        if let (name, v) = vassals.first(where: { engine.annexWait($0.land, in: state) == 0 }) {
            reminders.append(say("annex", .envoy, .calm,
                "\(name) have served us loyally for years. They could be annexed now, in peace: their land would be ours outright.",
                go: .territory(v), cooldown: 8))
        }
        if let (name, v) = vassals.first(where: { engine.levyWait($0.land, in: state) == 0 }) {
            reminders.append(say("levy", .general, .calm,
                "\(name) owe us a levy of warriors. Call them up wherever we need them.",
                go: .territory(v), cooldown: 6))
        }

        return alarms + intros + reminders
    }

    /// For the -demoAdvisor launch argument: the named topic if it applies now, else whatever the
    /// council would say first, else the steward on taxes.
    @MainActor static func demo(_ session: GameSession, key: String) -> AdvisorCall? {
        let all = calls(session)
        if let call = all.first(where: { $0.key == key }) ?? all.first { return call }
        guard let civ = session.human, let e = session.economy else { return nil }
        return AdvisorCall(key: "intro.taxes", role: .steward, name: Advisor.names(civ)[.steward] ?? "",
                           line: "At \(e.taxRate)% taxes we take in \(e.taxes) gold a turn. Higher taxes fill the treasury, but the people grow more slowly and grumble against the throne. You set the rate in the Realm.",
                           mood: .calm, go: .realm)
    }

    /// The first project the player can afford, capital first.
    @MainActor private static func buildable(_ civ: CivilizationID, _ session: GameSession)
        -> (kind: ProjectKind, at: TerritoryID, cost: ProjectCost)? {
        let engine = session.engine, state = session.state
        guard let cs = state.civs[civ] else { return nil }
        let seat = engine.seat(of: civ, in: state)
        let lands = state.territories(of: civ).sorted { a, b in (a == seat ? 0 : 1, a) < (b == seat ? 0 : 1, b) }
        let order: [ProjectKind] = [.farm, .granary, .walls, .road, .harbor, .mine, .drains, .levee]
        for t in lands where state.sieges[t] == nil {
            for kind in order where engine.canBuild(kind, in: t, state) {
                let c = engine.projectCost(kind, for: civ, state, at: t)
                if cs.gold >= c.gold, (cs.stock[.stone] ?? 0) >= c.stone, (cs.stock[.timber] ?? 0) >= c.timber {
                    return (kind, t, c)
                }
            }
        }
        return nil
    }
}

// MARK: The card

/// An advisor stepping forward with a word: portrait, name and role, the line, and two buttons.
struct AdvisorCard: View {
    let call: AdvisorCall
    let civ: CivilizationID
    let state: GameState
    let go: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AdvisorBust(role: call.role, civ: civ, color: Palette.color(civ, state), mood: call.mood)
                .frame(width: 78, height: 96)
                .background(RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.35)))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Bronze.gradient, lineWidth: 1))
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    CardTitle(text: call.name)
                    Text(call.title).font(.caption).foregroundStyle(.white.opacity(0.65))
                    if call.mood != .calm {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(call.mood == .alarm ? .red : .orange)
                    }
                    Spacer(minLength: 0)
                }
                Text("“\(call.line)”")
                    .font(.system(.callout, design: .serif))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Spacer(minLength: 0)
                    if call.go != nil {
                        Button(call.goLabel, action: go)
                            .font(.callout.bold()).foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .overlay(Capsule().stroke(.white.opacity(0.4)))
                    }
                    Button("Got it", action: dismiss).buttonStyle(BronzeButtonStyle())
                }
            }
        }
        .padding(12)
        .frame(width: 530)
        .woodPanel(RoundedRectangle(cornerRadius: 14), border: 2)
        .shadow(radius: 8)
    }
}

/// An advisor drawn head and shoulders, in the empire's colours, dressed for the office: the
/// general in a crested bronze helmet, the steward with his tablet and stylus, the envoy in a
/// fillet with a herald's staff, the high priest in a tall cap. They blink, and speak a moment.
struct AdvisorBust: View {
    let role: Advisor.Role
    let civ: CivilizationID
    let color: Color
    let mood: Advisor.Mood
    @State private var spokeAt = Date.now

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate
                let talk = max(0, 1 - tl.date.timeIntervalSince(spokeAt) / 2.4)
                ctx.scaleBy(x: size.width / 100, y: size.height / 120)
                draw(&ctx, t: t, talk: talk)
            }
        }
        .onAppear { spokeAt = .now }
        .accessibilityHidden(true)
    }

    private var skin: Color {
        switch civ {
        case "egypt": Color(red: 0.62, green: 0.42, blue: 0.27)
        case "mesopotamia": Color(red: 0.66, green: 0.47, blue: 0.32)
        default: Color(red: 0.86, green: 0.67, blue: 0.5)
        }
    }
    private let hair = Color(red: 0.14, green: 0.1, blue: 0.08)
    private let bronze = Color(red: 0.85, green: 0.62, blue: 0.3)
    private let ink = Color.black.opacity(0.75)

    private func draw(_ ctx: inout GraphicsContext, t: Double, talk: Double) {
        let breathe = sin(t * 1.6) * 0.8
        // Shoulders and robe.
        var robe = Path()
        robe.move(to: CGPoint(x: 8, y: 120))
        robe.addCurve(to: CGPoint(x: 50, y: 78 + breathe), control1: CGPoint(x: 10, y: 88), control2: CGPoint(x: 30, y: 80 + breathe))
        robe.addCurve(to: CGPoint(x: 92, y: 120), control1: CGPoint(x: 70, y: 80 + breathe), control2: CGPoint(x: 90, y: 88))
        robe.closeSubpath()
        ctx.fill(robe, with: .color(color))
        ctx.stroke(robe, with: .color(ink), lineWidth: 1)
        // A bronze collar or pectoral.
        var collar = Path()
        collar.addArc(center: CGPoint(x: 50, y: 78 + breathe), radius: 14, startAngle: .degrees(20), endAngle: .degrees(160), clockwise: false)
        ctx.stroke(collar, with: .color(bronze), lineWidth: 3)

        // Neck and head.
        ctx.fill(Path(CGRect(x: 44, y: 62 + breathe, width: 12, height: 16)), with: .color(skin))
        let head = Path(ellipseIn: CGRect(x: 33, y: 30 + breathe, width: 34, height: 40))
        ctx.fill(head, with: .color(skin))
        ctx.stroke(head, with: .color(ink), lineWidth: 1)

        let y = breathe
        // Eyes, with a blink every few seconds.
        let blink = (t.truncatingRemainder(dividingBy: 4.3)) < 0.14
        for x in [43.0, 57.0] {
            if blink {
                var lid = Path(); lid.move(to: CGPoint(x: x - 3, y: 48 + y)); lid.addLine(to: CGPoint(x: x + 3, y: 48 + y))
                ctx.stroke(lid, with: .color(ink), lineWidth: 1.2)
            } else {
                ctx.fill(Path(ellipseIn: CGRect(x: x - 2.5, y: 46 + y, width: 5, height: 4)), with: .color(.white))
                ctx.fill(Path(ellipseIn: CGRect(x: x - 1.3, y: 46.6 + y, width: 2.6, height: 2.8)), with: .color(ink))
            }
            // Brows: knit when worried.
            var brow = Path()
            let tilt = mood == .calm ? 0.0 : (x < 50 ? 1.5 : -1.5)
            brow.move(to: CGPoint(x: x - 4, y: 42 + y - tilt)); brow.addLine(to: CGPoint(x: x + 4, y: 42 + y + tilt))
            ctx.stroke(brow, with: .color(hair), lineWidth: 1.6)
        }
        // Nose.
        var nose = Path(); nose.move(to: CGPoint(x: 50, y: 49 + y)); nose.addLine(to: CGPoint(x: 48, y: 56 + y)); nose.addLine(to: CGPoint(x: 51, y: 57 + y))
        ctx.stroke(nose, with: .color(ink.opacity(0.6)), lineWidth: 1)

        // Beard for all but the priest (shaven in Egypt, as priests were).
        let bearded = !(role == .priest && civ == "egypt") && !(civ == "egypt" && role != .general)
        if bearded {
            var beard = Path()
            beard.move(to: CGPoint(x: 36, y: 54 + y))
            beard.addCurve(to: CGPoint(x: 50, y: 76 + y), control1: CGPoint(x: 37, y: 68 + y), control2: CGPoint(x: 44, y: 76 + y))
            beard.addCurve(to: CGPoint(x: 64, y: 54 + y), control1: CGPoint(x: 56, y: 76 + y), control2: CGPoint(x: 63, y: 68 + y))
            beard.addLine(to: CGPoint(x: 58, y: 60 + y)); beard.addLine(to: CGPoint(x: 42, y: 60 + y)); beard.closeSubpath()
            ctx.fill(beard, with: .color(role == .priest || role == .steward ? Color(white: 0.72) : hair))
        }
        // Mouth, moving while they speak.
        let open = talk > 0 ? abs(sin(t * 14)) * 3 * talk : 0
        let mouth = Path(ellipseIn: CGRect(x: 45, y: 61 + y - open / 2, width: 10, height: 1.5 + open))
        ctx.fill(mouth, with: .color(Color(red: 0.35, green: 0.12, blue: 0.1)))

        // Headgear for the office.
        switch role {
        case .general:
            var helm = Path()
            helm.move(to: CGPoint(x: 31, y: 50 + y))
            helm.addCurve(to: CGPoint(x: 69, y: 50 + y), control1: CGPoint(x: 29, y: 14 + y), control2: CGPoint(x: 71, y: 14 + y))
            helm.addLine(to: CGPoint(x: 67, y: 40 + y)); helm.addLine(to: CGPoint(x: 33, y: 40 + y)); helm.closeSubpath()
            ctx.fill(helm, with: .color(bronze))
            ctx.stroke(helm, with: .color(ink), lineWidth: 1)
            // Cheek guards.
            for x in [30.0, 63.0] {
                let guardPlate = Path(roundedRect: CGRect(x: x, y: 40 + y, width: 7, height: 17), cornerRadius: 3.5)
                ctx.fill(guardPlate, with: .color(bronze))
                ctx.stroke(guardPlate, with: .color(ink), lineWidth: 0.8)
            }
            // Crest, swaying.
            var crest = Path()
            let sway = sin(t * 2) * 1.5
            crest.move(to: CGPoint(x: 32, y: 30 + y))
            crest.addQuadCurve(to: CGPoint(x: 72 + sway, y: 36 + y), control: CGPoint(x: 50, y: -4 + y))
            crest.addQuadCurve(to: CGPoint(x: 32, y: 30 + y), control: CGPoint(x: 50, y: 12 + y))
            ctx.fill(crest, with: .color(Color(red: 0.7, green: 0.12, blue: 0.1)))
        case .steward:
            var cap = Path()
            cap.addArc(center: CGPoint(x: 50, y: 40 + y), radius: 17, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            ctx.fill(cap, with: .color(hair))
            // The clay tablet and stylus held up before him.
            let tablet = Path(roundedRect: CGRect(x: 60, y: 86, width: 22, height: 28), cornerRadius: 3)
            ctx.fill(tablet, with: .color(Color(red: 0.72, green: 0.56, blue: 0.38)))
            ctx.stroke(tablet, with: .color(ink), lineWidth: 1)
            for row in stride(from: 91.0, through: 109, by: 5) {
                var line = Path(); line.move(to: CGPoint(x: 64, y: row)); line.addLine(to: CGPoint(x: 78, y: row))
                ctx.stroke(line, with: .color(ink.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [2, 1.5]))
            }
            ctx.fill(Path(ellipseIn: CGRect(x: 56, y: 100, width: 10, height: 9)), with: .color(skin))
        case .envoy:
            var hairTop = Path()
            hairTop.addArc(center: CGPoint(x: 50, y: 42 + y), radius: 17, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            ctx.fill(hairTop, with: .color(hair))
            var fillet = Path(); fillet.move(to: CGPoint(x: 33, y: 38 + y)); fillet.addLine(to: CGPoint(x: 67, y: 38 + y))
            ctx.stroke(fillet, with: .color(.white), lineWidth: 2.5)
            // The herald's staff, wound with ribbons.
            var staff = Path(); staff.move(to: CGPoint(x: 20, y: 120)); staff.addLine(to: CGPoint(x: 22, y: 60))
            ctx.stroke(staff, with: .color(bronze), lineWidth: 3)
            ctx.stroke(Path(ellipseIn: CGRect(x: 16, y: 52, width: 12, height: 10)), with: .color(bronze), lineWidth: 2)
        case .priest:
            var hat = Path()
            hat.move(to: CGPoint(x: 35, y: 40 + y)); hat.addLine(to: CGPoint(x: 39, y: 10 + y))
            hat.addLine(to: CGPoint(x: 61, y: 10 + y)); hat.addLine(to: CGPoint(x: 65, y: 40 + y)); hat.closeSubpath()
            ctx.fill(hat, with: .color(Color(white: 0.92)))
            ctx.stroke(hat, with: .color(ink), lineWidth: 1)
            var band = Path(); band.move(to: CGPoint(x: 36, y: 34 + y)); band.addLine(to: CGPoint(x: 64, y: 34 + y))
            ctx.stroke(band, with: .color(bronze), lineWidth: 2.5)
            // A sun disc on the brow.
            ctx.fill(Path(ellipseIn: CGRect(x: 46, y: 18 + y, width: 8, height: 8)), with: .color(bronze))
        }
    }
}
