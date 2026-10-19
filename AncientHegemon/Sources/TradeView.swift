import HegemonCore
import SwiftUI

/// Every trade route, plainly: who it's with, what comes in, what goes out, the gold it earns
/// and what it costs in tolls, and who you could trade with if you made peace.
struct TradeView: View {
    let session: GameSession
    let show: (TerritoryID?) -> Void

    private var engine: Engine { session.engine }
    private var state: GameState { session.state }

    var body: some View {
        if let human = session.human {
            let reports = engine.tradeReports(for: human, in: state)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    summary(reports)
                    if reports.isEmpty {
                        Text("No trade routes. Empires at peace whose capitals can reach each other by land, or by sea lanes no enemy fleet blocks, trade automatically.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach(reports, id: \.partner) { r in card(r, human) }
                    prospects(human, trading: Set(reports.map(\.partner)))
                }
                .padding()
            }
            .navigationTitle("Trade")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    /// Everything trade brings in, added up.
    private func summary(_ reports: [TradeReport]) -> some View {
        var totals: [Resource: Int] = [:]
        for r in reports { for (res, n) in r.received { totals[res, default: 0] += n } }
        let gold = reports.reduce(0) { $0 + $1.gold + $1.wineSales }
        return VStack(alignment: .leading, spacing: 6) {
            Text("Trade brings you each turn").font(.headline)
            HStack(spacing: 14) {
                Text("🪙 +\(gold) gold").font(.callout.bold())
                ForEach(ResourcesView.order.filter { totals[$0] != nil }, id: \.self) { res in
                    (MapView.icon(res) + Text(" +\(totals[res]!)")).font(.callout.bold())
                }
                if !reports.isEmpty { Text("🌾 up to \(reports.reduce(0) { $0 + $1.grainImport }) grain if the harvest fails").font(.caption) }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.green.opacity(0.12)))
    }

    private func card(_ r: TradeReport, _ human: CivilizationID) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(Palette.color(r.partner, state)).frame(width: 10, height: 10)
                Text(Palette.name(r.partner, state)).font(.headline)
                Spacer()
                Text("+\(r.gold + r.wineSales) gold").font(.callout.bold().monospacedDigit()).foregroundStyle(.orange)
            }
            goods("You receive", r.received, empty: "nothing you lack")
            goods("You send", r.sent, empty: "nothing they lack")
            if r.wineSales > 0 {
                Text("🍷 They have no wine: yours sells there for +\(r.wineSales) gold.").font(.caption)
            }
            if !r.tolls.isEmpty {
                Text("Tolls to \(r.tolls.map { Palette.name($0, state) }.joined(separator: ", ")) at \(r.chokepoints.compactMap { id in engine.map.chokepoints.first { $0.id == id }?.name }.joined(separator: ", ")) take \(r.tolls.count * engine.rules.trade.chokepointToll) gold.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("War with \(Palette.name(r.partner, state)), an enemy fleet or a lost strait would cut this route.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }

    private func goods(_ label: String, _ flows: [Resource: Int], empty: String) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.caption.bold()).frame(width: 80, alignment: .leading)
            if flows.isEmpty {
                Text(empty).font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(ResourcesView.order.filter { flows[$0] != nil }, id: \.self) { res in
                    (MapView.icon(res) + Text(" \(flows[res]!) \(res.rawValue)")).font(.caption)
                }
            }
        }
    }

    /// Empires you could trade with: at war, or out of reach.
    @ViewBuilder private func prospects(_ human: CivilizationID, trading: Set<CivilizationID>) -> some View {
        let others = state.players.filter { $0 != human && !trading.contains($0) && !(state.civs[$0]?.eliminated ?? true) }
        if !others.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Not trading with").font(.headline)
                ForEach(others, id: \.self) { other in
                    let lacking = ResourcesView.order.filter { r in
                        (session.economy?.resources[r] ?? 0) == 0
                            && engine.yield(of: r, in: engine.homeNetwork(of: other, in: state), state) > 0
                    }
                    HStack(alignment: .top, spacing: 6) {
                        Circle().fill(Palette.color(other, state)).frame(width: 8, height: 8).padding(.top, 5)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Palette.name(other, state) + (state.atPeace(human, other) ? ": at peace, but no open way between your capitals" : ": at war"))
                                .font(.callout)
                            if !lacking.isEmpty {
                                lacking.reduce(Text("They have what you lack: ")) { $0 + Text(" ") + MapView.icon($1) + Text(" \($1.rawValue)") }
                                    .font(.caption).foregroundStyle(.green)
                            }
                        }
                    }
                }
            }
        }
    }
}
