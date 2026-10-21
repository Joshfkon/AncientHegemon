/// The AI's diplomacy beyond war and peace: what its court proposes to the others. At most one
/// proposal a turn, and to the same court at most every few rounds, so a person isn't flooded.
extension AIPlayer {
    func propose(_ civ: CivilizationID, _ state: inout GameState, _ turn: inout AITurn) {
        let d = rules.diplomacy
        guard state.turn >= 2 else { return }
        let others = state.players.filter { $0 != civ && !(state.civs[$0]?.eliminated ?? true) }.sorted()
        let mine = engine.trueStrength(civ, state)
        let cs = state.civs[civ]!
        func ready(_ other: CivilizationID) -> Bool {
            let last = state.lastProposal[PeaceOffer(from: civ, to: other)] ?? -100
            // A person sees one AI proposal at a time.
            let busy = state.civs[other]?.isHuman == true && state.proposals.contains { $0.to == other }
            return state.turn - last >= d.proposalRounds && !busy
        }
        func neighbours(_ a: CivilizationID, _ b: CivilizationID) -> Bool {
            state.territories(of: a).contains { map.landNeighbors(of: $0).contains { state.owner(of: $0) == b } }
        }
        func offer(_ deal: Deal, to other: CivilizationID) -> Bool {
            if state.civs[other]?.isHuman != true, !engine.wouldAccept(deal, from: civ, to: other, in: state) {
                return false
            }
            return attempt(.propose(to: other, deal), &state, &turn)
        }
        for other in others where ready(other) {
            let theirs = engine.trueStrength(other, state)
            let r = engine.regard(of: civ, toward: other, in: state)
            let border = neighbours(civ, other)
            let peace = state.atPeace(civ, other)
            // Frightened of a strong neighbour: a pact, and a gift to sweeten it.
            if peace, border, theirs * 10 > mine * 14, engine.pact(civ, other, in: state) == nil {
                // A gift only to mend real hostility, and only from a full treasury: gold is
                // prestige too, and a court that pays every neighbour off grows poor.
                if r <= -20, cs.gold >= 60, offer(.gift(.gold(6)), to: other) { return }
                if offer(.pact, to: other) { return }
            }
            // Friends marry.
            if peace, r >= d.marriageMinRegard + 15, !engine.married(civ, other, in: state),
               state.marriages.filter({ $0.a == civ || $0.b == civ }).count < 2, offer(.marriage, to: other) { return }
            // Bronze needs tin and copper: buy what's missing from a partner who has it.
            if peace {
                for want in [Resource.tin, .copper] where engine.effectiveYield(of: want, for: civ, in: state) == 0 {
                    let theyHave = engine.yield(of: want, in: engine.homeNetwork(of: other, in: state), state)
                    guard theyHave >= 1, cs.gold >= 20 else { continue }
                    if offer(.bargain(give: .gold(2), get: Goods(want, 1)), to: other) { return }
                }
            }
            // The strong lean on the weak next door: pay, or give us our cause.
            if personality.aggression >= 1, peace, border, mine * 100 >= theirs * 200, r <= 0, state.turn >= 8,
               let theirGold = state.civs[other]?.gold, theirGold >= 10,
               !engine.casusBelli(civ, against: other, in: state) {
                // Paid or refused, either serves: gold now, or a just cause for war.
                if attempt(.propose(to: other, .tribute(gold: min(20, max(5, theirGold / 3)))), &state, &turn) { return }
            }
            // At war: ask friends to stop trading with the enemy, and allies for passage.
            if peace {
                for enemy in others where enemy != other && state.atWar(civ, enemy) {
                    if engine.tradeRoute(between: other, and: enemy, in: state) != nil, offer(.embargo(against: enemy), to: other) { return }
                }
                if engine.allied(civ, other, in: state), !engine.grantsAccess(other, to: civ, in: state),
                   others.contains(where: { state.atWar(civ, $0) && neighbours(other, $0) }), offer(.access, to: other) { return }
            }
        }
    }

    /// Whether the court would rather not go to war on `other` now: a pact, kin, or high
    /// regard holds it back unless it is overwhelmingly stronger.
    func restrained(_ civ: CivilizationID, from other: CivilizationID, edge: Double, _ state: GameState) -> Bool {
        let overwhelming = edge >= 2.5
        if engine.pact(civ, other, in: state) != nil { return !overwhelming }
        if engine.married(civ, other, in: state) { return !overwhelming }
        return engine.regard(of: civ, toward: other, in: state) >= 40 && edge < 2
    }
}
