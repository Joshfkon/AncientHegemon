import HegemonCore
import SwiftUI

struct WorldView: View {
    let session: GameSession
    @State private var selected: TerritoryID?

    /// Landscape: the map takes the left, the empires and chronicle the right.
    var body: some View {
        HStack(spacing: 0) {
            MapView(state: session.state, map: session.engine.map, selected: $selected)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 0.12, green: 0.10, blue: 0.08))

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(title).font(.headline)
                    controls
                    if let selected {
                        TerritoryCard(id: selected, state: session.state, map: session.engine.map) {
                            self.selected = nil
                        }
                    }
                    if let victory = session.state.victory {
                        VictoryBanner(victory: victory, state: session.state, engine: session.engine)
                    }
                    EmpireTable(state: session.state, engine: session.engine)
                    chronicle
                }
                .padding(12)
            }
            .frame(width: 270)
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

/// The board as painted: territories in their terrain colors, tinted by owner, with rivers,
/// mountain peaks, the seam between the board's halves, and armies and fleets on top.
/// Tapping a territory selects it.
struct MapView: View {
    let state: GameState
    let map: GameMap
    @Binding var selected: TerritoryID?
    private let art = BoardArt.shared

    var body: some View {
        GeometryReader { geo in
            let t = BoardTransform(fitting: geo.size)
            Canvas { context, _ in draw(&context, t) }
                .contentShape(Rectangle())
                .onTapGesture { location in
                    let hit = map.territories.first { territory in
                        art.territories[territory.id].map { t.path($0.polygon).contains(location) } ?? false
                    }?.id
                    selected = hit == selected ? nil : hit
                }
        }
    }

    private static let terrain: [Terrain: Color] = [
        .plains: Color(red: 0.42, green: 0.70, blue: 0.32),
        .hills: Color(red: 0.29, green: 0.58, blue: 0.29),
        .forest: Color(red: 0.19, green: 0.47, blue: 0.23),
        .mountains: Color(red: 0.36, green: 0.55, blue: 0.31),
        .desert: Color(red: 0.93, green: 0.69, blue: 0.21),
    ]

    private func draw(_ context: inout GraphicsContext, _ t: BoardTransform) {
        let f = BoardArt.frame
        let board = Path(CGRect(origin: t.point([f.minX, f.minY]),
                                size: CGSize(width: f.width * t.scale, height: f.height * t.scale)))
        context.fill(board, with: .linearGradient(
            Gradient(colors: [Color(red: 0.16, green: 0.36, blue: 0.74), Color(red: 0.24, green: 0.50, blue: 0.82)]),
            startPoint: t.point([f.minX, f.minY]), endPoint: t.point([f.maxX, f.maxY])))

        // Land, painted by terrain and tinted by owner.
        for territory in map.territories {
            guard let shape = art.territories[territory.id] else { continue }
            let path = t.path(shape.polygon)
            context.fill(path, with: .color(Self.terrain[territory.terrain] ?? .green))
            if let owner = state.owner(of: territory.id) {
                let color = Palette.color(owner, state)
                context.fill(path, with: .color(color.opacity(0.38)))
                context.drawLayer { layer in
                    layer.clip(to: path)
                    layer.stroke(path, with: .color(color), lineWidth: 5)
                }
            }
            context.stroke(path, with: .color(.black.opacity(0.85)), lineWidth: 1.1)
        }

        // Rivers and peaks, as painted.
        for river in art.rivers {
            var path = Path()
            path.addLines(river.map(t.point))
            context.stroke(path, with: .color(Color(red: 0.15, green: 0.42, blue: 0.85)),
                           style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
        }
        for (_, peaks) in art.peaks {
            for p in peaks {
                let c = t.point(p)
                var peak = Path()
                peak.move(to: CGPoint(x: c.x - 4.5, y: c.y + 3.5))
                peak.addLine(to: CGPoint(x: c.x, y: c.y - 4.5))
                peak.addLine(to: CGPoint(x: c.x + 4.5, y: c.y + 3.5))
                peak.closeSubpath()
                context.fill(peak, with: .color(Color(white: 0.55)))
                context.stroke(peak, with: .color(.black.opacity(0.8)), lineWidth: 0.8)
            }
        }

        // The seam between the board's two halves.
        var seam = Path()
        seam.move(to: t.point([BoardArt.seamX, f.minY]))
        seam.addLine(to: t.point([BoardArt.seamX, f.maxY]))
        context.stroke(seam, with: .color(.black.opacity(0.75)), lineWidth: 1.6)

        if let selected, let shape = art.territories[selected] {
            context.stroke(t.path(shape.polygon), with: .color(.white), lineWidth: 2.5)
        }

        // Names in the board's hand lettering, then armies and fleets.
        for territory in map.territories {
            guard let shape = art.territories[territory.id] else { continue }
            let p = t.point(shape.label)
            var lettering = context
            lettering.translateBy(x: p.x, y: p.y)
            lettering.rotate(by: .degrees(shape.angle))
            lettering.draw(Text(territory.name.uppercased())
                            .font(.custom("ChalkboardSE-Bold", size: 6.5))
                            .foregroundStyle(.black.opacity(0.85)),
                           at: .zero)
            if let army = state.armies[territory.id], army.units.total > 0 {
                // Armies sit at the middle of the land, under the name for straight-lettered ones.
                // Just beneath the lettering, following its angle.
                let a = shape.angle * .pi / 180
                let c = CGPoint(x: p.x - 11 * sin(a), y: p.y + 11 * cos(a))
                let native = !state.isPlayer(army.owner)
                let r: CGFloat = native ? 5.5 : 7.5
                let led = state.generals.values.contains { $0.location == territory.id }
                let badge = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
                context.fill(badge, with: .color(Palette.color(army.owner, state).opacity(native ? 0.8 : 1)))
                context.stroke(badge, with: .color(.black.opacity(0.7)), lineWidth: 0.7)
                context.draw(Text("\(army.units.total)\(led ? "★" : "")")
                                .font(.system(size: native ? 7 : 8.5, weight: .heavy))
                                .foregroundStyle(native ? Color.black.opacity(0.7) : .white),
                             at: c)
            }
        }
        for (sea, label) in art.seas {
            let p = t.point(label)
            // The board doesn't name its seas, so only fleets are drawn there.
            for (i, fleet) in state.fleets.filter({ $0.sea == sea }).enumerated() {
                context.draw(Text("⛵\(fleet.ships)\(fleet.cargo.total > 0 ? "+\(fleet.cargo.total)" : "")")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Palette.color(fleet.owner, state)),
                             at: CGPoint(x: p.x, y: p.y + 10 + CGFloat(i) * 11))
            }
        }
    }
}

/// What a tapped territory holds.
struct TerritoryCard: View {
    let id: TerritoryID
    let state: GameState
    let map: GameMap
    let onClose: () -> Void

    var body: some View {
        let t = map.territory(id)!
        let owner = state.owner(of: id)
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(t.name).font(.headline)
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
            }
            Text("\(t.terrain.rawValue.capitalized) · grain \(t.grain)"
                 + t.resources.sorted { $0.key.rawValue < $1.key.rawValue }
                    .map { " · \($0.key.rawValue) \($0.value)" }.joined())
                .font(.caption)
            Text("Held by \(owner.map { Palette.name($0, state) } ?? "nobody") · population \(state.population(of: id))")
                .font(.caption)
            if let army = state.armies[id], army.units.total > 0 {
                Text("\(Palette.name(army.owner, state)): \(army.units.infantry) inf, \(army.units.archers) arc, "
                     + "\(army.units.cavalry) cav"
                     + (state.generals.values.first { $0.location == id }.map { " · \($0.name)" } ?? ""))
                    .font(.caption)
            }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}
