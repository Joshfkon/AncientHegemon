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

/// A request to bring a territory into view, e.g. when the panel opens over it.
struct MapCenter: Equatable {
    let territory: TerritoryID
    /// Zoom in at least this far.
    var minZoom: CGFloat = 1
    /// Only move if the territory is outside the visible area (otherwise always center it).
    var onlyIfHidden = true
    /// Distinguishes repeated requests for the same place.
    var id = 0
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
    /// Told, just before `onTap`, whether the tap landed on an army's cube rather than the land.
    var onCubeTap: (Bool) -> Void = { _ in }
    /// A long press, for a quick look.
    var onLongPress: (MapPick?) -> Void = { _ in }
    /// What happened this round, drawn as arrows, crossed swords and flashes.
    var marks: [MapMark] = []
    /// When each mark appeared (parallel to `marks`), to animate new ones.
    var markTimes: [Date] = []
    /// An attack being planned: an arrow with its label (the odds).
    var planned: (from: TerritoryID, to: TerritoryID, label: String?)?
    /// The player's armies that could still act this turn: they pulse.
    var idle: Set<TerritoryID> = []
    /// Width covered by the panel on the right; the map can pan further so nothing is stuck under it.
    var trailingInset: CGFloat = 0
    /// Height covered by the command bar along the bottom: territories are brought above it.
    var bottomInset: CGFloat = 0
    /// Bring a territory into the visible part of the map.
    var center: MapCenter?
    /// Territories to spotlight (e.g. where a resource comes from): the rest is dimmed.
    var spotlight: Set<TerritoryID> = []
    /// Territories that just changed hands: a sweep of the new owner's colour.
    var flashes: [TerritoryID: Date] = [:]
    /// What the player sees clearly; elsewhere armies, people and works are hidden. Nil: all.
    var sight: Set<TerritoryID>?

    private func seen(_ t: TerritoryID) -> Bool { sight?.contains(t) ?? true }
    @State private var viewSize: CGSize = .zero
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
            TimelineView(.animation(minimumInterval: 1 / 30, paused: idle.isEmpty && flashes.isEmpty && !animatingMarks && !armySelected)) { timeline in
                Canvas { context, _ in
                    draw(&context, t, now: timeline.date)
                    drawFlashes(&context, t, now: timeline.date)
                    drawIdle(&context, t, phase: timeline.date.timeIntervalSinceReferenceDate)
                }
            }
                .contentShape(Rectangle())
                .gesture(press(t).exclusively(before: SpatialTapGesture().onEnded {
                    onCubeTap(onCube($0.location, t))
                    onTap(pick(at: $0.location, t))
                }))
                .gesture(pinch(geo.size).simultaneously(with: drag(geo.size)))
                .onAppear {
                    viewSize = geo.size
                    if let center { bring(center, geo.size, animated: false) }
                }
                .onChange(of: geo.size) { _, size in viewSize = size }
                .onChange(of: center) { _, request in
                    if let request { bring(request, geo.size, animated: true) }
                }
                .onChange(of: trailingInset) { _, _ in
                    withAnimation(.easeInOut(duration: 0.3)) { pan = clamped(pan, geo.size) }
                }
                .overlay(alignment: .bottomLeading) {
                    if zoom > 1.01 {
                        Button {
                            withAnimation(.easeInOut(duration: 0.3)) { zoom = 1; pan = .zero }
                        } label: {
                            Image(systemName: "arrow.down.right.and.arrow.up.left")
                                .font(.callout.weight(.semibold))
                                .padding(9)
                                .foregroundStyle(.white)
                                .woodPanel(Circle())
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
        // With the panel open the board may slide left by its width, so the east isn't trapped.
        return CGSize(width: min(limit.width, max(-limit.width - trailingInset, pan.width)),
                      height: min(limit.height, max(-limit.height - bottomInset, pan.height)))
    }

    /// Zooms and pans so a territory sits in the middle of the visible area.
    private func bring(_ request: MapCenter, _ size: CGSize, animated: Bool) {
        guard size.width > 0, let shape = art.territories[request.territory] else { return }
        // Clear of the status panel at the top and the command bar at the bottom.
        let visible = CGRect(x: 0, y: 70, width: size.width - trailingInset, height: max(120, size.height - bottomInset - 70))
        let now = BoardTransform(fitting: size, zoom: zoom, pan: pan).point(shape.token)
        if request.onlyIfHidden, zoom >= request.minZoom, visible.insetBy(dx: 60, dy: 30).contains(now) { return }
        let newZoom = max(zoom, request.minZoom)
        let base = BoardTransform(fitting: size, zoom: newZoom, pan: .zero).point(shape.token)
        let update = {
            zoom = newZoom
            pan = clamped(CGSize(width: visible.midX - base.x, height: visible.midY - base.y), size)
        }
        if animated { withAnimation(.easeInOut(duration: 0.4), update) } else { update() }
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
           distance(t.point(token.value.token), location) < 12 * t.detail {
            return .territory(token.key)
        }
        return map.territories.first { territory in
            art.territories[territory.id].map { t.path($0.polygon).contains(location) } ?? false
        }.map { .territory($0.id) }
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    /// Whether a tap lands on an army's cube.
    private func onCube(_ location: CGPoint, _ t: BoardTransform) -> Bool {
        art.territories.contains { id, shape in
            (state.armies[id]?.units.total ?? 0) > 0 && distance(t.point(shape.token), CGPoint(x: location.x, y: location.y + 2)) < 15 * t.detail
        }
    }

    private static let terrain: [Terrain: Color] = [
        .plains: Color(red: 0.42, green: 0.70, blue: 0.32),
        .hills: Color(red: 0.29, green: 0.58, blue: 0.29),
        .forest: Color(red: 0.19, green: 0.47, blue: 0.23),
        .mountains: Color(red: 0.36, green: 0.55, blue: 0.31),
        .desert: Color(red: 0.93, green: 0.69, blue: 0.21),
    ]

    /// One of the player's armies is selected: it bobs, so the map keeps drawing.
    private var armySelected: Bool {
        guard case .territory(let id)? = selected, let focus else { return false }
        return state.armies[id]?.owner == focus
    }

    /// Marks young enough to still be moving.
    private var animatingMarks: Bool {
        guard let last = markTimes.last else { return false }
        return Date.now.timeIntervalSince(last) < 2.3
    }

    private func draw(_ context: inout GraphicsContext, _ t: BoardTransform, now: Date = .now) {
        let f = BoardArt.frame
        let board = Path(CGRect(origin: t.point([f.minX, f.minY]),
                                size: CGSize(width: f.width * t.scale, height: f.height * t.scale)))
        context.fill(board, with: .linearGradient(
            Gradient(colors: [Color(red: 0.12, green: 0.30, blue: 0.62), Color(red: 0.20, green: 0.45, blue: 0.76)]),
            startPoint: t.point([f.minX, f.minY]), endPoint: t.point([f.maxX, f.maxY])))
        drawWaves(&context, t)

        // Land, painted by terrain and tinted by owner.
        for territory in map.territories {
            guard let shape = art.territories[territory.id] else { continue }
            let path = t.path(shape.polygon)
            context.fill(path, with: .color(Self.terrain[territory.terrain] ?? .green))
            if let owner = state.owner(of: territory.id) {
                let color = Palette.color(owner, state)
                // A light wash keeps the terrain readable; the bold inner border says whose it is.
                context.fill(path, with: .color(color.opacity(0.13)))
                context.drawLayer { layer in
                    layer.clip(to: path)
                    layer.stroke(path, with: .color(color), lineWidth: 9 * t.detail)
                    layer.stroke(path, with: .color(.white.opacity(0.35)), lineWidth: 1.2)
                    // Relations with the player: a thin inner line, green at peace, red at war.
                    if let me = focus, owner != me, state.isPlayer(owner) {
                        layer.stroke(path, with: .color(state.atPeace(me, owner) ? .green : .red),
                                     style: StrokeStyle(lineWidth: 12, dash: [3, 4]))
                        layer.stroke(path, with: .color(color), lineWidth: 8)
                    }
                }
            } else if let k = state.stationed[territory.id]?.kingdom ?? state.armies[territory.id].flatMap({ isKingdom($0.owner) ? $0.owner : nil }),
                      let kingdom = state.kingdoms[k] {
                // A kingdom's land: a light wash and thin border in its colour; a vassal's is
                // ringed, dashed, in its overlord's.
                let color = Palette.color(k, state)
                context.fill(path, with: .color(color.opacity(0.16)))
                context.drawLayer { layer in
                    layer.clip(to: path)
                    if let lord = kingdom.overlord {
                        layer.stroke(path, with: .color(Palette.color(lord, state)),
                                     style: StrokeStyle(lineWidth: 8 * t.detail, dash: [6 * t.detail, 4 * t.detail]))
                    } else {
                        layer.stroke(path, with: .color(color.opacity(0.8)), lineWidth: 4 * t.detail)
                    }
                }
            }
            context.stroke(path, with: .color(.black.opacity(0.85)), lineWidth: 1.1)
        }

        // A paper grain over everything, so it reads as the painted board rather than flat colour.
        context.drawLayer { layer in
            layer.opacity = 0.18
            layer.blendMode = .multiply
            layer.fill(board, with: .tiledImage(Self.paper, origin: t.point([f.minX, f.minY]), scale: 0.5))
        }

        // Beyond sight: a pale haze, as on maps drawn from travellers' tales.
        if sight != nil {
            for territory in map.territories where !seen(territory.id) {
                guard let shape = art.territories[territory.id] else { continue }
                context.fill(t.path(shape.polygon), with: .color(Color(red: 0.93, green: 0.89, blue: 0.78).opacity(0.42)))
            }
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

        drawWorks(&context, t)

        // Land the selected army can march to glows white; coasts it can reach by ship glow blue.
        let overSea: (TerritoryID) -> Bool = { id in
            guard case .territory(let from)? = self.selected else { return false }
            return !self.map.areLandAdjacent(from, id)
        }
        for target in targets {
            if case .territory(let id) = target, let shape = art.territories[id] {
                let path = t.path(shape.polygon)
                let sea = overSea(id)
                let color = sea ? Color(red: 0.55, green: 0.85, blue: 1) : .white
                context.fill(path, with: .color(color.opacity(sea ? 0.25 : 0.18)))
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.8, dash: [4, 3]))
                if sea {
                    context.draw(Text(Image(systemName: "sailboat.fill")).font(.system(size: 11 * t.detail))
                                    .foregroundStyle(color),
                                 at: CGPoint(x: t.point(shape.token).x + 14 * t.detail, y: t.point(shape.token).y - 14 * t.detail))
                }
            }
        }
        if case .territory(let id)? = selected, let shape = art.territories[id] {
            let path = t.path(shape.polygon)
            context.stroke(path, with: .color(.black.opacity(0.6)), lineWidth: 5)
            context.stroke(path, with: .color(Self.bronze), lineWidth: 2.8)
        }

        switch layer {
        case .supply: drawSupply(&context, t)
        case .trade: drawTrade(&context, t)
        case .threats: drawThreats(&context, t)
        case .armies, .resources: break
        }
        drawMarks(&context, t, now: now)
        if !spotlight.isEmpty {
            for territory in map.territories {
                guard let shape = art.territories[territory.id] else { continue }
                let path = t.path(shape.polygon)
                if spotlight.contains(territory.id) {
                    context.stroke(path, with: .color(.yellow), style: StrokeStyle(lineWidth: 3, lineJoin: .round))
                } else {
                    context.fill(path, with: .color(.black.opacity(0.35)))
                }
            }
        }

        drawSieges(&context, t)
        // Names in the board's hand lettering.
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
        }
        // Each territory's plaque under its army token, then the token and its marks; the
        // selected territory last, so its plaque sits on top.
        let picked: TerritoryID? = if case .territory(let id)? = selected { id } else { nil }
        // Armies still on the road: their token appears where they arrive only once they get there.
        var arriving = Set<TerritoryID>()
        for (i, mark) in marks.enumerated() where i < markTimes.count && now.timeIntervalSince(markTimes[i]) < 0.6 {
            switch mark {
            case let .march(_, _, to, _), let .landing(_, _, to, _): arriving.insert(to)
            default: break
            }
        }
        for territory in map.territories.filter({ $0.id != picked }) + map.territories.filter({ $0.id == picked }) {
            guard let shape = art.territories[territory.id] else { continue }
            let c = t.point(shape.token)
            let army = state.armies[territory.id].flatMap { $0.units.total > 0 ? $0 : nil }
            let shown = seen(territory.id) || army?.owner == focus
            drawPlaque(&context, territory, at: c, army: layer == .resources || !shown ? nil : army, t,
                       emphasized: territory.id == picked, hidden: !seen(territory.id))
            if layer != .resources, let army, !arriving.contains(territory.id) {
                if seen(territory.id) || army.owner == focus {
                    drawArmy(&context, army, at: c, in: territory.id, t, now: now)
                } else if let engine, engine.rumoured(army.units) {
                    drawRumour(&context, army, at: c, t)
                }
            }
            if layer != .resources, engine != nil { drawBadges(&context, territory.id, at: c, t) }
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
            // The sea's name in the old maps' italic, so it's clear where ships are built and sail.
            if engine != nil, let name = map.sea(sea)?.name {
                let selectedHere: Bool = {
                    if case .territory(let t)? = selected { return map.territory(t)?.seas.contains(sea) ?? false }
                    return selected == .sea(sea)
                }()
                context.draw(Text(name)
                                .font(.system(size: 8 * t.detail, weight: .semibold, design: .serif).italic())
                                .foregroundStyle(.white.opacity(selectedHere ? 0.95 : 0.6)),
                             at: CGPoint(x: p.x, y: p.y - 9 * t.detail))
            }
            // Fleets are seen on seas that wash your sight, and your own everywhere.
            let watched = sight == nil || map.territories.contains { $0.seas.contains(sea) && seen($0.id) }
            for (i, fleet) in state.fleets.filter({ $0.sea == sea && (watched || $0.owner == focus) }).enumerated() {
                let label = context.resolve(Text("\(fleet.owner == piratesID ? "☠︎" : "⛵")\(fleet.ships)\(fleet.cargo.total > 0 ? " · \(fleet.cargo.total) aboard" : "")")
                                .font(.system(size: 9 * t.detail, weight: .bold)).foregroundStyle(.white))
                let size = label.measure(in: CGSize(width: 300, height: 40))
                let at = CGPoint(x: p.x, y: p.y + 6 * t.detail + CGFloat(i) * (size.height + 4))
                context.fill(Path(roundedRect: CGRect(x: at.x - size.width / 2 - 4, y: at.y - size.height / 2 - 1,
                                                      width: size.width + 8, height: size.height + 2), cornerRadius: (size.height + 2) / 2),
                             with: .color(Palette.color(fleet.owner, state)))
                context.draw(label, at: at)
            }
        }
    }
}

extension MapView {
    /// A seeded paper-grain texture, made once.
    static let paper: Image = {
        let size = 128
        var rng = SystemRandomNumberGenerator()
        _ = rng
        var seed: UInt64 = 0x1200BC
        func next() -> UInt64 { seed &+= 0x9E3779B97F4A7C15; var z = seed; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return z ^ (z >> 31) }
        var pixels = [UInt8](repeating: 255, count: size * size * 4)
        for i in 0..<(size * size) {
            let v = UInt8(170 + Int(next() % 86))
            pixels[i * 4] = v; pixels[i * 4 + 1] = v; pixels[i * 4 + 2] = UInt8(max(0, Int(v) - 12)); pixels[i * 4 + 3] = 255
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let cg = CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                         provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
        return Image(decorative: cg, scale: 1)
    }()

    /// Little painted wave marks scattered over the sea, as on old maps.
    fileprivate func drawWaves(_ context: inout GraphicsContext, _ t: BoardTransform) {
        let f = BoardArt.frame
        var waves = Path()
        var seed: UInt64 = 7
        func rand() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 33) / Double(1 << 31) }
        for _ in 0..<160 {
            let x = f.minX + rand() * f.width, y = f.minY + rand() * f.height
            let c = t.point([x, y])
            let w = 7 * t.detail
            waves.move(to: CGPoint(x: c.x - w, y: c.y))
            waves.addQuadCurve(to: CGPoint(x: c.x, y: c.y), control: CGPoint(x: c.x - w / 2, y: c.y - w * 0.45))
            waves.addQuadCurve(to: CGPoint(x: c.x + w, y: c.y), control: CGPoint(x: c.x + w / 2, y: c.y - w * 0.45))
        }
        context.stroke(waves, with: .color(.white.opacity(0.22)), style: StrokeStyle(lineWidth: 1 * t.detail, lineCap: .round))
    }

    /// Walls as stone ramparts around the land, roads as paved ways running from each road
    /// toward its neighbours; where two roads meet, the halves join into one road.
    fileprivate func drawWorks(_ context: inout GraphicsContext, _ t: BoardTransform) {
        let k = t.detail
        // Walls first, so roads run over the gates.
        for territory in map.territories where state.land[territory.id]?.improvements.contains(.walls) == true {
            guard let shape = art.territories[territory.id] else { continue }
            var inner = context
            let path = t.path(shape.polygon)
            inner.clip(to: path)
            // Stone rampart along the inside of the border, with battlements.
            inner.stroke(path, with: .color(Color(red: 0.3, green: 0.27, blue: 0.24)), lineWidth: 11 * k)
            inner.stroke(path, with: .color(Color(red: 0.72, green: 0.68, blue: 0.6)), lineWidth: 8 * k)
            inner.stroke(path, with: .color(Color(red: 0.45, green: 0.41, blue: 0.36)),
                         style: StrokeStyle(lineWidth: 8 * k, dash: [3 * k, 3 * k]))
        }
        let roads = map.territories.filter { state.land[$0.id]?.improvements.contains(.road) == true }
        for territory in roads {
            guard let a = token(territory.id, t) else { continue }
            let owner = state.owner(of: territory.id)
            for n in map.landNeighbors(of: territory.id) {
                guard let b = token(n, t), state.owner(of: n) == owner else { continue }
                let joined = state.land[n]?.improvements.contains(.road) == true
                // To the neighbour's token if it has a road too, else most of the way to the border.
                let end = joined ? CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                                 : CGPoint(x: a.x + (b.x - a.x) * 0.42, y: a.y + (b.y - a.y) * 0.42)
                var road = Path()
                road.move(to: a)
                road.addLine(to: end)
                context.stroke(road, with: .color(Color(red: 0.25, green: 0.18, blue: 0.1).opacity(0.85)),
                               style: StrokeStyle(lineWidth: 8 * k, lineCap: .round))
                context.stroke(road, with: .color(Color(red: 0.88, green: 0.78, blue: 0.56)),
                               style: StrokeStyle(lineWidth: 5.5 * k, lineCap: .round))
                context.stroke(road, with: .color(Color(red: 0.55, green: 0.45, blue: 0.3)),
                               style: StrokeStyle(lineWidth: 1.2 * k, lineCap: .round, dash: [4 * k, 4 * k]))
            }
        }
    }

    private func token(_ t: TerritoryID, _ bt: BoardTransform) -> CGPoint? {
        art.territories[t].map { bt.point($0.token) }
    }

    /// A shield on walled land, and a warning on the player's land that's cut off from supply.
    fileprivate func drawBadges(_ context: inout GraphicsContext, _ id: TerritoryID, at c: CGPoint, _ t: BoardTransform) {
        let k = t.detail
        if let me = focus, state.owner(of: id) == me, let engine,
           !engine.homeNetwork(of: me, in: state).contains(id) {
            context.draw(Text("⚠️").font(.system(size: 8.5 * k)), at: CGPoint(x: c.x - 10 * k, y: c.y - 10 * k))
        }
        // Restless land: needs a soldier or it may revolt, and pays no taxes meanwhile.
        if let me = focus, let engine, engine.restless(id, of: me, in: state) {
            let p = CGPoint(x: c.x + 11 * k, y: c.y - 11 * k)
            let r = 6 * k
            context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                         with: .color(Color(red: 0.75, green: 0.2, blue: 0.1)))
            context.draw(Text(Image(systemName: "hand.raised.fill")).font(.system(size: 7 * k, weight: .bold)).foregroundStyle(.white), at: p)
        }
        // A great work: a gold seal above the token; a work still rising, a pale one.
        let standing = state.monuments.first { $0.value == id }?.key
        if let m = standing ?? state.monumentSites[id]?.id {
            let p = CGPoint(x: c.x, y: c.y - 19 * k)
            let r = 7.5 * k
            let disc = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
            context.fill(disc, with: standing != nil ? .linearGradient(Gradient(colors: [Color(red: 1, green: 0.85, blue: 0.45), Color(red: 0.7, green: 0.48, blue: 0.15)]),
                                                                        startPoint: CGPoint(x: p.x, y: p.y - r), endPoint: CGPoint(x: p.x, y: p.y + r))
                                                      : .color(.white.opacity(0.7)))
            context.stroke(disc, with: .color(.black.opacity(0.6)), lineWidth: 0.8)
            context.draw(Text(Image(systemName: GreatWorksList.symbol(m))).font(.system(size: 8 * k, weight: .bold))
                            .foregroundStyle(Color(red: 0.25, green: 0.15, blue: 0.05).opacity(standing != nil ? 1 : 0.6)), at: p)
        }
    }

    /// A capture: the new owner's colour floods the land, then settles.
    fileprivate func drawFlashes(_ context: inout GraphicsContext, _ t: BoardTransform, now: Date) {
        for (id, start) in flashes {
            let e = now.timeIntervalSince(start)
            guard e >= 0, e < 1.6, let shape = art.territories[id], let owner = state.owner(of: id) ?? state.armies[id]?.owner else { continue }
            let path = t.path(shape.polygon)
            let color = Palette.color(owner, state)
            let k = e / 1.6
            context.fill(path, with: .color(color.opacity(0.75 * (1 - k))))
            context.drawLayer { layer in
                layer.clip(to: path)
                layer.stroke(path, with: .color(.white.opacity(1 - k)), lineWidth: (4 + 18 * k) * t.detail)
            }
            // A burst of bronze sparks from the token.
            if e < 0.9 {
                let c = t.point(shape.token)
                let b = e / 0.9
                let eased = 1 - (1 - b) * (1 - b)
                for i in 0..<14 {
                    let a = Double(i) / 14 * 2 * .pi + 0.2
                    let inner = (8 + 26 * eased) * t.detail, outer = inner + (10 * (1 - b) + 3) * t.detail
                    var ray = Path()
                    ray.move(to: CGPoint(x: c.x + cos(a) * inner, y: c.y + sin(a) * inner))
                    ray.addLine(to: CGPoint(x: c.x + cos(a) * outer, y: c.y + sin(a) * outer))
                    context.stroke(ray, with: .color((i % 2 == 0 ? Self.bronze : Color(red: 1, green: 0.92, blue: 0.6)).opacity(1 - b)),
                                   style: StrokeStyle(lineWidth: 2.4 * t.detail, lineCap: .round))
                }
                let r = (6 + 30 * eased) * t.detail
                context.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                               with: .color(color.opacity(1 - b)), lineWidth: 2 * t.detail)
            }
        }
    }

    /// A breathing ring round each army that could still act this turn.
    fileprivate func drawIdle(_ context: inout GraphicsContext, _ t: BoardTransform, phase: Double) {
        guard !idle.isEmpty, layer != .resources else { return }
        let pulse = 0.5 + 0.5 * sin(phase * 3.2)
        for id in idle where selected != .territory(id) {
            guard let c = token(id, t) else { continue }
            let r = (12.5 + 3 * pulse) * t.detail
            context.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                           with: .color(.white.opacity(0.4 + 0.5 * pulse)), lineWidth: 1.6)
        }
    }

    /// The player's territories by danger: hostile troops within reach against the garrison.
    fileprivate func drawThreats(_ context: inout GraphicsContext, _ t: BoardTransform) {
        guard let me = focus else { return }
        let threats = ThreatMap(for: me, in: state, map: map, engine: engine)
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
    fileprivate func drawMarks(_ context: inout GraphicsContext, _ t: BoardTransform, now: Date) {
        for (i, mark) in marks.enumerated() {
            // New marks animate in: armies glide along their path, battles burst.
            let age = i < markTimes.count ? now.timeIntervalSince(markTimes[i]) : 10
            let glide = min(1, max(0, age / 0.6))
            switch mark {
            case let .march(civ, from, to, units):
                guard let a = token(from, t), let b = token(to, t) else { continue }
                if glide < 1 {
                    marching(&context, from: a, to: b, progress: glide, color: Palette.color(civ, state), units: units, t)
                } else {
                    arrow(&context, from: a, to: b, color: Palette.color(civ, state), label: "\(units)", t)
                    arrival(&context, at: b, age: age - 0.6, color: Palette.color(civ, state), t)
                }
            case let .landing(civ, sea, to, units):
                guard let s = art.seas[sea].map(t.point), let b = token(to, t) else { continue }
                if glide < 1 {
                    marching(&context, from: s, to: b, progress: glide, color: Palette.color(civ, state), units: units, t)
                } else {
                    arrow(&context, from: s, to: b, color: Palette.color(civ, state), label: "⛵\(units)", t)
                    arrival(&context, at: b, age: age - 0.6, color: Palette.color(civ, state), t)
                }
            case let .battle(at, winner, _):
                guard let c = token(at, t) else { continue }
                if age < 0.9 {
                    // A clash: a flash and an expanding ring.
                    let k = age / 0.9
                    let r = (8 + 30 * k) * t.detail
                    context.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                                   with: .color(.orange.opacity(1 - k)), lineWidth: 3 * (1 - k) + 1)
                    context.fill(Path(ellipseIn: CGRect(x: c.x - 10 * t.detail, y: c.y - 10 * t.detail, width: 20 * t.detail, height: 20 * t.detail)),
                                 with: .color(.yellow.opacity(0.8 * (1 - k))))
                    context.draw(Text("⚔︎").font(.system(size: (14 + 10 * (1 - k)) * t.detail, weight: .black)).foregroundStyle(.white), at: c)
                }
                let r = 7 * t.detail
                context.fill(Path(ellipseIn: CGRect(x: c.x + r * 0.6, y: c.y - r * 1.8, width: r * 1.6, height: r * 1.6)),
                             with: .color(Palette.color(winner, state)))
                context.draw(Text("⚔︎").font(.system(size: 8 * t.detail, weight: .black)).foregroundStyle(.white),
                             at: CGPoint(x: c.x + r * 1.4, y: c.y - r))
            case let .captured(id, civ):
                // A planted flag in the taker's colour, beside the token.
                guard let c = token(id, t) else { continue }
                let k = t.detail
                let base = CGPoint(x: c.x + 9 * k, y: c.y + 6 * k)
                var pole = Path()
                pole.move(to: base)
                pole.addLine(to: CGPoint(x: base.x, y: base.y - 16 * k))
                context.stroke(pole, with: .color(.black.opacity(0.85)), lineWidth: 1.4 * k)
                var flag = Path()
                flag.move(to: CGPoint(x: base.x, y: base.y - 16 * k))
                flag.addLine(to: CGPoint(x: base.x + 10 * k, y: base.y - 12.5 * k))
                flag.addLine(to: CGPoint(x: base.x, y: base.y - 9 * k))
                flag.closeSubpath()
                context.fill(flag, with: .color(Palette.color(civ, state)))
                context.stroke(flag, with: .color(.black.opacity(0.7)), lineWidth: 0.8)
            case let .raised(id, civ, unit, count):
                // "+1 ⛑" rising from the token for a moment.
                guard age < 2.2, let c = token(id, t) else { continue }
                let k = age / 2.2
                let p = CGPoint(x: c.x, y: c.y - (12 + 26 * k) * t.detail)
                let plate = CGRect(x: p.x - 18 * t.detail, y: p.y - 8 * t.detail, width: 36 * t.detail, height: 16 * t.detail)
                context.opacity = 1 - k * k
                context.fill(Path(roundedRect: plate, cornerRadius: 8 * t.detail), with: .color(Palette.color(civ, state)))
                context.stroke(Path(roundedRect: plate, cornerRadius: 8 * t.detail), with: .color(.white), lineWidth: 1.2)
                context.draw(Text("+\(count)").font(.system(size: 10 * t.detail, weight: .black)).foregroundStyle(.white),
                             at: CGPoint(x: plate.minX + 11 * t.detail, y: p.y))
                context.fill(UnitShape(type: unit).path(in: CGRect(x: plate.maxX - 15 * t.detail, y: plate.minY + 2.5 * t.detail,
                                                                     width: 11 * t.detail, height: 11 * t.detail)),
                             with: .color(.white))
                context.opacity = 1
            case let .gain(id, gain):
                // "+1 person", "+6 gold": a little plaque that rises from the land and fades.
                guard age >= 0, age < 2.2, let c = token(id, t) else { continue }
                let k = age / 2.2
                let size = min(t.detail, 1.45)
                let (icon, text): (Text, String) = switch gain {
                case let .people(n): (Text(Image(systemName: "person.fill")).foregroundStyle(Self.cream), "+\(n)")
                case let .gold(n): (Self.icon(.gold), "+\(n)")
                case let .grain(n): (Self.icon(.grain), "+\(n)")
                case let .prestige(n): (Text(Image(systemName: "crown.fill")).foregroundStyle(Self.bronze), "+\(n)")
                case let .built(kind): (Text(Image(systemName: CommandBar.projectSymbol(kind))).foregroundStyle(Self.bronze), projectName(kind))
                }
                let label = context.resolve((icon + Text(" \(text)"))
                    .font(.system(size: 11 * size, weight: .heavy, design: .rounded)).foregroundStyle(Self.cream))
                let m = label.measure(in: CGSize(width: 300, height: 60))
                // Pops up quickly, then drifts and fades.
                let pop = min(1, age / 0.18)
                // Several gains at one place fan out side by side: centre, left, right, ...
                let slot = (0..<i).filter { j in
                    guard j < markTimes.count, case let .gain(other, _) = marks[j], other == id else { return false }
                    return abs(markTimes[j].timeIntervalSince(markTimes[i])) < 2.5
                }.count
                let side = CGFloat((slot + 1) / 2) * (slot % 2 == 1 ? -1 : 1)
                let p = CGPoint(x: c.x + side * (m.width + 18 * size), y: c.y - (16 + 30 * k) * t.detail)
                let plate = CGRect(x: p.x - m.width / 2 - 6 * size, y: p.y - m.height / 2 - 2 * size,
                                   width: m.width + 12 * size, height: m.height + 4 * size)
                var layer = context
                layer.opacity = (1 - k * k) * pop
                layer.translateBy(x: p.x, y: p.y)
                layer.scaleBy(x: 0.6 + 0.4 * pop, y: 0.6 + 0.4 * pop)
                layer.translateBy(x: -p.x, y: -p.y)
                let shape = Path(roundedRect: plate, cornerRadius: plate.height / 2)
                layer.fill(shape, with: .color(Self.wood.opacity(0.95)))
                layer.stroke(shape, with: .color(Self.bronze), lineWidth: 1.2 * size)
                layer.draw(label, at: p)
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

    /// An army on the move: a trail growing behind a token sliding along the path.
    private func marching(_ context: inout GraphicsContext, from a: CGPoint, to b: CGPoint, progress: Double,
                          color: Color, units: Int, _ t: BoardTransform) {
        let eased = progress < 0.5 ? 2 * progress * progress : 1 - pow(-2 * progress + 2, 2) / 2
        let dx = b.x - a.x, dy = b.y - a.y
        let len = max(1, hypot(dx, dy))
        let bend = CGPoint(x: (a.x + b.x) / 2 - dy / len * len * 0.15, y: (a.y + b.y) / 2 + dx / len * len * 0.15)
        func at(_ u: Double) -> CGPoint {
            let v = 1 - u
            return CGPoint(x: v * v * a.x + 2 * v * u * bend.x + u * u * b.x, y: v * v * a.y + 2 * v * u * bend.y + u * u * b.y)
        }
        var trail = Path()
        trail.move(to: a)
        for step in 1...20 { trail.addLine(to: at(eased * Double(step) / 20)) }
        context.stroke(trail, with: .color(color.opacity(0.8)), style: StrokeStyle(lineWidth: 3 * t.detail, lineCap: .round, dash: [5, 4]))
        // The army's own token, bobbing as it marches.
        var p = at(eased)
        p.y -= abs(sin(eased * .pi * 3)) * 3 * t.detail
        Self.drawCube(&context, at: p, half: 9 * t.detail, color: color, label: "\(units)", labelColor: .white, scale: t.detail)
    }

    /// An army arriving: a ring in its colour spreads from where it lands.
    private func arrival(_ context: inout GraphicsContext, at b: CGPoint, age: Double, color: Color, _ t: BoardTransform) {
        guard age >= 0, age < 0.45 else { return }
        let k = age / 0.45
        let r = (10 + 14 * k) * t.detail
        context.stroke(Path(ellipseIn: CGRect(x: b.x - r, y: b.y - r, width: 2 * r, height: 2 * r)),
                       with: .color(color.opacity(1 - k)), lineWidth: 3 * (1 - k) * t.detail + 0.5)
    }

    /// A curved arrow between two points, stopping short of the token, with an optional label.
    private func arrow(_ context: inout GraphicsContext, from a: CGPoint, to b: CGPoint, color: Color, label: String?,
                       _ t: BoardTransform, width: CGFloat = 3.2) {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = max(1, hypot(dx, dy))
        let inset = 11 * t.detail
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
            let extra = engine.haul(of: civ, to: territory, in: state)?.extraGrain ?? 0
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
            context.stroke(path, with: .color(.black.opacity(0.6)),
                           style: StrokeStyle(lineWidth: 5.5 * t.detail, lineCap: .round, lineJoin: .round))
            context.stroke(path, with: .color(.yellow),
                           style: StrokeStyle(lineWidth: 3 * t.detail, lineCap: .round, lineJoin: .round,
                                              dash: [8 * t.detail, 4 * t.detail]))
        }
        // Army tokens, for labels to keep clear of.
        let tokens: [CGRect] = map.territories.compactMap { territory in
            guard let shape = art.territories[territory.id], (state.armies[territory.id]?.units.total ?? 0) > 0 else { return nil }
            let c = t.point(shape.token), r = 11 * t.detail
            return CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
        }
        var placed = tokens
        // The strait markers and their names, drawn last, also need room.
        for strait in map.chokepoints {
            guard let link = strait.gatesSeaLink, let a = art.seas[link[0]], let b = art.seas[link[1]] else { continue }
            let pa = t.point(a), pb = t.point(b), k = t.detail
            placed.append(CGRect(x: (pa.x + pb.x) / 2 - 40 * k, y: (pa.y + pb.y) / 2 - 9 * k, width: 80 * k, height: 32 * k))
        }
        // What each route carries, near its middle: each partner's color, then what it receives.
        for route in routes {
            let stops = route.path.compactMap { point($0, t) }
            guard !stops.isEmpty else { continue }
            let middle = stops[stops.count / 2]
            let flows = engine.goods(along: route, in: state)
            var lines: [Text] = []
            for to in [route.partners.a, route.partners.b] {
                let goods = Resource.allCases.filter { flows[to]?[$0] != nil }
                guard !goods.isEmpty else { continue }
                lines.append(goods.reduce(Text("▸").foregroundStyle(Palette.color(to, state))) { $0 + Text(" ") + Self.icon($1) })
            }
            guard !lines.isEmpty else { continue }
            let k = t.detail
            let resolved = lines.map { context.resolve($0.font(.system(size: 9.5 * k, weight: .bold))) }
            let width = (resolved.map { $0.measure(in: CGSize(width: 400, height: 40)).width }.max() ?? 0) + 8 * k
            let row = 12 * k
            let height = CGFloat(lines.count) * row + 4 * k
            // Keep the label on the board.
            let left = t.point([BoardArt.frame.minX, 0]).x, right = t.point([BoardArt.frame.maxX, 0]).x
            func spot(_ p: CGPoint) -> CGRect {
                let x = min(max(p.x, left + width / 2 + 2), right - width / 2 - 2)
                return CGRect(x: x - width / 2, y: p.y - height / 2, width: width, height: height)
            }
            // The stop nearest the middle whose label covers no army and no other label.
            var along: [CGPoint] = []
            for (i, p) in stops.enumerated() {
                along.append(p)
                if i + 1 < stops.count { along.append(CGPoint(x: (p.x + stops[i + 1].x) / 2, y: (p.y + stops[i + 1].y) / 2)) }
            }
            let centre = along.count / 2
            let order = along.indices.sorted { abs($0 - centre) < abs($1 - centre) }
            let nudges = [CGSize.zero, CGSize(width: 0, height: -height), CGSize(width: 0, height: height),
                          CGSize(width: -width * 0.6, height: 0), CGSize(width: width * 0.6, height: 0)]
            let candidates = order.flatMap { i in nudges.map { spot(CGPoint(x: along[i].x + $0.width, y: along[i].y + $0.height)) } }
            func covered(_ b: CGRect) -> CGFloat {
                placed.reduce(0) { sum, p in let o = p.intersection(b); return sum + (o.isNull ? 0 : o.width * o.height) }
            }
            let box = candidates.first { covered($0) == 0 } ?? candidates.min { covered($0) < covered($1) } ?? spot(middle)
            placed.append(box)
            let mid = CGPoint(x: box.midX, y: box.midY)
            context.fill(Path(roundedRect: box,
                              cornerRadius: 4 * k), with: .color(.white.opacity(0.9)))
            for (i, line) in resolved.enumerated() {
                context.draw(line, at: CGPoint(x: mid.x, y: mid.y - height / 2 + 2 * k + row / 2 + CGFloat(i) * row))
            }
        }
        let tolled = Set(routes.flatMap(\.chokepoints))
        for strait in map.chokepoints {
            guard let link = strait.gatesSeaLink, let a = art.seas[link[0]], let b = art.seas[link[1]] else { continue }
            let pa = t.point(a), pb = t.point(b)
            let c = CGPoint(x: (pa.x + pb.x) / 2, y: (pa.y + pb.y) / 2)
            let holder = engine.holder(of: strait, in: state)
            let d = 8 * t.detail
            let dot = Path(ellipseIn: CGRect(x: c.x - d, y: c.y - d, width: 2 * d, height: 2 * d))
            context.fill(dot, with: .color(holder.map { Palette.color($0, state) } ?? Color(white: 0.8)))
            context.stroke(dot, with: .color(tolled.contains(strait.id) ? .yellow : .black), lineWidth: 1.5)
            let name = context.resolve(Text(strait.name).font(.system(size: 9 * t.detail, weight: .bold)).foregroundStyle(.white))
            let size = name.measure(in: CGSize(width: 300, height: 40))
            let at = CGPoint(x: c.x, y: c.y + d + 3 * t.detail + size.height / 2)
            context.fill(Path(roundedRect: CGRect(x: at.x - size.width / 2 - 4, y: at.y - size.height / 2 - 1,
                                                  width: size.width + 8, height: size.height + 2), cornerRadius: size.height / 2),
                         with: .color(.black.opacity(0.55)))
            context.draw(name, at: at)
        }
    }

    /// A resource as an inline icon, drawn in one style and tinted by what it is, readable on
    /// parchment and on dark wood alike.
    static func icon(_ r: Resource) -> Text {
        Text(r.symbolIsSystem ? Image(systemName: r.symbol) : Image(r.symbol)).foregroundStyle(tint(r))
    }

    static func tint(_ r: Resource) -> Color {
        switch r {
        case .grain: Color(red: 0.88, green: 0.68, blue: 0.2)
        case .copper: Color(red: 0.86, green: 0.48, blue: 0.2)
        case .tin: Color(red: 0.62, green: 0.68, blue: 0.75)
        case .iron: Color(red: 0.6, green: 0.5, blue: 0.5)
        case .horses: Color(red: 0.75, green: 0.52, blue: 0.3)
        case .timber: Color(red: 0.72, green: 0.5, blue: 0.27)
        case .gold: Color(red: 0.98, green: 0.78, blue: 0.2)
        case .wine: Color(red: 0.78, green: 0.25, blue: 0.4)
        case .luxuries: Color(red: 0.35, green: 0.75, blue: 0.9)
        case .stone: Color(red: 0.64, green: 0.64, blue: 0.62)
        }
    }

    static let bronze = Color(red: 0.84, green: 0.63, blue: 0.27)
    static let wood = Color(red: 0.17, green: 0.11, blue: 0.07)
    static let cream = Color(red: 0.98, green: 0.93, blue: 0.82)

    /// One wood-and-bronze plaque per territory, pinned under its army token: people, then
    /// (zoomed in, on the resources layer, or when selected) grain, resources and every
    /// building, and the army's make-up. Zoomed out it shows people and the works that matter
    /// most: roads, walls and harbors.
    fileprivate func drawPlaque(_ context: inout GraphicsContext, _ territory: Territory, at c: CGPoint, army: Army?,
                                _ t: BoardTransform, emphasized: Bool, hidden: Bool = false) {
        let id = territory.id
        // Beyond sight only the land's resources are known (on the resources layer).
        if hidden && layer != .resources { return }
        // Plaques grow with the zoom only so far, so close up they don't bury the land.
        let k = min(t.detail, 1.45) * (emphasized ? 1.2 : 1)
        let detailed = t.detail >= 1.3 || layer == .resources || emphasized
        let land = state.land[id]
        var items: [Text] = []
        let people = state.population(of: id)
        if people > 0, layer != .resources {
            items.append(Text(Image(systemName: "person.fill")).foregroundStyle(Self.cream.opacity(0.75)) + Text("\(people)"))
        }
        if detailed {
            let grain = engine?.territoryYield(.grain, id, state) ?? territory.grain
            items.append(Self.icon(.grain) + Text("\(grain)"))
            for r in ResourcesView.order {
                if let n = territory.resources[r], n > 0 { items.append(Self.icon(r) + Text("\(n)")) }
            }
        }
        let always: Set<ProjectKind> = [.road, .walls, .harbor]
        let built = hidden ? [] : ProjectKind.allCases.filter { (land?.improvements.contains($0) ?? false) && (detailed || always.contains($0)) }
        var works = built.map { Text(Image(systemName: CommandBar.projectSymbol($0))) }
        if detailed, land?.construction != nil { works.append(Text(Image(systemName: "hammer.fill")).foregroundStyle(.orange)) }
        if !works.isEmpty { items.append(works.dropFirst().reduce(works[0]) { $0 + Text(" ") + $1 }.foregroundStyle(Self.bronze)) }
        let units = t.detail >= 1.5 || emphasized ? army?.units : nil
        let types = UnitType.allCases.filter { (units?[$0] ?? 0) > 0 }
        guard !items.isEmpty || !types.isEmpty else { return }

        let line = items.isEmpty ? nil : context.resolve(
            items.dropFirst().reduce(items[0]) { $0 + Text("  ") + $1 }
                .font(.system(size: 9 * k, weight: .heavy, design: .rounded))
                .foregroundStyle(Self.cream))
        let lineSize = line?.measure(in: CGSize(width: 600, height: 80)) ?? .zero
        let step = 21 * k, unitRow: CGFloat = types.isEmpty ? 0 : 10 * k
        let stripe: CGFloat = 2.5 * k
        let pad: CGFloat = 2.5 * k
        let gap: CGFloat = line != nil && !types.isEmpty ? 2.5 * k : 0
        // Hung from the army token, which overlaps its top edge, or centred where there's none.
        let r: CGFloat = 10 * t.detail
        let tuck: CGFloat = army != nil ? 3 * k : 0
        let width = max(lineSize.width, CGFloat(types.count) * step) + 9 * k + stripe
        let height = tuck + pad + lineSize.height + gap + unitRow + pad
        let top = army != nil ? c.y + r - tuck : c.y - height / 2
        let rect = CGRect(x: c.x - width / 2, y: top, width: width, height: height)
        let plate = Path(roundedRect: rect, cornerRadius: 4 * k)
        context.fill(plate, with: .color(Self.wood.opacity(0.95)))
        if let owner = state.owner(of: id) {
            var inner = context
            inner.clip(to: plate)
            inner.fill(Path(CGRect(x: rect.minX, y: rect.minY, width: stripe, height: rect.height)), with: .color(Palette.color(owner, state)))
        }
        context.stroke(plate, with: .color(Self.bronze.opacity(emphasized ? 1 : 0.85)), lineWidth: (emphasized ? 1.6 : 0.9) * k)
        let midX = rect.midX + stripe / 2
        var y = rect.minY + tuck + pad
        if let line {
            context.draw(line, at: CGPoint(x: midX, y: y + lineSize.height / 2))
            y += lineSize.height + gap
        }
        // The army's make-up, as unit shapes with counts.
        let rowWidth = CGFloat(types.count) * step
        for (i, type) in types.enumerated() {
            let x = midX - rowWidth / 2 + CGFloat(i) * step
            let box = CGRect(x: x, y: y, width: 9 * k, height: 9 * k)
            context.fill(UnitShape(type: type).path(in: box), with: .color(Self.cream.opacity(0.85)))
            context.draw(Text("\(units![type])").font(.system(size: 9 * k, weight: .heavy, design: .rounded)).foregroundStyle(Self.cream),
                         at: CGPoint(x: box.maxX + 2 * k, y: box.midY), anchor: .leading)
        }
    }

    /// Sieges: a ring of tents round the town, a dashed line from the camp, and how long it has lasted.
    fileprivate func drawSieges(_ context: inout GraphicsContext, _ t: BoardTransform) {
        for (town, siege) in state.sieges.sorted(by: { $0.key < $1.key }) where seen(town) || seen(siege.camp) {
            guard let c = token(town, t), let camp = token(siege.camp, t) else { continue }
            let k = t.detail
            let color = Palette.color(siege.civ, state)
            var line = Path()
            line.move(to: camp)
            line.addLine(to: c)
            context.stroke(line, with: .color(.black.opacity(0.5)), style: StrokeStyle(lineWidth: 4 * k, lineCap: .round, dash: [5 * k, 4 * k]))
            context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 2.4 * k, lineCap: .round, dash: [5 * k, 4 * k]))
            // Tents round the walls.
            let r = 21 * k
            for i in 0..<8 {
                let a = Double(i) / 8 * 2 * .pi
                let p = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r * 0.8)
                var tent = Path()
                tent.move(to: CGPoint(x: p.x - 3.5 * k, y: p.y + 2.5 * k))
                tent.addLine(to: CGPoint(x: p.x, y: p.y - 3.5 * k))
                tent.addLine(to: CGPoint(x: p.x + 3.5 * k, y: p.y + 2.5 * k))
                tent.closeSubpath()
                context.fill(tent, with: .color(color))
                context.stroke(tent, with: .color(.black.opacity(0.7)), lineWidth: 0.7)
            }
            let label = context.resolve((Text(Image(systemName: "shield.lefthalf.filled.slash")) + Text(siege.rounds == 0 ? " Siege laid" : " Siege · round \(siege.rounds)"))
                .font(.system(size: 8.5 * min(k, 1.45), weight: .heavy, design: .rounded)).foregroundStyle(Self.cream))
            let size = label.measure(in: CGSize(width: 200, height: 40))
            let at = CGPoint(x: c.x, y: c.y - r - 9 * k)
            let plate = Path(roundedRect: CGRect(x: at.x - size.width / 2 - 5, y: at.y - size.height / 2 - 1,
                                                 width: size.width + 10, height: size.height + 2), cornerRadius: (size.height + 2) / 2)
            context.fill(plate, with: .color(Color(red: 0.5, green: 0.1, blue: 0.08)))
            context.stroke(plate, with: .color(Self.bronze), lineWidth: 1)
            context.draw(label, at: at)
        }
    }

    /// A great host beyond sight: rumour says it's there, not how strong.
    fileprivate func drawRumour(_ context: inout GraphicsContext, _ army: Army, at c: CGPoint, _ t: BoardTransform) {
        let r: CGFloat = 10 * t.detail
        let disc = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        context.fill(disc, with: .color(Palette.color(army.owner, state).opacity(0.55)))
        context.stroke(disc, with: .color(.white.opacity(0.8)), style: StrokeStyle(lineWidth: 1.4 * t.detail, dash: [3 * t.detail, 2 * t.detail]))
        context.draw(Text("?").font(.system(size: 13 * t.detail, weight: .black, design: .serif)).foregroundStyle(.white), at: c)
    }

    /// The army token: a disc in its owner's colour with a bronze rim, its size, a star for a
    /// general, and chevrons for veterans.
    fileprivate func drawArmy(_ context: inout GraphicsContext, _ army: Army, at c0: CGPoint, in id: TerritoryID,
                              _ t: BoardTransform, now: Date = .now) {
        let native = !state.isPlayer(army.owner)
        let led = state.generals.values.contains { $0.location == id }
        // The selected army rises off the board, glowing, with a marker bobbing above it.
        let chosen = selected == .territory(id) && army.owner == focus && focus != nil
        let phase = now.timeIntervalSinceReferenceDate
        let lift: CGFloat = chosen ? (5 + 1.5 * sin(phase * 4)) * t.detail : 0
        let c = CGPoint(x: c0.x, y: c0.y - lift)
        let a: CGFloat = (native ? 7 : 9) * t.detail
        if chosen {
            let pulse = 0.5 + 0.5 * sin(phase * 4)
            for k in 0..<2 {
                let r = (15 + 6 * CGFloat(k) + 3 * pulse) * t.detail
                context.stroke(Path(ellipseIn: CGRect(x: c0.x - r, y: c0.y + a * 0.6 - r * 0.45, width: 2 * r, height: r * 0.9)),
                               with: .color(Self.bronze.opacity(k == 0 ? 0.95 : 0.5 * (1 - pulse))), lineWidth: (k == 0 ? 3 : 2) * t.detail)
            }
        }
        Self.drawCube(&context, at: c, half: a, color: Palette.color(army.owner, state).opacity(native ? 0.85 : 1),
                      label: "\(army.units.total)\(led ? "★" : "")", labelColor: native ? Color.black.opacity(0.7) : .white,
                      lifted: lift, scale: t.detail)
        if chosen {
            // A bronze arrow bobbing over the cube.
            let y = c.y - a * 2.3 - 3 * sin(phase * 4) * t.detail
            var arrow = Path()
            arrow.move(to: CGPoint(x: c.x - 5 * t.detail, y: y - 5 * t.detail))
            arrow.addLine(to: CGPoint(x: c.x + 5 * t.detail, y: y - 5 * t.detail))
            arrow.addLine(to: CGPoint(x: c.x, y: y + 2 * t.detail))
            arrow.closeSubpath()
            context.fill(arrow, with: .color(Self.bronze))
            context.stroke(arrow, with: .color(.black.opacity(0.7)), lineWidth: 1)
        }
        let r = a * 1.3
        // Veterans wear chevrons above the token, one per rank.
        if let engine, engine.rank(of: army) > .green {
            let n = engine.rank(of: army).rawValue
            for i in 0..<n {
                var v = Path()
                let y = c.y - r - 2.5 * t.detail - CGFloat(i) * 2.6 * t.detail
                v.move(to: CGPoint(x: c.x - 4 * t.detail, y: y + 1.5 * t.detail))
                v.addLine(to: CGPoint(x: c.x, y: y - 1 * t.detail))
                v.addLine(to: CGPoint(x: c.x + 4 * t.detail, y: y + 1.5 * t.detail))
                context.stroke(v, with: .color(.black.opacity(0.6)), style: StrokeStyle(lineWidth: 2.6 * t.detail, lineCap: .round, lineJoin: .round))
                context.stroke(v, with: .color(Color(red: 0.98, green: 0.8, blue: 0.3)), style: StrokeStyle(lineWidth: 1.4 * t.detail, lineCap: .round, lineJoin: .round))
            }
        }
    }

    /// An army as a block from the board game: a cube in its owner's colour, seen from the front
    /// and a little above, with the troop count on its face and a shadow on the board.
    static func drawCube(_ context: inout GraphicsContext, at c: CGPoint, half a: CGFloat, color: Color,
                         label: String, labelColor: Color, lifted: CGFloat = 0, scale: CGFloat) {
        let d = a * 0.55  // depth offset of the top and side
        let front = CGRect(x: c.x - a - d / 2, y: c.y - a + d / 2, width: 2 * a, height: 2 * a)
        // Shadow on the board, further off as the cube lifts.
        let sh = 1 + lifted / max(1, a) * 0.4
        context.fill(Path(ellipseIn: CGRect(x: c.x - a * 1.3 * sh, y: front.maxY + lifted - a * 0.25, width: a * 2.6 * sh, height: a * 0.7)),
                     with: .color(.black.opacity(0.3 / sh)))
        var top = Path()
        top.move(to: CGPoint(x: front.minX, y: front.minY))
        top.addLine(to: CGPoint(x: front.minX + d, y: front.minY - d))
        top.addLine(to: CGPoint(x: front.maxX + d, y: front.minY - d))
        top.addLine(to: CGPoint(x: front.maxX, y: front.minY))
        top.closeSubpath()
        var side = Path()
        side.move(to: CGPoint(x: front.maxX, y: front.minY))
        side.addLine(to: CGPoint(x: front.maxX + d, y: front.minY - d))
        side.addLine(to: CGPoint(x: front.maxX + d, y: front.maxY - d))
        side.addLine(to: CGPoint(x: front.maxX, y: front.maxY))
        side.closeSubpath()
        let face = Path(front)
        context.fill(face, with: .color(color))
        context.fill(top, with: .color(color))
        context.fill(top, with: .color(.white.opacity(0.32)))
        context.fill(side, with: .color(color))
        context.fill(side, with: .color(.black.opacity(0.3)))
        // A soft sheen down the front face.
        context.fill(face, with: .linearGradient(Gradient(colors: [.white.opacity(0.18), .clear, .black.opacity(0.12)]),
                                                 startPoint: CGPoint(x: front.minX, y: front.minY), endPoint: CGPoint(x: front.maxX, y: front.maxY)))
        for p in [face, top, side] { context.stroke(p, with: .color(.black.opacity(0.75)), lineWidth: 0.9 * scale) }
        let fit: CGFloat = label.count >= 4 ? 0.6 : label.count == 3 ? 0.74 : 1
        context.draw(Text(label).font(.system(size: a * 1.25 * fit, weight: .heavy, design: .rounded)).foregroundStyle(labelColor),
                     at: CGPoint(x: front.midX, y: front.midY))
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

    static func projectGlyph(_ kind: ProjectKind) -> String {
        switch kind {
        case .road: "🛤"
        case .walls: "🧱"
        case .farm: "🌱"
        case .mine: "⛏"
        case .harbor: "⚓"
        case .granary: "🏺"
        case .levee: "🌊"
        case .drains: "⛲"
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
    var engine: Engine?
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
                    if let engine, engine.rank(of: army) > .green {
                        VeteranBadge(rank: engine.rank(of: army))
                    }
                }
                .font(.caption)
                if let engine, state.isPlayer(army.owner) {
                    let b = army.battles ?? 0
                    let next = engine.rules.veterans.rankAt.first { $0 > b }
                    Text("\(engine.rank(of: army).name): \(b) battle\(b == 1 ? "" : "s") survived"
                         + (next.map { " · \($0 - b) more to \(engine.rank(battles: $0).name.lowercased())" } ?? "")
                         + ". New recruits are green and dilute it.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Gold chevrons and the rank's name.
struct VeteranBadge: View {
    let rank: VeteranRank
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: rank == .elite ? "chevron.up.2" : "chevron.up")
            Text(rank.name)
        }
        .font(.caption2.bold())
        .foregroundStyle(Color(red: 0.6, green: 0.42, blue: 0.05))
        .padding(.horizontal, 5).padding(.vertical, 1)
        .background(Capsule().fill(Color(red: 0.98, green: 0.85, blue: 0.45).opacity(0.5)))
    }
}

extension Resource {
    /// The drawn icon: the game's own symbols where SF Symbols has nothing fitting.
    var symbol: String {
        switch self {
        case .grain: "wheat.ear"
        case .copper: "copper.ingot"
        case .tin: "tin.ingot"
        case .iron: "iron.bloom"
        case .horses: "figure.equestrian.sports"
        case .timber: "log.pile"
        case .gold: "coin.stamped"
        case .wine: "amphora"
        case .luxuries: "diamond.fill"
        case .stone: "stone.block"
        }
    }

    var symbolIsSystem: Bool { self == .horses || self == .luxuries }
}
