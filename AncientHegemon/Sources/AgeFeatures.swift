import HegemonCore
import SwiftUI

/// Names and symbols for the masters the court can fund (the choice itself is on the knowledge tree).
enum Patrons {
    static func patrons(_ f: KnowledgeField) -> String {
        switch f {
        case .agriculture: "Farmers"
        case .metallurgy: "Smiths"
        case .horsemanship: "Horse breeders"
        case .seafaring: "Shipwrights"
        case .construction: "Builders"
        case .warfare: "Drill masters"
        case .administration: "Scribes"
        }
    }

    static func symbol(_ f: KnowledgeField) -> String {
        switch f {
        case .agriculture: "leaf.fill"
        case .metallurgy: "hammer.fill"
        case .horsemanship: "figure.equestrian.sports"
        case .seafaring: "sailboat.fill"
        case .construction: "building.columns.fill"
        case .warfare: "shield.lefthalf.filled"
        case .administration: "scroll.fill"
        }
    }
}

/// The court's dilemma, put to the player as a card with two answers.
struct DecisionCard: View {
    let session: GameSession
    let kind: DecisionKind

    private var engine: Engine { session.engine }
    private var state: GameState { session.state }

    var body: some View {
        let (icon, title, text, yes, no) = words
        let (gain, loss) = consequences
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.title2).foregroundStyle(Bronze.gradient)
                CardTitle(text: title)
            }
            Text(text).font(.callout).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Button(no) { answer(false) }
                        .font(.callout.bold()).foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .overlay(Capsule().stroke(.white.opacity(0.4)))
                    Text(loss).font(.caption2.bold()).foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Button(yes) { answer(true) }.buttonStyle(BronzeButtonStyle())
                    Text(gain).font(.caption2.bold()).foregroundStyle(Bronze.gradient)
                }
            }
        }
        .padding(16)
        .frame(width: 460)
        .woodPanel(RoundedRectangle(cornerRadius: 16), border: 2)
    }

    private func answer(_ accept: Bool) {
        if session.order(.decide(accept: accept)) {
            SoundBoard.shared.play(accept ? .coins : .click, volume: 0.6)
        }
    }

    /// What each answer costs and brings, spelled out under its button.
    private var consequences: (yes: String, no: String) {
        let d = engine.rules.decisions
        switch kind {
        case let .famine(_, grain):
            return ("−\(grain) grain · +\(d.famineLegitimacy) legitimacy", "−\(d.famineLegitimacy) legitimacy · −1 person there")
        case let .honours(_, gold):
            return ("−\(gold) gold · +\(engine.rules.government.honorLoyalty) loyalty", "−\(d.honoursSnubLoyalty) loyalty")
        case let .mercenaries(warriors, gold):
            return ("−\(gold) gold · +\(warriors) blooded infantry", "Nothing lost")
        }
    }

    private var words: (String, String, String, String, String) {
        func place(_ t: TerritoryID) -> String { engine.map.territory(t)?.name ?? t }
        switch kind {
        case let .famine(t, grain):
            let granary = state.civs[session.human ?? ""]?.granary ?? 0
            return ("leaf.fill", "Famine in \(place(t))",
                    "The fields have failed and the people are hungry. Open the royal granaries (\(grain) of your \(granary) grain) and they will bless your name; keep them shut and some will die, and the land will remember.",
                    "Open the granaries", "Keep them shut")
        case let .honours(id, gold):
            let g = state.generals[id]
            return ("star.fill", "\(g?.name ?? "A general") demands honours",
                    "Proud after his campaigns, \(g?.name ?? "he") asks for gifts and a place at court: \(gold) gold. Refuse, and his loyalty will sour; generals who sulk have been known to seize thrones.",
                    "Honour him (\(gold) gold)", "Refuse")
        case let .mercenaries(warriors, gold):
            return ("sailboat.fill", "Sea raiders offer their swords",
                    "A chieftain of the Sea Peoples, tired of raiding, offers \(warriors) hardened warriors for \(gold) gold. They would serve at your capital. Blooded men, ready to march this turn; such offers don't come often.",
                    "Hire them (\(gold) gold)", "Send them away")
        }
    }
}

/// The age's great works: who holds which, who is building what, and (in your land) what
/// you could raise.
struct GreatWorksList: View {
    let session: GameSession
    /// Offer to build in this territory (the city view).
    var territory: TerritoryID?

    private var engine: Engine { session.engine }
    private var state: GameState { session.state }

    var body: some View {
        let list = engine.rules.monuments.list.filter { m in
            guard let territory else { return true }
            return state.monuments[m.id] == territory || state.monumentSites[territory]?.id == m.id
                || engine.canRaise(m.id, in: territory, state)
        }
        VStack(alignment: .leading, spacing: 8) {
            if list.isEmpty {
                Text("No great work can rise here. The pyramid and ziggurat need a river valley, the library and lighthouse a coast, the Lion Gate hills.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(list) { m in row(m) }
        }
    }

    @ViewBuilder private func row(_ m: Monument) -> some View {
        let holder = engine.holder(of: m.id, in: state)
        let sites = state.monumentSites.filter { $0.value.id == m.id }
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: Self.symbol(m.id)).font(.title3).frame(width: 26)
                .foregroundStyle(holder.map { Palette.color($0, state) } ?? Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(m.name).font(.callout.bold())
                    Spacer()
                    Text("+\(m.prestige) prestige").font(.caption.monospacedDigit()).foregroundStyle(.orange)
                }
                Text(m.effect).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let holder, let t = state.monuments[m.id] {
                    Text("Stands in \(engine.map.territory(t)?.name ?? t), held by \(Palette.name(holder, state)). Take the land to take it.")
                        .font(.caption2.bold()).foregroundStyle(Palette.color(holder, state))
                } else {
                    if !sites.isEmpty {
                        Text("Rising: " + sites.sorted { $0.key < $1.key }.map { "\(Palette.name(state.owner(of: $0.key) ?? "", state)) in \(engine.map.territory($0.key)?.name ?? $0.key), \($0.value.turnsLeft) turns left" }.joined(separator: "; "))
                            .font(.caption2.bold())
                    }
                    Text("Needs \(Self.ground(m.needs)) · \(m.gold) gold" + (m.stone > 0 ? " · \(m.stone) stone" : "") + (m.timber > 0 ? " · \(m.timber) timber" : "") + " · \(m.turns) turns")
                        .font(.caption2).foregroundStyle(.secondary)
                    if let territory, session.isHumanTurn, engine.canRaise(m.id, in: territory, state),
                       state.owner(of: territory) == session.human {
                        Button("Begin the \(m.name)") {
                            if session.order(.buildMonument(territory: territory, monument: m.id)) {
                                SoundBoard.shared.play(.horn, volume: 0.6)
                            }
                        }
                        .buttonStyle(BronzeButtonStyle())
                    }
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.5)))
    }

    static func symbol(_ id: MonumentID) -> String {
        switch id {
        case "pyramid": "triangle.fill"
        case "ziggurat": "square.stack.3d.up.fill"
        case "lionGate": "door.left.hand.closed"
        case "library": "books.vertical.fill"
        case "lighthouse": "light.beacon.max.fill"
        default: "building.columns.fill"
        }
    }

    static func ground(_ needs: String) -> String {
        switch needs {
        case "river_valley": "a river valley"
        case "coastal": "a coast"
        case "hills": "hills or mountains"
        default: "any land"
        }
    }
}
