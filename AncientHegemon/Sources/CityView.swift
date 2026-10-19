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
                Label("\(projectName(kind)): \(projectPurpose(kind))", systemImage: CommandBar.projectSymbol(kind))
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
                    let c = engine.projectCost(kind, for: civ, state)
                    let ok = cs.gold >= c.gold && (cs.stock[.stone] ?? 0) >= c.stone && (cs.stock[.timber] ?? 0) >= c.timber
                    Button {
                        if session.order(.build(territory: territory, project: kind)) { SoundBoard.shared.play(.coins, volume: 0.6) }
                    } label: {
                        HStack {
                            Image(systemName: CommandBar.projectSymbol(kind)).frame(width: 22)
                            VStack(alignment: .leading, spacing: 0) {
                                Text("Build \(projectName(kind).lowercased())").font(.callout.bold())
                                Text(projectPurpose(kind)).font(.caption2).foregroundStyle(.secondary)
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
struct TownScene: View {
    let session: GameSession
    let territory: TerritoryID
    let report: TerritoryReport
    @State private var sway = false

    private var state: GameState { session.state }
    private var engine: Engine { session.engine }

    var body: some View {
        let t = engine.map.territory(territory)!
        let land = state.land[territory]!
        let owner = state.owner(of: territory)
        let color = Palette.color(owner, state)
        let coastal = !t.seas.isEmpty
        let capital = owner.flatMap { engine.seat(of: $0, in: state) } == territory
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack(alignment: .topLeading) {
                // Sky and land.
                LinearGradient(colors: [Color(red: 0.55, green: 0.75, blue: 0.95), Color(red: 0.95, green: 0.85, blue: 0.7)],
                               startPoint: .top, endPoint: .center)
                Circle().fill(RadialGradient(colors: [.yellow, .orange.opacity(0.4), .clear], center: .center, startRadius: 4, endRadius: 46))
                    .frame(width: 92, height: 92).position(x: w * 0.82, y: h * 0.14)
                Rectangle().fill(LinearGradient(colors: [BattleBoard.ground(t.terrain, row: 0, col: 0),
                                                         BattleBoard.ground(t.terrain, row: 0, col: 1).opacity(0.85)],
                                                startPoint: .top, endPoint: .bottom))
                    .frame(height: h * 0.62).offset(y: h * 0.38)
                // A river valley's river, winding past the town.
                if t.has(.riverValley) {
                    Path { p in
                        p.move(to: CGPoint(x: w * 0.62, y: h * 0.38))
                        p.addCurve(to: CGPoint(x: w * 0.58, y: h), control1: CGPoint(x: w * 0.75, y: h * 0.6),
                                   control2: CGPoint(x: w * 0.5, y: h * 0.8))
                    }
                    .stroke(Color(red: 0.25, green: 0.5, blue: 0.8), style: StrokeStyle(lineWidth: 18, lineCap: .round))
                }
                // A few trees.
                ForEach(0..<(t.terrain == .forest ? 9 : t.terrain == .desert ? 0 : 4), id: \.self) { i in
                    Image(systemName: "tree.fill").font(.system(size: 26))
                        .foregroundStyle(Color(red: 0.2, green: 0.45, blue: 0.2))
                        .position(x: w * (0.06 + 0.09 * Double(i)), y: h * (0.43 + 0.03 * Double(i % 2)))
                }
                if t.terrain == .hills || t.terrain == .mountains || land.improvements.contains(.mine) {
                    Image(systemName: "mountain.2.fill").resizable().scaledToFit()
                        .foregroundStyle(Color(red: 0.45, green: 0.42, blue: 0.38))
                        .frame(width: w * 0.35).position(x: w * 0.2, y: h * 0.33)
                }
                // The sea, with a harbor and ships.
                if coastal {
                    Rectangle().fill(Color(red: 0.2, green: 0.45, blue: 0.75))
                        .frame(width: w * 0.22, height: h * 0.62).offset(x: w * 0.78, y: h * 0.38)
                    if land.improvements.contains(.harbor) {
                        Rectangle().fill(Color(red: 0.45, green: 0.3, blue: 0.15)).frame(width: w * 0.08, height: 10)
                            .position(x: w * 0.8, y: h * 0.6)
                    }
                    let ships = t.seas.compactMap { state.fleet(of: owner ?? "", in: $0)?.ships }.reduce(0, +)
                    ForEach(0..<min(ships, 6), id: \.self) { i in
                        Image(systemName: "sailboat.fill").font(.title2).foregroundStyle(.white)
                            .position(x: w * (0.84 + 0.05 * Double(i % 3)), y: h * (0.5 + 0.12 * Double(i / 3)))
                            .rotationEffect(.degrees(sway ? 3 : -3))
                    }
                }
                // Fields, one per grain.
                ForEach(0..<min(report.grain, 12), id: \.self) { i in
                    let col = i % 4, row = i / 4
                    RoundedRectangle(cornerRadius: 3)
                        .fill(i % 2 == 0 ? Color(red: 0.85, green: 0.75, blue: 0.35) : Color(red: 0.55, green: 0.7, blue: 0.3))
                        .overlay(Path { p in
                            for k in 0..<4 { p.move(to: CGPoint(x: 0, y: CGFloat(k) * 6 + 3)); p.addLine(to: CGPoint(x: w * 0.1, y: CGFloat(k) * 6 + 3)) }
                        }.stroke(.black.opacity(0.12), lineWidth: 1))
                        .frame(width: w * 0.1, height: h * 0.06)
                        .position(x: w * (0.08 + 0.11 * Double(col)), y: h * (0.78 + 0.075 * Double(row)))
                }
                if land.improvements.contains(.farm) {
                    Image(systemName: "drop.fill").foregroundStyle(.blue.opacity(0.6))
                        .position(x: w * 0.5, y: h * 0.8)
                }
                // The granary: a domed storehouse by the fields.
                if land.improvements.contains(.granary) {
                    Image(systemName: "archivebox.fill").font(.system(size: 34))
                        .foregroundStyle(Color(red: 0.8, green: 0.62, blue: 0.35))
                        .shadow(radius: 2)
                        .position(x: w * 0.6, y: h * 0.78)
                }
                // The road through town.
                if land.improvements.contains(.road) {
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: h * 0.68))
                        p.addQuadCurve(to: CGPoint(x: w * 0.78, y: h * 0.62), control: CGPoint(x: w * 0.4, y: h * 0.74))
                    }
                    .stroke(Color(red: 0.75, green: 0.65, blue: 0.5), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                }
                // Houses, one per person, around the palace or hall.
                ForEach(0..<min(report.people, 16), id: \.self) { i in
                    let col = i % 8, row = i / 8
                    Image(systemName: "house.fill").font(.system(size: 30))
                        .foregroundStyle(Color(red: 0.88, green: 0.8, blue: 0.65))
                        .shadow(radius: 1)
                        .position(x: w * (0.27 + 0.055 * Double(col)), y: h * (0.52 + 0.08 * Double(row)))
                }
                Image(systemName: capital ? "building.columns.fill" : "house.lodge.fill")
                    .font(.system(size: capital ? 56 : 36))
                    .foregroundStyle(capital ? AnyShapeStyle(Bronze.gradient) : AnyShapeStyle(Color(red: 0.7, green: 0.6, blue: 0.45)))
                    .shadow(radius: 3)
                    .position(x: w * 0.47, y: h * 0.4)
                // Walls around the town.
                if land.improvements.contains(.walls) {
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color(red: 0.55, green: 0.5, blue: 0.45), style: StrokeStyle(lineWidth: 8, dash: [14, 4]))
                        .frame(width: w * 0.5, height: h * 0.34)
                        .position(x: w * 0.47, y: h * 0.5)
                }
                // Building work.
                if land.construction != nil {
                    Image(systemName: "hammer.fill").font(.title).foregroundStyle(.orange)
                        .position(x: w * 0.66, y: h * 0.42)
                }
                // The army, camped outside, under its owner's flag.
                if let army = state.armies[territory], army.units.total > 0 {
                    let tents = min(8, max(1, army.units.total / 2))
                    ForEach(0..<tents, id: \.self) { i in
                        Image(systemName: "tent.fill").font(.system(size: 20))
                            .foregroundStyle(Palette.color(army.owner, state).opacity(0.9))
                            .position(x: w * (0.08 + 0.05 * Double(i % 4)), y: h * (0.55 + 0.07 * Double(i / 4)))
                    }
                    Image(systemName: "flag.fill").foregroundStyle(Palette.color(army.owner, state))
                        .rotationEffect(.degrees(sway ? 4 : -4), anchor: .bottomLeading)
                        .position(x: w * 0.1, y: h * 0.48)
                }
                // Name banner.
                Text(t.name.uppercased())
                    .font(.system(.title, design: .serif).weight(.bold)).tracking(4)
                    .foregroundStyle(.white).shadow(color: .black.opacity(0.6), radius: 4)
                    .padding(.horizontal, 16).padding(.vertical, 6)
                    .background(BannerRibbon().fill(color.opacity(0.9)).overlay(BannerRibbon().stroke(Bronze.gradient, lineWidth: 2)))
                    .position(x: w * 0.47, y: h * 0.12)
            }
            .frame(width: w, height: h)
            .clipped()
        }
        .onAppear { withAnimation(.easeInOut(duration: 1.6).repeatForever()) { sway = true } }
    }
}
