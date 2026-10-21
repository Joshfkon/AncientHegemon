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
        }
    }
}

/// What the player can propose to a rival court, each with how they'd likely answer.
struct DealsMenu: View {
    let session: GameSession
    let human: CivilizationID
    let other: CivilizationID

    private var engine: Engine { session.engine }
    private var state: GameState { session.state }

    var body: some View {
        Menu {
            let gold = state.civs[human]?.gold ?? 0
            Section("Gifts") {
                ForEach([5, 10, 20], id: \.self) { n in
                    Button("Send \(n) gold") { propose(.gift(.gold(n))) }.disabled(gold < n)
                }
            }
            if state.atPeace(human, other) {
                Section("Bonds") {
                    if !engine.married(human, other, in: state) { item("Royal marriage", .marriage) }
                    if engine.pact(human, other, in: state) == nil { item("Non-aggression pact", .pact) }
                    if !engine.grantsAccess(other, to: human, in: state) { item("Ask leave to march through", .access) }
                }
                Section("Trade") {
                    ForEach(Array(bargains.enumerated()), id: \.offset) { _, b in
                        item("\(DealText.goods(b.get)) a turn for \(DealText.goods(b.give))", .bargain(give: b.give, get: b.get))
                    }
                }
                let enemies = state.players.filter { e in
                    e != human && e != other && !(state.civs[e]?.eliminated ?? true)
                        && engine.tradeRoute(between: other, and: e, in: state) != nil
                }
                if !enemies.isEmpty {
                    Section("Embargo") {
                        ForEach(enemies, id: \.self) { e in item("Stop trading with \(Palette.name(e, state))", .embargo(against: e)) }
                    }
                }
            }
            if let theirs = state.civs[other]?.gold, theirs >= 5 {
                Section("Demands") {
                    item("Demand \(min(20, max(5, theirs / 3))) gold in tribute", .tribute(gold: min(20, max(5, theirs / 3))))
                }
            }
        } label: {
            Label("Propose…", systemImage: "scroll").font(.caption.bold())
        }
        .buttonStyle(.bordered).controlSize(.small)
    }

    private func item(_ title: String, _ deal: Deal) -> some View {
        let yes = engine.wouldAccept(deal, from: human, to: other, in: state)
        return Button("\(title) · \(yes ? "likely yes" : "likely no")") { propose(deal) }
    }

    /// Sensible bargains: what they have that we lack, for gold or what we can spare.
    private var bargains: [(give: Goods, get: Goods)] {
        let tradeable: [Resource] = [.tin, .copper, .horses, .iron, .timber, .stone, .wine, .luxuries, .grain]
        var result: [(give: Goods, get: Goods)] = []
        for r in tradeable {
            let want = Goods(r, r == .grain ? 2 : 1)
            guard engine.canGive(want, from: other, in: state), engine.worth(want, to: human, in: state) > 0 else { continue }
            let price = engine.worth(want, to: other, in: state) + 1
            let pay = Goods.gold(price)
            if engine.canGive(pay, from: human, in: state) { result.append((pay, want)) }
            if result.count >= 4 { break }
        }
        return result
    }

    private func propose(_ deal: Deal) {
        if session.order(.propose(to: other, deal)) { Feedback.select() }
    }
}
