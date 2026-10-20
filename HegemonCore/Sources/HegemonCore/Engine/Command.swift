/// An order from the active player. The UI and the AI issue the same commands.
public enum Command: Codable, Sendable, Equatable {
    /// Recruit units in an owned territory. Costs gold and turns population into soldiers.
    case recruit(territory: TerritoryID, unit: UnitType, count: Int)
    /// Talk to the tribe on unclaimed land next to yours.
    case parley(territory: TerritoryID, Parley)
    /// Call up half a vassal's warriors into neighbouring land of yours.
    case levy(territory: TerritoryID, to: TerritoryID)
    /// Make a loyal vassal's land your own, peacefully.
    case annex(territory: TerritoryID)
    /// How a fleet fights at sea.
    case setFleetPlan(sea: SeaZoneID, plan: BattlePlan)
    /// Alliances: offer, accept, leave; ask an ally to join a war; answer an ally's call.
    case offerAlliance(to: CivilizationID)
    case acceptAlliance(from: CivilizationID)
    case leaveAlliance(with: CivilizationID)
    case callToWar(ally: CivilizationID, against: CivilizationID)
    case answerCallToWar(from: CivilizationID, against: CivilizationID, join: Bool)
    /// Answers the court's dilemma.
    case decide(accept: Bool)
    /// Pays patrons of one field of learning each turn (nil stops).
    case setPatronage(KnowledgeField?)
    /// Begins a great work.
    case buildMonument(territory: TerritoryID, monument: MonumentID)
    /// Adorns the throne room.
    case decorate(DecorationID)
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
    /// Break up ships to save their upkeep. Ships still needed to carry the troops aboard stay.
    case disbandShips(sea: SeaZoneID, ships: Int)
    /// Load units that haven't moved this turn onto the civilization's fleet in an adjacent sea.
    case embark(territory: TerritoryID, sea: SeaZoneID, units: UnitCounts)
    /// Land units from a fleet onto a coast. Uses their move; landing on an enemy army is an
    /// amphibious battle.
    case land(sea: SeaZoneID, territory: TerritoryID, units: UnitCounts)
    /// Offer peace. The other civilization accepts on its turn.
    case offerPeace(to: CivilizationID)
    /// Accept an outstanding peace offer.
    case acceptPeace(from: CivilizationID)
    /// Turn an offer down: they won't offer again for a while.
    case declinePeace(from: CivilizationID)
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
    /// Line up a project to start (and be paid for) when the one under way finishes.
    case queueProject(territory: TerritoryID, project: ProjectKind)
    case clearQueue(territory: TerritoryID)
    /// Camp the army in `from` before the walls of `territory`: it is cut off, starves and its
    /// walls are worn down each round the siege lasts. Moving the army away lifts it.
    case besiege(territory: TerritoryID, from: TerritoryID)
    case liftSiege(territory: TerritoryID)
    /// One attack on `territory` by several armies at once, from neighbouring land and from
    /// fleets in its seas, fighting as one host. `general` names the land group he leads.
    case assault(territory: TerritoryID, groups: [AssaultGroup], general: TerritoryID?)
    /// Decide a contested succession (only offered to human rulers).
    case resolveCrisis(CrisisChoice)
    /// End the active player's turn.
    case endTurn
    /// Keep playing after the game has been won.
    case playOn
}

/// Something that happened as a result of a command, for the UI, logs and the simulator.
public enum GameEvent: Codable, Sendable, Equatable {
    case harvest(civ: CivilizationID, production: Int, consumption: Int, grown: Int, granary: Int, income: Int)
    case starvation(civ: CivilizationID, populationLost: Int, unitsLost: Int)
    /// Grain bought from trade partners to cover a short harvest.
    case grainImported(civ: CivilizationID, grain: Int, gold: Int)
    /// Soldiers paid this turn; if the treasury fell short, some unpaid soldiers went home.
    case armyPaid(civ: CivilizationID, gold: Int, deserted: Int)
    case outOfSupply(civ: CivilizationID, territory: TerritoryID, unitsLost: Int)
    case trade(civ: CivilizationID, partners: [CivilizationID], income: Int)
    case bronzeMade(civ: CivilizationID, amount: Int)
    case peaceOffered(from: CivilizationID, to: CivilizationID)
    case peaceMade(CivPair)
    case allianceOffered(from: CivilizationID, to: CivilizationID)
    case allianceMade(CivPair)
    case allianceRefused(by: CivilizationID, to: CivilizationID)
    case allianceEnded(CivPair, by: CivilizationID)
    case calledToWar(WarRequest)
    case joinedWar(civ: CivilizationID, against: CivilizationID, ally: CivilizationID)
    case warRefused(by: CivilizationID, ally: CivilizationID, against: CivilizationID)
    case warDeclared(by: CivilizationID, on: CivilizationID)
    case recruited(civ: CivilizationID, territory: TerritoryID, unit: UnitType, count: Int)
    case disbanded(civ: CivilizationID, territory: TerritoryID, units: UnitCounts, rejoined: Int)
    case tribeJoined(civ: CivilizationID, territory: TerritoryID, parley: Parley, warriors: Int)
    case vassalSworn(civ: CivilizationID, territory: TerritoryID)
    /// A vassal threw off its overlord, or was conquered by someone else.
    case vassalFreed(civ: CivilizationID, territory: TerritoryID)
    case levied(civ: CivilizationID, territory: TerritoryID, to: TerritoryID, warriors: Int)
    case annexed(civ: CivilizationID, territory: TerritoryID)
    /// A warlike people raided an empire's land; `won` if they got through to plunder.
    case peopleRaided(people: TerritoryID, territory: TerritoryID, civ: CivilizationID, gold: Int, won: Bool)
    /// A people came over to an empire of its own accord.
    case peopleJoined(civ: CivilizationID, territory: TerritoryID, warriors: Int)
    case decorated(civ: CivilizationID, decoration: DecorationID)
    case patronageSet(civ: CivilizationID, field: KnowledgeField?)
    case decisionOffered(civ: CivilizationID, DecisionKind)
    case decided(civ: CivilizationID, DecisionKind, accepted: Bool)
    case monumentStarted(civ: CivilizationID, territory: TerritoryID, monument: MonumentID)
    case monumentCompleted(civ: CivilizationID, territory: TerritoryID, monument: MonumentID)
    case monumentLost(civ: CivilizationID, territory: TerritoryID, monument: MonumentID)
    case trophyWon(civ: CivilizationID, trophy: TrophyKind)
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
    case shipsDisbanded(civ: CivilizationID, sea: SeaZoneID, count: Int)
    /// A storm sank ships away from shelter, drowning the troops that no longer fit aboard.
    case storm(civ: CivilizationID, sea: SeaZoneID, ships: Int, drowned: UnitCounts)
    case piratesAppeared(sea: SeaZoneID, ships: Int)
    case piratesScattered(sea: SeaZoneID)
    case piratesPlundered(civ: CivilizationID, territory: TerritoryID, gold: Int)
    /// Gold paid for pirate ships sunk.
    case bountyPaid(civ: CivilizationID, gold: Int)
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
    case projectQueued(civ: CivilizationID, territory: TerritoryID, project: ProjectKind)
    case peaceDeclined(by: CivilizationID, offerer: CivilizationID)
    case splendourBegan(civ: CivilizationID)
    case splendourEnded(civ: CivilizationID)
    case ironAgeBegan
    case playingOn
    case capitalSacked(by: CivilizationID, from: CivilizationID, territory: TerritoryID, gold: Int)
    case siegeLaid(civ: CivilizationID, territory: TerritoryID, camp: TerritoryID)
    case siegePressed(civ: CivilizationID, territory: TerritoryID, rounds: Int, starved: Int, sick: Int)
    case siegeLifted(civ: CivilizationID, territory: TerritoryID)
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
    case notVassal(TerritoryID)
    case tooSoon(TerritoryID)
    /// A vassal under the protection of its overlord, or of someone at peace with you.
    case shielded(TerritoryID)
    case gameOver
    case notWalled(TerritoryID)
    case noSiege(TerritoryID)
    case alreadyQueued(TerritoryID)
    case unknownCivilization(CivilizationID)
    case alreadyAtPeace(CivilizationID)
    case notAtPeace(CivilizationID)
    case noPeaceOffer(CivilizationID)
    case alreadyAllied(CivilizationID)
    case unknownMonument(MonumentID)
    case noDecision
    case insufficientGrain(needed: Int)
    case monumentUnavailable(MonumentID)
    case notAllied(CivilizationID)
    case noAllianceOffer(CivilizationID)
    case tooManyAllies
    case notAtWar(CivilizationID)
    case alreadyAsked(CivilizationID)
    case noWarRequest(CivilizationID)
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
    case unknownDecoration(DecorationID)
    case alreadyDecorated(DecorationID)
    case noTribe(TerritoryID)
    /// Each tribe hears one embassy a turn.
    case alreadyParleyed(TerritoryID)
    /// Already built, or something is being built there.
    case projectUnavailable(TerritoryID, ProjectKind)
    case insufficientStock(Resource, needed: Int, available: Int)
}
