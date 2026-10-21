/// Defensive alliances (Josh: "setup defense alliances and try to get the AIs to join us in a
/// war"). Allies are at peace and promise to fight whoever attacks either of them. An ally can
/// also be asked to join a war of your choosing; they weigh it as a real court would (is the
/// enemy too strong? do they have their own reasons?). Leaving an alliance, or abandoning an
/// ally under attack, costs standing.

/// An ally's request that another join its war.
public struct WarRequest: Codable, Sendable, Hashable {
    public let from: CivilizationID
    public let to: CivilizationID
    public let against: CivilizationID
    public init(from: CivilizationID, to: CivilizationID, against: CivilizationID) {
        self.from = from
        self.to = to
        self.against = against
    }
}

public struct AllianceRules: Codable, Sendable, Equatable {
    /// An ally refuses to fight an enemy more than this many times its own strength (percent).
    public let enemyTooStrongPercent: Int
    /// Legitimacy lost for leaving an alliance or abandoning an ally under attack.
    public let betrayalLegitimacy: Int
    /// Most allies one realm can keep.
    public let maxAllies: Int
    /// Rounds a court waits before offering peace again to someone who turned it down.
    public let rebuffedRounds: Int
}

extension Engine {
    public func allies(of civ: CivilizationID, in state: GameState) -> [CivilizationID] {
        state.alliances.compactMap { pair in
            pair.a == civ ? pair.b : pair.b == civ ? pair.a : nil
        }.filter { !(state.civs[$0]?.eliminated ?? true) }.sorted()
    }

    public func allied(_ a: CivilizationID, _ b: CivilizationID, in state: GameState) -> Bool {
        state.alliances.contains(CivPair(a, b))
    }

    /// Soldiers and ships `civ` commands, as far as `observer` can tell (limited sight).
    func militaryStrength(_ civ: CivilizationID, seenBy observer: CivilizationID, _ state: GameState) -> Int {
        perceivedStrength(of: civ, by: observer, ships: true, in: state)
    }

    /// Whether a civilization would go to war against `enemy` for an ally: not if the enemy is
    /// overwhelming; readily if it already fears or covets them (shared border).
    public func willingToFight(_ civ: CivilizationID, against enemy: CivilizationID, in state: GameState) -> Bool {
        let mine = max(1, militaryStrength(civ, seenBy: civ, state))
        let theirs = militaryStrength(enemy, seenBy: civ, state)
        return theirs * 100 <= mine * rules.alliances.enemyTooStrongPercent
    }

    /// Would an AI court accept an alliance? Yes if both face a common enemy that worries it
    /// (one it is at war with that is at least as strong as it), and it has room for an ally.
    public func wouldAlly(_ civ: CivilizationID, with other: CivilizationID, in state: GameState) -> Bool {
        guard state.atPeace(civ, other), !allied(civ, other, in: state),
              liege(of: civ, in: state) == nil, liege(of: other, in: state) == nil,
              allies(of: civ, in: state).count < rules.alliances.maxAllies else { return false }
        let mine = militaryStrength(civ, seenBy: civ, state)
        let sight = self.sight(of: civ, in: state)
        // Against a menace, any fellow enemy of it will do.
        if let m = menace(in: state), m != civ, m != other, state.atWar(civ, m), state.atWar(other, m) { return true }
        return state.players.contains { enemy in
            enemy != civ && enemy != other && !(state.civs[enemy]?.eliminated ?? true)
                && state.atWar(civ, enemy) && state.atWar(other, enemy)
                && perceivedStrength(of: enemy, by: civ, ships: true, sight: sight, in: state) >= mine
        }
    }

    // MARK: Commands

    func offerAlliance(_ to: CivilizationID, _ state: inout GameState) throws -> [GameEvent] {
        let civ = state.activePlayer
        guard to != civ, let c = state.civs[to], !c.eliminated else { throw GameError.unknownCivilization(to) }
        guard state.atPeace(civ, to) else { throw GameError.notAtPeace(to) }
        guard !allied(civ, to, in: state) else { throw GameError.alreadyAllied(to) }
        guard allies(of: civ, in: state).count < rules.alliances.maxAllies else { throw GameError.tooManyAllies }
        if let lord = liege(of: civ, in: state) { throw GameError.vassalBound(lord) }
        if liege(of: to, in: state) != nil { throw GameError.vassalBound(to) }
        // AI courts answer at once; people answer on their turn.
        if !(c.isHuman) {
            guard wouldAlly(to, with: civ, in: state) else { return [.allianceRefused(by: to, to: civ)] }
            state.alliances.insert(CivPair(civ, to))
            return [.allianceMade(CivPair(civ, to))] + makeVassalPeace(&state)
        }
        state.allianceOffers.insert(PeaceOffer(from: civ, to: to))
        return [.allianceOffered(from: civ, to: to)]
    }

    func acceptAlliance(_ from: CivilizationID, _ state: inout GameState) throws -> [GameEvent] {
        let civ = state.activePlayer
        guard state.allianceOffers.contains(PeaceOffer(from: from, to: civ)) else { throw GameError.noAllianceOffer(from) }
        state.allianceOffers.remove(PeaceOffer(from: from, to: civ))
        guard state.atPeace(civ, from) else { throw GameError.notAtPeace(from) }
        if let lord = liege(of: civ, in: state) { throw GameError.vassalBound(lord) }
        if liege(of: from, in: state) != nil { throw GameError.vassalBound(from) }
        state.alliances.insert(CivPair(civ, from))
        return [.allianceMade(CivPair(civ, from))] + makeVassalPeace(&state)
    }

    func leaveAlliance(_ with: CivilizationID, _ state: inout GameState) throws -> [GameEvent] {
        let civ = state.activePlayer
        guard allied(civ, with, in: state) else { throw GameError.notAllied(with) }
        state.alliances.remove(CivPair(civ, with))
        adjustLegitimacy(civ, -rules.alliances.betrayalLegitimacy, &state)
        return [.allianceEnded(CivPair(civ, with), by: civ)]
    }

    /// Asks an ally to join a war against `against`.
    func callToWar(_ ally: CivilizationID, against: CivilizationID, _ state: inout GameState) throws -> [GameEvent] {
        let civ = state.activePlayer
        guard allied(civ, ally, in: state) else { throw GameError.notAllied(ally) }
        guard state.atWar(civ, against), against != ally else { throw GameError.notAtWar(against) }
        guard state.atPeace(ally, against) else { return [] }  // already fighting them
        guard !state.calledToWar.contains(ally) else { throw GameError.alreadyAsked(ally) }
        state.calledToWar.insert(ally)
        if state.civs[ally]?.isHuman == true {
            state.warRequests.insert(WarRequest(from: civ, to: ally, against: against))
            return [.calledToWar(WarRequest(from: civ, to: ally, against: against))]
        }
        guard mayDeclareWar(ally, on: against, in: state), willingToFight(ally, against: against, in: state) else {
            return [.warRefused(by: ally, ally: civ, against: against)]
        }
        return joinWar(ally, against: against, for: civ, &state)
    }

    /// A person's answer to an ally's call.
    func answerCallToWar(_ from: CivilizationID, against: CivilizationID, join: Bool, _ state: inout GameState) throws -> [GameEvent] {
        let civ = state.activePlayer
        let request = WarRequest(from: from, to: civ, against: against)
        guard state.warRequests.contains(request) else { throw GameError.noWarRequest(from) }
        state.warRequests.remove(request)
        if join {
            guard state.atPeace(civ, against), mayDeclareWar(civ, on: against, in: state) else { return [] }
            return joinWar(civ, against: against, for: from, &state)
        }
        return abandon(civ, ally: from, against: against, &state)
    }

    /// Declares war for an ally: no shame in keeping a promise.
    private func joinWar(_ civ: CivilizationID, against: CivilizationID, for ally: CivilizationID,
                         _ state: inout GameState) -> [GameEvent] {
        state.peace.remove(CivPair(civ, against))
        state.peaceOffers.remove(PeaceOffer(from: civ, to: against))
        state.peaceOffers.remove(PeaceOffer(from: against, to: civ))
        // A war on one of your own allies ends that alliance.
        var events: [GameEvent] = [.joinedWar(civ: civ, against: against, ally: ally)]
        if allied(civ, against, in: state) {
            state.alliances.remove(CivPair(civ, against))
            events.append(.allianceEnded(CivPair(civ, against), by: civ))
        }
        return events
    }

    private func abandon(_ civ: CivilizationID, ally: CivilizationID, against: CivilizationID,
                         _ state: inout GameState) -> [GameEvent] {
        state.alliances.remove(CivPair(civ, ally))
        adjustLegitimacy(civ, -rules.alliances.betrayalLegitimacy, &state)
        return [.warRefused(by: civ, ally: ally, against: against), .allianceEnded(CivPair(civ, ally), by: civ)]
    }

    /// Someone attacked `victim`: its allies at peace with the attacker are called on. AI allies
    /// answer now (keeping faith unless the attacker is overwhelming, which ends the alliance);
    /// a person's ally gets a request to answer on their turn.
    func rallyAllies(of victim: CivilizationID, against attacker: CivilizationID, _ state: inout GameState) -> [GameEvent] {
        guard state.isPlayer(victim), state.isPlayer(attacker) else { return [] }
        var events: [GameEvent] = []
        for ally in allies(of: victim, in: state) where ally != attacker && state.atPeace(ally, attacker)
            && mayDeclareWar(ally, on: attacker, in: state) {
            if state.civs[ally]?.isHuman == true {
                let request = WarRequest(from: victim, to: ally, against: attacker)
                if !state.warRequests.contains(request) {
                    state.warRequests.insert(request)
                    events.append(.calledToWar(request))
                }
            } else if willingToFight(ally, against: attacker, in: state) {
                events += joinWar(ally, against: attacker, for: victim, &state)
            } else {
                events += abandon(ally, ally: victim, against: attacker, &state)
            }
        }
        return events
    }

    /// Calls to arms the person left unanswered by the time their ally moves again count as
    /// a refusal.
    func expireWarRequests(from civ: CivilizationID, _ state: inout GameState) -> [GameEvent] {
        var events: [GameEvent] = []
        for request in state.warRequests.filter({ $0.from == civ }).sorted(by: { $0.to < $1.to }) {
            state.warRequests.remove(request)
            if state.atPeace(request.to, request.against), allied(request.to, civ, in: state) {
                events += abandon(request.to, ally: civ, against: request.against, &state)
            }
        }
        return events
    }
}

// MARK: Coalitions

public struct CoalitionRules: Codable, Sendable, Equatable {
    /// An empire is a menace once its prestige is this much (percent) of the next one's…
    public let prestigeLeadPercent: Int
    /// …or once it holds this share (percent) of the land needed to win by domination.
    public let dominationSharePercent: Int
}

extension Engine {
    /// The empire everyone else fears, if one has pulled far enough ahead.
    public func menace(in state: GameState) -> CivilizationID? {
        let alive = state.players.filter { !(state.civs[$0]?.eliminated ?? true) }
        guard alive.count >= 3 else { return nil }
        let ranked = alive.sorted { (prestige(of: $0, in: state), $1) > (prestige(of: $1, in: state), $0) }
        let first = ranked[0], second = ranked[1]
        let c = rules.coalitions
        let lead = prestige(of: first, in: state) * 100 >= max(1, prestige(of: second, in: state)) * c.prestigeLeadPercent
        let share = landShare(of: first, in: state)
        let nearWin = share.percent * 100 >= share.toWin * c.dominationSharePercent
        // Prestige alone isn't enough: a menace must also hold a good share of the land.
        let large = share.percent * 100 >= share.toWin * c.dominationSharePercent / 2
        return (lead && large) || nearWin ? first : nil
    }
}
