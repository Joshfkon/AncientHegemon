import HegemonCore
import SwiftUI

struct WorldView: View {
    let session: GameSession

    /// Landscape: the map takes the left, the empires and chronicle the right.
    var body: some View {
        HStack(spacing: 0) {
            MapView(state: session.state, map: session.engine.map)
                .aspectRatio(MapLayout.aspectRatio, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 0.80, green: 0.88, blue: 0.95))

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(title).font(.headline)
                    controls
                    if let victory = session.state.victory {
                        VictoryBanner(victory: victory, state: session.state, engine: session.engine)
                    }
                    EmpireTable(state: session.state, engine: session.engine)
                    chronicle
                }
                .padding(12)
            }
            .frame(width: 300)
            .background(Color(.systemBackground))
        }
    }

    private var title: String {
        let limit = session.engine.rules.victory.roundLimit
        return "Round \(session.state.turn) of \(limit) · seed \(session.seed)"
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button {
                session.playing.toggle()
            } label: {
                Image(systemName: session.playing ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(session.isOver)

            Button {
                Task { await session.playRound() }
            } label: {
                Image(systemName: "forward.frame.fill")
            }
            .buttonStyle(.bordered)
            .disabled(session.busy || session.playing || session.isOver)

            if session.busy { ProgressView() }
            Spacer()
            Button("New game") { session.newGame() }
                .buttonStyle(.bordered)
        }
        .controlSize(.small)
    }

    private var chronicle: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Chronicle").font(.subheadline.bold())
            if session.log.isEmpty {
                Text("Press play to let the four empires fight it out.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(session.log.prefix(80)) { line in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(line.round)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        .frame(width: 20, alignment: .trailing)
                    Circle().fill(Palette.color(line.civ, session.state)).frame(width: 7, height: 7)
                    Text(line.text).font(.caption)
                }
            }
        }
    }
}

/// How the game was won, and how everyone finished.
struct VictoryBanner: View {
    let victory: Victory
    let state: GameState
    let engine: Engine

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(victory.grade.rawValue.capitalized) \(kindName) Victory")
                .font(.title3.bold())
            Text("\(Palette.name(victory.standings[0], state)), round \(victory.round)")
                .font(.subheadline)
            ForEach(Array(victory.standings.enumerated()), id: \.offset) { place, civ in
                HStack(spacing: 6) {
                    Text("\(place + 1).").font(.caption.monospacedDigit()).frame(width: 18, alignment: .trailing)
                    Circle().fill(Palette.color(civ, state)).frame(width: 7, height: 7)
                    Text(Palette.name(civ, state)).font(.caption)
                    Spacer()
                    Text(state.civs[civ]?.eliminated == true ? "fallen" : "\(engine.prestige(of: civ, in: state))")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(Palette.color(victory.standings[0], state).opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
    }

    private var kindName: String {
        switch victory.kind {
        case .domination: "Domination"
        case .trade: "Trade"
        case .legacy: "Legacy"
        case .lastStanding: "Conquest"
        }
    }
}

/// Each empire at a glance, by prestige: land, armies, treasury, legitimacy.
struct EmpireTable: View {
    let state: GameState
    let engine: Engine

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
            GridRow {
                Text("Empire"); Text("Land"); Text("Army"); Text("Gold"); Text("Legit"); Text("Prest.")
            }
            .font(.caption2.bold())
            .foregroundStyle(.secondary)
            ForEach(engine.standings(in: state), id: \.self) { civ in
                let cs = state.civs[civ]!
                GridRow {
                    HStack(spacing: 4) {
                        Circle().fill(Palette.color(civ, state)).frame(width: 8, height: 8)
                        Text(Palette.name(civ, state)).lineLimit(1)
                    }
                    Text("\(state.territories(of: civ).count)")
                    Text("\(state.totalUnits(of: civ).total)")
                    Text("\(cs.gold)")
                    Text("\(cs.legitimacy)")
                    Text("\(engine.prestige(of: civ, in: state))")
                }
                .font(.caption.monospacedDigit())
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
