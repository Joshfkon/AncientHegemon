/// An order from the active player. The UI and the AI issue the same commands.
public enum Command: Codable, Sendable, Equatable {
    /// Recruit units in an owned territory. Costs gold and turns population into soldiers.
    case recruit(territory: TerritoryID, unit: UnitType, count: Int)
    /// Talk to the tribe on unclaimed land next to yours.
    case parley(territory: TerritoryID, Parley)
    /// Sends soldiers home: on the empire's own land they go back to the fields as people.
    case disband(territory: TerritoryID, units: UnitCounts)
    /// Move units across a land border. Each unit moves once per turn. Entering an unowned or
    /// undefended enemy territory captures it; entering an enemy army's territory is a battle.
    /// With `general`, the general standing in `from` goes with them.
    case move(from: TerritoryID, to: TerritoryID, units: UnitCounts, general: Bool = false)
    /// Choose the formation an army fights in, attacking or defending.
    case setFormation(territory: TerritoryID, formation: FormationID)
    /// Formation, line depth and stratagem together.
    case setBattlePlan(territory: TerritoryID, plan: BattlePlan)
    /// Build ships at a coastal territory in the home network, into one of its seas.
    case buildShips(territory: TerritoryID, sea: SeaZoneID, count: Int)
    /// Sail ships (and the cargo they carry) to an adjacent sea. Ships sail once per turn.
    /// Sailing into an enemy fleet is a naval battle.
    case moveFleet(from: SeaZoneID, to: SeaZoneID, ships: Int, cargo: UnitCounts = .zero)
    /// Load units that haven't moved this turn onto the civilization's fleet in an adjacent sea.
    case embark(territory: TerritoryID, sea: SeaZoneID, units: UnitCounts)
    /// Land units from a fleet onto a coast. Uses their move; landing on an enemy army is an
    /// amphibious battle.
    case land(sea: SeaZoneID, territory: TerritoryID, units: UnitCounts)
    /// Offer peace. The other civilization accepts on its turn.
    case offerPeace(to: CivilizationID)
    /// Accept an outstanding peace offer.
    case acceptPeace(from: CivilizationID)
    /// End a peace. Withdraws any offers between the two.
    case declareWar(on: CivilizationID)
    /// Appoint a new general to lead the army in a home territory. Costs gold.
    case appointGeneral(territory: TerritoryID)
    /// Shower a general with honors: costs gold (more for famous ones), restores loyalty.
    case honorGeneral(GeneralID)
    /// Set the tax rate (0–100, in steps of 10).
    case setTaxRate(Int)
    /// Start a project in an owned home territory. Costs are paid up front.
    case build(territory: TerritoryID, project: ProjectKind)
    /// Decide a contested succession (only offered to human rulers).
    case resolveCrisis(CrisisChoice)
    /// End the active player's turn.
    case endTurn
}

/// Something that happened as a result of a command, for the UI, logs and the simulator.
public enum GameEvent: Codable, Sendable, Equatable {
    case harvest(civ: CivilizationID, production: Int, consumption: Int, grown: Int, granary: Int, income: Int)
    case starvation(civ: CivilizationID, populationLost: Int, unitsLost: Int)
    /// Grain bought from trade partners to cover a short harvest.
    case grainImported(civ: CivilizationID, grain: Int, gold: Int)
    case outOfSupply(civ: CivilizationID, territory: TerritoryID, unitsLost: Int)
    case trade(civ: CivilizationID, partners: [CivilizationID], income: Int)
    case bronzeMade(civ: CivilizationID, amount: Int)
    case peaceOffered(from: CivilizationID, to: CivilizationID)
    case peaceMade(CivPair)
    case warDeclared(by: CivilizationID, on: CivilizationID)
    case recruited(civ: CivilizationID, territory: TerritoryID, unit: UnitType, count: Int)
    case disbanded(civ: CivilizationID, territory: TerritoryID, units: UnitCounts, rejoined: Int)
    case tribeJoined(civ: CivilizationID, territory: TerritoryID, parley: Parley, warriors: Int)
    case tribeRefused(civ: CivilizationID, territory: TerritoryID, parley: Parley)
    case moved(civ: CivilizationID, from: TerritoryID, to: TerritoryID, units: UnitCounts)
    case captured(civ: CivilizationID, territory: TerritoryID, from: CivilizationID?)
    case formationSet(civ: CivilizationID, territory: TerritoryID, formation: FormationID)
    case battlePlanSet(civ: CivilizationID, territory: TerritoryID, plan: BattlePlan)
    case battle(BattleReport)
    case navalBattle(sea: SeaZoneID, report: NavalReport)
    case retreated(civ: CivilizationID, from: TerritoryID, to: TerritoryID, units: UnitCounts)
    case fleetRetreated(civ: CivilizationID, from: SeaZoneID, to: SeaZoneID, ships: Int)
    /// Units wiped out with nowhere to retreat, or lost at sea with sunk ships.
    case destroyed(civ: CivilizationID, units: UnitCounts, ships: Int)
    case generalKilled(GeneralID)
    case shipsBuilt(civ: CivilizationID, sea: SeaZoneID, count: Int)
    case fleetMoved(civ: CivilizationID, from: SeaZoneID, to: SeaZoneID, ships: Int, cargo: UnitCounts)
    case embarked(civ: CivilizationID, territory: TerritoryID, sea: SeaZoneID, units: UnitCounts)
    case landed(civ: CivilizationID, sea: SeaZoneID, territory: TerritoryID, units: UnitCounts)
    case eliminated(civ: CivilizationID)
    case victory(civ: CivilizationID)
    case turnStarted(civ: CivilizationID, turn: Int)
    case rulerDied(civ: CivilizationID, name: String, age: Int, cause: DeathCause)
    case succession(civ: CivilizationID, ruler: String, outcome: SuccessionOutcome)
    case heirBorn(civ: CivilizationID, name: String)
    /// A human ruler must decide a contested succession before doing anything else.
    case successionCrisis(civ: CivilizationID, claimants: [GeneralID])
    /// A general rose up: `rebel` is the new civilization, holding `territories`.
    case civilWar(civ: CivilizationID, rebel: CivilizationID, general: GeneralID, territories: [TerritoryID])
    case generalAppointed(civ: CivilizationID, general: GeneralID)
    case taxRateSet(civ: CivilizationID, rate: Int)
    /// A civilization reached a new level in a field of knowledge.
    case discovery(civ: CivilizationID, field: KnowledgeField, level: Int)
    case projectStarted(civ: CivilizationID, territory: TerritoryID, project: ProjectKind)
    case projectCompleted(civ: CivilizationID, territory: TerritoryID, project: ProjectKind)
    case projectDestroyed(territory: TerritoryID, project: ProjectKind)
    case generalHonored(GeneralID)
    case generalsUnpaid(civ: CivilizationID, count: Int)
    case event(EventReport)
}

public enum CrisisChoice: String, Codable, Sendable, CaseIterable {
    /// Buy off every claimant with gold.
    case payOff
    /// Give the throne to the strongest claimant: a new dynasty, but no war.
    case crownClaimant
    /// Refuse them all: each claimant rises in civil war.
    case standFirm
}

public enum DeathCause: String, Codable, Sendable {
    case oldAge, plague
}

public enum SuccessionOutcome: String, Codable, Sendable {
    /// An adult heir or an elected successor took over.
    case smooth
    /// A child or missing heir: a regent rules, legitimacy suffers.
    case regency
    /// Rival claimants were paid off.
    case bribed
    /// Claimants could not be bought: civil war.
    case civilWar
    /// A famous general seized the republic and made himself king.
    case coup
    /// The realm crowned the strongest claimant to avoid war.
    case claimantCrowned
}

/// A random event striking a civilization (DESIGN §8).
public struct EventReport: Codable, Sendable, Equatable {
    public let kind: EventKind
    public let civ: CivilizationID
    public let territory: TerritoryID?
    /// Population lost, units in a horde, grain percent, and so on, depending on the kind.
    public let amount: Int
    /// The other civilization involved, e.g. the partner of a broken trade route.
    public var partner: CivilizationID? = nil
}

public enum GameError: Error, Equatable, Sendable {
    case gameOver
    case unknownCivilization(CivilizationID)
    case alreadyAtPeace(CivilizationID)
    case notAtPeace(CivilizationID)
    case noPeaceOffer(CivilizationID)
    /// Recruiting needs a territory in the home supply network.
    case outOfSupply(TerritoryID)
    /// Armies can't enter a peace partner's territory; declare war first.
    case atPeace(TerritoryID)
    case unknownTerritory(TerritoryID)
    case notOwner(TerritoryID)
    case invalidCount
    case insufficientGold(needed: Int, available: Int)
    case insufficientPopulation(TerritoryID)
    case resourceLimit(Resource)
    case notAdjacent(TerritoryID, TerritoryID)
    case insufficientUnits(TerritoryID)
    /// Recruiting where another civilization's army stands.
    case contested(TerritoryID)
    case unknownFormation(FormationID)
    case noGeneral(TerritoryID)
    case unknownSea(SeaZoneID)
    case notCoastal(TerritoryID, SeaZoneID)
    case noFleet(SeaZoneID)
    case insufficientShips(SeaZoneID)
    case overCapacity(SeaZoneID)
    /// The sea lane is shut by an enemy-held chokepoint.
    case chokepointClosed(SeaZoneID, SeaZoneID)
    /// An enemy fleet controls the sea.
    case blockaded(SeaZoneID)
    /// The omens forbid attacking this turn.
    case badOmen
    case unknownGeneral(GeneralID)
    case tooManyGenerals
    /// A succession crisis must be resolved first.
    case crisisPending
    case noCrisis
    case invalidTaxRate
    /// The formation or stratagem isn't unlocked for this army.
    case planLocked
    case noTribe(TerritoryID)
    /// Each tribe hears one embassy a turn.
    case alreadyParleyed(TerritoryID)
    /// Already built, or something is being built there.
    case projectUnavailable(TerritoryID, ProjectKind)
    case insufficientStock(Resource, needed: Int, available: Int)
}
