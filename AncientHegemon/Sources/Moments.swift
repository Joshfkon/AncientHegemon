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
                         subtitle: KnowledgeView.effect(field, level).capitalizedFirst,
                         color: Color(red: 0.62, green: 0.45, blue: 0.12), stamp: false)
        case let .peace(other):
            return Style(icon: "dove.fill", title: "Peace with \(Palette.name(other, state))",
                         subtitle: "Trade can flow", color: Color(red: 0.15, green: 0.5, blue: 0.3), stamp: true)
        case let .war(other):
            return Style(icon: "flame.fill", title: "War with \(Palette.name(other, state))",
                         subtitle: nil, color: Color(red: 0.6, green: 0.1, blue: 0.08), stamp: true)
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
        case .war: (true, nil)
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
