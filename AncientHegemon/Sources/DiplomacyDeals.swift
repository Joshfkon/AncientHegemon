import HegemonCore
import SwiftUI

/// Words for the courts' dealings: deals, goods and regard.
enum DealText {
    static func goods(_ g: Goods) -> String {
        guard let r = g.resource, r != .gold else { return "\(g.amount) gold" }
        return "\(g.amount) \(name(r))"
    }

    static func name(_ r: Resource) -> String {
        switch r {
        case .luxuries: "luxuries"
        default: r.rawValue
        }
    }

    /// "Greece offers a royal marriage", from the recipient's side ("you").
    static func describe(_ deal: Deal, from: CivilizationID, _ state: GameState, _ engine: Engine) -> String {
        let who = Palette.name(from, state)
        let rounds = engine.rules.diplomacy
        switch deal {
        case let .gift(g): return "\(who) sends a gift of \(goods(g))"
        case .marriage: return "\(who) offers a royal marriage between your houses"
        case let .bargain(give, get):
            return "\(who) offers \(goods(give)) a turn for \(goods(get)) a turn, for \(rounds.bargainRounds) rounds"
        case let .tribute(gold): return "\(who) demands \(gold) gold in tribute"
        case .pact: return "\(who) proposes a pact of non-aggression for \(rounds.pactRounds) rounds"
        case .access: return "\(who) asks leave to march through and camp in your land"
        case let .embargo(against):
            return "\(who) asks you to stop trading with \(Palette.name(against, state)) for \(rounds.embargoRounds) rounds"
        }
    }

    /// What answering means, for the inbox.
    static func consequence(_ deal: Deal, _ engine: Engine) -> String {
        let d = engine.rules.diplomacy
        switch deal {
        case .gift: return ""
        case .marriage: return "Kin regard each other warmly and rarely make war; +\(d.marriageLegitimacy) legitimacy for both thrones."
        case .bargain: return "Kept each turn while both can; a bargain broken is resented."
        case .tribute: return "Pay, and they'll resent you less than a refusal would cost: refused, they have just cause for war."
        case .pact: return "Breaking a pact costs \(-d.pactBrokenLegitimacy) legitimacy more than breaking a peace, and every court remembers it."
        case .access: return "Their armies may cross and stand in your land, but not where yours stand. You can revoke it."
        case .embargo: return "Your trade route with them closes; they will resent it."
        }
    }

    static func regard(_ r: Int) -> (text: String, color: Color) {
        switch r {
        case 60...: ("devoted to you", .green)
        case 30..<60: ("friendly", .green)
        case 10..<30: ("warm", .green.opacity(0.8))
        case -10..<10: ("indifferent", .secondary)
        case -30 ..< -10: ("cool", .orange)
        case -60 ..< -30: ("hostile", .red)
        default: ("bitter enemies", .red)
        }
    }
}

/// A deal another court put to the player, with Accept and Decline.
struct ProposalCard: View {
    let session: GameSession
    let proposal: Proposal
    /// Told how the player answered (in an audience, the ruler reacts).
    var answered: ((Bool) -> Void)? = nil

    var body: some View {
        let engine = session.engine
        VStack(alignment: .leading, spacing: 6) {
            Label(DealText.describe(proposal.deal, from: proposal.from, session.state, engine), systemImage: "scroll.fill")
                .font(.callout.bold()).fixedSize(horizontal: false, vertical: true)
            let why = DealText.consequence(proposal.deal, engine)
            if !why.isEmpty {
                Text(why).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button(isDemand ? "Pay" : "Accept") { answer(true) }
                    .buttonStyle(.borderedProminent).tint(isDemand ? .orange : .green).controlSize(.small)
                Button(isDemand ? "Refuse" : "Decline") { answer(false) }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.12)))
    }

    private var isDemand: Bool { if case .tribute = proposal.deal { true } else { false } }

    private func answer(_ yes: Bool) {
        if session.order(.answer(from: proposal.from, proposal.deal, accept: yes)) {
            yes ? SoundBoard.shared.play(.coins, volume: 0.5) : Feedback.select()
            answered?(yes)
        }
    }
}

/// How a rival ruler answers a deal to your face.
enum DealReply {
    static func line(_ deal: Deal, accepted: Bool, turn: Int) -> String {
        func pick(_ lines: [String]) -> String { lines[abs(turn) % lines.count] }
        guard accepted else {
            switch deal {
            case .tribute: return pick(["You will have nothing from us but iron.", "Come and take it, if you can."])
            case .marriage: return pick(["My house will not join yours. Not yet.", "No daughter of mine goes to your court."])
            case .bargain: return pick(["Not for that price.", "You ask too much and offer too little."])
            case .pact: return pick(["I will not tie my hands.", "Swear oaths to someone else."])
            case .access: return pick(["Keep your soldiers on your own roads.", "No foreign army camps in my land."])
            case .embargo: return pick(["Our merchants trade where they please.", "Your quarrels are not ours."])
            case .gift: return "We accept your gift."
            }
        }
        switch deal {
        case .gift: return pick(["Your generosity is noted, and will be remembered.", "A fine gift. Our friendship grows."])
        case .marriage: return pick(["So be it: our houses are one.", "Let the wedding feast begin."])
        case .bargain: return pick(["Agreed. Let the wagons roll.", "A fair bargain. Our scribes will record it."])
        case .tribute: return pick(["Take it, then. We will remember this.", "Here is your gold. Enjoy it while you can."])
        case .pact: return pick(["Let no spear cross our border while this oath stands.", "Sworn, before the gods."])
        case .access: return pick(["Your armies may pass. See that they keep to the roads.", "Pass, friend."])
        case .embargo: return pick(["Their ships will find our harbours closed.", "Done. They will feel it."])
        }
    }
}

/// Everything a player can put to a rival court, in the audience: gifts, bonds, demands,
/// embargoes and a trade of any goods for any goods. Each shows how they'd likely answer.
struct AudienceDeals: View {
    let session: GameSession
    let human: CivilizationID
    let civ: CivilizationID
    /// Their answer, to show and speak.
    let reply: (Deal, Bool) -> Void

    @State private var giveKind: Resource? = nil
    @State private var giveAmount = 3
    @State private var getKind: Resource? = .tin
    @State private var getAmount = 1

    private var engine: Engine { session.engine }
    private var state: GameState { session.state }
    private static let goods: [Resource?] = [nil, .grain, .copper, .tin, .horses, .timber, .stone, .iron, .wine, .luxuries]

    var body: some View {
        let peace = state.atPeace(human, civ)
        let gold = state.civs[human]?.gold ?? 0
        VStack(alignment: .leading, spacing: 10) {
            heading("Gifts")
            HStack(spacing: 8) {
                ForEach([5, 10, 20], id: \.self) { n in
                    Button("\(n) gold") { propose(.gift(.gold(n))) }
                        .buttonStyle(.bordered).controlSize(.small).disabled(gold < n)
                }
            }
            if peace {
                heading("Bonds")
                if !engine.married(human, civ, in: state) { option("A royal marriage", .marriage) }
                if engine.pact(human, civ, in: state) == nil { option("A pact of non-aggression", .pact) }
                if !engine.grantsAccess(civ, to: human, in: state) { option("Leave to march through their land", .access) }
                if engine.grantsAccess(human, to: civ, in: state) {
                    Button("Revoke their leave to march through your land") { _ = session.order(.revokeAccess(from: civ)) }
                        .font(.caption.bold()).foregroundStyle(.orange)
                }
                trade
                let partners = state.players.filter { e in
                    e != human && e != civ && !(state.civs[e]?.eliminated ?? true)
                        && engine.tradeRoute(between: civ, and: e, in: state) != nil
                }
                if !partners.isEmpty {
                    heading("Embargo")
                    ForEach(partners, id: \.self) { e in option("Stop trading with \(Palette.name(e, state))", .embargo(against: e)) }
                }
            }
            if let theirs = state.civs[civ]?.gold, theirs >= 5 {
                heading("Demands")
                option("Demand \(min(20, max(5, theirs / 3))) gold in tribute", .tribute(gold: min(20, max(5, theirs / 3))))
            }
        }
    }

    /// Any goods for any goods, every turn for some rounds.
    @ViewBuilder private var trade: some View {
        heading("Trade, each turn for \(engine.rules.diplomacy.bargainRounds) rounds")
        let give = Goods(giveKind, giveAmount), get = Goods(getKind, getAmount)
        tradeRow("You give, each turn", amount: $giveAmount, kind: $giveKind)
        tradeRow("You get, each turn", amount: $getAmount, kind: $getKind)
        let canGive = engine.canGive(give, from: human, in: state)
        let canGet = engine.canGive(get, from: civ, in: state)
        let same = giveKind == getKind
        let deal = Deal.bargain(give: give, get: get)
        HStack {
            Text(same ? "Pick different goods" : !canGive ? "You can't spare that" : !canGet ? "They don't have that to spare"
                 : engine.wouldAccept(deal, from: human, to: civ, in: state) ? "They'd likely agree" : "They'd likely refuse")
                .font(.caption2).foregroundStyle(.white.opacity(0.65))
            Spacer()
            Button("Offer the trade") { propose(deal) }
                .buttonStyle(.bordered).controlSize(.small).disabled(same || !canGive || !canGet)
        }
    }

    /// A side of the trade: how many of what, on its own line beneath its label.
    private func tradeRow(_ label: String, amount: Binding<Int>, kind: Binding<Resource?>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.65))
            HStack(spacing: 8) {
                Stepper("", value: amount, in: 1...20).labelsHidden().fixedSize()
                Text("\(amount.wrappedValue)").font(.callout.monospacedDigit().bold()).frame(minWidth: 22)
                goodsPicker(kind)
                Spacer(minLength: 0)
            }
        }
    }

    private func goodsPicker(_ kind: Binding<Resource?>) -> some View {
        Picker("", selection: kind) {
            ForEach(Self.goods, id: \.self) { r in Text(r.map { DealText.name($0) } ?? "gold").tag(r) }
        }
        .pickerStyle(.menu).labelsHidden().tint(.white).fixedSize()
    }

    private func heading(_ text: String) -> some View {
        Text(text.uppercased()).font(.caption2.bold()).tracking(1).foregroundStyle(Bronze.gradient).padding(.top, 4)
    }

    private func option(_ title: String, _ deal: Deal) -> some View {
        let likely = engine.wouldAccept(deal, from: human, to: civ, in: state)
        return Button { propose(deal) } label: {
            HStack {
                Text(title).font(.callout.bold())
                Spacer()
                Text(likely ? "likely yes" : "likely no").font(.caption2)
                    .foregroundStyle(likely ? Color.green : Color.white.opacity(0.5))
            }
        }
        .buttonStyle(.plain).foregroundStyle(.white)
    }

    private func propose(_ deal: Deal) {
        // An AI court answers at once, as `wouldAccept` foresees (the engine decides the same way).
        let yes = engine.wouldAccept(deal, from: human, to: civ, in: state)
        if session.order(.propose(to: civ, deal)) {
            reply(deal, yes)
            yes ? SoundBoard.shared.play(.coins, volume: 0.5) : Feedback.select()
        }
    }
}
