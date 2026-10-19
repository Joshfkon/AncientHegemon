import HegemonCore
import SwiftUI

/// Every resource the realm has (or lacks): how much a turn, from its own land or from trade,
/// what's in store, what it's for, and where to find more.
struct ResourcesView: View {
    let session: GameSession
    /// Highlight a resource's sources on the map.
    let show: (Resource) -> Void
    var focus: Resource?

    private var engine: Engine { session.engine }
    private var state: GameState { session.state }

    static let order: [Resource] = [.horses, .copper, .tin, .iron, .timber, .stone, .gold, .wine, .luxuries]

    var body: some View {
        if let human = session.human {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Self.order, id: \.self) { r in
                            card(r, human).id(r)
                        }
                    }
                    .padding()
                }
                .onAppear { if let focus { proxy.scrollTo(focus, anchor: .top) } }
            }
            .navigationTitle("Resources")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func card(_ r: Resource, _ human: CivilizationID) -> some View {
        let income = engine.resourceIncome(r, for: human, in: state)
        let total = income.own + income.trade.reduce(0) { $0 + $1.amount }
        let locked = r == .iron && engine.level(.metallurgy, of: human, in: state) < 2
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                MapView.icon(r).font(.title3)
                Text(r.rawValue.capitalized).font(.headline)
                Spacer()
                Text(locked ? "unusable" : "\(total) a turn")
                    .font(.callout.bold().monospacedDigit())
                    .foregroundStyle(total == 0 || locked ? .red : .primary)
            }
            Text(Self.purpose(r)).font(.caption).foregroundStyle(.secondary)
            if locked {
                Text("Iron ore is just rock until your smiths learn Ironworking (Metallurgy level 2).")
                    .font(.caption).foregroundStyle(.orange)
            }
            if !locked, total > 0 {
                Text(([income.own > 0 ? "\(income.own) from your land" : nil]
                      + income.trade.map { "\($0.amount) from trade with \(Palette.name($0.partner, state))" })
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
            }
            if let stock = state.civs[human]?.stock[r], Resource.stockpiled.contains(r) {
                Text("In store: \(stock) of \(engine.rules.economy.stockCap)").font(.caption)
            }
            limit(r, human)
            let sources = engine.sources(of: r, for: human, in: state).filter { $0.owner != human }.prefix(3)
            if !sources.isEmpty {
                Text("Get more: " + sources.map { s in
                    let name = engine.map.territory(s.territory)?.name ?? s.territory
                    let who = s.owner.map { Palette.name($0, state) } ?? "unclaimed"
                    return "\(name) (\(who), \(s.steps == 99 ? "overseas" : "\(s.steps) away"))"
                }.joined(separator: ", ") + ". Take the land, or make peace with whoever holds it and trade.")
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                show(r)
            } label: {
                Label("Show on map", systemImage: "scope")
            }
            .font(.caption.bold())
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(r == focus ? Color.accentColor.opacity(0.12) : Color(.secondarySystemBackground)))
    }

    /// What the resource is limiting right now.
    @ViewBuilder private func limit(_ r: Resource, _ human: CivilizationID) -> some View {
        if r == .horses, let a = engine.recruitAllowance(.cavalry, for: human, in: state) {
            Text("Cavalry you can raise this turn: \(a.left) of \(a.perTurn)")
                .font(.caption.bold()).foregroundStyle(a.left > 0 ? .green : .orange)
        }
        if r == engine.rules.ships.requires {
            let a = engine.shipAllowance(for: human, in: state)
            Text("Ships you can build this turn: \(a.left) of \(a.perTurn)")
                .font(.caption.bold()).foregroundStyle(a.left > 0 ? .green : .orange)
        }
    }

    static func purpose(_ r: Resource) -> String {
        switch r {
        case .horses: "Each horse a turn lets you raise one cavalry (two with Horse breeding)."
        case .copper: "With tin, makes bronze, which arms your troops."
        case .tin: "With copper, makes bronze. Scarce: only the far west has it."
        case .iron: "Arms troops without tin, and doesn't wear out, once you know Ironworking."
        case .timber: "Each timber a turn lets you build one ship; also builds farms, mines and harbors."
        case .stone: "Builds roads, walls and harbors."
        case .gold: "Mined for gold each turn."
        case .wine: "Sells for gold, more to trade partners who have none."
        case .luxuries: "Purple dye, ivory, incense: they keep your people content and your ruler secure."
        case .grain: "Feeds people and armies."
        }
    }
}
