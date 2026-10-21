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
                // The courts of the age: tap a ruler to visit.
                HStack(spacing: 14) {
                    ForEach(rivals, id: \.self) { other in
                        Button { session.audience = Audience(civ: other, reason: .visit) } label: {
                            VStack(spacing: 3) {
                                RulerPortrait(civ: other, state: state, size: 46)
                                Text(state.civs[other]?.ruler.name ?? "").font(.caption2.bold()).lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 8)
                Text("Tap a ruler to visit their court.").font(.caption2).foregroundStyle(.secondary)
                // Deals other courts have put to us: answered at their court.
                ForEach(state.proposals.filter { $0.to == human }, id: \.self) { p in
                    HStack {
                        Label(DealText.describe(p.deal, from: p.from, state, engine), systemImage: "scroll.fill")
                            .font(.caption.bold()).fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("Answer at court") { session.audience = Audience(civ: p.from, reason: .proposal) }
                            .buttonStyle(.borderedProminent).tint(.orange).controlSize(.small)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.12)))
                }
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
                ForEach(Array(state.submissionDemands.filter { $0.to == human }).sorted { $0.from < $1.from }, id: \.self) { d in
                    VStack(alignment: .leading, spacing: 6) {
                        Label("\(Palette.name(d.from, state)) demands that you submit", systemImage: "link")
                            .font(.callout.bold())
                        Text("As their vassal: a peace neither may break, \(engine.rules.submission.tributePercent)% of your gold income to them each turn, no alliances and no war on their allies. You go free once your army outgrows theirs. Unanswered by their next turn, it lapses.")
                            .font(.caption2).foregroundStyle(.secondary)
                        HStack {
                            Button("Submit") { session.order(.answerSubmission(from: d.from, accept: true)) }
                                .buttonStyle(.borderedProminent).tint(.orange).controlSize(.small)
                            Button("Refuse") { session.order(.answerSubmission(from: d.from, accept: false)) }
                                .buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.12)))
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
                    .fixedSize()
                if let tie = tie(human, other) {
                    Label(tie, systemImage: "link")
                        .font(.caption.bold())
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2), in: Capsule())
                        .foregroundStyle(.orange)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer()
            }
            action(human, other).frame(maxWidth: .infinity, alignment: .trailing)
            HStack(spacing: 12) {
                let lands = state.territories(of: other).count, troops = state.totalUnits(of: other).total
                fact("map", "\(lands) land\(lands == 1 ? "" : "s")")
                fact("shield.lefthalf.filled", "\(troops) troop\(troops == 1 ? "" : "s")")
                fact("crown", "\(engine.prestige(of: other, in: state)) prestige")
            }
            let mood = attitude(human, other, trading: route != nil)
            Label(mood.text, systemImage: mood.icon)
                .font(.caption.bold()).foregroundStyle(mood.color)
            bonds(human, other)
            HStack(alignment: .top, spacing: 10) {
                Button { session.audience = Audience(civ: other, reason: .visit) } label: {
                    RulerPortrait(civ: other, state: state, size: 38).padding(.top, 6)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Visit \(cs.ruler.name)")
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

    /// How their court regards ours, what binds us, and what we can propose.
    @ViewBuilder private func bonds(_ human: CivilizationID, _ other: CivilizationID) -> some View {
        let r = engine.regard(of: other, toward: human, in: state)
        let word = DealText.regard(r)
        HStack(spacing: 8) {
            Label("They regard you: \(word.text) (\(r > 0 ? "+" : "")\(r))", systemImage: "heart.text.square")
                .font(.caption.bold()).foregroundStyle(word.color)
            Spacer(minLength: 0)
            // Gifts, marriages, trade and the rest are proposed at their court.
            Button { session.audience = Audience(civ: other, reason: .visit) } label: {
                Label("Visit court", systemImage: "building.columns").font(.caption.bold())
            }
            .buttonStyle(.bordered).controlSize(.small)
        }
        let ties = bondList(human, other)
        if !ties.isEmpty {
            Text(ties.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if engine.grantsAccess(human, to: other, in: state) {
            Button("Revoke their leave to march through your land") { session.order(.revokeAccess(from: other)) }
                .font(.caption2).buttonStyle(.bordered).controlSize(.mini)
        }
    }

    private func bondList(_ human: CivilizationID, _ other: CivilizationID) -> [String] {
        var ties: [String] = []
        if engine.married(human, other, in: state) { ties.append("Married houses") }
        if let until = engine.pact(human, other, in: state) { ties.append("Pact until round \(until)") }
        if engine.grantsAccess(other, to: human, in: state) { ties.append("You may march through their land") }
        if engine.grantsAccess(human, to: other, in: state) { ties.append("They may march through yours") }
        for b in state.bargains where (b.a == human && b.b == other) || (b.a == other && b.b == human) {
            let (gives, gets) = b.a == human ? (b.aGives, b.bGives) : (b.bGives, b.aGives)
            ties.append("Bargain: your \(DealText.goods(gives)) for their \(DealText.goods(gets)) a turn, until round \(b.until)")
        }
        for e in state.embargoes where e.until >= state.turn && (e.by == other || e.against == other) {
            ties.append(e.by == other ? "Embargo on \(Palette.name(e.against, state))" : "Embargoed by \(Palette.name(e.by, state))")
        }
        if engine.casusBelli(human, against: other, in: state) { ties.append("You have just cause for war") }
        if engine.casusBelli(other, against: human, in: state) { ties.append("They have just cause for war on you") }
        return ties
    }

    /// How vassalage ties them: to you, or to someone else.
    private func tie(_ human: CivilizationID, _ other: CivilizationID) -> String? {
        if let lord = engine.liege(of: other, in: state) { return lord == human ? "Your vassal" : "Vassal of \(Palette.name(lord, state))" }
        if engine.liege(of: human, in: state) == other { return "Your overlord" }
        let vassals = engine.vassalEmpires(of: other, in: state)
        return vassals.isEmpty ? nil : "Overlord of \(vassals.map { Palette.name($0, state) }.joined(separator: ", "))"
    }

    /// The alliance row: offer, answer an offer, call the ally to a war, or leave.
    @ViewBuilder private func alliance(_ human: CivilizationID, _ other: CivilizationID) -> some View {
        let allied = engine.allied(human, other, in: state)
        let s = engine.rules.submission
        if engine.liege(of: other, in: state) == human {
            Text("They pay you \(s.tributePercent)% of their gold income (\(state.vassalage[other]?.lastTribute ?? 0) last turn), keep the peace with you and your allies, and add \(s.prestige) to your prestige. They go free if their army outgrows yours.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        } else if engine.liege(of: human, in: state) == other {
            Text("You pay them \(s.tributePercent)% of your gold income, may not war on them or their allies, and keep no alliances. You go free once your army outgrows theirs.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        } else if allied {
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
        } else if engine.liege(of: human, in: state) != nil || engine.liege(of: other, in: state) != nil {
            EmptyView()
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
            if state.atPeace(human, other), !engine.mayDeclareWar(human, on: other, in: state) {
                Text(engine.bound(human, other, in: state) ? "Bound by vassalage" : "Your overlord's ally")
                    .font(.caption).foregroundStyle(.secondary)
            } else if state.atPeace(human, other) {
                Button("Declare war") { warOn = other }
                    .buttonStyle(.bordered).tint(.red).controlSize(.small).fixedSize()
                Text("−\(-engine.rules.government.legitimacy.brokePeace) legitimacy, ends trade").font(.caption2).foregroundStyle(.secondary)
            } else if state.peaceOffers.contains(PeaceOffer(from: other, to: human)) {
                HStack(spacing: 6) {
                    Button("Decline") { session.order(.declinePeace(from: other)) }
                        .buttonStyle(.bordered).controlSize(.small).fixedSize()
                    Button("Accept peace") { session.order(.acceptPeace(from: other)) }
                        .buttonStyle(.borderedProminent).tint(.green).controlSize(.small).fixedSize()
                }
                Text("If declined, they won't ask for \(engine.rules.alliances.rebuffedRounds) rounds")
                    .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            } else if state.peaceOffers.contains(PeaceOffer(from: human, to: other)) {
                Text("Peace offered").font(.caption).foregroundStyle(.secondary)
            } else {
                Button("Offer peace") { session.order(.offerPeace(to: other)) }
                    .buttonStyle(.bordered).controlSize(.small).fixedSize()
                Text("Free · if they accept, trade opens").font(.caption2).foregroundStyle(.secondary)
            }
            if !state.atPeace(human, other), engine.liege(of: human, in: state) == nil, engine.liege(of: other, in: state) == nil {
                let likely = engine.wouldSubmit(other, to: human, in: state)
                Button("Demand submission") { session.order(.demandSubmission(of: other)) }
                    .buttonStyle(.bordered).tint(.orange).controlSize(.small).fixedSize()
                Text(likely ? "They're beaten: they'd likely bow"
                            : "Only if you hold their capital or they're under \(engine.rules.submission.acceptStrengthPercent)% of your strength")
                    .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
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
