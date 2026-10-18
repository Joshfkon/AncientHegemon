import HegemonCore
import SwiftUI

/// The player's realm: standings, economy, ruler and generals.
struct EmpireView: View {
    let session: GameSession

    private var engine: Engine { session.engine }
    private var state: GameState { session.state }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            EmpireTable(state: state, engine: engine)
            if let human = session.human {
                CollapseGauge(pressure: engine.collapsePressure(state))
                if let econ = session.economy {
                    TaxesView(session: session, econ: econ)
                    EconomyView(econ: econ, state: state, engine: engine)
                }
                KnowledgeView(civ: human, state: state, engine: engine)
                ruler(human)
                generals(human)
            }
        }
    }

    private func ruler(_ human: CivilizationID) -> some View {
        let cs = state.civs[human]!
        return VStack(alignment: .leading, spacing: 2) {
            Text("Ruler").font(.subheadline.bold())
            Text("\(cs.ruler.name), \(cs.ruler.age) · \(cs.government == .republic ? "Republic" : "Monarchy")")
                .font(.callout)
            if let heir = cs.heir {
                Text("Heir: \(heir.name), \(heir.age)\(heir.age < engine.rules.government.adultAge ? " (a child)" : "")")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func generals(_ human: CivilizationID) -> some View {
        let list = state.generals.values.filter { $0.owner == human && $0.isAlive }.sorted { $0.id < $1.id }
        return VStack(alignment: .leading, spacing: 6) {
            Text("Generals").font(.subheadline.bold())
            if list.isEmpty { Text("None. Appoint one from a territory with an army.").font(.caption).foregroundStyle(.secondary) }
            ForEach(list) { g in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(g.name).font(.callout.bold())
                        Text("\(traitName(g.trait)) · renown \(g.renown)").font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Loyalty \(g.loyalty)").font(.caption.monospacedDigit())
                            .foregroundStyle(g.loyalty < engine.rules.government.successionDisloyalty ? .red : .primary)
                        ProgressView(value: Double(g.loyalty), total: 100).frame(width: 60)
                        Text(g.location.flatMap { engine.map.territory($0)?.name } ?? "").font(.caption)
                        Spacer()
                        Button("Honor (\(engine.rules.government.honorCost * (1 + g.renown)))") {
                            session.order(.honorGeneral(g.id))
                        }
                        .buttonStyle(.bordered).controlSize(.mini)
                        .disabled(!session.isHumanTurn)
                    }
                }
            }
        }
    }
}

/// Where grain and gold come from and go, trade, bronze and the resources within reach.
struct EconomyView: View {
    let econ: EconomyReport
    let state: GameState
    let engine: Engine

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Economy").font(.subheadline.bold())
            if !econ.cutOff.isEmpty {
                Label("Cut off from the capital: \(econ.cutOff.compactMap { engine.map.territory($0)?.name }.joined(separator: ", ")). "
                      + "No taxes or recruits there, and armies lose a unit a turn.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.red)
            }
            ledger("Grain", [
                ("Harvest", econ.grainProduced),
                ("People eat", -econ.eatenByPeople),
                ("Armies eat", -econ.eatenByArmies),
                ("Long supply lines", -econ.eatenByDistance),
                ("Ships' crews", -econ.eatenAtSea),
            ], total: ("Each turn", econ.grainBalance))
            Text("Granary \(econ.granary) of \(econ.granaryCap)"
                 + (econ.grainBalance < 0 ? " · empties in \(max(1, econ.granary / max(1, -econ.grainBalance) + 1)) turns, then people starve" : ""))
                .font(.caption).foregroundStyle(econ.grainBalance < 0 ? .red : .secondary)
            ledger("Gold", [("Taxes", econ.taxes), ("Mines", econ.mines), ("Trade", econ.trade)],
                   total: ("Next harvest", econ.income))
            VStack(alignment: .leading, spacing: 3) {
                Text("Trade").font(.caption.bold())
                if econ.tradePartners.isEmpty {
                    Text("No routes. Make peace with empires you can reach by land or open sea.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(econ.tradePartners.map { Palette.name($0, state) }.joined(separator: ", "))
                        .font(.caption)
                    Text("Each partner shares half its ore, horses, timber, stone and luxuries; wine sells to partners who have none.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Resources within reach").font(.caption.bold())
                HStack(spacing: 10) {
                    resource("Copper", .copper); resource("Tin", .tin); resource("Iron", .iron); resource("Horses", .horses)
                }
                HStack(spacing: 10) {
                    resource("Gold", .gold); resource("Wine", .wine); resource("Luxuries", .luxuries)
                }
                HStack(spacing: 10) {
                    ForEach(Resource.stockpiled, id: \.self) { r in
                        Text("\(r.rawValue.capitalized) \(econ.stock[r] ?? 0)/\(econ.stockCap)")
                            .font(.caption.monospacedDigit())
                    }
                    Text("in store").font(.caption).foregroundStyle(.secondary)
                }
                Text("Bronze \(econ.bronze) (+\(econ.bronzePerTurn) cast, −\(econ.bronzeWear) worn a turn). "
                     + "Troops \(econ.equipmentPercent)% equipped: up to +\(engine.rules.battle.bronzeBonusPercent)% in battle.")
                    .font(.caption)
                Text("Bronze needs copper and tin together and wears out; iron needs ironworking but lasts. "
                     + "Stone and timber build projects; horses limit cavalry recruits.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func resource(_ name: String, _ r: Resource) -> some View {
        Text("\(name) \(econ.resources[r] ?? 0)").font(.caption.monospacedDigit())
            .foregroundStyle((econ.resources[r] ?? 0) == 0 ? .secondary : .primary)
    }

    private func ledger(_ title: String, _ rows: [(String, Int)], total: (String, Int)) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.bold())
            ForEach(rows.filter { $0.1 != 0 }, id: \.0) { row in
                HStack {
                    Text(row.0).font(.caption)
                    Spacer()
                    Text(row.1 > 0 ? "+\(row.1)" : "\(row.1)").font(.caption.monospacedDigit())
                }
            }
            HStack {
                Text(total.0).font(.caption.bold())
                Spacer()
                Text(total.1 >= 0 ? "+\(total.1)" : "\(total.1)").font(.caption.bold().monospacedDigit())
                    .foregroundStyle(total.1 < 0 ? .red : .primary)
            }
        }
    }
}

/// The chronicle and the battles fought, each replayable.
struct ChronicleView: View {
    let session: GameSession
    @State private var replay: BattleEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if !session.battles.isEmpty {
                Text("Battles").font(.subheadline.bold())
                ForEach(session.battles.prefix(12)) { entry in
                    Button {
                        replay = entry
                    } label: {
                        let r = entry.report
                        let won = r.winner == .attacker
                        HStack(spacing: 5) {
                            Image(systemName: "play.circle")
                            Text("\(session.engine.map.territory(entry.territory)?.name ?? entry.territory): "
                                 + "\(Palette.name(r.setup.attacker.civ, session.state)) \(won ? "won" : "repulsed")")
                                .font(.caption).lineLimit(1)
                        }
                    }
                }
                Divider()
            }
            Text("Chronicle").font(.subheadline.bold())
            ForEach(session.log.prefix(120)) { line in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(line.round)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        .frame(width: 20, alignment: .trailing)
                    Circle().fill(Palette.color(line.civ, session.state)).frame(width: 7, height: 7)
                    Text(line.text).font(.caption)
                }
            }
        }
        .sheet(item: $replay) { entry in
            NavigationStack {
                BattleReplayView(entry: entry, state: session.state, map: session.engine.map, autoplay: true, perspective: session.human)
                    .id(entry.id)
                    .toolbar { Button("Done") { replay = nil } }
            }
        }
    }
}

/// A contested succession: the player chooses how to settle it.
struct CrisisView: View {
    let session: GameSession

    var body: some View {
        let engine = session.engine
        let state = session.state
        if let human = session.human, let crisis = session.crisis {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("The throne is contested").font(.title2.bold())
                    Text("The old ruler is dead. \(crisis.ruler) should rule \(Palette.name(human, state)), "
                         + "but powerful generals press their own claims, each at the head of an army.")
                        .font(.callout)
                    ForEach(crisis.claimants, id: \.self) { id in
                        if let g = state.generals[id] {
                            let army = g.location.flatMap { state.armies[$0] }?.units.total ?? 0
                            Text("• \(g.name), renown \(g.renown), loyalty \(g.loyalty), \(army) troops in "
                                 + "\(g.location.flatMap { engine.map.territory($0)?.name } ?? "?")")
                                .font(.callout)
                        }
                    }
                    let gold = state.civs[human]!.gold
                    choice("Pay them off", "Costs \(crisis.bribeCost) gold (you have \(gold)). The claimants stand down; "
                           + "legitimacy suffers a little.", enabled: gold >= crisis.bribeCost, .payOff)
                    if let first = crisis.claimants.first.flatMap({ state.generals[$0] }) {
                        choice("Crown \(first.name)", "A new dynasty without bloodshed. \(first.name) leaves the army "
                               + "for the throne; the other claimants accept.", enabled: true, .crownClaimant)
                    }
                    choice("Stand firm", "\(crisis.ruler) takes the throne, and every claimant rises in civil war, "
                           + "taking the lands nearest him.", enabled: true, .standFirm)
                }
                .padding()
            }
        }
    }

    private func choice(_ title: String, _ detail: String, enabled: Bool, _ choice: CrisisChoice) -> some View {
        Button {
            session.order(.resolveCrisis(choice))
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.caption).multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .disabled(!enabled)
    }
}

/// The opening screen: choose a civilization, or watch the AIs.
