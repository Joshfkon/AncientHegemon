import HegemonCore
import SwiftUI

/// Every rival empire as the player's court sees it: war or peace, what passes between you in
/// trade, how strong they are, whether they border you, and what you can do about it.
struct DiplomacyView: View {
    let session: GameSession
    /// A declaration of war waiting for confirmation: breaking a peace costs legitimacy.
    @State private var warOn: CivilizationID?

    private var engine: Engine { session.engine }
    private var state: GameState { session.state }

    var body: some View {
        if let human = session.human {
            let rivals = engine.standings(in: state).filter { $0 != human && !(state.civs[$0]?.eliminated ?? true) }
            VStack(alignment: .leading, spacing: 10) {
                Text("Diplomacy").font(.subheadline.bold())
                if rivals.isEmpty {
                    Text("No rivals remain.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(rivals, id: \.self) { other in card(human, other) }
                Text("At peace, empires that can reach each other by land or open sea trade automatically. "
                     + "Breaking a peace costs \(-engine.rules.government.legitimacy.brokePeace) legitimacy.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .confirmationDialog("Break the peace with \(warOn.map { Palette.name($0, state) } ?? "")?",
                                isPresented: Binding(get: { warOn != nil }, set: { if !$0 { warOn = nil } }),
                                titleVisibility: .visible) {
                Button("Declare war", role: .destructive) {
                    if let warOn { session.order(.declareWar(on: warOn)) }
                    warOn = nil
                }
            } message: {
                Text("Breaking a peace costs \(-engine.rules.government.legitimacy.brokePeace) legitimacy and ends any trade route between you.")
            }
        }
    }

    private func card(_ human: CivilizationID, _ other: CivilizationID) -> some View {
        let peace = state.atPeace(human, other)
        let cs = state.civs[other]!
        let route = engine.tradeRoute(between: human, and: other, in: state)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(Palette.color(other, state)).frame(width: 10, height: 10)
                Text(Palette.name(other, state)).font(.callout.bold()).lineLimit(1).minimumScaleFactor(0.8)
                Text(peace ? "Peace" : "War")
                    .font(.caption.bold())
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background((peace ? Color.green : Color.red).opacity(0.2), in: Capsule())
                    .foregroundStyle(peace ? .green : .red)
                Spacer()
                action(human, other)
            }
            HStack(spacing: 12) {
                let lands = state.territories(of: other).count, troops = state.totalUnits(of: other).total
                fact("map", "\(lands) land\(lands == 1 ? "" : "s")")
                fact("shield.lefthalf.filled", "\(troops) troop\(troops == 1 ? "" : "s")")
                fact("crown", "\(engine.prestige(of: other, in: state)) prestige")
            }
            Text("\(cs.ruler.name) rules, \(legitimacyWord(cs.legitimacy)) on the throne.")
                .font(.caption).foregroundStyle(.secondary)
            Text(neighborhood(human, other)).font(.caption).foregroundStyle(.secondary)
            if let route {
                let flows = engine.goods(along: route, in: state)
                HStack(spacing: 4) {
                    Image(systemName: "arrow.left.arrow.right").font(.caption)
                    Text("Trading · you get \(goods(flows[human])) · they get \(goods(flows[other]))")
                        .font(.caption)
                }
                if !route.tolls.isEmpty {
                    Text("Tolls paid to \(route.tolls.map { Palette.name($0, state) }.joined(separator: ", ")) at the straits.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } else if peace {
                Text("No trade route: no open way between your capitals.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
    }

    @ViewBuilder private func action(_ human: CivilizationID, _ other: CivilizationID) -> some View {
        if state.atPeace(human, other) {
            Button("Declare war") { warOn = other }
                .buttonStyle(.bordered).tint(.red).controlSize(.small).fixedSize()
        } else if state.peaceOffers.contains(PeaceOffer(from: other, to: human)) {
            Button("Accept peace") { session.order(.acceptPeace(from: other)) }
                .buttonStyle(.borderedProminent).tint(.green).controlSize(.small).fixedSize()
        } else if state.peaceOffers.contains(PeaceOffer(from: human, to: other)) {
            Text("Peace offered").font(.caption).foregroundStyle(.secondary)
        } else {
            Button("Offer peace") { session.order(.offerPeace(to: other)) }
                .buttonStyle(.bordered).controlSize(.small).fixedSize()
        }
    }

    private func fact(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol).font(.caption).labelStyle(.titleAndIcon)
    }

    private func goods(_ flow: [Resource: Int]?) -> String {
        let items = Resource.allCases.filter { (flow?[$0] ?? 0) > 0 }.map(MapView.glyph)
        return items.isEmpty ? "nothing" : items.joined(separator: " ")
    }

    private func legitimacyWord(_ l: Int) -> String {
        switch l {
        case 70...: "secure"
        case 45..<70: "steady"
        case 25..<45: "shaky"
        default: "tottering"
        }
    }

    /// Whether their land touches ours, and where.
    private func neighborhood(_ human: CivilizationID, _ other: CivilizationID) -> String {
        let mine = Set(state.territories(of: human))
        let borders = state.territories(of: other).filter { t in engine.map.landNeighbors(of: t).contains(where: mine.contains) }
        guard !borders.isEmpty else { return "No shared border." }
        let names = borders.prefix(3).compactMap { engine.map.territory($0)?.name }
        return "Borders you at " + names.joined(separator: ", ") + (borders.count > 3 ? " and more." : ".")
    }
}
