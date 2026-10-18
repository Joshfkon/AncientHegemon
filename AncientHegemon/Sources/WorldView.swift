import HegemonCore
import SwiftUI

struct WorldView: View {
    let session: GameSession

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        MapView(state: session.state, map: session.engine.map)
                            .frame(width: 820, height: 440)
                    }
                    .background(Color(red: 0.80, green: 0.88, blue: 0.95))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    controls
                    EmpireTable(state: session.state)
                    chronicle
                }
                .padding(.horizontal, 12)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var title: String {
        if let winner = session.state.winner {
            return "\(Palette.name(winner, session.state)) wins · round \(session.state.turn)"
        }
        return "Round \(session.state.turn) · seed \(session.seed)"
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                session.playing.toggle()
            } label: {
                Label(session.playing ? "Pause" : "Play", systemImage: session.playing ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(session.isOver)

            Button {
                Task { await session.playRound() }
            } label: {
                Label("Round", systemImage: "forward.frame.fill")
            }
            .buttonStyle(.bordered)
            .disabled(session.busy || session.playing || session.isOver)

            Spacer()
            if session.busy { ProgressView() }
            Button("New game") { session.newGame() }
                .buttonStyle(.bordered)
        }
    }

    private var chronicle: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Chronicle").font(.headline)
            if session.log.isEmpty {
                Text("Press Play to let the four empires fight it out.")
                    .foregroundStyle(.secondary)
            }
            ForEach(session.log.prefix(80)) { line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(line.round)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .frame(width: 26, alignment: .trailing)
                    Circle().fill(Palette.color(line.civ, session.state)).frame(width: 8, height: 8)
                    Text(line.text).font(.callout)
                }
            }
        }
        .padding(.bottom, 24)
    }
}

/// Each empire at a glance: land, armies, treasury, standing and ruler.
struct EmpireTable: View {
    let state: GameState

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
            GridRow {
                Text("Empire"); Text("Land"); Text("Army"); Text("Gold"); Text("Legit."); Text("Ruler")
            }
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            ForEach(state.players, id: \.self) { civ in
                let cs = state.civs[civ]!
                GridRow {
                    HStack(spacing: 6) {
                        Circle().fill(Palette.color(civ, state)).frame(width: 10, height: 10)
                        Text(Palette.name(civ, state)).lineLimit(1)
                    }
                    Text("\(state.territories(of: civ).count)")
                    Text("\(state.totalUnits(of: civ).total)")
                    Text("\(cs.gold)")
                    Text("\(cs.legitimacy)")
                    Text("\(cs.ruler.name), \(cs.ruler.age)\(cs.government == .republic ? " ⚖︎" : " ♛")")
                        .lineLimit(1)
                }
                .font(.callout.monospacedDigit())
                .opacity(cs.eliminated ? 0.35 : 1)
            }
        }
    }
}

/// The schematic map: territories as circles colored by owner, sized by grain, with army counts.
struct MapView: View {
    let state: GameState
    let map: GameMap

    var body: some View {
        Canvas { context, size in
            // Borders.
            for link in map.landLinks {
                var path = Path()
                path.move(to: MapLayout.point(link.a, in: size))
                path.addLine(to: MapLayout.point(link.b, in: size))
                let style: StrokeStyle = link.crossing == nil ? StrokeStyle(lineWidth: 1.5)
                    : StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                context.stroke(path, with: .color(link.crossing == .river ? .blue.opacity(0.6) : .black.opacity(0.35)),
                               style: style)
            }
            // Seas and fleets.
            for sea in map.seas {
                let p = MapLayout.seaPoint(sea.id, in: size)
                context.draw(Text(sea.name).font(.system(size: 8)).italic().foregroundStyle(.blue.opacity(0.55)),
                             at: p)
                let fleets = state.fleets.filter { $0.sea == sea.id }
                for (i, fleet) in fleets.enumerated() {
                    let label = Text("⛵\(fleet.ships)\(fleet.cargo.total > 0 ? "+\(fleet.cargo.total)" : "")")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Palette.color(fleet.owner, state))
                    context.draw(label, at: CGPoint(x: p.x, y: p.y + 11 + CGFloat(i) * 12))
                }
            }
            // Territories.
            let capitals = Set(state.players.compactMap { civ in
                map.civilization(civ)?.capital
            })
            for t in map.territories {
                let p = MapLayout.point(t.id, in: size)
                let r = 6 + CGFloat(t.grain) * 1.1
                let circle = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
                let owner = state.owner(of: t.id)
                context.fill(circle, with: .color(Palette.color(owner, state)))
                context.stroke(circle, with: .color(.black.opacity(capitals.contains(t.id) ? 0.9 : 0.4)),
                               lineWidth: capitals.contains(t.id) ? 2.5 : 0.8)
                context.draw(Text(t.name).font(.system(size: 8)).foregroundStyle(.black.opacity(0.75)),
                             at: CGPoint(x: p.x, y: p.y + r + 6))
                if let army = state.armies[t.id], army.units.total > 0 {
                    let led = state.generals.values.contains { $0.location == t.id }
                    let badge = Text("\(army.units.total)\(led ? "★" : "")")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(army.owner == owner ? Color.black : Palette.color(army.owner, state))
                    context.draw(badge, at: p)
                }
            }
        }
    }
}
