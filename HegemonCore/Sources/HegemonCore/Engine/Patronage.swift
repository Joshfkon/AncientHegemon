/// Patronage of learning (Josh: "choose where your learning goes"): pay smiths, scribes,
/// shipwrights or another craft each turn, and that field learns faster. Knowledge still comes
/// from what the realm does; patronage tilts it.

public struct PatronageRules: Codable, Sendable, Equatable {
    /// Gold a turn, and the experience it buys in the chosen field.
    public let gold: Int
    public let experience: Int
}

extension Engine {
    func setPatronage(_ field: KnowledgeField?, _ state: inout GameState) throws -> [GameEvent] {
        let civ = state.activePlayer
        state.civs[civ]!.patronage = field
        return [.patronageSet(civ: civ, field: field)]
    }

    /// Pays this turn's patrons, if the treasury can, and their craft gains experience.
    func payPatrons(_ civ: CivilizationID, _ state: inout GameState) -> [GameEvent] {
        guard let field = state.civs[civ]!.patronage else { return [] }
        let p = rules.patronage
        guard state.civs[civ]!.gold >= p.gold else {
            state.civs[civ]!.patronage = nil
            return [.patronageSet(civ: civ, field: nil)]
        }
        state.civs[civ]!.gold -= p.gold
        addExperience(civ, field, p.experience, &state)
        return []
    }
}
