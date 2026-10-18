import HegemonCore
import SwiftUI

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
/// What the map emphasizes.
enum MapLayer: String, CaseIterable {
    case armies = "Armies", threats = "Threats", supply = "Supply", trade = "Trade", resources = "Resources"
}

struct MapView: View {
    let state: GameState
    let map: GameMap
    /// Needed for the supply and trade layers.
    var engine: Engine?
    var layer = MapLayer.armies
    /// Whose supply lines to show.
    var focus: CivilizationID?
    /// The selected territory or sea.
    var selected: MapPick?
    /// Where the current selection can go: drawn with a dashed glow.
    var targets: Set<MapPick> = []
    /// A tap on a territory, or on a sea near its fleet marker.
    var onTap: (MapPick?) -> Void = { _ in }
    /// A long press, for a quick look.
    var onLongPress: (MapPick?) -> Void = { _ in }
    /// What happened this round, drawn as arrows, crossed swords and flashes.
    var marks: [MapMark] = []
    /// An attack being planned: an arrow with its label (the odds).
    var planned: (from: TerritoryID, to: TerritoryID, label: String?)?
    /// The player's armies that could still act this turn: they pulse.
    var idle: Set<TerritoryID> = []
    private let art = BoardArt.shared

    /// Pinch to zoom (about the pinch), drag to pan.
    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var pinchStart: (zoom: CGFloat, pan: CGSize)?
    @State private var dragStart: CGSize?
    static let maxZoom: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            let t = BoardTransform(fitting: geo.size, zoom: zoom, pan: pan)
            TimelineView(.animation(minimumInterval: 1 / 15, paused: idle.isEmpty)) { timeline in
                Canvas { context, _ in
                    draw(&context, t)
                    drawIdle(&context, t, phase: timeline.date.timeIntervalSinceReferenceDate)
                }
            }
                .contentShape(Rectangle())
                .gesture(press(t).exclusively(before: SpatialTapGesture().onEnded { onTap(pick(at: $0.location, t)) }))
                .gesture(pinch(geo.size).simultaneously(with: drag(geo.size)))
                .overlay(alignment: .bottomLeading) {
                    if zoom > 1.01 {
                        Button {
                            withAnimation(.easeInOut(duration: 0.3)) { zoom = 1; pan = .zero }
                        } label: {
                            Image(systemName: "arrow.down.right.and.arrow.up.left")
                                .font(.callout.weight(.semibold))
                                .padding(9)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .padding(10)
                        .transition(.opacity)
                    }
                }
        }
    }

    /// A long press, reported where the finger lifts.
    private func press(_ t: BoardTransform) -> some Gesture {
        LongPressGesture(minimumDuration: 0.45)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onEnded { value in
                if case .second(true, let drag?) = value { onLongPress(pick(at: drag.location, t)) }
            }
    }

    private func pinch(_ size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = pinchStart ?? (zoom, pan)
                if pinchStart == nil { pinchStart = start }
                let newZoom = min(Self.maxZoom, max(1, start.zoom * value.magnification))
                // Keep the point under the fingers where it is.
                let anchor = CGPoint(x: value.startAnchor.x * size.width - size.width / 2,
                                     y: value.startAnchor.y * size.height - size.height / 2)
                let k = newZoom / start.zoom
                zoom = newZoom
                pan = clamped(CGSize(width: anchor.x - (anchor.x - start.pan.width) * k,
                                     height: anchor.y - (anchor.y - start.pan.height) * k), size)
            }
            .onEnded { _ in pinchStart = nil }
    }

    private func drag(_ size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard pinchStart == nil, zoom > 1 else { return }
                let start = dragStart ?? pan
                if dragStart == nil { dragStart = start }
                pan = clamped(CGSize(width: start.width + value.translation.width,
                                     height: start.height + value.translation.height), size)
            }
            .onEnded { _ in dragStart = nil }
    }

    private func clamped(_ pan: CGSize, _ size: CGSize) -> CGSize {
        let limit = BoardTransform.panLimit(size, zoom: zoom)
        return CGSize(width: min(limit.width, max(-limit.width, pan.width)),
                      height: min(limit.height, max(-limit.height, pan.height)))
    }

    /// Seas win when the tap is near their fleet marker; otherwise the territory under the finger.
    private func pick(at location: CGPoint, _ t: BoardTransform) -> MapPick? {
        if let sea = art.seas.min(by: { distance(t.point($0.value), location) < distance(t.point($1.value), location) }),
           distance(t.point(sea.value), location) < 16 {
            return .sea(sea.key)
        }
        // Army tokens can sit near an edge; a tap on one picks its territory.
        if let token = art.territories.min(by: { distance(t.point($0.value.token), location)
                                                  < distance(t.point($1.value.token), location) }),
           distance(t.point(token.value.token), location) < 9 * t.detail {
            return .territory(token.key)
        }
        return map.territories.first { territory in
            art.territories[territory.id].map { t.path($0.polygon).contains(location) } ?? false
        }.map { .territory($0.id) }
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

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
                    // Relations with the player: a thin inner line, green at peace, red at war.
                    if let me = focus, owner != me, state.isPlayer(owner) {
                        layer.stroke(path, with: .color(state.atPeace(me, owner) ? .green : .red),
                                     style: StrokeStyle(lineWidth: 12, dash: [3, 4]))
                        layer.stroke(path, with: .color(color), lineWidth: 8)
                    }
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

        for target in targets {
            if case .territory(let id) = target, let shape = art.territories[id] {
                let path = t.path(shape.polygon)
                context.fill(path, with: .color(.white.opacity(0.18)))
                context.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 1.8, dash: [4, 3]))
            }
        }
        if case .territory(let id)? = selected, let shape = art.territories[id] {
            context.stroke(t.path(shape.polygon), with: .color(.white), lineWidth: 2.5)
        }

        switch layer {
        case .supply: drawSupply(&context, t)
        case .trade: drawTrade(&context, t)
        case .threats: drawThreats(&context, t)
        case .armies, .resources: break
        }
        drawMarks(&context, t)

        // Names in the board's hand lettering, then armies and fleets.
        for territory in map.territories {
            guard let shape = art.territories[territory.id] else { continue }
            let p = t.point(shape.label)
            var lettering = context
            lettering.translateBy(x: p.x, y: p.y)
            lettering.rotate(by: .degrees(shape.angle))
            lettering.draw(Text(territory.name.uppercased())
                            .font(.custom("ChalkboardSE-Bold", size: 6.5 * t.detail))
                            .foregroundStyle(.black.opacity(0.85)),
                           at: .zero)
            // Zoomed in: grain, people and buildings under the army token (a clear spot even
            // where the lettering runs sideways), below its troop plate.
            if t.detail >= 1.3, layer != .resources {
                let c = t.point(shape.token)
                let k = t.detail
                let army = (state.armies[territory.id]?.units.total ?? 0) > 0
                let below: CGFloat = army ? 7.5 * k + (k >= 1.5 ? 8 * k + 10 : 4) + 6 * k : 0
                drawInfoLine(&context, territory, at: CGPoint(x: c.x, y: c.y + below), scale: k)
            }
            if layer == .resources {
                drawResources(&context, territory, at: t.point(shape.token))
            } else if let army = state.armies[territory.id], army.units.total > 0 {
                let c = t.point(shape.token)
                let native = !state.isPlayer(army.owner)
                let r: CGFloat = (native ? 5.5 : 7.5) * t.detail
                let led = state.generals.values.contains { $0.location == territory.id }
                let badge = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
                context.fill(badge, with: .color(Palette.color(army.owner, state).opacity(native ? 0.8 : 1)))
                context.stroke(badge, with: .color(.black.opacity(0.7)), lineWidth: 0.7)
                context.draw(Text("\(army.units.total)\(led ? "★" : "")")
                                .font(.system(size: (native ? 7 : 8.5) * t.detail, weight: .heavy))
                                .foregroundStyle(native ? Color.black.opacity(0.7) : .white),
                             at: c)
                // Zoomed in, the army's make-up shows under its token.
                if t.detail >= 1.5 {
                    drawComposition(&context, army.units, below: CGPoint(x: c.x, y: c.y + r + 2), owner: army.owner, scale: t.detail)
                }
            }
            if layer != .resources { drawBadges(&context, territory.id, at: t.point(shape.token), t) }
        }
        if let planned { drawPlanned(&context, planned, t) }
        for (sea, label) in art.seas {
            let p = t.point(label)
            if targets.contains(.sea(sea)) || selected == .sea(sea) {
                let ring = Path(ellipseIn: CGRect(x: p.x - 13, y: p.y - 4, width: 26, height: 26))
                context.stroke(ring, with: .color(.white),
                               style: StrokeStyle(lineWidth: selected == .sea(sea) ? 2.5 : 1.6,
                                                  dash: selected == .sea(sea) ? [] : [4, 3]))
            }
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

extension MapView {
    private func token(_ t: TerritoryID, _ bt: BoardTransform) -> CGPoint? {
        art.territories[t].map { bt.point($0.token) }
    }

    /// A shield on walled land, and a warning on the player's land that's cut off from supply.
    fileprivate func drawBadges(_ context: inout GraphicsContext, _ id: TerritoryID, at c: CGPoint, _ t: BoardTransform) {
        let land = state.land[id]
        let k = t.detail
        if land?.improvements.contains(.walls) == true {
            let s = 5.5 * k
            let o = CGPoint(x: c.x + 6 * k, y: c.y - 9 * k)
            var shield = Path()
            shield.move(to: CGPoint(x: o.x - s / 2, y: o.y - s / 2))
            shield.addLine(to: CGPoint(x: o.x + s / 2, y: o.y - s / 2))
            shield.addLine(to: CGPoint(x: o.x + s / 2, y: o.y))
            shield.addQuadCurve(to: CGPoint(x: o.x, y: o.y + s * 0.7), control: CGPoint(x: o.x + s / 2, y: o.y + s * 0.5))
            shield.addQuadCurve(to: CGPoint(x: o.x - s / 2, y: o.y), control: CGPoint(x: o.x - s / 2, y: o.y + s * 0.5))
            shield.closeSubpath()
            context.fill(shield, with: .color(Color(white: 0.85)))
            context.stroke(shield, with: .color(.black.opacity(0.8)), lineWidth: 0.8)
        }
        if let me = focus, state.owner(of: id) == me, let engine,
           !engine.homeNetwork(of: me, in: state).contains(id) {
            context.draw(Text("⚠️").font(.system(size: 7 * k)), at: CGPoint(x: c.x - 8 * k, y: c.y - 8 * k))
        }
    }

    /// "🌾3 👥2 🧱🌱" under a territory's name.
    fileprivate func drawInfoLine(_ context: inout GraphicsContext, _ territory: Territory, at p: CGPoint, scale: CGFloat) {
        guard let engine else { return }
        let land = state.land[territory.id]
        let built = ProjectKind.allCases.filter { land?.improvements.contains($0) ?? false }.map(Self.projectGlyph).joined()
        let text = Text("🌾\(engine.territoryYield(.grain, territory.id, state)) 👥\(state.population(of: territory.id))"
                        + (built.isEmpty ? "" : " " + built) + (land?.construction != nil ? "🏗" : ""))
            .font(.system(size: 7.5 * scale, weight: .semibold))
            .foregroundStyle(.black.opacity(0.8))
        let resolved = context.resolve(text)
        let size = resolved.measure(in: CGSize(width: 200, height: 20))
        context.fill(Path(roundedRect: CGRect(x: p.x - size.width / 2 - 2, y: p.y - size.height / 2,
                                              width: size.width + 4, height: size.height), cornerRadius: 3 * scale),
                     with: .color(.white.opacity(0.6)))
        context.draw(resolved, at: p)
    }

    /// A breathing ring round each army that could still act this turn.
    fileprivate func drawIdle(_ context: inout GraphicsContext, _ t: BoardTransform, phase: Double) {
        guard !idle.isEmpty, layer != .resources else { return }
        let pulse = 0.5 + 0.5 * sin(phase * 3.2)
        for id in idle {
            guard let c = token(id, t) else { continue }
            let r = (10 + 3 * pulse) * t.detail
            context.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                           with: .color(.white.opacity(0.4 + 0.5 * pulse)), lineWidth: 1.6)
        }
    }

    /// The player's territories by danger: hostile troops within reach against the garrison.
    fileprivate func drawThreats(_ context: inout GraphicsContext, _ t: BoardTransform) {
        guard let me = focus else { return }
        let threats = ThreatMap(for: me, in: state, map: map)
        for territory in map.territories {
            guard let shape = art.territories[territory.id] else { continue }
            let path = t.path(shape.polygon)
            guard state.owner(of: territory.id) == me else {
                context.fill(path, with: .color(.black.opacity(0.3)))
                continue
            }
            let danger = threats.threat[territory.id] ?? 0
            let garrison = threats.garrison[territory.id] ?? 0
            let color: Color = danger == 0 ? .green : danger > garrison ? .red : .orange
            context.fill(path, with: .color(color.opacity(danger == 0 ? 0.15 : 0.4)))
            if danger > 0, let c = token(territory.id, t) {
                let label = context.resolve(Text("⚔︎\(danger) vs \(garrison)").font(.system(size: 7.5 * t.detail, weight: .heavy))
                    .foregroundStyle(.white))
                let size = label.measure(in: CGSize(width: 200, height: 30))
                let box = CGRect(x: c.x - size.width / 2 - 3, y: c.y + 9 * t.detail, width: size.width + 6, height: size.height + 2)
                context.fill(Path(roundedRect: box, cornerRadius: 4), with: .color(color.opacity(0.9)))
                context.draw(label, at: CGPoint(x: box.midX, y: box.midY))
            }
        }
    }

    /// This round's happenings: arrows for marches and landings, swords for battles, flashes for
    /// captures, glyphs for disasters.
    fileprivate func drawMarks(_ context: inout GraphicsContext, _ t: BoardTransform) {
        for mark in marks {
            switch mark {
            case let .march(civ, from, to, units):
                guard let a = token(from, t), let b = token(to, t) else { continue }
                arrow(&context, from: a, to: b, color: Palette.color(civ, state), label: "\(units)", t)
            case let .landing(civ, sea, to, units):
                guard let s = art.seas[sea].map(t.point), let b = token(to, t) else { continue }
                arrow(&context, from: s, to: b, color: Palette.color(civ, state), label: "⛵\(units)", t)
            case let .battle(at, winner, _):
                guard let c = token(at, t) else { continue }
                let r = 7 * t.detail
                context.fill(Path(ellipseIn: CGRect(x: c.x + r * 0.6, y: c.y - r * 1.8, width: r * 1.6, height: r * 1.6)),
                             with: .color(Palette.color(winner, state)))
                context.draw(Text("⚔︎").font(.system(size: 8 * t.detail, weight: .black)).foregroundStyle(.white),
                             at: CGPoint(x: c.x + r * 1.4, y: c.y - r))
            case let .captured(id, civ):
                guard let shape = art.territories[id] else { continue }
                context.stroke(t.path(shape.polygon), with: .color(Palette.color(civ, state)),
                               style: StrokeStyle(lineWidth: 3, dash: [6, 3]))
            case let .event(id, kind):
                guard let c = token(id, t) else { continue }
                context.draw(Text(MapMark.glyph(kind)).font(.system(size: 9 * t.detail)),
                             at: CGPoint(x: c.x - 10 * t.detail, y: c.y + 8 * t.detail))
            }
        }
    }

    fileprivate func drawPlanned(_ context: inout GraphicsContext, _ plan: (from: TerritoryID, to: TerritoryID, label: String?),
                                 _ t: BoardTransform) {
        guard let a = token(plan.from, t), let b = token(plan.to, t) else { return }
        arrow(&context, from: a, to: b, color: .white, label: plan.label, t, width: 3.5)
    }

    /// A curved arrow between two points, stopping short of the token, with an optional label.
    private func arrow(_ context: inout GraphicsContext, from a: CGPoint, to b: CGPoint, color: Color, label: String?,
                       _ t: BoardTransform, width: CGFloat = 2.4) {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = max(1, hypot(dx, dy))
        let inset = 9 * t.detail
        let start = CGPoint(x: a.x + dx / len * inset, y: a.y + dy / len * inset)
        let end = CGPoint(x: b.x - dx / len * inset, y: b.y - dy / len * inset)
        let bend = CGPoint(x: (start.x + end.x) / 2 - dy / len * len * 0.15, y: (start.y + end.y) / 2 + dx / len * len * 0.15)
        var path = Path()
        path.move(to: start)
        path.addQuadCurve(to: end, control: bend)
        context.stroke(path, with: .color(.black.opacity(0.5)), style: StrokeStyle(lineWidth: width + 2, lineCap: .round))
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
        // Head, pointing along the last stretch of the curve.
        let ang = atan2(end.y - bend.y, end.x - bend.x)
        let h = 6 * t.detail
        var head = Path()
        head.move(to: end)
        head.addLine(to: CGPoint(x: end.x - h * cos(ang - 0.45), y: end.y - h * sin(ang - 0.45)))
        head.addLine(to: CGPoint(x: end.x - h * cos(ang + 0.45), y: end.y - h * sin(ang + 0.45)))
        head.closeSubpath()
        context.fill(head, with: .color(color))
        context.stroke(head, with: .color(.black.opacity(0.5)), lineWidth: 0.8)
        if let label {
            let mid = CGPoint(x: (start.x + 2 * bend.x + end.x) / 4, y: (start.y + 2 * bend.y + end.y) / 4)
            let text = context.resolve(Text(label).font(.system(size: 7.5 * t.detail, weight: .heavy)).foregroundStyle(.black))
            let size = text.measure(in: CGSize(width: 200, height: 30))
            context.fill(Path(roundedRect: CGRect(x: mid.x - size.width / 2 - 3, y: mid.y - size.height / 2 - 1,
                                                  width: size.width + 6, height: size.height + 2), cornerRadius: 4),
                         with: .color(color.opacity(0.95)))
            context.draw(text, at: mid)
        }
    }

    private func point(_ node: NetworkNode, _ t: BoardTransform) -> CGPoint? {
        switch node {
        case .land(let id): art.territories[id].map { t.point($0.token) }
        case .sea(let id): art.seas[id].map(t.point)
        }
    }

    private func line(through nodes: [NetworkNode], _ t: BoardTransform) -> Path {
        var path = Path()
        path.addLines(nodes.compactMap { point($0, t) })
        return path
    }

    /// The focus civ's supply network: other land dimmed, cut-off land in red, and a line from
    /// the capital to every army, orange or red where the distance costs extra grain.
    fileprivate func drawSupply(_ context: inout GraphicsContext, _ t: BoardTransform) {
        guard let engine, let civ = focus else { return }
        let pockets = engine.supplyPockets(of: civ, in: state)
        let home = Set(pockets.first ?? [])
        for territory in map.territories {
            guard let shape = art.territories[territory.id] else { continue }
            let path = t.path(shape.polygon)
            if state.owner(of: territory.id) != civ {
                context.fill(path, with: .color(.black.opacity(0.35)))
            } else if !home.contains(territory.id) {
                context.fill(path, with: .color(.red.opacity(0.45)))
            }
        }
        for (territory, _) in state.armies(of: civ) where home.contains(territory) {
            guard let route = engine.supplyRoute(of: civ, to: territory, in: state), route.count > 1 else { continue }
            let extra = engine.supplyStrain(of: civ, at: territory, in: state)?.extraGrain ?? 0
            let color: Color = extra == 0 ? .white : extra == 1 ? .orange : .red
            context.stroke(line(through: route, t), with: .color(.black.opacity(0.5)),
                           style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            context.stroke(line(through: route, t), with: .color(color),
                           style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
        }
        if let seat = engine.seat(of: civ, in: state), let shape = art.territories[seat] {
            let c = t.point(shape.token)
            context.draw(Text("♛").font(.system(size: 13, weight: .bold)).foregroundStyle(.yellow),
                         at: CGPoint(x: c.x, y: c.y - 12))
        }
    }

    /// Every trade route along its path, and who holds each sea strait.
    fileprivate func drawTrade(_ context: inout GraphicsContext, _ t: BoardTransform) {
        guard let engine else { return }
        for territory in map.territories {
            if let shape = art.territories[territory.id], state.owner(of: territory.id) == nil {
                context.fill(t.path(shape.polygon), with: .color(.black.opacity(0.25)))
            }
        }
        let routes = engine.tradeRoutes(in: state)
        for route in routes {
            let path = line(through: route.path, t)
            context.stroke(path, with: .color(.black.opacity(0.5)),
                           style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            context.stroke(path, with: .color(.yellow),
                           style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round, dash: [6, 3]))
        }
        // What each route carries, at its middle: each partner's color, then what it receives.
        for route in routes {
            let stops = route.path.compactMap { point($0, t) }
            guard !stops.isEmpty else { continue }
            let middle = stops[stops.count / 2]
            let flows = engine.goods(along: route, in: state)
            var lines: [Text] = []
            for to in [route.partners.a, route.partners.b] {
                let goods = Resource.allCases.compactMap { r in flows[to]?[r].map { _ in Self.glyph(r) } }
                guard !goods.isEmpty else { continue }
                lines.append(Text("▸ ").foregroundStyle(Palette.color(to, state))
                             + Text(goods.joined(separator: " ")).foregroundStyle(.black))
            }
            guard !lines.isEmpty else { continue }
            let resolved = lines.map { context.resolve($0.font(.system(size: 6.5, weight: .bold))) }
            let width = (resolved.map { $0.measure(in: CGSize(width: 200, height: 20)).width }.max() ?? 0) + 4
            let height = CGFloat(lines.count) * 9 + 3
            // Keep the label on the board.
            let left = t.point([BoardArt.frame.minX, 0]).x, right = t.point([BoardArt.frame.maxX, 0]).x
            let mid = CGPoint(x: min(max(middle.x, left + width / 2 + 2), right - width / 2 - 2), y: middle.y)
            context.fill(Path(roundedRect: CGRect(x: mid.x - width / 2, y: mid.y - height / 2, width: width, height: height),
                              cornerRadius: 3), with: .color(.white.opacity(0.8)))
            for (i, line) in resolved.enumerated() {
                context.draw(line, at: CGPoint(x: mid.x, y: mid.y - height / 2 + 6 + CGFloat(i) * 9))
            }
        }
        let tolled = Set(routes.flatMap(\.chokepoints))
        for strait in map.chokepoints {
            guard let link = strait.gatesSeaLink, let a = art.seas[link[0]], let b = art.seas[link[1]] else { continue }
            let pa = t.point(a), pb = t.point(b)
            let c = CGPoint(x: (pa.x + pb.x) / 2, y: (pa.y + pb.y) / 2)
            let holder = engine.holder(of: strait, in: state)
            let dot = Path(ellipseIn: CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12))
            context.fill(dot, with: .color(holder.map { Palette.color($0, state) } ?? Color(white: 0.8)))
            context.stroke(dot, with: .color(tolled.contains(strait.id) ? .yellow : .black), lineWidth: 1.5)
            context.draw(Text(strait.name).font(.system(size: 6.5, weight: .semibold)).foregroundStyle(.white),
                         at: CGPoint(x: c.x, y: c.y + 11))
        }
    }

    /// Unit icons with counts, on a small plate.
    fileprivate func drawComposition(_ context: inout GraphicsContext, _ units: UnitCounts, below top: CGPoint,
                                     owner: CivilizationID, scale: CGFloat) {
        let types = UnitType.allCases.filter { units[$0] > 0 }
        guard !types.isEmpty else { return }
        let icon = 8 * scale, step = 17 * scale
        let width = CGFloat(types.count) * step + 2
        let plate = CGRect(x: top.x - width / 2, y: top.y, width: width, height: icon + 4)
        context.fill(Path(roundedRect: plate, cornerRadius: 3), with: .color(.white.opacity(0.85)))
        for (i, type) in types.enumerated() {
            let x = plate.minX + 2 + CGFloat(i) * step
            let box = CGRect(x: x, y: plate.minY + 2, width: icon, height: icon)
            context.fill(UnitShape(type: type).path(in: box), with: .color(.black.opacity(0.8)))
            context.draw(Text("\(units[type])").font(.system(size: 7 * scale, weight: .bold)).foregroundStyle(.black),
                         at: CGPoint(x: box.maxX + 2, y: box.midY), anchor: .leading)
        }
    }

    static func glyph(_ r: Resource) -> String {
        switch r {
        case .grain: "🌾"
        case .copper: "Cu"
        case .tin: "Sn"
        case .iron: "Fe"
        case .horses: "🐎"
        case .timber: "🪵"
        case .gold: "🪙"
        case .wine: "🍷"
        case .luxuries: "💎"
        case .stone: "🪨"
        }
    }

    /// Grain and resources on each territory, as on the board's tokens, and what's been built.
    fileprivate func drawResources(_ context: inout GraphicsContext, _ territory: Territory, at c: CGPoint) {
        var parts = [Text("🌾\(territory.grain)").foregroundStyle(.black)]
        let metals: [Resource: Color] = [.copper: Color(red: 0.7, green: 0.35, blue: 0.1), .tin: Color(white: 0.35),
                                         .iron: Color(red: 0.45, green: 0.2, blue: 0.2)]
        for resource in Resource.allCases where resource != .grain {
            if let n = territory.resources[resource], n > 0 {
                parts.append(Text(" \(Self.glyph(resource))\(n)").foregroundStyle(metals[resource] ?? .black))
            }
        }
        let label = context.resolve(parts.dropFirst().reduce(parts[0]) { $0 + $1 }.font(.system(size: 6.5, weight: .bold)))
        let measured = label.measure(in: CGSize(width: 200, height: 20))
        let size = CGSize(width: measured.width + 4, height: measured.height + 1)
        context.fill(Path(roundedRect: CGRect(x: c.x - size.width / 2, y: c.y - size.height / 2, width: size.width, height: size.height),
                          cornerRadius: 3), with: .color(.white.opacity(0.75)))
        context.draw(label, at: c)
        let land = state.land[territory.id]
        let built = ProjectKind.allCases.filter { land?.improvements.contains($0) ?? false }.map(Self.projectGlyph)
            + (land?.construction == nil ? [] : ["🏗"])
        if !built.isEmpty {
            context.draw(Text(built.joined()).font(.system(size: 7)), at: CGPoint(x: c.x, y: c.y + 11))
        }
    }

    static func projectGlyph(_ kind: ProjectKind) -> String {
        switch kind {
        case .road: "🛤"
        case .walls: "🧱"
        case .farm: "🌱"
        case .mine: "⛏"
        case .harbor: "⚓"
        }
    }
}

/// Something on the map that can be selected.
enum MapPick: Hashable {
    case territory(TerritoryID)
    case sea(SeaZoneID)
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
            let built = state.land[id]?.improvements ?? []
            if !built.isEmpty || state.land[id]?.construction != nil {
                Text((ProjectKind.allCases.filter { built.contains($0) }.map(projectName)
                      + (state.land[id]?.construction.map { ["building \(projectName($0.kind).lowercased())"] } ?? []))
                        .joined(separator: " · "))
                    .font(.caption)
            }
            if let army = state.armies[id], army.units.total > 0 {
                HStack(spacing: 6) {
                    Text("\(Palette.name(army.owner, state)):")
                    UnitRow(units: army.units, size: 12)
                    if let g = state.generals.values.first(where: { $0.location == id }) { Text("· \(g.name)") }
                }
                .font(.caption)
            }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}
