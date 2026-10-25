import HegemonCore
import SwiftUI

/// A big moment for the player, shown as a banner over the map: a capture, a loss, a discovery,
/// war or peace, or a disaster striking their land.
struct Moment: Identifiable, Equatable {
    enum Kind: Equatable {
        case captured(TerritoryID)
        case lost(TerritoryID)
        case discovery(KnowledgeField, Int)
        case peace(CivilizationID)
        case war(CivilizationID)
        case disaster(EventKind, TerritoryID?)
        /// The treasury couldn't pay the army and soldiers went home.
        case unpaid(Int)
        /// The player's ships fought at sea.
        case seaBattle(SeaZoneID, won: Bool, against: CivilizationID)
        /// An alliance made (or broken by the other side).
        case ally(CivilizationID, joined: Bool)
        /// An ally went to war for us.
        case allyJoins(CivilizationID, CivilizationID)
        /// An ally calls on us to fight.
        case callToArms(CivilizationID, CivilizationID)
        /// A rival struck the player's land.
        case attacked(CivilizationID, TerritoryID?)
        /// A great work finished somewhere, by us or a rival.
        case monument(MonumentID, CivilizationID)
        /// A rival finished first: our site is abandoned.
        case monumentLost(MonumentID)
        /// Our town is besieged, or we laid siege to one.
        case besieged(TerritoryID, by: CivilizationID)
        /// A capital sacked: ours by them, or theirs by us.
        case sacked(TerritoryID, by: CivilizationID, gold: Int)
        /// An age of splendour begins (or ends).
        case splendour(began: Bool)
        /// The Iron Age dawns.
        case ironAge
        /// One of our generals rose in revolt and took land with him (and had he been paid off?).
        case rebellion(general: String, lands: [TerritoryID], rebel: CivilizationID, bribed: Bool)
    }
    let id = UUID()
    let kind: Kind
}

/// How a moment looks: icon, words, colour, and the shake or tint it brings.
struct MomentBanner: View {
    let moment: Moment
    let session: GameSession
    @State private var unfurled = false

    var body: some View {
        let style = Self.style(moment.kind, session)
        HStack(spacing: 12) {
            Image(systemName: style.icon)
                .font(.title2.bold())
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(style.color.opacity(0.9), in: Circle())
                .overlay(Circle().stroke(Bronze.gradient, lineWidth: 2))
            VStack(alignment: .leading, spacing: 1) {
                Text(style.title)
                    .font(.system(size: 20, weight: .black, design: .serif))
                    .foregroundStyle(.white)
                if let sub = style.subtitle {
                    Text(sub).font(.callout).foregroundStyle(.white.opacity(0.85))
                }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .background(
            BannerRibbon()
                .fill(LinearGradient(colors: [style.color, style.color.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                .overlay(BannerRibbon().stroke(Bronze.gradient, lineWidth: 2))
                .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
        )
        .scaleEffect(x: unfurled ? 1 : 0.1, y: 1)
        .opacity(unfurled ? 1 : 0)
        .rotationEffect(.degrees(style.stamp && !unfurled ? -12 : 0))
        .scaleEffect(style.stamp && !unfurled ? 1.8 : 1)
        .onAppear {
            withAnimation(.spring(duration: 0.45, bounce: style.stamp ? 0.4 : 0.2)) { unfurled = true }
        }
    }

    struct Style {
        let icon: String
        let title: String
        let subtitle: String?
        let color: Color
        /// Slams down like a seal rather than unrolling.
        let stamp: Bool
    }

    static func style(_ kind: Moment.Kind, _ session: GameSession) -> Style {
        let engine = session.engine
        let state = session.state
        func place(_ t: TerritoryID?) -> String { t.flatMap { engine.map.territory($0)?.name } ?? "" }
        let mine = session.human.map { Palette.color($0, state) } ?? .blue
        switch kind {
        case let .captured(t):
            return Style(icon: "flag.fill", title: "\(place(t)) taken",
                         subtitle: "+\(engine.rules.victory.prestige.perTerritory) prestige", color: mine, stamp: false)
        case let .lost(t):
            return Style(icon: "flag.slash.fill", title: "\(place(t)) lost", subtitle: nil,
                         color: Color(red: 0.45, green: 0.08, blue: 0.08), stamp: false)
        case let .discovery(field, level):
            return Style(icon: "sparkles", title: engine.levelName(field, level) ?? "Discovery",
                         subtitle: KnowledgeView.benefit(field, level),
                         color: Color(red: 0.62, green: 0.45, blue: 0.12), stamp: false)
        case let .peace(other):
            return Style(icon: "dove.fill", title: "Peace with \(Palette.name(other, state))",
                         subtitle: "\(state.civs[other]?.ruler.name ?? ""): “\(RulerVoice.line(.peace, other, state))”",
                         color: Color(red: 0.15, green: 0.5, blue: 0.3), stamp: true)
        case let .war(other):
            return Style(icon: "flame.fill", title: "War with \(Palette.name(other, state))",
                         subtitle: "\(state.civs[other]?.ruler.name ?? ""): “\(RulerVoice.line(.war, other, state))”",
                         color: Color(red: 0.6, green: 0.1, blue: 0.08), stamp: true)
        case let .seaBattle(sea, won, other):
            let water = engine.map.sea(sea)?.name ?? sea
            return Style(icon: "sailboat.fill",
                         title: won ? "Victory at sea" : "Our fleet is beaten",
                         subtitle: won ? "\(Palette.name(other, state))'s ships driven from the \(water)"
                                       : "\(Palette.name(other, state)) now holds the \(water); its troops can land",
                         color: won ? Color(red: 0.1, green: 0.3, blue: 0.6) : Color(red: 0.35, green: 0.1, blue: 0.1), stamp: !won)
        case let .ally(other, joined):
            return Style(icon: joined ? "shield.lefthalf.filled" : "shield.slash",
                         title: joined ? "Alliance with \(Palette.name(other, state))" : "\(Palette.name(other, state)) abandons us",
                         subtitle: joined ? "\(state.civs[other]?.ruler.name ?? ""): “\(RulerVoice.line(.ally, other, state))”" : "The alliance is broken",
                         color: joined ? Color(red: 0.15, green: 0.3, blue: 0.6) : Color(red: 0.4, green: 0.1, blue: 0.1), stamp: true)
        case let .allyJoins(civ, against):
            return Style(icon: "flag.2.crossed.fill", title: "\(Palette.name(civ, state)) joins the war",
                         subtitle: "Our ally marches against \(Palette.name(against, state))", color: Palette.color(civ, state), stamp: true)
        case let .callToArms(from, against):
            return Style(icon: "megaphone.fill", title: "\(Palette.name(from, state)) calls us to arms",
                         subtitle: "Answer on the Rivals tab: fight \(Palette.name(against, state)), or break the alliance",
                         color: Palette.color(from, state), stamp: true)
        case let .attacked(by, t):
            return Style(icon: "flame.fill", title: "\(Palette.name(by, state)) attacks!",
                         subtitle: t.map { "Their army struck \(place($0))" }, color: Palette.color(by, state), stamp: true)
        case let .monument(id, civ):
            let m = engine.rules.monuments.list.first { $0.id == id }
            let ours = civ == session.human
            return Style(icon: GreatWorksList.symbol(id),
                         title: ours ? "The \(m?.name ?? id) is complete" : "\(Palette.name(civ, state)) raises the \(m?.name ?? id)",
                         subtitle: ours ? "+\(m?.prestige ?? 0) prestige. \(m?.effect ?? "")" : "Take the land to take its glory",
                         color: ours ? Color(red: 0.62, green: 0.45, blue: 0.12) : Palette.color(civ, state), stamp: ours)
        case let .monumentLost(id):
            let m = engine.rules.monuments.list.first { $0.id == id }
            return Style(icon: "hammer.circle", title: "Our \(m?.name ?? id) is abandoned",
                         subtitle: "A rival finished first; half the cost is recovered",
                         color: Color(red: 0.35, green: 0.22, blue: 0.12), stamp: false)
        case let .besieged(town, by):
            let ours = by == session.human
            return Style(icon: "shield.lefthalf.filled.slash", title: ours ? "Siege of \(place(town))" : "\(place(town)) besieged!",
                         subtitle: ours ? "Hold the camp: each round they starve and the walls weaken"
                                        : "\(Palette.name(by, state)) cuts it off. Drive them from the camp, or it starves",
                         color: ours ? mine : Color(red: 0.5, green: 0.1, blue: 0.08), stamp: !ours)
        case let .sacked(town, by, gold):
            let ours = by == session.human
            return Style(icon: "flame.fill", title: ours ? "\(place(town)) sacked!" : "\(place(town)) is sacked",
                         subtitle: ours ? "+\(gold) gold carried off, +\(engine.rules.sack.prestige) prestige"
                                        : "\(Palette.name(by, state)) carries off \(gold) gold",
                         color: ours ? Color(red: 0.62, green: 0.45, blue: 0.12) : Color(red: 0.45, green: 0.08, blue: 0.08), stamp: true)
        case let .splendour(began):
            let r = engine.rules.splendour
            return Style(icon: "sun.max.fill", title: began ? "An age of splendour" : "The age of splendour fades",
                         subtitle: began ? "\(r.rounds) rounds: building twice as fast, +\(r.goldPercent)% gold, faster growth" : "Build it again: a secure throne and a leading name",
                         color: Color(red: 0.62, green: 0.45, blue: 0.12), stamp: began)
        case .ironAge:
            return Style(icon: "hammer.fill", title: "The Iron Age dawns",
                         subtitle: "Iron needs no tin: every realm can now arm with it",
                         color: Color(red: 0.3, green: 0.28, blue: 0.3), stamp: true)
        case let .rebellion(general, lands, _, bribed):
            let names = lands.prefix(3).map(place).joined(separator: ", ") + (lands.count > 3 ? " and more" : "")
            return Style(icon: "flame.fill", title: "\(general) rebels!",
                         subtitle: (bribed ? "Your gold bought only a season. " : "")
                            + (lands.isEmpty ? "His army turns on you" : "He seizes \(names)"),
                         color: Color(red: 0.55, green: 0.08, blue: 0.08), stamp: true)
        case let .unpaid(n):
            return Style(icon: "dollarsign.circle", title: "\(n) unpaid soldier\(n == 1 ? "" : "s") went home",
                         subtitle: "An army beyond what your people can spare costs full pay",
                         color: Color(red: 0.5, green: 0.35, blue: 0.08), stamp: false)
        case let .disaster(kind, t):
            let (icon, title): (String, String) = switch kind {
            case .famine: ("leaf.fill", "Famine in \(place(t))")
            case .drought: ("sun.max.fill", "Drought")
            case .flood: ("water.waves", "Floods in \(place(t))")
            case .plague: ("allergens", "Plague")
            case .earthquake: ("waveform.path.ecg", "Earthquake in \(place(t))")
            case .seaPeoples: ("sailboat.fill", "Sea Peoples land in \(place(t))")
            case .barbarians: ("figure.fencing", "Barbarians at \(place(t))")
            case .revolt: ("hand.raised.fill", "\(place(t)) revolts")
            default: ("exclamationmark.triangle.fill", "Disaster")
            }
            return Style(icon: icon, title: title, subtitle: nil, color: Color(red: 0.35, green: 0.22, blue: 0.12), stamp: false)
        }
    }

    /// The screen effect for a moment: a shake, and a colour wash over everything.
    static func effect(_ kind: Moment.Kind) -> (shake: Bool, tint: Color?) {
        switch kind {
        case .disaster(.earthquake, _): (true, Color(red: 0.4, green: 0.3, blue: 0.2))
        case .disaster(.famine, _), .disaster(.drought, _): (false, Color(red: 0.75, green: 0.55, blue: 0.2))
        case .disaster(.seaPeoples, _), .disaster(.flood, _): (true, Color(red: 0.1, green: 0.3, blue: 0.7))
        case .disaster(.plague, _): (false, Color(red: 0.35, green: 0.5, blue: 0.2))
        case .disaster, .lost: (true, Color(red: 0.5, green: 0.05, blue: 0.05))
        case .war, .attacked: (true, nil)
        case .rebellion: (true, Color(red: 0.5, green: 0.05, blue: 0.05))
        case .seaBattle(_, false, _): (true, Color(red: 0.1, green: 0.2, blue: 0.5))
        default: (false, nil)
        }
    }
}

/// A ribbon banner with notched ends.
struct BannerRibbon: Shape {
    func path(in r: CGRect) -> Path {
        let n: CGFloat = 14
        var p = Path()
        p.move(to: CGPoint(x: r.minX - n, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX + n, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX + n / 3, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX + n, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX - n, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX - n / 3, y: r.midY))
        p.closeSubpath()
        return p
    }
}

/// Shakes its content when `trigger` changes.
struct Shake: GeometryEffect {
    var amount: CGFloat = 8
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: amount * sin(animatableData * .pi * 6), y: 0))
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
