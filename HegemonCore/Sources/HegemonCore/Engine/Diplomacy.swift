/// Diplomacy between the empires, in the manner of the Amarna letters (Josh: "more diplomacy
/// options… let's do all of those"):
///
/// - **Regard.** Each court remembers how it has been treated by each other: gifts and marriages
///   warm it; wars, demands and broken pacts chill it; trade, shared enemies and kinship pull it
///   up over time, a long border and war pull it down. Regard decides every AI court's answer.
/// - **Gifts** of gold or goods, at once.
/// - **Royal marriages**: lasting regard, legitimacy for both, and kin don't lightly make war.
/// - **Bargains**: so much of one good for so much of another (or gold), every turn for a while.
/// - **Demands for tribute**: the weaker may pay; a refusal is a just cause for war (declared
///   without the usual cost in legitimacy), and either way the demand is resented.
/// - **Non-aggression pacts** for some rounds: breaking one costs far more than breaking a
///   peace, and every court thinks the worse of the breaker.
/// - **Military access**: armies may cross and stand in the grantor's land.
/// - **Embargoes**: a friend agrees to stop trading with your enemy for a while.
///
/// An AI court answers a proposal at once; a person answers on their turn. AI courts propose
/// deals of their own, to each other and to the player.

/// Goods offered in a deal: gold (no resource), or so many of a resource.
public struct Goods: Codable, Sendable, Hashable {
    public let resource: Resource?
    public let amount: Int
    public init(_ resource: Resource? = nil, _ amount: Int) {
        self.resource = resource
        self.amount = amount
    }
    public static func gold(_ n: Int) -> Goods { Goods(nil, n) }
}

public enum Deal: Codable, Sendable, Hashable {
    /// Given at once, no answer needed.
    case gift(Goods)
    case marriage
    /// The proposer gives `give` and receives `get`, every turn for a while.
    case bargain(give: Goods, get: Goods)
    /// A demand: the recipient pays this much gold now.
    case tribute(gold: Int)
    case pact
    /// The proposer asks for access to the recipient's land.
    case access
    /// The proposer asks the recipient to stop trading with `against` for a while.
    case embargo(against: CivilizationID)
}

/// A deal waiting for a person's answer.
public struct Proposal: Codable, Sendable, Hashable {
    public let from: CivilizationID
    public let to: CivilizationID
    public let deal: Deal
    public let round: Int
    public init(from: CivilizationID, to: CivilizationID, deal: Deal, round: Int) {
        self.from = from
        self.to = to
        self.deal = deal
        self.round = round
    }
}

/// How `holder` regards `about`.
public struct Opinion: Codable, Sendable, Hashable {
    public let holder: CivilizationID
    public let about: CivilizationID
    public init(_ holder: CivilizationID, about: CivilizationID) {
        self.holder = holder
        self.about = about
    }
}

/// A standing exchange: `a` sends `aGives` to `b` and `b` sends `bGives` to `a`, every turn
/// through round `until`.
public struct Bargain: Codable, Sendable, Hashable {
    public let a: CivilizationID
    public let b: CivilizationID
    public let aGives: Goods
    public let bGives: Goods
    public let until: Int
}

public struct Embargo: Codable, Sendable, Hashable {
    public let by: CivilizationID
    public let against: CivilizationID
    public let until: Int
}

public struct DiplomacyRules: Codable, Sendable, Equatable {
    /// Regard drifts this much a round toward where the courts' circumstances put it: these
    /// for war, trade, kinship, alliance, a shared enemy, and a long border.
    public let drift: Int
    public let warRegard: Int
    public let tradeRegard: Int
    public let kinRegard: Int
    public let allyRegard: Int
    public let sharedEnemyRegard: Int
    public let borderRegard: Int
    /// A declaration of war against the victim (and, by half, its allies and kin).
    public let declaredWarRegard: Int
    /// Gifts: regard per gold's worth, up to a cap per gift.
    public let giftRegardPerGold: Int
    public let giftRegardMax: Int
    /// Marriages: the regard and legitimacy they bring, and the regard needed to agree.
    public let marriageRegard: Int
    public let marriageLegitimacy: Int
    public let marriageMinRegard: Int
    /// Bargains run this many rounds; an AI court wants this much more in value than it gives
    /// (in percent, less half its regard for the proposer).
    public let bargainRounds: Int
    public let bargainMarginPercent: Int
    /// Tribute: resented by the payer; paid only to someone this much stronger (percent); a
    /// refusal gives just cause for war for this many rounds.
    public let tributeRegard: Int
    public let tributeFearPercent: Int
    public let casusBelliRounds: Int
    /// Pacts run this many rounds; breaking one costs this legitimacy and this regard with the
    /// victim, and every other court thinks this much worse of the breaker.
    public let pactRounds: Int
    public let pactBrokenLegitimacy: Int
    public let pactBrokenRegard: Int
    public let reputationRegard: Int
    /// Regard needed to grant access, or to join an embargo (of the target, at most `embargoMaxRegard`).
    public let accessRegard: Int
    public let embargoRounds: Int
    public let embargoMinRegard: Int
    public let embargoMaxRegard: Int
    /// An AI court proposes to the same court at most every so many rounds.
    public let proposalRounds: Int
}

extension Engine {
    // MARK: Regard

    public func regard(of holder: CivilizationID, toward about: CivilizationID, in state: GameState) -> Int {
        state.regard[Opinion(holder, about: about)] ?? 0
    }

    func changeRegard(of holder: CivilizationID, toward about: CivilizationID, by delta: Int, _ state: inout GameState) {
        guard holder != about, state.isPlayer(holder), state.isPlayer(about) else { return }
        let now = regard(of: holder, toward: about, in: state)
        state.regard[Opinion(holder, about: about)] = max(-100, min(100, now + delta))
    }

    public func married(_ a: CivilizationID, _ b: CivilizationID, in state: GameState) -> Bool {
        state.marriages.contains(CivPair(a, b))
    }

    /// The round a pact between two courts runs through, if one holds.
    public func pact(_ a: CivilizationID, _ b: CivilizationID, in state: GameState) -> Int? {
        state.pacts[CivPair(a, b)].flatMap { $0 >= state.turn ? $0 : nil }
    }

    /// Whether `civ` has just cause for war on `target` (a refused demand).
    public func casusBelli(_ civ: CivilizationID, against target: CivilizationID, in state: GameState) -> Bool {
        (state.casusBelli[PeaceOffer(from: civ, to: target)] ?? 0) >= state.turn
    }

    public func embargoed(_ a: CivilizationID, _ b: CivilizationID, in state: GameState) -> Bool {
        state.embargoes.contains { $0.until >= state.turn && (($0.by == a && $0.against == b) || ($0.by == b && $0.against == a)) }
    }

    /// Whether `grantor` lets `grantee`'s armies cross and stand in its land.
    public func grantsAccess(_ grantor: CivilizationID, to grantee: CivilizationID, in state: GameState) -> Bool {
        state.access.contains(PeaceOffer(from: grantor, to: grantee))
    }

    /// Where regard between two courts settles, given how things stand between them.
    func regardTarget(_ a: CivilizationID, _ b: CivilizationID, routes: [TradeRoute], _ state: GameState) -> Int {
        let d = rules.diplomacy
        var t = 0
        if state.atWar(a, b) { t += d.warRegard }
        if routes.contains(where: { $0.involves(a) && $0.involves(b) }) { t += d.tradeRegard }
        if married(a, b, in: state) { t += d.kinRegard }
        if allied(a, b, in: state) { t += d.allyRegard }
        let shared = state.players.contains { c in
            c != a && c != b && !(state.civs[c]?.eliminated ?? true) && state.atWar(a, c) && state.atWar(b, c)
        }
        if shared { t += d.sharedEnemyRegard }
        let border = state.territories(of: a).contains { map.landNeighbors(of: $0).contains { state.owner(of: $0) == b } }
        if border { t += d.borderRegard }
        return t
    }

    /// Once a round: regard drifts; pacts, embargoes, bargains, just causes and old proposals expire.
    func diplomacyRound(_ state: inout GameState) -> [GameEvent] {
        let d = rules.diplomacy
        let alive = state.players.filter { !(state.civs[$0]?.eliminated ?? true) }
        let routes = tradeRoutes(in: state)
        for a in alive {
            for b in alive where a != b {
                let target = regardTarget(a, b, routes: routes, state)
                let now = regard(of: a, toward: b, in: state)
                let next = now > target ? max(target, now - d.drift) : min(target, now + d.drift)
                if next != now { state.regard[Opinion(a, about: b)] = next }
            }
        }
        var events: [GameEvent] = []
        for (pair, until) in state.pacts.sorted(by: { ($0.key.a, $0.key.b) < ($1.key.a, $1.key.b) }) where until < state.turn {
            state.pacts[pair] = nil
            events.append(.pactEnded(pair))
        }
        state.embargoes.removeAll { $0.until < state.turn }
        state.bargains.removeAll { $0.until < state.turn }
        state.casusBelli = state.casusBelli.filter { $0.value >= state.turn }
        state.proposals.removeAll { $0.round < state.turn - 1 }
        return events
    }

    // MARK: Value

    /// What goods are worth to `civ`, a turn: scarce strategic goods most, and double what it lacks.
    public func worth(_ goods: Goods, to civ: CivilizationID, in state: GameState) -> Int {
        guard let r = goods.resource else { return goods.amount }
        let base: Int = switch r {
        case .tin: 5
        case .copper, .iron: 4
        case .horses, .luxuries: 3
        case .timber, .stone, .wine: 2
        case .grain, .gold: 1
        }
        let have: Int = if Resource.stockpiled.contains(r) { state.civs[civ]?.stock[r] ?? 0 }
            else if r == .grain { state.civs[civ]?.granary ?? 0 }
            else { effectiveYield(of: r, for: civ, in: state) }
        return goods.amount * base * (have == 0 ? 2 : 1)
    }

    /// Whether `civ` can keep sending these goods.
    public func canGive(_ goods: Goods, from civ: CivilizationID, in state: GameState) -> Bool {
        guard goods.amount > 0, let cs = state.civs[civ] else { return false }
        guard let r = goods.resource else { return cs.gold >= goods.amount }
        if Resource.stockpiled.contains(r) { return (cs.stock[r] ?? 0) >= goods.amount }
        if r == .grain { return cs.granary >= goods.amount }
        if r == .gold { return cs.gold >= goods.amount }
        return yield(of: r, in: homeNetwork(of: civ, in: state), state) >= goods.amount
    }

    /// Goods flowing through bargains, for a resource used as a yield (copper, tin, horses,
    /// wine, luxuries): what `civ` receives less what it sends.
    func bargainYield(_ resource: Resource, for civ: CivilizationID, in state: GameState) -> Int {
        guard !Resource.stockpiled.contains(resource), resource != .grain, resource != .gold else { return 0 }
        return state.bargains.filter { $0.until >= state.turn }.reduce(0) { total, deal in
            var n = total
            if deal.a == civ {
                if deal.aGives.resource == resource { n -= deal.aGives.amount }
                if deal.bGives.resource == resource { n += deal.bGives.amount }
            } else if deal.b == civ {
                if deal.bGives.resource == resource { n -= deal.bGives.amount }
                if deal.aGives.resource == resource { n += deal.aGives.amount }
            }
            return n
        }
    }

    // MARK: Would an AI court agree?

    public func wouldAccept(_ deal: Deal, from proposer: CivilizationID, to court: CivilizationID, in state: GameState) -> Bool {
        let d = rules.diplomacy
        let r = regard(of: court, toward: proposer, in: state)
        switch deal {
        case .gift:
            return true
        case .marriage:
            return state.atPeace(court, proposer) && !married(court, proposer, in: state) && r >= d.marriageMinRegard
        case let .bargain(give, get):
            guard state.atPeace(court, proposer), r > -20, canGive(get, from: court, in: state),
                  canGive(give, from: proposer, in: state) else { return false }
            let margin = max(80, d.bargainMarginPercent - r / 2)
            return worth(give, to: court, in: state) * 100 >= worth(get, to: court, in: state) * margin
        case let .tribute(gold):
            guard let cs = state.civs[court], gold > 0, cs.gold >= gold else { return false }
            return trueStrength(proposer, state) * 100 >= trueStrength(court, state) * d.tributeFearPercent
        case .pact:
            guard state.atPeace(court, proposer), pact(court, proposer, in: state) == nil, r >= 0 else { return false }
            // Not with a neighbour it means to fall on.
            return trueStrength(court, state) * 10 < trueStrength(proposer, state) * 13 || r >= 20
        case .access:
            return state.atPeace(court, proposer) && (allied(court, proposer, in: state) || r >= d.accessRegard)
        case let .embargo(against):
            guard against != court, against != proposer, state.isPlayer(against), !allied(court, against, in: state),
                  !married(court, against, in: state) else { return false }
            return r >= d.embargoMinRegard && (regard(of: court, toward: against, in: state) <= d.embargoMaxRegard || state.atWar(court, against))
        }
    }

    // MARK: Orders

    func propose(_ deal: Deal, to: CivilizationID, _ state: inout GameState) throws -> [GameEvent] {
        let civ = state.activePlayer
        guard to != civ, let other = state.civs[to], !other.eliminated else { throw GameError.unknownCivilization(to) }
        switch deal {
        case let .gift(goods):
            guard canGive(goods, from: civ, in: state) else { throw GameError.cannotAfford }
            transfer(goods, from: civ, to: to, &state)
            let worth = goods.resource == nil ? goods.amount : self.worth(goods, to: to, in: state)
            changeRegard(of: to, toward: civ, by: min(rules.diplomacy.giftRegardMax, worth * rules.diplomacy.giftRegardPerGold), &state)
            return [.giftSent(from: civ, to: to, goods: goods)]
        case .marriage, .pact, .access:
            guard state.atPeace(civ, to) else { throw GameError.notAtPeace(to) }
        case let .bargain(give, get):
            guard state.atPeace(civ, to) else { throw GameError.notAtPeace(to) }
            guard give.amount > 0, get.amount > 0, canGive(give, from: civ, in: state) else { throw GameError.cannotAfford }
        case let .tribute(gold):
            guard gold > 0 else { throw GameError.invalidCount }
        case let .embargo(against):
            guard state.atPeace(civ, to), against != to, against != civ, state.isPlayer(against) else { throw GameError.unknownCivilization(against) }
        }
        if case .marriage = deal, married(civ, to, in: state) { throw GameError.alreadyMarried(to) }
        if case .pact = deal, pact(civ, to, in: state) != nil { throw GameError.alreadyAtPeace(to) }
        if case .access = deal, grantsAccess(to, to: civ, in: state) { throw GameError.alreadyAtPeace(to) }
        guard !state.proposals.contains(where: { $0.from == civ && $0.to == to && $0.deal == deal }) else {
            throw GameError.alreadyProposed(to)
        }
        // AI courts answer at once; people answer on their turn.
        if !other.isHuman {
            return settle(Proposal(from: civ, to: to, deal: deal, round: state.turn),
                          accept: wouldAccept(deal, from: civ, to: to, in: state), &state)
        }
        state.proposals.append(Proposal(from: civ, to: to, deal: deal, round: state.turn))
        return [.dealProposed(from: civ, to: to, deal: deal)]
    }

    func answer(_ from: CivilizationID, _ deal: Deal, accept: Bool, _ state: inout GameState) throws -> [GameEvent] {
        let civ = state.activePlayer
        guard let i = state.proposals.firstIndex(where: { $0.from == from && $0.to == civ && $0.deal == deal }) else {
            throw GameError.noProposal(from)
        }
        let proposal = state.proposals.remove(at: i)
        // A deal that can no longer be kept (gold spent, war broken out) falls through.
        if accept, case let .bargain(give, get) = deal,
           !canGive(get, from: civ, in: state) || !canGive(give, from: from, in: state) || state.atWar(civ, from) {
            return settle(proposal, accept: false, &state)
        }
        if accept, case let .tribute(gold) = deal, (state.civs[civ]?.gold ?? 0) < gold { throw GameError.cannotAfford }
        return settle(proposal, accept: accept, &state)
    }

    /// Carries out an answer.
    private func settle(_ p: Proposal, accept: Bool, _ state: inout GameState) -> [GameEvent] {
        let d = rules.diplomacy
        state.lastProposal[PeaceOffer(from: p.from, to: p.to)] = state.turn
        guard accept else {
            switch p.deal {
            case .tribute:
                // Refused: the demander has its cause for war, and resents the refusal.
                state.casusBelli[PeaceOffer(from: p.from, to: p.to)] = state.turn + d.casusBelliRounds
                changeRegard(of: p.from, toward: p.to, by: -10, &state)
                changeRegard(of: p.to, toward: p.from, by: d.tributeRegard / 2, &state)
            default:
                changeRegard(of: p.from, toward: p.to, by: -3, &state)
            }
            return [.dealRefused(from: p.from, to: p.to, deal: p.deal)]
        }
        switch p.deal {
        case .gift:
            break
        case .marriage:
            state.marriages.insert(CivPair(p.from, p.to))
            changeRegard(of: p.from, toward: p.to, by: d.marriageRegard, &state)
            changeRegard(of: p.to, toward: p.from, by: d.marriageRegard, &state)
            adjustLegitimacy(p.from, d.marriageLegitimacy, &state)
            adjustLegitimacy(p.to, d.marriageLegitimacy, &state)
        case let .bargain(give, get):
            state.bargains.append(Bargain(a: p.from, b: p.to, aGives: give, bGives: get, until: state.turn + d.bargainRounds))
        case let .tribute(gold):
            transfer(.gold(gold), from: p.to, to: p.from, &state)
            changeRegard(of: p.to, toward: p.from, by: d.tributeRegard, &state)
        case .pact:
            state.pacts[CivPair(p.from, p.to)] = state.turn + d.pactRounds
            changeRegard(of: p.to, toward: p.from, by: 5, &state)
            changeRegard(of: p.from, toward: p.to, by: 5, &state)
        case .access:
            state.access.insert(PeaceOffer(from: p.to, to: p.from))
        case let .embargo(against):
            state.embargoes.append(Embargo(by: p.to, against: against, until: state.turn + d.embargoRounds))
            changeRegard(of: against, toward: p.to, by: -15, &state)
        }
        return [.dealMade(from: p.from, to: p.to, deal: p.deal)]
    }

    /// Withdraws access `civ` granted to `grantee`: its armies there go home.
    func revokeAccess(_ grantee: CivilizationID, _ state: inout GameState) throws -> [GameEvent] {
        let civ = state.activePlayer
        guard grantsAccess(civ, to: grantee, in: state) else { throw GameError.noProposal(grantee) }
        state.access.remove(PeaceOffer(from: civ, to: grantee))
        changeRegard(of: grantee, toward: civ, by: -10, &state)
        return [.accessRevoked(by: civ, from: grantee)] + withdrawGarrisons(of: grantee, from: civ, &state)
    }

    func transfer(_ goods: Goods, from: CivilizationID, to: CivilizationID, _ state: inout GameState) {
        guard state.civs[from] != nil, state.civs[to] != nil else { return }
        switch goods.resource {
        case nil, .gold?:
            let n = min(goods.amount, state.civs[from]!.gold)
            state.civs[from]!.gold -= n
            state.civs[to]!.gold += n
        case .grain?:
            let n = min(goods.amount, state.civs[from]!.granary)
            state.civs[from]!.granary -= n
            state.civs[to]!.granary += n
        case let r? where Resource.stockpiled.contains(r):
            let n = min(goods.amount, state.civs[from]!.stock[r] ?? 0)
            state.civs[from]!.stock[r, default: 0] -= n
            state.civs[to]!.stock[r, default: 0] += n
        default:
            // Yields (copper, tin, horses, wine, luxuries) flow through `bargainYield` instead.
            break
        }
    }

    /// At the start of `civ`'s turn, after the harvest: what it owes under its bargains goes out.
    /// A bargain it can no longer keep lapses.
    func keepBargains(_ civ: CivilizationID, _ state: inout GameState) -> [GameEvent] {
        var events: [GameEvent] = []
        for (i, deal) in state.bargains.enumerated().reversed() where deal.until >= state.turn && (deal.a == civ || deal.b == civ) {
            let (gives, to) = deal.a == civ ? (deal.aGives, deal.b) : (deal.bGives, deal.a)
            if !canGive(gives, from: civ, in: state) {
                state.bargains.remove(at: i)
                changeRegard(of: to, toward: civ, by: -15, &state)
                events.append(.bargainBroken(by: civ, with: to))
                continue
            }
            transfer(gives, from: civ, to: to, &state)
        }
        return events
    }

    /// What breaking the peace costs, beyond the war itself: a pact broken, a just cause, kin.
    func warConsequences(_ civ: CivilizationID, on target: CivilizationID, _ state: inout GameState) -> [GameEvent] {
        let d = rules.diplomacy
        var events: [GameEvent] = []
        if pact(civ, target, in: state) != nil {
            adjustLegitimacy(civ, d.pactBrokenLegitimacy, &state)
            changeRegard(of: target, toward: civ, by: d.pactBrokenRegard, &state)
            for other in state.players where other != civ && other != target {
                changeRegard(of: other, toward: civ, by: d.reputationRegard, &state)
            }
            state.pacts[CivPair(civ, target)] = nil
            events.append(.pactBroken(by: civ, with: target))
        } else {
            changeRegard(of: target, toward: civ, by: d.declaredWarRegard, &state)
        }
        for friend in allies(of: target, in: state) where friend != civ {
            changeRegard(of: friend, toward: civ, by: d.declaredWarRegard / 2, &state)
        }
        if married(civ, target, in: state) {
            state.marriages.remove(CivPair(civ, target))
            events.append(.marriageEnded(CivPair(civ, target)))
        }
        // Deals between them are off; armies standing in each other's land by leave go home.
        state.bargains.removeAll { ($0.a == civ && $0.b == target) || ($0.a == target && $0.b == civ) }
        let hadAccess = grantsAccess(target, to: civ, in: state), gaveAccess = grantsAccess(civ, to: target, in: state)
        state.access.remove(PeaceOffer(from: target, to: civ))
        state.access.remove(PeaceOffer(from: civ, to: target))
        if hadAccess { events += withdrawGarrisons(of: civ, from: target, &state) }
        if gaveAccess { events += withdrawGarrisons(of: target, from: civ, &state) }
        state.proposals.removeAll { ($0.from == civ && $0.to == target) || ($0.from == target && $0.to == civ) }
        return events
    }
}
