import HegemonCore
import SwiftUI

/// A territory up close, like the throne room: the town drawn from what's really there (houses
/// for its people, fields for its grain, walls, mine, harbor, road, the army camped outside),
/// beside what it brings in each turn and what can be built.
struct CityView: View {
    let session: GameSession
    let territory: TerritoryID
    let done: () -> Void

    private var engine: Engine { session.engine }
    private var state: GameState { session.state }
    private var civ: CivilizationID { session.human! }

    var body: some View {
        let report = engine.territoryReport(territory, for: civ, in: state)
        HStack(spacing: 0) {
            TownScene(session: session, territory: territory, report: report)
                .ignoresSafeArea()
            sidebar(report)
                .frame(width: 340)
                .background(Parchment())
        }
        .background(Color.black)
    }

    private func sidebar(_ r: TerritoryReport) -> some View {
        let t = engine.map.territory(territory)!
        let capital = engine.seat(of: civ, in: state) == territory
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text(t.name).font(.system(.title2, design: .serif).weight(.bold))
                    Text((capital ? "Your capital · " : "") + t.terrain.rawValue.capitalized
                         + (r.supplySteps.map { $0 == 0 ? "" : " · \($0) steps from the capital" } ?? " · cut off"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done", action: done).bold()
            }
            .padding([.horizontal, .top])
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ledger(r)
                    if !r.resources.isEmpty {
                        section("Yields") {
                            HStack(spacing: 12) {
                                ForEach(ResourcesView.order.filter { r.resources[$0] != nil }, id: \.self) { res in
                                    (MapView.icon(res) + Text(" \(r.resources[res]!)")).font(.callout.bold())
                                }
                            }
                            Text("Shared with your whole realm; trade partners get half of what you don't use.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    buildings
                    section("Great works") {
                        GreatWorksList(session: session, territory: territory)
                    }
                    if engine.restless(territory, of: civ, in: state) {
                        Label("Restless: newly taken or far from the capital, it pays no taxes and may revolt. Keep at least \(engine.rules.unrest.garrisonToCalm) soldier here to calm it.",
                              systemImage: "hand.raised.fill").font(.caption).foregroundStyle(.red)
                    } else if engine.needsGarrison(territory, of: civ, in: state) {
                        Label("Calm while its garrison stays: withdraw every soldier and it grows restless.",
                              systemImage: "shield.lefthalf.filled").font(.caption).foregroundStyle(.secondary)
                    }
                    if r.supplySteps == nil {
                        Label("Cut off from the capital: no taxes, no recruits, and its garrison wastes away.",
                              systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.red)
                    }
                }
                .padding()
            }
        }
    }

    private func ledger(_ r: TerritoryReport) -> some View {
        section("Each turn") {
            row(MapView.icon(.grain) + Text(" Grain grown"), "\(r.grain)")
            row("👥 People", "\(r.people) of \(r.peopleCap)")
            row(MapView.icon(.gold) + Text(" Taxes"), "+\(r.taxes)")
            if r.mines > 0 { row("⛏ Gold mines", "+\(r.mines)") }
            if r.wine > 0 { row("🍷 Wine sold", "+\(r.wine)") }
            if r.harbor > 0 { row("⚓ Harbor trade", "+\(r.harbor)") }
            Divider()
            row("Gold from here", "+\(r.gold)", bold: true)
            if r.fortification > 0 { row("🧱 Walls", "+\(r.fortification)% defence") }
        }
    }

    @ViewBuilder private var buildings: some View {
        let land = state.land[territory]!
        let cs = state.civs[civ]!
        let buildable = ProjectKind.allCases.filter { engine.canBuild($0, in: territory, state) }
        section("Buildings") {
            ForEach(ProjectKind.allCases.filter { land.improvements.contains($0) }, id: \.self) { kind in
                Label(kind == .walls ? "\(wallName(engine.wallLevel(at: territory, state))): +\(engine.fortification(at: territory, state))% defence"
                                     : "\(projectName(kind)): \(projectPurpose(kind))", systemImage: CommandBar.projectSymbol(kind))
                    .font(.callout)
            }
            if let site = land.construction {
                Label("\(projectName(site.kind)) under construction: \(site.turnsLeft) turn\(site.turnsLeft == 1 ? "" : "s") left",
                      systemImage: "hammer.fill").font(.callout).foregroundStyle(.orange)
            }
            if land.improvements.isEmpty && land.construction == nil {
                Text("Nothing built yet.").font(.caption).foregroundStyle(.secondary)
            }
            if land.construction == nil, session.isHumanTurn {
                ForEach(buildable, id: \.self) { kind in
                    let c = engine.projectCost(kind, for: civ, state, at: territory)
                    let ok = cs.gold >= c.gold && (cs.stock[.stone] ?? 0) >= c.stone && (cs.stock[.timber] ?? 0) >= c.timber
                    Button {
                        if session.order(.build(territory: territory, project: kind)) { SoundBoard.shared.play(.coins, volume: 0.6) }
                    } label: {
                        HStack {
                            Image(systemName: CommandBar.projectSymbol(kind)).frame(width: 22)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(engine.wallLevel(at: territory, state) > 0 && kind == .walls ? projectName(kind, at: territory, engine, state)
                                     : "Build \(projectName(kind, at: territory, engine, state).lowercased())").font(.callout.bold())
                                Text(projectPurpose(kind, at: territory, engine, state)).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            CommandBar.cost(gold: c.gold, stone: c.stone, timber: c.timber, turns: c.turns)
                                .font(.caption2.monospacedDigit()).foregroundStyle(ok ? .primary : Color.red)
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.55)))
                    }
                    .buttonStyle(.plain)
                    .opacity(ok ? 1 : 0.7)
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.system(.caption, design: .serif).weight(.bold)).tracking(2)
                .foregroundStyle(Color(red: 0.5, green: 0.33, blue: 0.12))
            content()
        }
    }

    private func row(_ name: String, _ value: String, bold: Bool = false) -> some View {
        row(Text(name), value, bold: bold)
    }

    private func row(_ name: Text, _ value: String, bold: Bool = false) -> some View {
        HStack {
            name
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(bold ? .callout.bold() : .callout)
    }
}

/// The town itself, drawn from its numbers: one house per person, one field per grain, and each
/// building where it would stand.
/// The town painted from what's really there: houses for its people in the realm's own style, the
/// palace or temple at its heart, fields for its grain, the river, harbour and ships, the mine,
/// walls, granary, any great work, building sites, and the army camped outside. Ships bob, the
/// flag stirs and smoke rises.
struct TownScene: View {
    let session: GameSession
    let territory: TerritoryID
    let report: TerritoryReport

    private var state: GameState { session.state }
    private var engine: Engine { session.engine }

    var body: some View {
        let t = engine.map.territory(territory)!
        let owner = state.owner(of: territory)
        TimelineView(.animation(minimumInterval: 1 / 20)) { tl in
            Canvas { ctx, size in
                TownPainter(t: t, land: Self.shown(state.land[territory]!), owner: owner, state: state, engine: engine,
                            report: report, territory: territory, time: tl.date.timeIntervalSinceReferenceDate)
                    .paint(&ctx, size)
            }
        }
        .overlay(alignment: .top) {
            Text(t.name.uppercased())
                .font(.system(.title, design: .serif).weight(.bold)).tracking(4)
                .foregroundStyle(.white).shadow(color: .black.opacity(0.6), radius: 4)
                .padding(.horizontal, 16).padding(.vertical, 6)
                .background(BannerRibbon().fill(Palette.color(owner, state).opacity(0.9))
                    .overlay(BannerRibbon().stroke(Bronze.gradient, lineWidth: 2)))
                .padding(.top, 18)
        }
        .clipped()
    }
}

extension TownScene {
    /// The land as painted (debug: -demoTown full paints every building and a site; -demoWalls
    /// paints walls of a given height).
    static func shown(_ land: TerritoryState) -> TerritoryState {
        #if DEBUG
        // -demoWalls 1|2|3 paints walls of that height.
        let walls = UserDefaults.standard.integer(forKey: "demoWalls")
        if walls > 0 {
            var l = land
            l.improvements.insert(.walls)
            l.wallLevel = walls
            return l
        }
        if UserDefaults.standard.string(forKey: "demoTown") == "full" {
            var l = land
            l.improvements.formUnion([.walls, .road, .farm, .granary, .harbor, .mine, .levee, .drains])
            l.construction = Construction(kind: .walls, turnsLeft: 2)
            return l
        }
        #endif
        return land
    }
}

/// Paints the town in a 1000 × 600 frame, scaled to fill the view.
private struct TownPainter {
    let t: Territory
    let land: TerritoryState
    let owner: CivilizationID?
    let state: GameState
    let engine: Engine
    let report: TerritoryReport
    let territory: TerritoryID
    let time: Double

    private var style: String {
        switch owner {
        case "egypt"?: "egypt"
        case "mesopotamia"?: "meso"
        case "greece"?, "italia"?: "med"
        default: t.terrain == .desert ? "meso" : "med"
        }
    }
    private var color: Color { Palette.color(owner, state) }
    private var capital: Bool { owner.flatMap { engine.seat(of: $0, in: state) } == territory }
    private var coastal: Bool { !t.seas.isEmpty }
    private let ink = Color.black.opacity(0.55)

    /// A steady pseudo-random number in 0..<1 for slot `i`, the same every frame.
    private func r(_ i: Int) -> Double {
        var h: UInt64 = 1469598103934665603
        for b in "\(territory)#\(i)".utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return Double(h % 10_000) / 10_000
    }

    func paint(_ ctx: inout GraphicsContext, _ size: CGSize) {
        // Fit the scene's height, centred on the town; sky, land and sea run on past the sides.
        let scale = size.height / 600 * 0.9
        ctx.translateBy(x: size.width / 2 - 470 * scale, y: size.height - 600 * scale)
        ctx.scaleBy(x: scale, y: scale)
        sky(&ctx)
        distance(&ctx)
        ground(&ctx)
        if t.has(.riverValley) { river(&ctx) }
        if coastal { sea(&ctx) }
        if land.improvements.contains(.mine) || t.terrain == .hills || t.terrain == .mountains { mine(&ctx) }
        fields(&ctx)
        produce(&ctx)
        if land.improvements.contains(.road) { road(&ctx) }
        greatWork(&ctx)
        town(&ctx)
        if land.improvements.contains(.walls) { walls(&ctx) }
        if land.improvements.contains(.granary) { granary(&ctx) }
        if land.improvements.contains(.drains) { well(&ctx) }
        if land.construction != nil { scaffold(&ctx) }
        camp(&ctx)
        trees(&ctx)
    }

    // MARK: Landscape

    private func sky(_ ctx: inout GraphicsContext) {
        ctx.fill(Path(CGRect(x: -600, y: -200, width: 2200, height: 460)),
                 with: .linearGradient(Gradient(colors: [Color(red: 0.42, green: 0.62, blue: 0.86), Color(red: 0.98, green: 0.86, blue: 0.66)]),
                                       startPoint: CGPoint(x: 0, y: -100), endPoint: CGPoint(x: 0, y: 260)))
        ctx.fill(Path(ellipseIn: CGRect(x: 790, y: 50, width: 70, height: 70)),
                 with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.95, blue: 0.7), Color(red: 1, green: 0.8, blue: 0.4).opacity(0)]),
                                       center: CGPoint(x: 825, y: 85), startRadius: 20, endRadius: 70))
        ctx.fill(Path(ellipseIn: CGRect(x: 805, y: 70, width: 40, height: 40)), with: .color(Color(red: 1, green: 0.93, blue: 0.7)))
        // Drifting clouds.
        for k in 0..<3 {
            let x = (Double(k) * 330 + time * (6 + Double(k) * 2)).truncatingRemainder(dividingBy: 1200) - 150
            let y = 50 + Double(k) * 32
            for (dx, dy, w) in [(0.0, 0.0, 90.0), (40, -14, 70), (75, 2, 80)] {
                ctx.fill(Path(ellipseIn: CGRect(x: x + dx, y: y + dy, width: w, height: 30)), with: .color(.white.opacity(0.75)))
            }
        }
    }

    /// Far hills (or dunes, or mountains) along the horizon.
    private func distance(_ ctx: inout GraphicsContext) {
        let far = t.terrain == .desert ? Color(red: 0.86, green: 0.72, blue: 0.48) : Color(red: 0.5, green: 0.6, blue: 0.62)
        var hills = Path()
        hills.move(to: CGPoint(x: -600, y: 260))
        hills.addQuadCurve(to: CGPoint(x: 0, y: 252), control: CGPoint(x: -300, y: 200))
        let peaks = t.terrain == .mountains ? 7 : 5
        for k in 0...peaks {
            let x = Double(k) / Double(peaks) * 1000
            let height = t.terrain == .mountains ? 90 + r(k) * 70 : t.terrain == .desert ? 20 + r(k) * 18 : 40 + r(k) * 40
            hills.addQuadCurve(to: CGPoint(x: x, y: 260 - height * 0.2), control: CGPoint(x: x - 500 / Double(peaks), y: 260 - height))
        }
        hills.addQuadCurve(to: CGPoint(x: 1600, y: 252), control: CGPoint(x: 1300, y: 200))
        hills.addLine(to: CGPoint(x: 1600, y: 260))
        hills.closeSubpath()
        ctx.fill(hills, with: .color(far.opacity(0.85)))
        if t.terrain == .mountains {
            for k in 0..<4 {
                let x = 120 + Double(k) * 230 + r(k + 20) * 60
                var snow = Path()
                snow.move(to: CGPoint(x: x - 22, y: 196))
                snow.addLine(to: CGPoint(x: x, y: 172))
                snow.addLine(to: CGPoint(x: x + 22, y: 196))
                ctx.fill(snow, with: .color(.white.opacity(0.8)))
            }
        }
    }

    private func ground(_ ctx: inout GraphicsContext) {
        let top = BattleBoard.ground(t.terrain, row: 0, col: 0), bottom = BattleBoard.ground(t.terrain, row: 0, col: 1)
        ctx.fill(Path(CGRect(x: -600, y: 250, width: 2200, height: 350)),
                 with: .linearGradient(Gradient(colors: [top.opacity(0.9), bottom]), startPoint: CGPoint(x: 0, y: 250), endPoint: CGPoint(x: 0, y: 600)))
        // Grass tufts or sand ripples.
        for k in 0..<40 {
            let x = r(k + 100) * 1000, y = 270 + r(k + 200) * 320
            var tuft = Path()
            tuft.move(to: CGPoint(x: x - 5, y: y)); tuft.addLine(to: CGPoint(x: x, y: y - 6)); tuft.addLine(to: CGPoint(x: x + 5, y: y))
            ctx.stroke(tuft, with: .color(.black.opacity(0.1)), lineWidth: 1.5)
        }
    }

    private func river(_ ctx: inout GraphicsContext) {
        var water = Path()
        water.move(to: CGPoint(x: 600, y: 250))
        water.addCurve(to: CGPoint(x: 560, y: 600), control1: CGPoint(x: 760, y: 360), control2: CGPoint(x: 420, y: 480))
        ctx.stroke(water, with: .color(Color(red: 0.45, green: 0.38, blue: 0.22).opacity(0.5)), style: StrokeStyle(lineWidth: 64, lineCap: .round))
        ctx.stroke(water, with: .color(Color(red: 0.26, green: 0.52, blue: 0.78)), style: StrokeStyle(lineWidth: 50, lineCap: .round))
        if land.improvements.contains(.levee) {
            // Earthen banks along both sides.
            for offset in [-30.0, 30] {
                var bank = Path()
                bank.move(to: CGPoint(x: 600 + offset, y: 250))
                bank.addCurve(to: CGPoint(x: 560 + offset, y: 600), control1: CGPoint(x: 760 + offset, y: 360), control2: CGPoint(x: 420 + offset, y: 480))
                ctx.stroke(bank, with: .color(Color(red: 0.55, green: 0.42, blue: 0.26)), style: StrokeStyle(lineWidth: 9, lineCap: .round))
                ctx.stroke(bank, with: .color(Color(red: 0.45, green: 0.6, blue: 0.3)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        }
        // Glints drifting downstream.
        let shift = time * 30
        ctx.stroke(water, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [8, 34], dashPhase: -shift))
        // Reeds along the banks.
        for k in 0..<10 {
            let x = 610 + r(k + 300) * 120 - 60, y = 300 + Double(k) * 28
            for d in [-3.0, 0, 3] {
                var reed = Path()
                reed.move(to: CGPoint(x: x + d, y: y)); reed.addLine(to: CGPoint(x: x + d * 2, y: y - 16))
                ctx.stroke(reed, with: .color(Color(red: 0.3, green: 0.45, blue: 0.2)), lineWidth: 2)
            }
        }
    }

    private func sea(_ ctx: inout GraphicsContext) {
        var shore = Path()
        shore.move(to: CGPoint(x: 1600, y: 250))
        shore.addLine(to: CGPoint(x: 800, y: 250))
        shore.addCurve(to: CGPoint(x: 760, y: 600), control1: CGPoint(x: 740, y: 360), control2: CGPoint(x: 820, y: 470))
        shore.addLine(to: CGPoint(x: 1600, y: 600))
        shore.closeSubpath()
        ctx.fill(shore, with: .linearGradient(Gradient(colors: [Color(red: 0.3, green: 0.55, blue: 0.82), Color(red: 0.12, green: 0.32, blue: 0.6)]),
                                              startPoint: CGPoint(x: 0, y: 250), endPoint: CGPoint(x: 0, y: 600)))
        ctx.stroke(shore, with: .color(Color(red: 0.95, green: 0.88, blue: 0.68)), lineWidth: 8)
        for k in 0..<14 {
            let x = 820 + r(k + 400) * 170 + sin(time + Double(k)) * 4, y = 280 + r(k + 450) * 300
            var wave = Path()
            wave.move(to: CGPoint(x: x - 10, y: y)); wave.addQuadCurve(to: CGPoint(x: x + 10, y: y), control: CGPoint(x: x, y: y - 6))
            ctx.stroke(wave, with: .color(.white.opacity(0.4)), lineWidth: 1.5)
        }
        if land.improvements.contains(.harbor) {
            // A stone quay and a wooden pier.
            ctx.fill(Path(CGRect(x: 790, y: 400, width: 120, height: 14)), with: .color(Color(red: 0.6, green: 0.56, blue: 0.5)))
            for x in stride(from: 800.0, through: 900, by: 20) {
                ctx.fill(Path(CGRect(x: x, y: 414, width: 5, height: 18)), with: .color(Color(red: 0.4, green: 0.27, blue: 0.14)))
            }
        }
        let ships = t.seas.compactMap { state.fleet(of: owner ?? "", in: $0)?.ships }.reduce(0, +)
        for k in 0..<min(ships, 5) {
            ship(&ctx, at: CGPoint(x: 850 + Double(k % 3) * 50, y: 360 + Double(k / 3) * 80 + Double(k % 2) * 18), phase: Double(k))
        }
    }

    private func ship(_ ctx: inout GraphicsContext, at p: CGPoint, phase: Double) {
        let bob = sin(time * 1.8 + phase) * 3
        var c = ctx
        c.translateBy(x: p.x, y: p.y + bob)
        c.rotate(by: .degrees(sin(time * 1.4 + phase) * 3))
        var hull = Path()
        hull.move(to: CGPoint(x: -26, y: 0)); hull.addLine(to: CGPoint(x: 26, y: 0))
        hull.addQuadCurve(to: CGPoint(x: -26, y: 0), control: CGPoint(x: 0, y: 18))
        c.fill(hull, with: .color(Color(red: 0.42, green: 0.27, blue: 0.13)))
        c.stroke(hull, with: .color(ink), lineWidth: 1)
        c.fill(Path(CGRect(x: -1.5, y: -36, width: 3, height: 36)), with: .color(Color(red: 0.35, green: 0.22, blue: 0.1)))
        var sail = Path()
        sail.move(to: CGPoint(x: -16, y: -32)); sail.addLine(to: CGPoint(x: 16, y: -32))
        sail.addQuadCurve(to: CGPoint(x: 16, y: -8), control: CGPoint(x: 22, y: -20))
        sail.addLine(to: CGPoint(x: -16, y: -8))
        sail.addQuadCurve(to: CGPoint(x: -16, y: -32), control: CGPoint(x: -10, y: -20))
        c.fill(sail, with: .color(color.opacity(0.9)))
        c.stroke(sail, with: .color(ink), lineWidth: 1)
    }

    private func mine(_ ctx: inout GraphicsContext) {
        var hill = Path()
        hill.move(to: CGPoint(x: 20, y: 330))
        hill.addQuadCurve(to: CGPoint(x: 300, y: 330), control: CGPoint(x: 150, y: 170))
        hill.closeSubpath()
        ctx.fill(hill, with: .linearGradient(Gradient(colors: [Color(red: 0.55, green: 0.5, blue: 0.42), Color(red: 0.42, green: 0.38, blue: 0.32)]),
                                             startPoint: CGPoint(x: 150, y: 220), endPoint: CGPoint(x: 150, y: 330)))
        guard land.improvements.contains(.mine) else { return }
        var mouth = Path()
        mouth.move(to: CGPoint(x: 130, y: 320)); mouth.addLine(to: CGPoint(x: 130, y: 296))
        mouth.addQuadCurve(to: CGPoint(x: 170, y: 296), control: CGPoint(x: 150, y: 278)); mouth.addLine(to: CGPoint(x: 170, y: 320))
        ctx.fill(mouth, with: .color(Color(red: 0.12, green: 0.1, blue: 0.08)))
        ctx.stroke(mouth, with: .color(Color(red: 0.45, green: 0.3, blue: 0.15)), lineWidth: 5)
        ctx.fill(Path(ellipseIn: CGRect(x: 175, y: 314, width: 50, height: 16)), with: .color(Color(red: 0.4, green: 0.36, blue: 0.3)))
        // A cart of ore.
        ctx.fill(Path(CGRect(x: 92, y: 312, width: 28, height: 12)), with: .color(Color(red: 0.45, green: 0.3, blue: 0.15)))
        for x in [96.0, 112] { ctx.fill(Path(ellipseIn: CGRect(x: x, y: 320, width: 8, height: 8)), with: .color(.black.opacity(0.7))) }
    }

    /// Fields in the foreground, one strip per grain; channels if irrigated.
    private func fields(_ ctx: inout GraphicsContext) {
        let n = min(report.grain, 14)
        for i in 0..<n {
            let col = Double(i % 7), row = Double(i / 7)
            let x0 = 20 + col * 72 + row * 18, y0 = 470 + row * 62
            var plot = Path()
            plot.move(to: CGPoint(x: x0, y: y0)); plot.addLine(to: CGPoint(x: x0 + 66, y: y0))
            plot.addLine(to: CGPoint(x: x0 + 76, y: y0 + 54)); plot.addLine(to: CGPoint(x: x0 + 8, y: y0 + 54)); plot.closeSubpath()
            let ripe = (i + Int(row)) % 2 == 0
            ctx.fill(plot, with: .color(ripe ? Color(red: 0.86, green: 0.74, blue: 0.34) : Color(red: 0.52, green: 0.68, blue: 0.3)))
            ctx.drawLayer { l in
                l.clip(to: plot)
                for k in 0..<7 {
                    var furrow = Path()
                    furrow.move(to: CGPoint(x: x0 + Double(k) * 11, y: y0)); furrow.addLine(to: CGPoint(x: x0 + 8 + Double(k) * 11, y: y0 + 54))
                    l.stroke(furrow, with: .color(.black.opacity(0.12)), lineWidth: 2)
                }
            }
            ctx.stroke(plot, with: .color(.black.opacity(0.2)), lineWidth: 1)
        }
        if land.improvements.contains(.farm), n > 0 {
            var channel = Path()
            channel.move(to: CGPoint(x: 10, y: 466)); channel.addLine(to: CGPoint(x: 540, y: 466))
            ctx.stroke(channel, with: .color(Color(red: 0.3, green: 0.55, blue: 0.82)), lineWidth: 5)
            // A shaduf at the channel.
            var pole = Path()
            pole.move(to: CGPoint(x: 548, y: 470)); pole.addLine(to: CGPoint(x: 548, y: 420))
            pole.move(to: CGPoint(x: 520, y: 412)); pole.addLine(to: CGPoint(x: 580, y: 432))
            ctx.stroke(pole, with: .color(Color(red: 0.4, green: 0.27, blue: 0.14)), lineWidth: 3)
        }
    }

    /// What the land yields, in the foreground: vines, horses, timber, a quarry, a market.
    private func produce(_ ctx: inout GraphicsContext) {
        var slot = 0
        func next() -> CGPoint {
            defer { slot += 1 }
            return CGPoint(x: 620 + Double(slot % 2) * 120, y: 500 + Double(slot / 2) * 70)
        }
        if (t.resources[.wine] ?? 0) > 0 {
            let p = next()
            for row in 0..<4 {
                for k in 0..<6 {
                    let x = p.x - 50 + Double(k) * 18 + Double(row) * 4, y = p.y - 20 + Double(row) * 14
                    ctx.fill(Path(CGRect(x: x, y: y - 10, width: 2, height: 10)), with: .color(Color(red: 0.4, green: 0.27, blue: 0.14)))
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 5, y: y - 14, width: 12, height: 8)), with: .color(Color(red: 0.3, green: 0.5, blue: 0.2)))
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 1, y: y - 9, width: 4, height: 4)), with: .color(Color(red: 0.45, green: 0.12, blue: 0.35)))
                }
            }
        }
        if (t.resources[.horses] ?? 0) > 0 {
            let p = next()
            for k in 0..<3 {
                let x = p.x - 40 + Double(k) * 34, y = p.y + Double(k % 2) * 10
                let graze = sin(time * 0.8 + Double(k)) * 2
                let coat = [Color(red: 0.45, green: 0.28, blue: 0.15), Color(red: 0.2, green: 0.15, blue: 0.1), Color(red: 0.75, green: 0.68, blue: 0.6)][k]
                ctx.fill(Path(ellipseIn: CGRect(x: x - 14, y: y - 18, width: 28, height: 12)), with: .color(coat))
                var neck = Path()
                neck.move(to: CGPoint(x: x + 10, y: y - 14)); neck.addLine(to: CGPoint(x: x + 18, y: y - 4 + graze))
                ctx.stroke(neck, with: .color(coat), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                for lx in [-9.0, -4, 5, 10] { ctx.fill(Path(CGRect(x: x + lx, y: y - 8, width: 2.5, height: 10)), with: .color(coat)) }
            }
        }
        if (t.resources[.timber] ?? 0) > 0 {
            let p = next()
            for (k, row) in [(0, 3), (1, 2), (2, 1)] {
                for i in 0..<row {
                    let c = CGPoint(x: p.x - 20 + Double(i) * 16 + Double(k) * 8, y: p.y - Double(k) * 13)
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - 8, y: c.y - 8, width: 16, height: 16)), with: .color(Color(red: 0.62, green: 0.44, blue: 0.24)))
                    ctx.stroke(Path(ellipseIn: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)), with: .color(.black.opacity(0.25)), lineWidth: 1)
                }
            }
        }
        if (t.resources[.stone] ?? 0) > 0 {
            let p = next()
            for (dx, dy, w) in [(-30.0, 0.0, 26.0), (-2, 4, 22), (22, -2, 28), (-16, -16, 24), (8, -18, 20)] {
                let b = Path(CGRect(x: p.x + dx, y: p.y + dy - 14, width: w, height: 14))
                ctx.fill(b, with: .color(Color(white: 0.78)))
                ctx.stroke(b, with: .color(ink), lineWidth: 0.8)
            }
        }
        if (t.resources[.luxuries] ?? 0) > 0 {
            let p = next()
            ctx.fill(Path(CGRect(x: p.x - 26, y: p.y - 26, width: 52, height: 26)), with: .color(Color(red: 0.6, green: 0.42, blue: 0.22)))
            var awning = Path()
            awning.move(to: CGPoint(x: p.x - 32, y: p.y - 26)); awning.addLine(to: CGPoint(x: p.x - 22, y: p.y - 40))
            awning.addLine(to: CGPoint(x: p.x + 22, y: p.y - 40)); awning.addLine(to: CGPoint(x: p.x + 32, y: p.y - 26)); awning.closeSubpath()
            ctx.fill(awning, with: .color(color.opacity(0.85)))
            for (k, c) in [Color.orange, .purple, .yellow].enumerated() {
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 18 + Double(k) * 14, y: p.y - 20, width: 10, height: 8)), with: .color(c))
            }
        }
    }

    private func road(_ ctx: inout GraphicsContext) {
        var road = Path()
        road.move(to: CGPoint(x: 0, y: 440))
        road.addQuadCurve(to: CGPoint(x: 400, y: 380), control: CGPoint(x: 200, y: 450))
        ctx.stroke(road, with: .color(Color(red: 0.55, green: 0.47, blue: 0.36)), style: StrokeStyle(lineWidth: 30, lineCap: .round))
        ctx.stroke(road, with: .color(Color(red: 0.8, green: 0.72, blue: 0.58)), style: StrokeStyle(lineWidth: 24, lineCap: .round))
        ctx.stroke(road, with: .color(.black.opacity(0.12)), style: StrokeStyle(lineWidth: 24, dash: [10, 6]))
    }

    private func trees(_ ctx: inout GraphicsContext) {
        let count = t.terrain == .forest ? 16 : t.terrain == .desert ? 2 : 9
        for k in 0..<count {
            let x = r(k + 500) * 260 + (k % 2 == 0 ? 0 : 640), y = 270 + r(k + 550) * 140
            if coastal && x > 760 { continue }
            let sway = sin(time * 1.2 + Double(k)) * 2
            ctx.fill(Path(CGRect(x: x - 3, y: y, width: 6, height: 18)), with: .color(Color(red: 0.4, green: 0.26, blue: 0.14)))
            if style == "egypt" || style == "meso" {
                // A date palm.
                for a in stride(from: -60.0, through: 60, by: 30) {
                    var frond = Path()
                    frond.move(to: CGPoint(x: x, y: y))
                    frond.addQuadCurve(to: CGPoint(x: x + a * 0.5 + sway, y: y + 6), control: CGPoint(x: x + a * 0.3, y: y - 14))
                    ctx.stroke(frond, with: .color(Color(red: 0.25, green: 0.48, blue: 0.22)), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                }
            } else {
                ctx.fill(Path(ellipseIn: CGRect(x: x - 16 + sway, y: y - 30, width: 32, height: 36)), with: .color(Color(red: 0.24, green: 0.45, blue: 0.22)))
                ctx.fill(Path(ellipseIn: CGRect(x: x - 10 + sway, y: y - 28, width: 14, height: 14)), with: .color(.white.opacity(0.1)))
            }
        }
    }

    // MARK: Town

    private func town(_ ctx: inout GraphicsContext) {
        // Houses, back rows first, around the centre.
        // A household of two homes to each person counted.
        let houses = min(report.people * 2, 22)
        var spots: [(Double, Double)] = []
        for i in 0..<houses {
            let ring = Double(i / 8) + 1, a = Double(i % 8) / 8 * .pi * 2 + r(i) * 0.5
            spots.append((470 + cos(a) * (90 + ring * 40), 360 + sin(a) * (28 + ring * 16)))
        }
        let behind = spots.filter { $0.1 < 352 }.sorted { $0.1 < $1.1 }
        let front = spots.filter { $0.1 >= 352 }.sorted { $0.1 < $1.1 }
        for (i, s) in behind.enumerated() { house(&ctx, at: CGPoint(x: s.0, y: s.1), seed: i) }
        centre(&ctx)
        for (i, s) in front.enumerated() { house(&ctx, at: CGPoint(x: s.0, y: s.1), seed: i + 40) }
    }

    private func house(_ ctx: inout GraphicsContext, at p: CGPoint, seed: Int) {
        let k = 0.75 + (p.y - 300) / 300  // nearer is larger
        let w = (38 + r(seed + 600) * 12) * k, h = (26 + r(seed + 650) * 10) * k
        let wall = style == "med" ? Color(red: 0.94, green: 0.91, blue: 0.84) : Color(red: 0.85, green: 0.72, blue: 0.52)
        let body = Path(CGRect(x: p.x - w / 2, y: p.y - h, width: w, height: h))
        ctx.fill(body, with: .color(wall))
        // A shaded side wall for depth.
        ctx.fill(Path(CGRect(x: p.x + w / 2 - w * 0.22, y: p.y - h, width: w * 0.22, height: h)), with: .color(.black.opacity(0.12)))
        ctx.stroke(body, with: .color(ink), lineWidth: 0.8)
        if style == "med" {
            var roof = Path()
            roof.move(to: CGPoint(x: p.x - w / 2 - 4, y: p.y - h)); roof.addLine(to: CGPoint(x: p.x, y: p.y - h - 14 * k))
            roof.addLine(to: CGPoint(x: p.x + w / 2 + 4, y: p.y - h)); roof.closeSubpath()
            ctx.fill(roof, with: .color(Color(red: 0.72, green: 0.32, blue: 0.2)))
            ctx.stroke(roof, with: .color(ink), lineWidth: 0.8)
        } else {
            // A flat roof with a parapet, and an awning in the realm's colour on some.
            ctx.fill(Path(CGRect(x: p.x - w / 2 - 2, y: p.y - h - 4 * k, width: w + 4, height: 4 * k)), with: .color(wall.opacity(0.8)))
            if seed % 3 == 0 {
                ctx.fill(Path(CGRect(x: p.x - w / 2, y: p.y - h - 10 * k, width: w * 0.5, height: 6 * k)), with: .color(color.opacity(0.75)))
            }
        }
        ctx.fill(Path(roundedRect: CGRect(x: p.x - 4 * k, y: p.y - 12 * k, width: 8 * k, height: 12 * k), cornerRadius: 2), with: .color(Color(red: 0.35, green: 0.22, blue: 0.12)))
        ctx.fill(Path(CGRect(x: p.x - w / 2 + 5 * k, y: p.y - h + 6 * k, width: 5 * k, height: 5 * k)), with: .color(.black.opacity(0.55)))
    }

    /// The heart of the town: the palace or temple of the capital, a hall elsewhere.
    private func centre(_ ctx: inout GraphicsContext) {
        let c = CGPoint(x: 470, y: 352)
        guard capital else {
            hall(&ctx, at: c, wide: 90, high: 46)
            return
        }
        switch style {
        case "egypt":
            // A temple pylon: two sloping towers and a gate, a flag on each pole.
            for side in [-1.0, 1] {
                var tower = Path()
                let x = c.x + side * 50
                tower.move(to: CGPoint(x: x - 40, y: c.y)); tower.addLine(to: CGPoint(x: x - 32, y: c.y - 110))
                tower.addLine(to: CGPoint(x: x + 32, y: c.y - 110)); tower.addLine(to: CGPoint(x: x + 40, y: c.y)); tower.closeSubpath()
                ctx.fill(tower, with: .linearGradient(Gradient(colors: [Color(red: 0.93, green: 0.84, blue: 0.62), Color(red: 0.8, green: 0.68, blue: 0.46)]),
                                                      startPoint: CGPoint(x: x, y: c.y - 110), endPoint: CGPoint(x: x, y: c.y)))
                ctx.stroke(tower, with: .color(ink), lineWidth: 1)
                for k in 0..<3 { ctx.fill(Path(CGRect(x: x - 20 + Double(k) * 14, y: c.y - 90, width: 8, height: 40)), with: .color(color.opacity(0.5))) }
                pennant(&ctx, at: CGPoint(x: x + side * 26, y: c.y - 110), height: 50)
            }
            ctx.fill(Path(CGRect(x: c.x - 18, y: c.y - 70, width: 36, height: 70)), with: .color(Color(red: 0.35, green: 0.24, blue: 0.14)))
            ctx.fill(Path(CGRect(x: c.x - 24, y: c.y - 78, width: 48, height: 8)), with: .color(Color(red: 0.9, green: 0.75, blue: 0.3)))
        case "meso":
            // A ziggurat with a shrine on top.
            for (k, w) in [180.0, 136, 92].enumerated() {
                let y = c.y - Double(k) * 34
                let tier = Path(CGRect(x: c.x - w / 2, y: y - 34, width: w, height: 34))
                ctx.fill(tier, with: .color(Color(red: 0.78, green: 0.62, blue: 0.42).opacity(1 - Double(k) * 0.08)))
                ctx.stroke(tier, with: .color(ink), lineWidth: 1)
                for x in stride(from: c.x - w / 2 + 8, to: c.x + w / 2, by: 14) {
                    ctx.fill(Path(CGRect(x: x, y: y - 28, width: 3, height: 22)), with: .color(.black.opacity(0.12)))
                }
            }
            ctx.fill(Path(CGRect(x: c.x - 22, y: c.y - 130, width: 44, height: 28)), with: .color(Color(red: 0.2, green: 0.36, blue: 0.7)))
            ctx.fill(Path(CGRect(x: c.x - 8, y: c.y - 102, width: 16, height: 102)), with: .color(Color(red: 0.7, green: 0.55, blue: 0.36)))
        default:
            // A columned temple on a stepped base, a pediment in the realm's colour.
            ctx.fill(Path(CGRect(x: c.x - 110, y: c.y - 14, width: 220, height: 14)), with: .color(Color(red: 0.85, green: 0.83, blue: 0.78)))
            ctx.fill(Path(CGRect(x: c.x - 100, y: c.y - 24, width: 200, height: 10)), with: .color(Color(red: 0.9, green: 0.88, blue: 0.83)))
            for k in 0..<7 {
                let x = c.x - 90 + Double(k) * 30
                let col = Path(CGRect(x: x - 6, y: c.y - 104, width: 12, height: 80))
                ctx.fill(col, with: .linearGradient(Gradient(colors: [.white, Color(white: 0.8)]), startPoint: CGPoint(x: x - 6, y: 0), endPoint: CGPoint(x: x + 6, y: 0)))
                ctx.stroke(col, with: .color(ink.opacity(0.6)), lineWidth: 0.6)
            }
            ctx.fill(Path(CGRect(x: c.x - 104, y: c.y - 116, width: 208, height: 12)), with: .color(Color(white: 0.92)))
            var pediment = Path()
            pediment.move(to: CGPoint(x: c.x - 110, y: c.y - 116)); pediment.addLine(to: CGPoint(x: c.x, y: c.y - 150))
            pediment.addLine(to: CGPoint(x: c.x + 110, y: c.y - 116)); pediment.closeSubpath()
            ctx.fill(pediment, with: .color(Color(white: 0.95)))
            ctx.stroke(pediment, with: .color(ink), lineWidth: 1)
            var frieze = Path()
            frieze.move(to: CGPoint(x: c.x - 80, y: c.y - 120)); frieze.addLine(to: CGPoint(x: c.x, y: c.y - 143)); frieze.addLine(to: CGPoint(x: c.x + 80, y: c.y - 120)); frieze.closeSubpath()
            ctx.fill(frieze, with: .color(color.opacity(0.7)))
            pennant(&ctx, at: CGPoint(x: c.x, y: c.y - 150), height: 40)
        }
    }

    private func hall(_ ctx: inout GraphicsContext, at c: CGPoint, wide: Double, high: Double) {
        let body = Path(CGRect(x: c.x - wide / 2, y: c.y - high, width: wide, height: high))
        ctx.fill(body, with: .color(style == "med" ? Color(white: 0.9) : Color(red: 0.82, green: 0.68, blue: 0.48)))
        ctx.stroke(body, with: .color(ink), lineWidth: 1)
        var roof = Path()
        roof.move(to: CGPoint(x: c.x - wide / 2 - 8, y: c.y - high)); roof.addLine(to: CGPoint(x: c.x, y: c.y - high - 26))
        roof.addLine(to: CGPoint(x: c.x + wide / 2 + 8, y: c.y - high)); roof.closeSubpath()
        ctx.fill(roof, with: .color(style == "med" ? Color(red: 0.72, green: 0.32, blue: 0.2) : color.opacity(0.8)))
        ctx.stroke(roof, with: .color(ink), lineWidth: 1)
        ctx.fill(Path(CGRect(x: c.x - 9, y: c.y - 22, width: 18, height: 22)), with: .color(Color(red: 0.35, green: 0.22, blue: 0.12)))
        pennant(&ctx, at: CGPoint(x: c.x, y: c.y - high - 26), height: 30)
    }

    /// A flag in the owner's colour, stirring in the wind.
    private func pennant(_ ctx: inout GraphicsContext, at top: CGPoint, height: Double) {
        guard owner != nil else { return }
        var pole = Path()
        pole.move(to: top); pole.addLine(to: CGPoint(x: top.x, y: top.y - height))
        ctx.stroke(pole, with: .color(Color(red: 0.35, green: 0.25, blue: 0.15)), lineWidth: 2.5)
        var flag = Path()
        let y = top.y - height
        flag.move(to: CGPoint(x: top.x, y: y))
        for k in 0...6 {
            let x = top.x + Double(k) * 5
            flag.addLine(to: CGPoint(x: x, y: y + sin(time * 4 + Double(k)) * 2))
        }
        for k in (0...6).reversed() {
            let x = top.x + Double(k) * 5
            flag.addLine(to: CGPoint(x: x, y: y + 16 + sin(time * 4 + Double(k)) * 2))
        }
        flag.closeSubpath()
        ctx.fill(flag, with: .color(color))
        ctx.stroke(flag, with: .color(ink), lineWidth: 0.6)
    }

    // MARK: Works

    /// A standing wall along the town's front, as high as it has been raised: mud-brick with a
    /// low gate; stone with battlements and two gate towers; or cyclopean, huge rough-fitted
    /// blocks with four towers, like Mycenae's or Troy's.
    private func walls(_ ctx: inout GraphicsContext) {
        let level = max(1, min(3, land.wallLevel ?? 1))
        let (stone, shade): (Color, Color) = switch level {
        case 1: (Color(red: 0.8, green: 0.64, blue: 0.44), Color(red: 0.6, green: 0.45, blue: 0.3))
        case 2: (Color(red: 0.7, green: 0.66, blue: 0.58), Color(red: 0.5, green: 0.46, blue: 0.4))
        default: (Color(red: 0.66, green: 0.63, blue: 0.58), Color(red: 0.42, green: 0.4, blue: 0.37))
        }
        func at(_ u: Double) -> CGPoint {
            let a = CGPoint(x: 250, y: 400), c = CGPoint(x: 470, y: 470), b = CGPoint(x: 690, y: 400)
            let v = 1 - u
            return CGPoint(x: v * v * a.x + 2 * v * u * c.x + u * u * b.x, y: v * v * a.y + 2 * v * u * c.y + u * u * b.y)
        }
        let n = 40
        let height = [20.0, 26, 38][level - 1]
        var face = Path()
        face.move(to: at(0))
        for k in 1...n { face.addLine(to: at(Double(k) / Double(n))) }
        for k in stride(from: n, through: 0, by: -1) { let p = at(Double(k) / Double(n)); face.addLine(to: CGPoint(x: p.x, y: p.y - height)) }
        face.closeSubpath()
        ctx.fill(face, with: .linearGradient(Gradient(colors: [stone, shade]), startPoint: CGPoint(x: 0, y: 380), endPoint: CGPoint(x: 0, y: 470)))
        switch level {
        case 1:
            // Courses of mud brick, staggered.
            for row in 1..<4 {
                var course = Path()
                course.move(to: CGPoint(x: at(0).x, y: at(0).y - Double(row) * 5))
                for k in 1...n { let p = at(Double(k) / Double(n)); course.addLine(to: CGPoint(x: p.x, y: p.y - Double(row) * 5)) }
                ctx.stroke(course, with: .color(.black.opacity(0.12)), lineWidth: 0.8)
            }
        case 2:
            for row in 1..<3 {
                var course = Path()
                course.move(to: CGPoint(x: at(0).x, y: at(0).y - Double(row) * 9))
                for k in 1...n { let p = at(Double(k) / Double(n)); course.addLine(to: CGPoint(x: p.x, y: p.y - Double(row) * 9)) }
                ctx.stroke(course, with: .color(.black.opacity(0.15)), lineWidth: 1)
            }
        default:
            // Great rough blocks: joints at uneven angles, two tiers of them.
            for k in 0..<n where k % 2 == 0 {
                let p = at(Double(k) / Double(n)), q = at(Double(k + 2) / Double(n))
                let lean = Double((k * 7) % 5) - 2
                var joint = Path()
                joint.move(to: CGPoint(x: p.x + lean, y: p.y)); joint.addLine(to: CGPoint(x: p.x - lean, y: p.y - height / 2))
                joint.move(to: CGPoint(x: (p.x + q.x) / 2 - lean, y: (p.y + q.y) / 2 - height / 2))
                joint.addLine(to: CGPoint(x: (p.x + q.x) / 2 + lean, y: (p.y + q.y) / 2 - height))
                ctx.stroke(joint, with: .color(.black.opacity(0.25)), lineWidth: 1)
            }
            var mid = Path()
            mid.move(to: CGPoint(x: at(0).x, y: at(0).y - height / 2))
            for k in 1...n { let p = at(Double(k) / Double(n)); mid.addLine(to: CGPoint(x: p.x, y: p.y - height / 2 + Double((k * 3) % 4) - 1.5)) }
            ctx.stroke(mid, with: .color(.black.opacity(0.25)), lineWidth: 1)
        }
        ctx.stroke(face, with: .color(ink), lineWidth: 1)
        // Merlons along the top (mud-brick walls have a plain parapet).
        if level >= 2 {
            for k in stride(from: 0, to: n, by: 2) {
                let p = at(Double(k) / Double(n) + 0.012)
                let m = Path(CGRect(x: p.x - 5, y: p.y - height - 8, width: 10, height: 8))
                ctx.fill(m, with: .color(stone))
                ctx.stroke(m, with: .color(ink), lineWidth: 0.8)
            }
        }
        let towers: [Double] = level == 3 ? [300, 440, 500, 640] : [440, 500]
        let towerHeight = [40.0, 62, 84][level - 1]
        for x in towers {
            let base = at((x - 250) / 440).y
            let w = level == 3 ? 46.0 : 40
            let tower = Path(CGRect(x: x - w / 2, y: base - towerHeight, width: w, height: towerHeight))
            ctx.fill(tower, with: .linearGradient(Gradient(colors: [stone, shade]), startPoint: CGPoint(x: x - w / 2, y: 0), endPoint: CGPoint(x: x + w / 2, y: 0)))
            ctx.stroke(tower, with: .color(ink), lineWidth: 1)
            if level >= 2 {
                for k in 0..<3 { ctx.fill(Path(CGRect(x: x - w / 2 + Double(k) * (w - 10) / 2, y: base - towerHeight - 8, width: 10, height: 8)), with: .color(stone)) }
            }
            ctx.fill(Path(CGRect(x: x - 4, y: base - towerHeight * 0.75, width: 8, height: 12)), with: .color(.black.opacity(0.5)))
        }
        let gate = at(0.5)
        let gh = level == 1 ? 26.0 : 36
        ctx.fill(Path(roundedRect: CGRect(x: gate.x - 18, y: gate.y - gh, width: 36, height: gh), cornerRadius: 14), with: .color(Color(red: 0.28, green: 0.18, blue: 0.1)))
        if level == 3 {
            // A great lintel over the gate, as at Mycenae.
            ctx.fill(Path(CGRect(x: gate.x - 26, y: gate.y - gh - 8, width: 52, height: 9)), with: .color(shade))
            ctx.stroke(Path(CGRect(x: gate.x - 26, y: gate.y - gh - 8, width: 52, height: 9)), with: .color(ink), lineWidth: 1)
        }
    }

    private func granary(_ ctx: inout GraphicsContext) {
        for k in 0..<3 {
            let x = 330 + Double(k) * 30, y = 452.0
            var dome = Path()
            dome.move(to: CGPoint(x: x - 14, y: y)); dome.addLine(to: CGPoint(x: x - 14, y: y - 20))
            dome.addQuadCurve(to: CGPoint(x: x + 14, y: y - 20), control: CGPoint(x: x, y: y - 48)); dome.addLine(to: CGPoint(x: x + 14, y: y))
            dome.closeSubpath()
            ctx.fill(dome, with: .color(Color(red: 0.86, green: 0.74, blue: 0.52)))
            ctx.stroke(dome, with: .color(ink), lineWidth: 1)
            ctx.fill(Path(CGRect(x: x - 4, y: y - 10, width: 8, height: 10)), with: .color(Color(red: 0.35, green: 0.22, blue: 0.12)))
        }
    }

    /// A public well with a stone basin and a channel draining away.
    private func well(_ ctx: inout GraphicsContext) {
        let c = CGPoint(x: 560, y: 452)
        var drain = Path()
        drain.move(to: CGPoint(x: c.x + 14, y: c.y)); drain.addLine(to: CGPoint(x: c.x + 90, y: c.y + 20))
        ctx.stroke(drain, with: .color(Color(red: 0.55, green: 0.5, blue: 0.44)), lineWidth: 7)
        ctx.stroke(drain, with: .color(Color(red: 0.3, green: 0.55, blue: 0.82)), lineWidth: 3)
        let basin = Path(ellipseIn: CGRect(x: c.x - 18, y: c.y - 8, width: 36, height: 16))
        ctx.fill(basin, with: .color(Color(white: 0.75)))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - 12, y: c.y - 5, width: 24, height: 9)), with: .color(Color(red: 0.3, green: 0.55, blue: 0.82)))
        ctx.stroke(basin, with: .color(ink), lineWidth: 1)
        var frame = Path()
        frame.move(to: CGPoint(x: c.x - 14, y: c.y)); frame.addLine(to: CGPoint(x: c.x - 14, y: c.y - 30))
        frame.addLine(to: CGPoint(x: c.x + 14, y: c.y - 30)); frame.addLine(to: CGPoint(x: c.x + 14, y: c.y))
        ctx.stroke(frame, with: .color(Color(red: 0.4, green: 0.27, blue: 0.14)), lineWidth: 3)
    }

    private func scaffold(_ ctx: inout GraphicsContext) {
        let wood = Color(red: 0.55, green: 0.38, blue: 0.18)
        var frame = Path()
        var c = ctx
        c.translateBy(x: -330, y: 0)
        for x in [600.0, 630, 660] { frame.move(to: CGPoint(x: x, y: 380)); frame.addLine(to: CGPoint(x: x, y: 310)) }
        for y in [330.0, 355] { frame.move(to: CGPoint(x: 596, y: y)); frame.addLine(to: CGPoint(x: 664, y: y)) }
        frame.move(to: CGPoint(x: 600, y: 380)); frame.addLine(to: CGPoint(x: 660, y: 310))
        c.stroke(frame, with: .color(wood), lineWidth: 3)
        // A crane's arm swinging a block.
        let swing = sin(time * 0.9) * 10
        var arm = Path()
        arm.move(to: CGPoint(x: 630, y: 300)); arm.addLine(to: CGPoint(x: 690 + swing, y: 290))
        c.stroke(arm, with: .color(wood), lineWidth: 3)
        var rope = Path()
        rope.move(to: CGPoint(x: 690 + swing, y: 290)); rope.addLine(to: CGPoint(x: 690 + swing, y: 318))
        c.stroke(rope, with: .color(.black.opacity(0.6)), lineWidth: 1)
        c.fill(Path(CGRect(x: 682 + swing, y: 318, width: 16, height: 12)), with: .color(Color(white: 0.75)))
    }

    private func greatWork(_ ctx: inout GraphicsContext) {
        guard let id = state.monuments.first(where: { $0.value == territory })?.key else { return }
        let gold = Color(red: 0.92, green: 0.78, blue: 0.45)
        switch id {
        case "pyramid":
            var p = Path()
            p.move(to: CGPoint(x: 160, y: 300)); p.addLine(to: CGPoint(x: 280, y: 130)); p.addLine(to: CGPoint(x: 400, y: 300)); p.closeSubpath()
            ctx.fill(p, with: .linearGradient(Gradient(colors: [gold, Color(red: 0.75, green: 0.6, blue: 0.36)]), startPoint: CGPoint(x: 200, y: 200), endPoint: CGPoint(x: 400, y: 300)))
            ctx.stroke(p, with: .color(ink), lineWidth: 1)
        case "ziggurat":
            for (k, w) in [220.0, 160, 100].enumerated() {
                ctx.fill(Path(CGRect(x: 280 - w / 2, y: 300 - Double(k + 1) * 46, width: w, height: 46)), with: .color(gold.opacity(0.9 - Double(k) * 0.1)))
            }
        case "lighthouse":
            ctx.fill(Path(CGRect(x: 880, y: 150, width: 34, height: 140)), with: .color(Color(white: 0.92)))
            ctx.fill(Path(ellipseIn: CGRect(x: 872, y: 132, width: 50, height: 28)), with: .color(Color(red: 1, green: 0.8, blue: 0.3).opacity(0.6 + sin(time * 3) * 0.3)))
        case "library":
            hall(&ctx, at: CGPoint(x: 700, y: 310), wide: 110, high: 50)
        case "lionGate":
            ctx.fill(Path(CGRect(x: 230, y: 230, width: 120, height: 70)), with: .color(Color(red: 0.66, green: 0.62, blue: 0.55)))
            ctx.fill(Path(CGRect(x: 268, y: 254, width: 44, height: 46)), with: .color(Color(red: 0.25, green: 0.17, blue: 0.1)))
            var lions = Path()
            lions.move(to: CGPoint(x: 268, y: 250)); lions.addLine(to: CGPoint(x: 290, y: 220)); lions.addLine(to: CGPoint(x: 312, y: 250)); lions.closeSubpath()
            ctx.fill(lions, with: .color(Color(white: 0.85)))
        default:
            break
        }
    }

    /// The army camped outside the town, under its owner's flag, a fire smoking.
    private func camp(_ ctx: inout GraphicsContext) {
        guard let army = state.armies[territory], army.units.total > 0 else { return }
        let tint = Palette.color(army.owner, state)
        let tents = min(9, max(1, army.units.total / 2))
        for k in 0..<tents {
            let x = 110 + Double(k % 5) * 44 + Double(k / 5) * 22, y = 400 + Double(k / 5) * 36
            var tent = Path()
            tent.move(to: CGPoint(x: x - 18, y: y)); tent.addLine(to: CGPoint(x: x, y: y - 28)); tent.addLine(to: CGPoint(x: x + 18, y: y)); tent.closeSubpath()
            ctx.fill(tent, with: .color(tint.opacity(0.9)))
            ctx.fill(Path { p in p.move(to: CGPoint(x: x, y: y - 28)); p.addLine(to: CGPoint(x: x + 18, y: y)); p.addLine(to: CGPoint(x: x, y: y)); p.closeSubpath() },
                     with: .color(.black.opacity(0.18)))
            ctx.stroke(tent, with: .color(ink), lineWidth: 1)
        }
        // Campfire smoke.
        let fx = 150.0, fy = 448.0
        ctx.fill(Path(ellipseIn: CGRect(x: fx - 7, y: fy - 5, width: 14, height: 8)), with: .color(Color(red: 1, green: 0.55, blue: 0.15)))
        for k in 0..<4 {
            let rise = (time * 14 + Double(k) * 18).truncatingRemainder(dividingBy: 72)
            ctx.fill(Path(ellipseIn: CGRect(x: fx - 6 + sin(rise / 10) * 6, y: fy - 12 - rise, width: 12 + rise * 0.2, height: 10 + rise * 0.2)),
                     with: .color(Color(white: 0.6).opacity(0.5 * (1 - rise / 72))))
        }
        var c = ctx
        c.translateBy(x: 0, y: 0)
        pennantFor(&c, army.owner, at: CGPoint(x: 92, y: 400))
    }

    private func pennantFor(_ ctx: inout GraphicsContext, _ civ: CivilizationID, at p: CGPoint) {
        var pole = Path()
        pole.move(to: p); pole.addLine(to: CGPoint(x: p.x, y: p.y - 60))
        ctx.stroke(pole, with: .color(Color(red: 0.35, green: 0.25, blue: 0.15)), lineWidth: 2.5)
        var flag = Path()
        let y = p.y - 60
        flag.move(to: CGPoint(x: p.x, y: y))
        for k in 0...7 { flag.addLine(to: CGPoint(x: p.x + Double(k) * 5, y: y + sin(time * 4 + Double(k)) * 2.5)) }
        for k in (0...7).reversed() { flag.addLine(to: CGPoint(x: p.x + Double(k) * 5, y: y + 20 + sin(time * 4 + Double(k)) * 2.5)) }
        flag.closeSubpath()
        ctx.fill(flag, with: .color(Palette.color(civ, state)))
        ctx.stroke(flag, with: .color(ink), lineWidth: 0.6)
    }
}
