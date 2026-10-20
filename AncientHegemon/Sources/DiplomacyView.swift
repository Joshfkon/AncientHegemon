import HegemonCore
import SwiftUI

/// Every rival empire as the player's court sees it: war or peace, what passes between you in
/// trade, how strong they are, whether they border you, and what you can do about it.
struct DiplomacyView: View {
    let session: GameSession
    /// A declaration of war waiting for confirmation: breaking a peace costs legitimacy.
    @State private var warOn: CivilizationID?

    private var engine: Engine { session.engine }
    private var state: GameState { session.state }

    var body: some View {
        if let human = session.human {
            let rivals = engine.standings(in: state).filter { $0 != human && !(state.civs[$0]?.eliminated ?? true) }
            VStack(alignment: .leading, spacing: 10) {
                Text("Diplomacy").font(.subheadline.bold())
                ForEach(Array(state.warRequests.filter { $0.to == human }).sorted { $0.from < $1.from }, id: \.self) { r in
                    VStack(alignment: .leading, spacing: 6) {
                        Label("\(Palette.name(r.from, state)) calls you to war against \(Palette.name(r.against, state))",
                              systemImage: "megaphone.fill").font(.callout.bold())
                        Text("Your alliance promised it. Refusing breaks the alliance and costs \(engine.rules.alliances.betrayalLegitimacy) legitimacy; ignoring it until they move again counts as refusing.")
                            .font(.caption2).foregroundStyle(.secondary)
                        HStack {
                            Button("Join the war") { session.order(.answerCallToWar(from: r.from, against: r.against, join: true)) }
                                .buttonStyle(.borderedProminent).tint(.red).controlSize(.small)
                            Button("Refuse") { session.order(.answerCallToWar(from: r.from, against: r.against, join: false)) }
                                .buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.red.opacity(0.12)))
                }
                if rivals.isEmpty {
                    Text("No rivals remain.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(rivals, id: \.self) { other in card(human, other) }
                Text("At peace, empires that can reach each other by land or open sea trade automatically. "
                     + "Breaking a peace costs \(-engine.rules.government.legitimacy.brokePeace) legitimacy.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .confirmationDialog("Break the peace with \(warOn.map { Palette.name($0, state) } ?? "")?",
                                isPresented: Binding(get: { warOn != nil }, set: { if !$0 { warOn = nil } }),
                                titleVisibility: .visible) {
                Button("Declare war", role: .destructive) {
                    if let warOn { session.order(.declareWar(on: warOn)) }
                    warOn = nil
                }
            } message: {
                Text("Breaking a peace costs \(-engine.rules.government.legitimacy.brokePeace) legitimacy and ends any trade route between you.")
            }
        }
    }

    /// Which of the ruler's voices fits their court's mood.
    private func voiceMoment(_ mood: String) -> RulerVoice.Moment {
        if mood.hasPrefix("They want peace") { return .peace }
        if mood.hasPrefix("They think we are weak") { return .covets }
        if mood.hasPrefix("They fear") { return .fears }
        if mood.hasPrefix("Good friends") { return .friends }
        if mood.hasPrefix("Awed") { return .awed }
        if mood.hasPrefix("Hostile") { return .hostile }
        return .cordial
    }

    /// How their court regards us, read from what moves the AI: relative strength, a shared
    /// border, trade, offers on the table and our court's splendour.
    private func attitude(_ human: CivilizationID, _ other: CivilizationID, trading: Bool)
        -> (text: String, icon: String, color: Color) {
        func strength(_ c: CivilizationID) -> Int {
            state.totalUnits(of: c).total + state.fleets(of: c).reduce(0) { $0 + $1.cargo.total }
        }
        let edge = Double(strength(other)) / Double(max(1, strength(human)))
        let border = state.territories(of: other).contains { t in
            engine.map.landNeighbors(of: t).contains { state.owner(of: $0) == human }
        }
        let peace = state.atPeace(human, other)
        let awed = engine.magnificence(of: human, in: state) >= engine.rules.throneRoom.peaceMagnificence
        if state.peaceOffers.contains(PeaceOffer(from: other, to: human)) {
            return ("They want peace", "dove.fill", .green)
        }
        if border && edge >= 1.3 {
            return (peace ? "They think we are weak, and covet our land" : "They think we are weak", "exclamationmark.triangle.fill", .red)
        }
        if edge < 0.75 { return ("They fear our armies", "shield.fill", .blue) }
        if peace && trading { return ("Good friends: trade binds us", "heart.fill", .green) }
        if awed { return ("Awed by our court", "sparkles", .orange) }
        if peace { return (border ? "Wary neighbours" : "Distant but cordial", "hand.raised.fill", .secondary) }
        return (border ? "Hostile, at our border" : "Hostile, but far away", "flame.fill", .orange)
    }

    private func card(_ human: CivilizationID, _ other: CivilizationID) -> some View {
        let peace = state.atPeace(human, other)
        let cs = state.civs[other]!
        let route = engine.tradeRoute(between: human, and: other, in: state)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(Palette.color(other, state)).frame(width: 10, height: 10)
                Text(Palette.name(other, state)).font(.callout.bold()).lineLimit(1).minimumScaleFactor(0.8)
                Text(peace ? "Peace" : "War")
                    .font(.caption.bold())
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background((peace ? Color.green : Color.red).opacity(0.2), in: Capsule())
                    .foregroundStyle(peace ? .green : .red)
                Spacer()
                action(human, other)
            }
            HStack(spacing: 12) {
                let lands = state.territories(of: other).count, troops = state.totalUnits(of: other).total
                fact("map", "\(lands) land\(lands == 1 ? "" : "s")")
                fact("shield.lefthalf.filled", "\(troops) troop\(troops == 1 ? "" : "s")")
                fact("crown", "\(engine.prestige(of: other, in: state)) prestige")
            }
            let mood = attitude(human, other, trading: route != nil)
            Label(mood.text, systemImage: mood.icon)
                .font(.caption.bold()).foregroundStyle(mood.color)
            HStack(alignment: .top, spacing: 10) {
                RulerPortrait(civ: other, state: state, size: 38).padding(.top, 6)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(cs.ruler.name), \(RulerVoice.temperament(other))").font(.caption.bold())
                    Text("“\(RulerVoice.line(voiceMoment(mood.text), other, state))”")
                        .font(.system(.callout, design: .serif).italic())
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(legitimacyWord(cs.legitimacy).capitalizedFirst) on the throne.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Text(neighborhood(human, other)).font(.caption).foregroundStyle(.secondary)
            alliance(human, other)
            if let answer = session.answers[other], answer.round == state.turn {
                Label(answer.text, systemImage: answer.good ? "checkmark.seal.fill" : "xmark.seal.fill")
                    .font(.caption.bold())
                    .foregroundStyle(answer.good ? Color.green : Color.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill((answer.good ? Color.green : Color.red).opacity(0.12)))
            }
            if let route {
                let flows = engine.goods(along: route, in: state)
                HStack(spacing: 4) {
                    Image(systemName: "arrow.left.arrow.right").font(.caption)
                    Text("Trading · you get \(goods(flows[human])) · they get \(goods(flows[other]))")
                        .font(.caption)
                }
                if !route.tolls.isEmpty {
                    Text("Tolls paid to \(route.tolls.map { Palette.name($0, state) }.joined(separator: ", ")) at the straits.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } else if peace {
                Text("No trade route: no open way between your capitals.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
    }

    /// The alliance row: offer, answer an offer, call the ally to a war, or leave.
    @ViewBuilder private func alliance(_ human: CivilizationID, _ other: CivilizationID) -> some View {
        let allied = engine.allied(human, other, in: state)
        if allied {
            VStack(alignment: .leading, spacing: 6) {
                Label("Allies: each fights whoever attacks the other", systemImage: "shield.lefthalf.filled")
                    .font(.caption.bold()).foregroundStyle(.blue)
                let enemies = state.players.filter { e in
                    e != human && e != other && !(state.civs[e]?.eliminated ?? true) && state.atWar(human, e) && state.atPeace(other, e)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(enemies, id: \.self) { e in
                            Button("Ask to fight \(Palette.name(e, state))") {
                                session.order(.callToWar(ally: other, against: e))
                            }
                            .buttonStyle(.bordered).controlSize(.small)
                            .disabled(state.calledToWar.contains(other))
                        }
                        Button("Leave alliance") { session.order(.leaveAlliance(with: other)) }
                            .buttonStyle(.bordered).tint(.orange).controlSize(.small)
                    }
                }
                if !enemies.isEmpty {
                    Text("They'll join a war if the enemy isn't more than twice their strength. Leaving costs \(engine.rules.alliances.betrayalLegitimacy) legitimacy.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        } else if state.allianceOffers.contains(PeaceOffer(from: other, to: human)) {
            HStack {
                Text("\(Palette.name(other, state)) proposes an alliance.").font(.caption.bold())
                Spacer()
                Button("Ally") { session.order(.acceptAlliance(from: other)) }
                    .buttonStyle(.borderedProminent).tint(.blue).controlSize(.small)
            }
        } else if state.atPeace(human, other) {
            let likely = engine.wouldAlly(other, with: human, in: state)
            HStack {
                Text(likely ? "We share an enemy: they would likely ally." : "No common enemy worries them yet.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Propose alliance") { session.order(.offerAlliance(to: other)) }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
    }

    @ViewBuilder private func action(_ human: CivilizationID, _ other: CivilizationID) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            if state.atPeace(human, other) {
                Button("Declare war") { warOn = other }
                    .buttonStyle(.bordered).tint(.red).controlSize(.small).fixedSize()
                Text("−\(-engine.rules.government.legitimacy.brokePeace) legitimacy, ends trade").font(.caption2).foregroundStyle(.secondary)
            } else if state.peaceOffers.contains(PeaceOffer(from: other, to: human)) {
                Button("Accept peace") { session.order(.acceptPeace(from: other)) }
                    .buttonStyle(.borderedProminent).tint(.green).controlSize(.small).fixedSize()
                Text("Free · trade opens, merchants see their capital").font(.caption2).foregroundStyle(.secondary)
            } else if state.peaceOffers.contains(PeaceOffer(from: human, to: other)) {
                Text("Peace offered").font(.caption).foregroundStyle(.secondary)
            } else {
                Button("Offer peace") { session.order(.offerPeace(to: other)) }
                    .buttonStyle(.bordered).controlSize(.small).fixedSize()
                Text("Free · if they accept, trade opens").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func fact(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol).font(.caption).labelStyle(.titleAndIcon)
    }

    private func goods(_ flow: [Resource: Int]?) -> String {
        let items = Resource.allCases.filter { (flow?[$0] ?? 0) > 0 }.map(MapView.glyph)
        return items.isEmpty ? "nothing" : items.joined(separator: " ")
    }

    private func legitimacyWord(_ l: Int) -> String {
        switch l {
        case 70...: "secure"
        case 45..<70: "steady"
        case 25..<45: "shaky"
        default: "tottering"
        }
    }

    /// Whether their land touches ours, and where.
    private func neighborhood(_ human: CivilizationID, _ other: CivilizationID) -> String {
        let mine = Set(state.territories(of: human))
        let borders = state.territories(of: other).filter { t in engine.map.landNeighbors(of: t).contains(where: mine.contains) }
        guard !borders.isEmpty else { return "No shared border." }
        let names = borders.prefix(3).compactMap { engine.map.territory($0)?.name }
        return "Borders you at " + names.joined(separator: ", ") + (borders.count > 3 ? " and more." : ".")
    }
}
