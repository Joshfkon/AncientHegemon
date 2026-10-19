import HegemonCore
import SwiftUI

// MARK: Quick look

/// Everything about a territory at a glance, from a long press: no panel, no orders.
struct QuickLookCard: View {
    let id: TerritoryID
    let session: GameSession
    let close: () -> Void

    var body: some View {
        let engine = session.engine
        let state = session.state
        let t = engine.map.territory(id)!
        let land = state.land[id]
        let owner = state.owner(of: id)
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle().fill(Palette.color(owner, state)).frame(width: 9, height: 9)
                Text(t.name).font(.headline)
                Text(owner.map { Palette.name($0, state) } ?? "Unclaimed").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(action: close) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
            }
            Text("\(t.terrain.rawValue.capitalized) · 🌾 \(engine.territoryYield(.grain, id, state)) grain · 👥 \(state.population(of: id)) people")
                .font(.caption)
            if let army = state.armies[id], army.units.total > 0 {
                HStack(spacing: 6) {
                    Text(Palette.name(army.owner, state)).font(.caption.bold())
                    UnitRow(units: army.units, size: 12).font(.caption)
                    if let g = state.generals.values.first(where: { $0.location == id }) {
                        Text("★ \(g.name)").font(.caption)
                    }
                }
            } else {
                Text("No army").font(.caption).foregroundStyle(.secondary)
            }
            let walls = land?.improvements.contains(.walls) == true
            let built = ProjectKind.allCases.filter { land?.improvements.contains($0) ?? false }
            if !built.isEmpty || land?.construction != nil {
                Text((built.map(projectName) + (land?.construction.map { ["building \(projectName($0.kind).lowercased())"] } ?? []))
                        .joined(separator: " · ") + (walls ? " (+\(engine.fortification(at: id, state))% defense)" : ""))
                    .font(.caption)
            }
            if let human = session.human {
                if owner == human {
                    let home = engine.homeNetwork(of: human, in: state).contains(id)
                    Text(home ? (engine.supplyStrain(of: human, at: id, in: state).map { "In supply, \($0.steps) step\($0.steps == 1 ? "" : "s") from the capital" } ?? "In supply")
                              : "⚠️ Cut off from your capital")
                        .font(.caption).foregroundStyle(home ? .secondary : Color.orange)
                    let levy = engine.levy(at: id, state)
                    if levy > 0 { Text("If attacked, its people raise \(levy) militia").font(.caption).foregroundStyle(.secondary) }
                    let threat = ThreatMap(for: human, in: state, map: engine.map, engine: engine).threat[id] ?? 0
                    if threat > 0 { Text("⚔︎ \(threat) hostile troops could strike here next turn").font(.caption).foregroundStyle(.red) }
                } else {
                    let reach = engine.map.landNeighbors(of: id).reduce(0) { total, n in
                        guard let a = state.armies[n], a.owner == human else { return total }
                        return total + max(0, (a.units - (state.moved[n] ?? .zero)).total)
                    }
                    Text(reach > 0 ? "\(reach) of your troops could march here this turn" : "None of your troops can reach it this turn")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(width: 330)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(radius: 8)
    }
}

// MARK: Turn report

/// "Since your last turn": the player's own news first, highlighted; everyone else's folded into
/// one line that opens. Tap a line to see it on the map.
struct TurnReportCard: View {
    let session: GameSession
    let jump: (TerritoryID) -> Void
    @State private var showOthers = false

    var body: some View {
        let state = session.state
        let mine = session.report.filter { $0.mine == true }
        let others = session.report.filter { $0.mine != true }
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Since your last turn").font(.headline)
                Spacer()
                Button("Got it") { session.showReport = false }
                    .buttonStyle(.borderedProminent).controlSize(.small)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if mine.isEmpty {
                        Text("Nothing touched your realm.").font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach(mine) { line in row(line, state, strong: true) }
                    if !others.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: showOthers ? "chevron.down" : "chevron.right")
                            Text("\(others.count) other event\(others.count == 1 ? "" : "s") across the world")
                        }
                        .font(.callout)
                        .foregroundStyle(Color.accentColor)
                        .padding(.top, 4)
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation { showOthers.toggle() } }
                        if showOthers {
                            ForEach(others) { line in row(line, state, strong: false) }
                        }
                    }
                }
            }
            .frame(height: min(240, CGFloat(mine.count) * 30 + (mine.isEmpty ? 24 : 0)
                                + (others.isEmpty ? 0 : 34) + (showOthers ? CGFloat(others.count) * 24 : 0) + 6))
            Text("Arrows and markers on the map show these until you end your turn.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 440)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 10)
    }

    private func row(_ line: LogLine, _ state: GameState, strong: Bool) -> some View {
        Button {
            if let t = line.territory { jump(t) }
        } label: {
            HStack(alignment: .top, spacing: 6) {
                Circle().fill(Palette.color(line.civ, state)).frame(width: 8, height: 8).padding(.top, 5)
                Text(line.text)
                    .font(strong ? .callout.weight(.semibold) : .footnote)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(strong ? .primary : .secondary)
                Spacer(minLength: 0)
                if line.territory != nil {
                    Image(systemName: "scope").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .allowsHitTesting(line.territory != nil)
    }
}

// MARK: Explaining the numbers

enum StatTopic: String, Identifiable {
    case gold, grain, legitimacy
    var id: String { rawValue }
}

/// Where a number in the status box comes from and goes.
struct StatExplainer: View {
    let topic: StatTopic
    let session: GameSession

    var body: some View {
        let econ = session.economy
        VStack(alignment: .leading, spacing: 8) {
            switch topic {
            case .gold:
                Text("Gold").font(.headline)
                if let e = econ {
                    row("Taxes (\(e.taxRate)%)", e.taxes)
                    row("Mines", e.mines)
                    row("Trade", e.trade)
                    Divider()
                    row("Next harvest", e.income, bold: true)
                }
                Text("Spend it on troops, ships, generals and buildings. Higher taxes bring more but slow growth and cost legitimacy.")
                    .font(.caption).foregroundStyle(.secondary)
            case .grain:
                Text("Grain").font(.headline)
                if let e = econ {
                    row("Harvest", e.grainProduced)
                    row("People eat", -e.eatenByPeople)
                    row("Armies eat", -e.eatenByArmies)
                    row("Long supply lines", -e.eatenByDistance)
                    row("Ships' crews", -e.eatenAtSea)
                    Divider()
                    row("Each turn", e.grainBalance, bold: true)
                    Text("Granary \(e.granary) of \(e.granaryCap).").font(.caption)
                }
                Text("This is a forecast for your next harvest. Famine, drought and floods strike at the start of a turn and can cut it; they show in your news and as ⚠ here.")
                    .font(.caption).foregroundStyle(.orange)
                Text("Armies far from your capital eat more. When the granary runs dry, people and soldiers starve.")
                    .font(.caption).foregroundStyle(.secondary)
            case .legitimacy:
                Text("Legitimacy").font(.headline)
                if let e = econ {
                    row("From taxes and luxuries, each turn", e.taxLegitimacy)
                }
                Text("How firmly your ruler holds the throne. It rises with victories, low taxes and luxuries, and falls with defeats, famine, lost capitals and broken peace. Low legitimacy brings bad omens, disloyal generals and civil war when a ruler dies.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 320)
    }

    private func row(_ name: String, _ value: Int, bold: Bool = false) -> some View {
        HStack {
            Text(name)
            Spacer()
            Text(value >= 0 ? "+\(value)" : "\(value)").monospacedDigit()
                .foregroundStyle(value < 0 ? .red : .primary)
        }
        .font(bold ? .callout.bold() : .callout)
    }
}

// MARK: First-time tips

/// One-time hints, each shown the first time its moment comes up.
enum Tip: String, CaseIterable {
    case map, orders, battle, rivals, collapse, knowledge

    var text: String {
        switch self {
        case .map: "Tap your army (the token with ★) to give it orders. Pinch to zoom; long-press any territory for a quick look."
        case .orders: "Highlighted land is where this army can go. Every army eats grain, and more the farther it is from your capital."
        case .battle: "Pick a battle plan. Your officers judge each formation for this fight; locked plans show what would unlock them."
        case .rivals: "Arrows show what your rivals did. They stay on the map until you end your turn."
        case .collapse: "The Bronze Age is ending: Sea Peoples, droughts, earthquakes and broken trade will grow more common. Wall your coasts."
        case .knowledge: "Your people discovered something. The books button opens the knowledge tree."
        }
    }

    private static let key = "seenTips"
    static var seen: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: key) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: key) }
    }
    var isNew: Bool { !Self.seen.contains(rawValue) }
    func markSeen() { Self.seen.insert(rawValue) }
}

struct TipBanner: View {
    let tip: Tip
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb.fill").foregroundStyle(.yellow)
            Text(tip.text).font(.callout).fixedSize(horizontal: false, vertical: true)
            Button(action: dismiss) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
        }
        .padding(10)
        .frame(minWidth: 260, maxWidth: 400)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 6)
    }
}

// MARK: Codex

/// The rules in brief, from the ⋯ menu.
struct CodexView: View {
    private let sections: [(String, String, String)] = [
        ("flag.fill", "Winning",
         "Hold 60% of the land for a domination victory, dominate trade for a trade victory, or have the most prestige when the age ends at round 50. Wins come in decisive, major and minor grades."),
        ("arrow.triangle.turn.up.right.diamond.fill", "A turn",
         "Your turn starts with events and the harvest. Then move armies (each unit once), recruit, build, sail and make peace or war. End the turn and every rival moves in turn."),
        ("leaf.fill", "Grain and supply",
         "Land grows grain; people and soldiers eat it: each soldier and each ship's crew 1 grain a turn (there's no gold upkeep). Armies eat more the farther they are from the capital along their supply line. Land cut off from the capital can't recruit, and its armies waste away."),
        ("arrow.left.arrow.right", "Trade and resources",
         "Empires at peace that can reach each other trade automatically, sharing ore, horses, timber and more. Copper and tin make bronze, which arms your troops; it wears out without fresh tin. Iron needs Ironworking."),
        ("shield.lefthalf.filled", "Battles",
         "Battles are fought on a 5×5 field. Your formation, line depth and stratagem matter, as do terrain, rivers, walls, generals and equipment. Defenders have the edge in even fights."),
        ("books.vertical.fill", "Knowledge",
         "Nobody picks technologies. Your people learn from what they do: farming, mining, sailing, fighting, trading. Neighbors and trade partners who know more pass some of it on."),
        ("crown.fill", "Rulers",
         "Rulers age and die. A weak heir means a regency; ambitious generals may claim the throne. Keep legitimacy up with victories, low taxes and luxuries."),
        ("flame.fill", "The collapse",
         "From round 12 the world grows harsher: Sea Peoples raid coasts, droughts wither fields, earthquakes topple walls and trade routes break. Walls, granaries and iron help you endure."),
    ]

    var body: some View {
        List(sections, id: \.1) { icon, title, text in
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon).font(.title3).foregroundStyle(.tint).frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(text).font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .navigationTitle("Rules reference")
        .navigationBarTitleDisplayMode(.inline)
    }
}
