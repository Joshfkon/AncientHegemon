import HegemonCore
import SwiftUI

/// The ruler's hall, in the empire's own style: what has been bought to adorn it, the trophies
/// won, and the council standing before the throne. Advice can be followed to the map.
struct ThroneRoomView: View {
    let session: GameSession
    /// Leave the hall, optionally to look at something an advisor pointed at.
    let done: (Advisor.Target?) -> Void
    @State private var chosen: Advisor.Role?

    private var engine: Engine { session.engine }
    private var state: GameState { session.state }
    private var civ: CivilizationID { session.human! }
    private var cs: CivState { state.civs[civ]! }

    var body: some View {
        let council = Council.advice(session)
        HStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                Hall(civ: civ, decorations: cs.decorations, trophies: cs.trophies, ruler: cs.ruler.name, state: state)
                HStack(alignment: .bottom, spacing: 18) {
                    ForEach(council) { a in
                        AdvisorFigure(advisor: a, color: Palette.color(civ, state), chosen: chosen == a.role)
                            .onTapGesture {
                                Feedback.select()
                                withAnimation(.spring(duration: 0.3)) { chosen = a.role }
                            }
                    }
                }
                .padding(.bottom, 14)
            }
            .ignoresSafeArea()
            sidebar(council)
                .frame(width: 330)
                .background(Parchment())
        }
        .background(Color.black)
        .onAppear { SoundBoard.shared.play(.horn, volume: 0.4) }
    }

    private func sidebar(_ council: [Advisor]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Throne room").font(.system(.title2, design: .serif).weight(.bold))
                Spacer()
                Button("Done") { done(nil) }.bold()
            }
            .padding([.horizontal, .top])
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        splendour
                        Text("The council").font(.headline)
                        ForEach(council) { a in
                            AdviceCard(advisor: a, highlighted: chosen == a.role) { done(a.target) }
                                .id(a.role)
                                .onTapGesture { withAnimation { chosen = a.role } }
                        }
                        Text("Adorn the hall").font(.headline).padding(.top, 6)
                        ForEach(engine.rules.throneRoom.decorations) { d in decorationRow(d) }
                        if !cs.trophies.isEmpty {
                            Text("Trophies").font(.headline).padding(.top, 6)
                            ForEach(cs.trophies.indices, id: \.self) { i in
                                Label(Self.trophyName(cs.trophies[i].kind, engine, state) + " · round \(cs.trophies[i].round)",
                                      systemImage: Self.trophySymbol(cs.trophies[i].kind))
                                    .font(.caption)
                            }
                        } else {
                            Text("Trophies come from every territory you take, a rival's capital, beating off raiders, and winning tribes over.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                }
                .onChange(of: chosen) { _, role in
                    if let role { withAnimation { proxy.scrollTo(role, anchor: .center) } }
                }
            }
        }
    }

    private var splendour: some View {
        let m = engine.magnificence(of: civ, in: state)
        let ease = engine.successionEase(of: civ, in: state)
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Image(systemName: "sparkles").foregroundStyle(Bronze.gradient)
                Text("Magnificence \(m)").font(.subheadline.bold())
            }
            let r = engine.rules.throneRoom
            let court = engine.courtLegitimacy(of: civ, in: state)
            Text(["+\(m * r.prestigePerMagnificence) prestige",
                  court > 0 ? "+\(court) legitimacy a turn" : "legitimacy a turn at \(r.magnificencePerLegitimacy)",
                  m >= r.magnificencePerGiftPercent ? "tribes \(m / max(1, r.magnificencePerGiftPercent))% likelier to take gifts" : nil,
                  m >= r.peaceMagnificence ? "rivals rarely refuse your peace offers" : "rivals heed your envoys at \(r.peaceMagnificence)",
                  ease > 0 ? "an heir needs \(ease) less legitimacy to be crowned smoothly" : nil]
                    .compactMap { $0 }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.5)))
    }

    private func decorationRow(_ d: Decoration) -> some View {
        let owned = cs.decorations.contains(d.id)
        let affordable = cs.gold >= d.gold && d.stock.allSatisfy { (cs.stock[$0.key] ?? 0) >= $0.value }
        return Button {
            if session.order(.decorate(d.id)) {
                SoundBoard.shared.play(.coins, volume: 0.7)
                Feedback.outcome(true)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: Hall.symbol(d.id)).frame(width: 24).foregroundStyle(Bronze.gradient)
                VStack(alignment: .leading, spacing: 1) {
                    Text(d.name).font(.callout.bold())
                    (owned ? Text("In the hall") : Self.cost(d))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if owned {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                } else {
                    Text("+\(d.magnificence)").font(.caption.bold()).foregroundStyle(.orange)
                }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(owned ? 0.25 : 0.55)))
        }
        .buttonStyle(.plain)
        .disabled(owned || !affordable || !session.isHumanTurn)
        .opacity(owned || affordable ? 1 : 0.55)
    }

    static func cost(_ d: Decoration) -> Text {
        d.stock.sorted { $0.key.rawValue < $1.key.rawValue }.reduce(Text("\(d.gold) gold")) { t, s in
            t + Text(" · \(s.value) ") + MapView.icon(s.key)
        }
    }

    static func trophyName(_ kind: TrophyKind, _ engine: Engine, _ state: GameState) -> String {
        switch kind {
        case let .standard(civ): "The standard of \(Palette.name(civ, state))"
        case .raiderShield: "A raider's shield"
        case let .totem(t): "The totem of \(engine.map.territory(t)?.name ?? t)"
        case let .spoils(t): "Spoils of \(engine.map.territory(t)?.name ?? t)"
        }
    }

    static func trophySymbol(_ kind: TrophyKind) -> String {
        switch kind {
        case .standard: "flag.fill"
        case .raiderShield: "shield.fill"
        case .totem: "figure.stand"
        case .spoils: "shippingbox.fill"
        }
    }
}

/// One advisor's word, with a button to go and see.
private struct AdviceCard: View {
    let advisor: Advisor
    let highlighted: Bool
    let go: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: advisor.symbol)
                Text("\(advisor.name), \(advisor.title.lowercased())").font(.caption.bold())
                Spacer()
                if advisor.mood != .calm {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(advisor.mood == .alarm ? .red : .orange)
                }
            }
            Text("“\(advisor.advice)”").font(.callout).fixedSize(horizontal: false, vertical: true)
            if advisor.target != nil {
                Button(action: go) {
                    Label(advisor.target == .diplomacy ? "To the Rivals tab" : advisor.target == .realm ? "To the Realm tab" : "Show me",
                          systemImage: "arrow.right.circle.fill")
                        .font(.caption.bold())
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(highlighted ? 0.85 : 0.5)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Bronze.gradient, lineWidth: highlighted ? 2 : 0))
    }
}

/// An advisor standing in the hall.
private struct AdvisorFigure: View {
    let advisor: Advisor
    let color: Color
    let chosen: Bool
    @State private var bob = false

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle().fill(color.opacity(0.9)).frame(width: 46, height: 46)
                Circle().stroke(Bronze.gradient, lineWidth: chosen ? 3 : 1.5).frame(width: 46, height: 46)
                Image(systemName: advisor.symbol).font(.title3).foregroundStyle(.white)
            }
            .overlay(alignment: .topTrailing) {
                if advisor.mood != .calm {
                    Circle().fill(advisor.mood == .alarm ? .red : .orange).frame(width: 12, height: 12)
                        .overlay(Circle().stroke(.white, lineWidth: 1.5))
                        .scaleEffect(bob ? 1.15 : 0.9)
                }
            }
            Text(advisor.title).font(.caption2.bold()).foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(Capsule().fill(.black.opacity(0.5)))
        }
        .scaleEffect(chosen ? 1.12 : 1)
        .offset(y: bob && advisor.mood == .alarm ? -2 : 0)
        .onAppear { withAnimation(.easeInOut(duration: 0.8).repeatForever()) { bob = true } }
    }
}

/// The hall itself, drawn in the empire's style, with whatever has been bought or won.
struct Hall: View {
    let civ: CivilizationID
    let decorations: Set<DecorationID>
    let trophies: [Trophy]
    let ruler: String
    let state: GameState
    @State private var flicker = false

    private struct Style {
        let wall: [Color]
        let floor: Color
        let column: Color
        let frieze: Color
    }

    private var style: Style {
        switch civ {
        case "egypt": Style(wall: [Color(red: 0.86, green: 0.74, blue: 0.52), Color(red: 0.72, green: 0.58, blue: 0.38)],
                            floor: Color(red: 0.62, green: 0.5, blue: 0.34), column: Color(red: 0.9, green: 0.8, blue: 0.6),
                            frieze: Color(red: 0.15, green: 0.45, blue: 0.55))
        case "greece": Style(wall: [Color(red: 0.92, green: 0.88, blue: 0.8), Color(red: 0.8, green: 0.74, blue: 0.64)],
                             floor: Color(red: 0.55, green: 0.42, blue: 0.32), column: Color(red: 0.62, green: 0.18, blue: 0.14),
                             frieze: Color(red: 0.2, green: 0.35, blue: 0.65))
        case "italia": Style(wall: [Color(red: 0.6, green: 0.45, blue: 0.32), Color(red: 0.45, green: 0.32, blue: 0.22)],
                             floor: Color(red: 0.4, green: 0.3, blue: 0.22), column: Color(red: 0.35, green: 0.22, blue: 0.14),
                             frieze: Color(red: 0.7, green: 0.25, blue: 0.15))
        default: Style(wall: [Color(red: 0.18, green: 0.35, blue: 0.62), Color(red: 0.12, green: 0.24, blue: 0.45)],
                       floor: Color(red: 0.55, green: 0.45, blue: 0.32), column: Color(red: 0.75, green: 0.62, blue: 0.4),
                       frieze: Color(red: 0.85, green: 0.7, blue: 0.3))
        }
    }

    static func symbol(_ id: DecorationID) -> String {
        switch id {
        case "braziers": "flame.fill"
        case "hangings": "flag.fill"
        case "columns": "building.columns.fill"
        case "ceiling": "square.stack.3d.up.fill"
        case "mosaic": "square.grid.3x3.fill"
        case "statue": "figure.stand"
        case "throne": "chair.fill"
        default: "sparkles"
        }
    }

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let floorTop = h * 0.68
            let s = style
            ZStack(alignment: .topLeading) {
                // Back wall, with a painted frieze, and glazed bricks in Mesopotamia.
                LinearGradient(colors: s.wall, startPoint: .top, endPoint: .bottom)
                if civ == "mesopotamia" {
                    Path { p in
                        for row in stride(from: 0, to: floorTop, by: 14) {
                            p.move(to: CGPoint(x: 0, y: row)); p.addLine(to: CGPoint(x: w, y: row))
                        }
                    }
                    .stroke(.black.opacity(0.15), lineWidth: 1)
                }
                Rectangle().fill(s.frieze).frame(height: 12).offset(y: h * 0.16)
                // Ceiling: bare rafters, or a cedar ceiling.
                Rectangle()
                    .fill(decorations.contains("ceiling")
                          ? AnyShapeStyle(LinearGradient(colors: [Color(red: 0.45, green: 0.25, blue: 0.12), Color(red: 0.3, green: 0.16, blue: 0.08)], startPoint: .top, endPoint: .bottom))
                          : AnyShapeStyle(Color.black.opacity(0.35)))
                    .frame(height: h * 0.12)
                if decorations.contains("ceiling") {
                    ForEach(0..<9, id: \.self) { i in
                        Rectangle().fill(.black.opacity(0.25)).frame(width: 4, height: h * 0.12)
                            .offset(x: w * CGFloat(i) / 8)
                    }
                    Rectangle().fill(Bronze.gradient).frame(height: 3).offset(y: h * 0.12)
                }
                // Hangings on the wall.
                if decorations.contains("hangings") {
                    ForEach([0.2, 0.8], id: \.self) { x in
                        BannerShape().fill(Color(red: 0.42, green: 0.12, blue: 0.4))
                            .overlay(BannerShape().stroke(Bronze.gradient, lineWidth: 2))
                            .frame(width: w * 0.09, height: h * 0.32)
                            .position(x: w * x, y: h * 0.36)
                    }
                }
                // Trophies on a shelf along the wall.
                HStack(spacing: 10) {
                    ForEach(trophies.indices.prefix(14), id: \.self) { i in trophy(trophies[i].kind) }
                }
                .frame(width: w)
                .offset(y: h * 0.21)
                // Columns.
                ForEach([0.06, 0.32, 0.68, 0.94], id: \.self) { x in
                    column(s, painted: decorations.contains("columns"))
                        .frame(width: w * 0.055, height: floorTop - h * 0.12)
                        .position(x: w * x, y: h * 0.12 + (floorTop - h * 0.12) / 2)
                }
                // Floor: packed earth, or a mosaic.
                Group {
                    if decorations.contains("mosaic") {
                        Canvas { ctx, size in
                            let tile: CGFloat = 16
                            for y in stride(from: 0, to: size.height, by: tile) {
                                for x in stride(from: 0, to: size.width, by: tile) {
                                    let k = (Int(x / tile) + Int(y / tile)) % 3
                                    let c: Color = k == 0 ? s.frieze : k == 1 ? Color(white: 0.85) : Color(red: 0.62, green: 0.3, blue: 0.18)
                                    ctx.fill(Path(CGRect(x: x + 1, y: y + 1, width: tile - 2, height: tile - 2)), with: .color(c))
                                }
                            }
                        }
                    } else {
                        Rectangle().fill(s.floor)
                    }
                }
                .frame(width: w, height: h - floorTop)
                .offset(y: floorTop)
                // Braziers either side of the throne.
                if decorations.contains("braziers") {
                    ForEach([0.36, 0.64], id: \.self) { x in brazier.position(x: w * x, y: floorTop - 4) }
                }
                // The statue.
                if decorations.contains("statue") {
                    VStack(spacing: 0) {
                        Image(systemName: "figure.stand").resizable().scaledToFit().foregroundStyle(Color(white: 0.85))
                            .frame(height: h * 0.3)
                        Rectangle().fill(Color(white: 0.7)).frame(width: 40, height: 14)
                    }
                    .shadow(radius: 4)
                    .position(x: w * 0.82, y: floorTop - h * 0.12)
                }
                // The throne, the realm's emblem above it.
                VStack(spacing: 6) {
                    CivBanner.emblem(civ)
                        .foregroundStyle(decorations.contains("throne") ? AnyShapeStyle(Bronze.gradient) : AnyShapeStyle(Color.white.opacity(0.85)))
                        .frame(width: 44, height: 44)
                    throne
                    Text(ruler).font(.caption.bold()).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Capsule().fill(.black.opacity(0.45)))
                }
                .position(x: w * 0.5, y: floorTop - h * 0.12)
            }
            .frame(width: w, height: h)
            .clipped()
        }
        .onAppear { withAnimation(.easeInOut(duration: 0.35).repeatForever()) { flicker = true } }
    }

    private func column(_ s: Style, painted: Bool) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(painted ? AnyShapeStyle(Bronze.gradient) : AnyShapeStyle(s.column.opacity(0.9))).frame(height: 10)
            ZStack {
                Rectangle().fill(s.column)
                if painted {
                    VStack(spacing: 14) {
                        ForEach(0..<6, id: \.self) { _ in Rectangle().fill(s.frieze).frame(height: 4) }
                    }
                }
            }
            Rectangle().fill(s.column.opacity(0.8)).frame(height: 8)
        }
        .shadow(color: .black.opacity(0.3), radius: 3, x: 2)
    }

    private var brazier: some View {
        VStack(spacing: 0) {
            Image(systemName: "flame.fill").font(.title)
                .foregroundStyle(LinearGradient(colors: [.yellow, .orange, .red], startPoint: .top, endPoint: .bottom))
                .scaleEffect(flicker ? 1.1 : 0.92, anchor: .bottom)
                .shadow(color: .orange, radius: flicker ? 12 : 6)
            Capsule().fill(Bronze.gradient).frame(width: 30, height: 8)
            Rectangle().fill(Bronze.gradient).frame(width: 5, height: 34)
        }
    }

    private var throne: some View {
        let gilded = decorations.contains("throne")
        let wood: AnyShapeStyle = gilded ? AnyShapeStyle(Bronze.gradient) : AnyShapeStyle(Color(red: 0.42, green: 0.3, blue: 0.2))
        let cloth = gilded ? Color(red: 0.45, green: 0.1, blue: 0.4) : Color(red: 0.55, green: 0.48, blue: 0.4)
        return ZStack(alignment: .bottom) {
            // Tall back with a rounded top, then the seat between two arms, on a dais.
            UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26).fill(wood)
                .frame(width: 62, height: 96).offset(y: -22)
            UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20).fill(cloth)
                .frame(width: 44, height: 62).offset(y: -36)
            HStack(spacing: 42) {
                RoundedRectangle(cornerRadius: 4).fill(wood).frame(width: 12, height: 40)
                RoundedRectangle(cornerRadius: 4).fill(wood).frame(width: 12, height: 40)
            }
            .offset(y: -12)
            RoundedRectangle(cornerRadius: 3).fill(cloth).frame(width: 50, height: 12).offset(y: -22)
            RoundedRectangle(cornerRadius: 2).fill(gilded ? AnyShapeStyle(Bronze.gradient) : AnyShapeStyle(Color(white: 0.55)))
                .frame(width: 100, height: 12)
        }
        .frame(width: 100, height: 120, alignment: .bottom)
        .shadow(color: gilded ? .yellow.opacity(0.5) : .black.opacity(0.3), radius: gilded ? 10 : 4)
    }

    @ViewBuilder private func trophy(_ kind: TrophyKind) -> some View {
        switch kind {
        case let .standard(civ):
            Image(systemName: "flag.fill").font(.title2).foregroundStyle(Palette.color(civ, state)).shadow(radius: 2)
        case .raiderShield:
            Image(systemName: "shield.fill").font(.title2).foregroundStyle(Color(red: 0.5, green: 0.35, blue: 0.2)).shadow(radius: 2)
        case .totem:
            Image(systemName: "figure.stand").font(.title2).foregroundStyle(Color(red: 0.35, green: 0.25, blue: 0.15)).shadow(radius: 2)
        case .spoils:
            Image(systemName: "shippingbox.fill").font(.title3).foregroundStyle(Bronze.gradient).shadow(radius: 2)
        }
    }
}
