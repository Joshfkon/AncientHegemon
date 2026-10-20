import Charts
import HegemonCore
import SwiftUI

/// The race at a glance, always on screen: every empire's prestige as a bar, the leader first,
/// yours outlined, and a warning when anyone nears a domination victory. Tap for the detail.
struct StandingsBar: View {
    let session: GameSession
    let open: () -> Void

    private var engine: Engine { session.engine }
    private var state: GameState { session.state }

    var body: some View {
        let order = engine.standings(in: state).filter { !(state.civs[$0]?.eliminated ?? true) && state.isPlayer($0) }
        let scores = order.map { engine.prestige(of: $0, in: state) }
        let top = max(1, scores.max() ?? 1)
        // Bars run from a little below the last-placed empire, so small gaps show.
        let floor = Double(scores.min() ?? 0) * 0.7
        let threat = order.first { engine.landShare(of: $0, in: state).percent * 100 >= engine.landShare(of: $0, in: state).toWin * 80 }
        let menace = engine.menace(in: state)
        Button(action: open) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    ForEach(Array(order.enumerated()), id: \.element) { i, civ in
                        let mine = civ == session.human
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 3) {
                                if i == 0 { Image(systemName: "crown.fill").font(.system(size: 8)).foregroundStyle(Bronze.gradient) }
                                Text(Self.short(civ, state)).font(.caption2.weight(mine ? .heavy : .semibold))
                                    .foregroundStyle(.white.opacity(mine ? 1 : 0.8))
                                    .lineLimit(1).fixedSize()
                                Text("\(scores[i])").font(.caption2.monospacedDigit()).foregroundStyle(.white.opacity(0.7))
                                    .lineLimit(1).fixedSize()
                            }
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(.white.opacity(0.12))
                                    Capsule().fill(Palette.color(civ, state))
                                        .frame(width: max(4, g.size.width * CGFloat((Double(scores[i]) - floor) / max(1, Double(top) - floor))))
                                }
                            }
                            .frame(height: 5)
                            .overlay(Capsule().stroke(mine ? Color.white : .clear, lineWidth: 1))
                        }
                        .frame(minWidth: 56)
                    }
                }
                if let civ = threat {
                    let share = engine.landShare(of: civ, in: state)
                    Text("⚠︎ \(Palette.name(civ, state)) holds \(share.percent)% of the land; \(share.toWin)% wins")
                        .font(.caption2.bold()).foregroundStyle(.orange)
                        .lineLimit(1).minimumScaleFactor(0.8)
                } else if let menace {
                    Text(menace == session.human ? "⚠︎ The world fears you: rivals will band together against you"
                                                 : "⚠︎ \(Palette.name(menace, state)) grows too strong: rivals will ally against it")
                        .font(.caption2.bold()).foregroundStyle(.orange)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .woodPanel(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Standings")
        .animation(.easeInOut(duration: 0.4), value: scores)
    }

    static func short(_ civ: CivilizationID, _ state: GameState) -> String {
        let name = Palette.name(civ, state)
        return name.count > 8 ? String(name.prefix(6)) + "." : name
    }
}

/// The full standings: prestige over the game, where each empire's comes from, and how close
/// anyone is to winning outright.
struct StandingsView: View {
    let session: GameSession

    private var engine: Engine { session.engine }
    private var state: GameState { session.state }

    var body: some View {
        let order = engine.standings(in: state).filter { state.isPlayer($0) }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Round \(state.turn) of \(engine.roundLimit(state)). The empire with the most prestige when the age ends wins, unless someone holds \(engine.rules.victory.territoryPercent)% of the land first.")
                    .font(.callout).foregroundStyle(.secondary)
                chart(order)
                ForEach(Array(order.enumerated()), id: \.element) { i, civ in card(i + 1, civ) }
                Text("Great works of the age").font(.headline)
                GreatWorksList(session: session)
            }
            .padding()
        }
        .navigationTitle("Standings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func chart(_ order: [CivilizationID]) -> some View {
        EmpireGraphs(history: session.statsHistory, lastRound: state.turn, order: order, human: session.human, state: state)
    }

    private func card(_ place: Int, _ civ: CivilizationID) -> some View {
        let fallen = state.civs[civ]?.eliminated ?? true
        let share = engine.landShare(of: civ, in: state)
        let trend = trend(civ)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("\(place)").font(.title3.bold().monospacedDigit()).frame(width: 22)
                Circle().fill(Palette.color(civ, state)).frame(width: 12, height: 12)
                Text(Palette.name(civ, state) + (civ == session.human ? " (you)" : "")).font(.headline)
                Spacer()
                if fallen {
                    Text("Fallen").font(.callout.bold()).foregroundStyle(.secondary)
                } else {
                    if let trend {
                        Text(trend >= 0 ? "▲\(trend)" : "▼\(-trend)").font(.caption.bold().monospacedDigit())
                            .foregroundStyle(trend >= 0 ? .green : .red)
                    }
                    Text("\(engine.prestige(of: civ, in: state))").font(.title3.bold().monospacedDigit())
                }
            }
            if !fallen {
                ForEach(engine.prestigeBreakdown(of: civ, in: state), id: \.source) { part in
                    HStack {
                        Text(part.source)
                        Spacer()
                        Text("+\(part.points)").monospacedDigit()
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    ProgressView(value: Double(min(share.percent, share.toWin)), total: Double(share.toWin))
                        .tint(Palette.color(civ, state))
                    Text("\(share.percent)% of the land").font(.caption.monospacedDigit())
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(civ == session.human ? Palette.color(civ, state) : .clear, lineWidth: 2))
    }

    /// Prestige gained over the last five rounds.
    private func trend(_ civ: CivilizationID) -> Int? {
        let h = session.statsHistory
        guard h.count >= 2, let then = h[max(0, h.count - 6)][civ]?.prestige else { return nil }
        return engine.prestige(of: civ, in: state) - then
    }
}

/// Age of Empires–style graphs: each empire's rise and fall over the game, one measure at a time.
struct EmpireGraphs: View {
    let history: [[CivilizationID: RoundStats]]
    /// The round of the last entry (older saves begin part-way through).
    let lastRound: Int
    let order: [CivilizationID]
    let human: CivilizationID?
    let state: GameState
    var height: CGFloat = 200
    @State private var metric = Metric.prestige

    enum Metric: String, CaseIterable, Identifiable {
        case prestige = "Prestige", land = "Land", people = "People", gold = "Gold", army = "Army",
             ships = "Ships", knowledge = "Knowledge"
        var id: String { rawValue }
        func value(_ s: RoundStats) -> Int {
            switch self {
            case .prestige: s.prestige
            case .land: s.land
            case .people: s.people
            case .gold: s.gold
            case .army: s.army
            case .ships: s.ships
            case .knowledge: s.knowledge
            }
        }
    }

    private struct Point: Identifiable {
        let round: Int
        let civ: CivilizationID
        let value: Int
        var id: String { "\(civ)-\(round)" }
    }

    var body: some View {
        let first = lastRound - history.count + 1
        let points: [Point] = history.enumerated().flatMap { i, row in
            row.map { Point(round: first + i, civ: $0.key, value: metric.value($0.value)) }
        }
        VStack(alignment: .leading, spacing: 8) {
            Picker("Graph", selection: $metric) {
                ForEach(Metric.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            Chart(points) { p in
                LineMark(x: .value("Round", p.round), y: .value(metric.rawValue, p.value))
                    .foregroundStyle(by: .value("Empire", Palette.name(p.civ, state)))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: p.civ == human ? 3.5 : 1.8))
                if p.civ == human, p.round == lastRound {
                    PointMark(x: .value("Round", p.round), y: .value(metric.rawValue, p.value))
                        .foregroundStyle(Palette.color(p.civ, state))
                }
            }
            .chartForegroundStyleScale(domain: order.map { Palette.name($0, state) }, range: order.map { Palette.color($0, state) })
            .chartXAxisLabel("Round")
            .frame(height: height)
            .overlay {
                if history.count < 2 {
                    Text("The race is drawn here as the rounds go by.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: metric)
        }
    }
}
