/// Vassal empires (Josh: "an option to have a conquered country be a vassal state. lots of
/// advantages"). An empire at war may demand that a beaten rival submit. A court that has lost
/// its capital to the demander, or whose army has shrunk to a fraction of the demander's, bows;
/// a person is asked in an audience. A vassal empire keeps its land, ruler and army, but:
/// - it is at peace with its overlord, and neither may break that peace;
/// - it makes peace with the overlord's allies, may not war on them, and keeps no alliances of
///   its own (its foreign friends are its overlord's business);
/// - it pays a share of its gold income to the overlord every turn;
/// - it adds to the overlord's prestige.
/// It throws off the yoke once its army outgrows its overlord's, or when the overlord falls.

public struct SubmissionRules: Codable, Sendable, Equatable {
    /// An AI court submits when its strength is below this share (percent) of the demander's,
    /// or when the demander holds its capital (and in either case it is the weaker).
    public let acceptStrengthPercent: Int
    /// Share (percent) of the vassal's gold income paid to the overlord each turn.
    public let tributePercent: Int
    /// Prestige to the overlord for each vassal empire.
    public let prestige: Int
}

/// An empire's submission to another.
public struct Vassalage: Codable, Sendable, Equatable {
    public let overlord: CivilizationID
    /// The round it submitted.
    public let since: Int
    /// Gold paid at the vassal's last harvest.
    public var lastTribute: Int = 0

    public init(overlord: CivilizationID, since: Int) {
        self.overlord = overlord
        self.since = since
    }
}

extension Engine {
    // MARK: Who serves whom

    /// The empire `civ` has submitted to, if any.
    public func liege(of civ: CivilizationID, in state: GameState) -> CivilizationID? {
        state.vassalage[civ]?.overlord
    }

    /// Empires that have submitted to `civ`.
    public func vassalEmpires(of civ: CivilizationID, in state: GameState) -> [CivilizationID] {
        state.vassalage.filter { $0.value.overlord == civ && !(state.civs[$0.key]?.eliminated ?? true) }
            .map(\.key).sorted()
    }

    /// Whether `a` and `b` are bound by vassalage (either way), so neither may break the peace.
    public func bound(_ a: CivilizationID, _ b: CivilizationID, in state: GameState) -> Bool {
        liege(of: a, in: state) == b || liege(of: b, in: state) == a
    }

    /// Whether `civ` may declare war on `target`: not on its overlord or its vassal, and a vassal
    /// not on its overlord's allies either.
    public func mayDeclareWar(_ civ: CivilizationID, on target: CivilizationID, in state: GameState) -> Bool {
        if bound(civ, target, in: state) { return false }
        if let lord = liege(of: civ, in: state), allied(lord, target, in: state) { return false }
        return true
    }

    /// Soldiers and ships an empire actually commands.
    func trueStrength(_ civ: CivilizationID, _ state: GameState) -> Int {
        militaryStrength(civ, seenBy: civ, state)
    }

    /// Whether `target` would submit to `demander` now: they're at war, neither already serves
    /// anyone, the demander's land borders the target's, and the target is beaten: its capital
    /// is in the demander's hands, or its army is a fraction of the demander's (as far as it can
    /// see). A court still stronger than the demander never bows.
    public func wouldSubmit(_ target: CivilizationID, to demander: CivilizationID, in state: GameState) -> Bool {
        guard target != demander, state.isPlayer(target), state.isPlayer(demander),
              !(state.civs[target]?.eliminated ?? true), !(state.civs[demander]?.eliminated ?? true),
              state.atWar(target, demander),
              liege(of: target, in: state) == nil, liege(of: demander, in: state) == nil else { return false }
        let capitalTaken = map.civilization(target).map { state.owner(of: $0.capital) == demander } ?? false
        // Only a conqueror at the gates is feared: an empire across the sea, however large, must
        // first land and take ground next to the target's.
        let theirLand = Set(state.territories(of: demander))
        let atTheGates = capitalTaken || state.territories(of: target).contains { t in
            map.landNeighbors(of: t).contains(where: theirLand.contains)
        }
        guard atTheGates else { return false }
        let mine = trueStrength(target, state)
        let theirs = militaryStrength(demander, seenBy: target, state)
        guard mine < theirs else { return false }
        return capitalTaken || mine * 100 < theirs * rules.submission.acceptStrengthPercent
    }

    /// Gold the vassal will pay from an income of `income`.
    public func tribute(fromIncome income: Int) -> Int {
        max(0, income) * rules.submission.tributePercent / 100
    }

    // MARK: Commands

    /// Demands that a rival at war submit. An AI court answers at once; a person is asked.
    func demandSubmission(_ target: CivilizationID, _ state: inout GameState) throws -> [GameEvent] {
        let civ = state.activePlayer
        guard target != civ, let c = state.civs[target], !c.eliminated else { throw GameError.unknownCivilization(target) }
        guard state.atWar(civ, target) else { throw GameError.notAtWar(target) }
        guard liege(of: civ, in: state) == nil else { throw GameError.vassalBound(liege(of: civ, in: state)!) }
        guard liege(of: target, in: state) == nil else { throw GameError.vassalBound(target) }
        if c.isHuman {
            let demand = PeaceOffer(from: civ, to: target)
            guard !state.submissionDemands.contains(demand) else { throw GameError.alreadyAsked(target) }
            state.submissionDemands.insert(demand)
            return [.submissionDemanded(from: civ, to: target)]
        }
        guard wouldSubmit(target, to: civ, in: state) else { return [.submissionRefused(by: target, to: civ)] }
        return submit(target, to: civ, &state)
    }

    /// A person's answer to a demand for submission.
    func answerSubmission(_ from: CivilizationID, accept: Bool, _ state: inout GameState) throws -> [GameEvent] {
        let civ = state.activePlayer
        let demand = PeaceOffer(from: from, to: civ)
        guard state.submissionDemands.contains(demand) else { throw GameError.noSubmissionDemand(from) }
        state.submissionDemands.remove(demand)
        guard accept else {
            state.submissionRebuffed[demand] = state.turn + rules.alliances.rebuffedRounds
            return [.submissionRefused(by: civ, to: from)]
        }
        guard state.atWar(civ, from), !(state.civs[from]?.eliminated ?? true),
              liege(of: from, in: state) == nil, liege(of: civ, in: state) == nil else { return [] }
        return submit(civ, to: from, &state)
    }

    /// `vassal` bows to `lord` (public for debug setups): peace with the overlord and its allies, alliances given up, and
    /// any empires that served the vassal go free.
    public func submit(_ vassal: CivilizationID, to lord: CivilizationID, _ state: inout GameState) -> [GameEvent] {
        state.vassalage[vassal] = Vassalage(overlord: lord, since: state.turn)
        var events: [GameEvent] = [.submitted(vassal: vassal, overlord: lord)]
        for pair in state.alliances.filter({ $0.a == vassal || $0.b == vassal }).sorted(by: { ($0.a, $0.b) < ($1.a, $1.b) }) {
            state.alliances.remove(pair)
            events.append(.allianceEnded(pair, by: vassal))
        }
        state.allianceOffers = state.allianceOffers.filter { $0.from != vassal && $0.to != vassal }
        state.warRequests = state.warRequests.filter { $0.to != vassal && $0.from != vassal }
        state.submissionDemands = state.submissionDemands.filter { $0.to != vassal }
        for freed in vassalEmpires(of: vassal, in: state) {
            state.vassalage[freed] = nil
            events.append(.vassalEmpireFreed(vassal: freed, overlord: vassal, overlordFell: false))
        }
        events += makeVassalPeace(&state)
        return events
    }

    /// Every vassal empire at peace with its overlord and its overlord's allies.
    func makeVassalPeace(_ state: inout GameState) -> [GameEvent] {
        var events: [GameEvent] = []
        for (vassal, v) in state.vassalage.sorted(by: { $0.key < $1.key }) {
            for other in [v.overlord] + allies(of: v.overlord, in: state) where other != vassal && state.atWar(vassal, other) {
                state.peace.insert(CivPair(vassal, other))
                state.peaceOffers.remove(PeaceOffer(from: vassal, to: other))
                state.peaceOffers.remove(PeaceOffer(from: other, to: vassal))
                events.append(.peaceMade(CivPair(vassal, other)))
            }
        }
        return events
    }

    // MARK: Each turn

    /// At the start of a vassal's turn: it goes free if its overlord has fallen or it has
    /// outgrown it. Demands the active civ made last turn lapse.
    func vassalageChecks(_ civ: CivilizationID, _ state: inout GameState) -> [GameEvent] {
        state.submissionDemands = state.submissionDemands.filter { $0.from != civ }
        guard let v = state.vassalage[civ] else { return [] }
        let fell = state.civs[v.overlord]?.eliminated ?? true
        guard fell || trueStrength(civ, state) > trueStrength(v.overlord, state) else { return [] }
        state.vassalage[civ] = nil
        return [.vassalEmpireFreed(vassal: civ, overlord: v.overlord, overlordFell: fell)]
    }

    /// A fallen empire's vassals go free at once; a fallen vassal is forgotten.
    func vassalageAfterElimination(of civ: CivilizationID, _ state: inout GameState) -> [GameEvent] {
        state.vassalage[civ] = nil
        state.submissionDemands = state.submissionDemands.filter { $0.from != civ && $0.to != civ }
        var events: [GameEvent] = []
        for (vassal, v) in state.vassalage.sorted(by: { $0.key < $1.key }) where v.overlord == civ {
            state.vassalage[vassal] = nil
            events.append(.vassalEmpireFreed(vassal: vassal, overlord: civ, overlordFell: true))
        }
        return events
    }

    /// The vassal's harvest: a share of its income goes to the overlord.
    func payTribute(_ civ: CivilizationID, income: Int, _ state: inout GameState) -> [GameEvent] {
        guard let v = state.vassalage[civ], state.civs[v.overlord] != nil else { return [] }
        let gold = min(tribute(fromIncome: income), state.civs[civ]!.gold)
        state.vassalage[civ]!.lastTribute = gold
        guard gold > 0 else { return [] }
        state.civs[civ]!.gold -= gold
        state.civs[v.overlord]!.gold += gold
        return [.tributePaid(vassal: civ, overlord: v.overlord, gold: gold)]
    }
}
