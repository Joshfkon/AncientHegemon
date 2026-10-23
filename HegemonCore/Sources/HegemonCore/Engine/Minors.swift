/// Minor kingdoms (Josh: "making the smaller regions have their own AIs and personalities… not
/// playable for users"; "make the independent regions stronger… leaders for them and let them
/// be their own AIs and expand"). Every native land that isn't a barbarian homeland starts as a
/// named kingdom with a ruler and a temperament, and its own banner: its warriors are its own,
/// not just "natives". Kingdoms remember how each empire treats them (gifts warm them, attacks
/// and threats chill them, and their neighbours take fright) and act each round: their
/// warriors grow back; warlike and proud kingdoms take weakly held land next door (empty land,
/// tribes, other kingdoms, and the land of empires they hate) and grow into realms of several
/// lands; warlike ones raid empires they hate; mercantile ones trade with friends; a kingdom
/// that loves an empire may come over of its own accord. Their people take up arms to defend
/// their homes, as an empire's do.
///
/// Vassals (Josh: "an option to have a conquered country be a vassal state. lots of
/// advantages"). A kingdom overawed by your troops, or fond enough of you, can swear to you
/// instead of being conquered. A vassal keeps its lands and warriors and needs no garrison, so
/// it causes no unrest; it pays tribute every turn, sends warriors when you levy them, adds to
/// your prestige, and is shielded from anyone at peace with you. Your armies may march through
/// its land and be stationed there to defend it. After some loyal rounds you may annex it
/// peacefully. Leave it without troops nearby and it may break free.

public enum Temperament: String, Codable, Sendable, CaseIterable, CodingKeyRepresentable {
    case warlike, proud, mercantile, peaceable
}

public struct People: Codable, Sendable, Equatable {
    public let name: String
    public let ruler: String
    public let temperament: Temperament
    /// How their ruler dresses (see RulerFigure in the app).
    public let look: String?
}

public struct MinorRules: Codable, Sendable, Equatable {
    public let peoples: [TerritoryID: People]
    /// Where a kingdom's feelings toward each empire start, and drift back to.
    public let baseAttitude: [Temperament: Int]
    /// Gifts warm them even when they don't bow; threats and refused terms chill them.
    public let giftAttitude: Int
    public let demandRefusedAttitude: Int
    public let vassalRefusedAttitude: Int
    /// Attacked: the kingdom itself, and (fear) every kingdom next door.
    public let attackedAttitude: Int
    public let fearAttitude: Int
    /// Attitudes move this much a round back toward the temperament's base.
    public let drift: Int
    /// A warrior grows back in each land every so many rounds, up to the land's natural
    /// strength (as at the start) plus this many.
    public let growthRounds: Int
    public let growthCap: Int
    /// Warlike kingdoms raid empires they feel this badly about, with this chance a round, when
    /// they have enough warriors and the target land is weakly held. A raid carries off gold.
    public let raidAttitude: Int
    public let raidPercent: Int
    public let raidMinWarriors: Int
    public let raidGold: Int
    /// Each round a kingdom may try to take one land next door, with this chance by temperament,
    /// sending all but one warrior of a land with at least `expandMinWarriors`, and only where
    /// they outnumber the defenders (garrison and levy) by `expandRatioPercent`. Peaceable and
    /// mercantile kingdoms only settle empty land; empires' land is taken only by the warlike,
    /// and only from empires they hate. Nobody's capital is taken.
    public let expandPercent: [Temperament: Int]
    /// The levy a kingdom's people raise in defence of their land, in percent of an empire's.
    public let levyPercent: Int
    public let expandMinWarriors: Int
    public let expandRatioPercent: Int
    /// Mercantile kingdoms pay this much gold a turn to each empire they're friendly with.
    public let friendAttitude: Int
    public let friendGold: Int
    /// A kingdom this fond of a neighbouring empire may come over, with this chance a round.
    public let joinAttitude: Int
    public let joinPercent: Int
    /// They swear as vassals when your troops next to their lands outnumber all their warriors
    /// this many times, or when they like you this much.
    public let vassalRatio: Int
    public let vassalAttitude: Int
    /// Tribute a turn: base, plus one gold for every so much of the kingdom's grain.
    public let tributeBase: Int
    public let tributeGrainPerGold: Int
    /// Rounds between levies, and loyal rounds before a vassal can be annexed.
    public let levyRounds: Int
    public let annexRounds: Int
    /// Annexing then costs gold (buying off their nobles: per land and per warrior), and the
    /// overlord's troops with them or next door must outnumber their warriors this many times.
    public let annexGoldPerLand: Int
    public let annexGoldPerWarrior: Int
    public let annexRatio: Int
    /// Chance a round that a vassal with none of its overlord's troops nearby breaks free.
    public let breakFreePercent: Int
    public let vassalPrestige: Int
}

/// A kingdom: a named people, its ruler, and what it remembers. Its lands are wherever its
/// warriors stand on unclaimed land (or stand beside its overlord's garrison).
public struct Kingdom: Codable, Sendable, Equatable {
    /// The land the people came from: their entry in the rules.
    public let homeland: TerritoryID
    public let name: String
    public let ruler: String
    public var attitude: [CivilizationID: Int] = [:]
    public var overlord: CivilizationID?
    public var vassalSince: Int?
    public var lastLevy: Int?

    public init(homeland: TerritoryID, name: String, ruler: String) {
        self.homeland = homeland
        self.name = name
        self.ruler = ruler
    }
}

/// A kingdom's warriors standing beside its overlord's garrison in one of its lands.
public struct Stationed: Codable, Sendable, Equatable {
    public let kingdom: CivilizationID
    public var warriors: Int
}

/// A kingdom's banner: its warriors are owned by this id.
public func kingdomID(_ homeland: TerritoryID) -> CivilizationID { "k_" + homeland }
public func isKingdom(_ id: CivilizationID?) -> Bool { id?.hasPrefix("k_") ?? false }
/// Natives of any kind: a nameless tribe or a kingdom.
public func isNative(_ id: CivilizationID?) -> Bool { id == nativesID || isKingdom(id) }

extension Engine {
    // MARK: Who they are and how they feel

    /// The kingdom holding a territory: its warriors stand on the unclaimed land, or beside its
    /// overlord's garrison there.
    public func kingdom(at territory: TerritoryID, in state: GameState) -> CivilizationID? {
        guard state.owner(of: territory) == nil else { return nil }
        if let st = state.stationed[territory], state.kingdoms[st.kingdom] != nil { return st.kingdom }
        guard let owner = state.armies[territory]?.owner, isKingdom(owner), state.kingdoms[owner] != nil else { return nil }
        return owner
    }

    /// A kingdom's lands.
    public func lands(of kingdom: CivilizationID, in state: GameState) -> [TerritoryID] {
        map.territories.map(\.id).filter { self.kingdom(at: $0, in: state) == kingdom }
    }

    public func people(of kingdom: CivilizationID, in state: GameState) -> People? {
        state.kingdoms[kingdom].flatMap { people(from: $0.homeland) }
    }

    /// The named people whose homeland a territory is: a generated world's own, else the rules'.
    public func people(from homeland: TerritoryID) -> People? {
        map.peoples.map { $0[homeland] } ?? rules.minors.peoples[homeland]
    }

    /// The people of the kingdom holding a territory, if one does.
    public func people(at territory: TerritoryID, in state: GameState) -> People? {
        kingdom(at: territory, in: state).flatMap { people(of: $0, in: state) }
    }

    /// The natives' own warriors in a territory, whether they hold it alone or beside a garrison.
    public func warriors(at territory: TerritoryID, in state: GameState) -> Int {
        state.stationed[territory]?.warriors ?? state.armies[territory].map { isNative($0.owner) ? $0.units.total : 0 } ?? 0
    }

    /// All a kingdom's warriors.
    public func warriors(of kingdom: CivilizationID, in state: GameState) -> Int {
        lands(of: kingdom, in: state).reduce(0) { $0 + warriors(at: $1, in: state) }
    }

    /// Whether the overlord's troops are stationed in a vassal's land.
    public func garrisoned(_ territory: TerritoryID, in state: GameState) -> Bool {
        guard let st = state.stationed[territory] else { return false }
        return state.armies[territory]?.owner == state.kingdoms[st.kingdom]?.overlord
    }

    public func baseAttitude(of kingdom: CivilizationID, in state: GameState) -> Int {
        people(of: kingdom, in: state).map { rules.minors.baseAttitude[$0.temperament] ?? 0 } ?? 0
    }

    /// How a kingdom feels about an empire, from −100 to 100.
    public func attitude(of kingdom: CivilizationID, toward civ: CivilizationID, in state: GameState) -> Int {
        state.kingdoms[kingdom]?.attitude[civ] ?? baseAttitude(of: kingdom, in: state)
    }

    /// How the kingdom holding a territory feels about an empire.
    public func attitude(at territory: TerritoryID, toward civ: CivilizationID, in state: GameState) -> Int {
        kingdom(at: territory, in: state).map { attitude(of: $0, toward: civ, in: state) } ?? 0
    }

    func changeAttitude(of kingdom: CivilizationID, toward civ: CivilizationID, by delta: Int, _ state: inout GameState) {
        guard state.kingdoms[kingdom] != nil else { return }
        let now = attitude(of: kingdom, toward: civ, in: state)
        state.kingdoms[kingdom]!.attitude[civ] = max(-100, min(100, now + delta))
    }

    /// Whose vassal the kingdom holding a territory is, if any.
    public func overlord(of territory: TerritoryID, in state: GameState) -> CivilizationID? {
        kingdom(at: territory, in: state).flatMap { state.kingdoms[$0]?.overlord }
    }

    /// The kingdoms sworn to `civ`, with land.
    public func vassals(of civ: CivilizationID, in state: GameState) -> [CivilizationID] {
        state.kingdoms.filter { $0.value.overlord == civ }.keys
            .filter { !lands(of: $0, in: state).isEmpty }.sorted()
    }

    /// A vassal shielded from `civ`: its own, or the vassal of an empire at peace with it.
    public func shielded(_ territory: TerritoryID, from civ: CivilizationID, in state: GameState) -> Bool {
        guard let lord = overlord(of: territory, in: state) else { return false }
        return lord == civ || state.atPeace(lord, civ)
    }

    /// `civ`'s troops on land bordering any of a kingdom's lands, each army counted once.
    public func troopsNextTo(kingdom: CivilizationID, for civ: CivilizationID, in state: GameState) -> Int {
        let held = Set(lands(of: kingdom, in: state))
        let near = Set(held.flatMap { map.landNeighbors(of: $0) }).subtracting(held)
        return near.reduce(0) { total, n in
            guard let a = state.armies[n], a.owner == civ else { return total }
            return total + a.units.total
        }
    }

    /// Whether the kingdom holding a territory would swear to `civ` as vassals now.
    public func wouldSwear(_ territory: TerritoryID, to civ: CivilizationID, in state: GameState) -> Bool {
        guard let k = kingdom(at: territory, in: state) else { return false }
        let m = rules.minors
        return troopsNextTo(kingdom: k, for: civ, in: state) >= m.vassalRatio * max(1, warriors(of: k, in: state))
            || attitude(of: k, toward: civ, in: state) >= m.vassalAttitude
    }

    /// Tribute a vassal kingdom pays a turn.
    public func tribute(of kingdom: CivilizationID, in state: GameState) -> Int {
        let grain = lands(of: kingdom, in: state).reduce(0) { $0 + (map.territory($1)?.grain ?? 0) }
        return rules.minors.tributeBase + grain / max(1, rules.minors.tributeGrainPerGold)
    }

    /// Tribute the kingdom holding a territory pays (or would pay) a turn.
    public func tribute(at territory: TerritoryID, in state: GameState) -> Int {
        kingdom(at: territory, in: state).map { tribute(of: $0, in: state) } ?? 0
    }

    /// Gold a turn from vassals' tribute and from trading with friendly mercantile kingdoms.
    public func peoplesGold(of civ: CivilizationID, in state: GameState) -> (tribute: Int, trade: Int) {
        let m = rules.minors
        let tribute = vassals(of: civ, in: state).reduce(0) { $0 + tribute(of: $1, in: state) }
        let coasts = Set(state.territories(of: civ).flatMap { map.seas(bordering: $0) })
        let trade = state.kingdoms.keys.filter { k in
            guard people(of: k, in: state)?.temperament == .mercantile, state.kingdoms[k]?.overlord == nil,
                  attitude(of: k, toward: civ, in: state) >= m.friendAttitude else { return false }
            // Within reach: next door, or across a sea the empire's coasts touch.
            return lands(of: k, in: state).contains { t in
                map.landNeighbors(of: t).contains { state.owner(of: $0) == civ }
                    || map.seas(bordering: t).contains(where: coasts.contains)
            }
        }.count * m.friendGold
        return (tribute, trade)
    }

    /// Rounds until the vassal holding a territory may be levied again, or annexed (0: now).
    public func levyWait(_ territory: TerritoryID, in state: GameState) -> Int {
        guard let k = kingdom(at: territory, in: state), let last = state.kingdoms[k]?.lastLevy else { return 0 }
        return max(0, last + rules.minors.levyRounds - state.turn)
    }

    public func annexWait(_ territory: TerritoryID, in state: GameState) -> Int {
        guard let k = kingdom(at: territory, in: state), let since = state.kingdoms[k]?.vassalSince else {
            return rules.minors.annexRounds
        }
        return max(0, since + rules.minors.annexRounds - state.turn)
    }

    /// A vassal's land an army of `civ` can march straight through from `from` to reach `to`
    /// in one order (its warriors stand aside for their overlord), if there is one.
    public func vassalPassage(_ from: TerritoryID, _ to: TerritoryID, for civ: CivilizationID,
                              in state: GameState) -> TerritoryID? {
        guard from != to else { return nil }
        return map.landNeighbors(of: from).sorted().first { v in
            overlord(of: v, in: state) == civ && v != to && map.areLandAdjacent(v, to)
        }
    }

    /// Land beyond `civ`'s vassals that an army in `from` can reach in one march, with the vassal
    /// passed through.
    public func passageTargets(from: TerritoryID, for civ: CivilizationID, in state: GameState) -> [TerritoryID: TerritoryID] {
        let near = Set(map.landNeighbors(of: from))
        var result: [TerritoryID: TerritoryID] = [:]
        for v in near.sorted() where overlord(of: v, in: state) == civ {
            for to in map.landNeighbors(of: v).sorted() where to != from && !near.contains(to) && result[to] == nil {
                if overlord(of: to, in: state) == civ { continue }
                result[to] = v
            }
        }
        return result
    }

    // MARK: Garrisons

    /// The overlord's troops march into a vassal's land to defend it: the kingdom's warriors
    /// there stand with them.
    func station(_ units: UnitCounts, battles: Int, in territory: TerritoryID, by civ: CivilizationID, _ state: inout GameState) {
        if state.stationed[territory] == nil, let k = kingdom(at: territory, in: state) {
            state.stationed[territory] = Stationed(kingdom: k, warriors: warriors(at: territory, in: state))
            state.armies[territory] = nil
        }
        join(units, battles: battles, to: territory, owner: civ, &state)
        state.moved[territory, default: .zero] += units
    }

    /// Once the last of a garrison has gone, the kingdom holds its land alone again; once the
    /// land is lost, its warriors there are gone.
    func settleGarrisons(_ state: inout GameState) {
        for (t, st) in state.stationed {
            let lord = state.kingdoms[st.kingdom]?.overlord
            if state.armies[t] == nil, state.owner(of: t) == nil, state.kingdoms[st.kingdom] != nil {
                state.armies[t] = st.warriors > 0 ? Army(owner: st.kingdom, units: UnitCounts(infantry: st.warriors)) : nil
                state.stationed[t] = nil
            } else if state.armies[t]?.owner != lord || state.owner(of: t) != nil {
                state.stationed[t] = nil
            }
        }
    }

    // MARK: Being attacked

    /// An empire attacks a kingdom: it hates the empire for it, and its neighbours fear it.
    func notePeopleAttacked(_ territory: TerritoryID, by civ: CivilizationID, _ state: inout GameState) {
        guard let k = kingdom(at: territory, in: state), state.isPlayer(civ) else { return }
        changeAttitude(of: k, toward: civ, by: rules.minors.attackedAttitude, &state)
        let near = Set(map.landNeighbors(of: territory).compactMap { kingdom(at: $0, in: state) }).subtracting([k])
        for n in near.sorted() { changeAttitude(of: n, toward: civ, by: rules.minors.fearAttitude, &state) }
    }

    // MARK: Orders

    /// The kingdom holding a territory swears to `civ`: it keeps its lands and warriors.
    func swear(_ territory: TerritoryID, to civ: CivilizationID, _ state: inout GameState) -> [GameEvent] {
        guard let k = kingdom(at: territory, in: state) else { return [] }
        state.kingdoms[k]!.overlord = civ
        state.kingdoms[k]!.vassalSince = state.turn
        state.kingdoms[k]!.lastLevy = nil
        state.kingdoms[k]!.attitude[civ] = max(attitude(of: k, toward: civ, in: state), 50)
        return [.vassalSworn(civ: civ, territory: territory)]
    }

    /// A whole kingdom comes over to `civ`: its lands become the empire's, and some of its
    /// warriors (all of them, when `all`) take service. Returns the warriors who joined.
    func absorb(_ k: CivilizationID, into civ: CivilizationID, joinPercent: Int, settled: Bool, _ state: inout GameState) -> Int {
        var joined = 0
        for t in lands(of: k, in: state) {
            let own = UnitCounts(infantry: warriors(at: t, in: state) * joinPercent / 100)
            joined += own.total
            if garrisoned(t, in: state) {
                state.armies[t]!.units += own
            } else {
                state.armies[t] = own.isEmpty ? nil : Army(owner: civ, units: own)
            }
            state.stationed[t] = nil
            state.land[t]!.owner = civ
            // Won over by talk, the land is restless a while; annexed after loyal years, it isn't.
            if !settled { taken(t, &state) }
        }
        state.kingdoms[k] = nil
        return joined
    }

    /// Calls up half the vassal's warriors in one land into neighbouring land of the overlord's.
    /// They arrive having marched.
    func levy(_ territory: TerritoryID, to: TerritoryID, _ state: inout GameState) throws -> [GameEvent] {
        let civ = state.activePlayer
        guard overlord(of: territory, in: state) == civ, let k = kingdom(at: territory, in: state) else {
            throw GameError.notVassal(territory)
        }
        guard map.areLandAdjacent(territory, to), state.owner(of: to) == civ,
              state.armies[to].map({ $0.owner == civ }) ?? true else { throw GameError.notAdjacent(territory, to) }
        guard levyWait(territory, in: state) == 0 else { throw GameError.tooSoon(territory) }
        let called = warriors(at: territory, in: state) / 2
        guard called > 0 else { throw GameError.insufficientUnits(territory) }
        if state.stationed[territory] != nil {
            state.stationed[territory]!.warriors -= called
        } else {
            state.armies[territory]!.units.infantry -= called
        }
        let units = UnitCounts(infantry: called)
        join(units, battles: 0, to: to, owner: civ, &state)
        state.moved[to, default: .zero] += units
        state.kingdoms[k]!.lastLevy = state.turn
        return [.levied(civ: civ, territory: territory, to: to, warriors: called)]
    }

    /// After loyal years, the vassal's lands become the overlord's, quietly: no unrest, and its
    /// warriors take service.
    /// What annexing the vassal holding a territory would take: gold, and troops with them or
    /// next door (and how many `civ` has there now).
    public func annexTerms(_ territory: TerritoryID, for civ: CivilizationID, in state: GameState)
        -> (gold: Int, troopsNeeded: Int, troops: Int) {
        guard let k = kingdom(at: territory, in: state) else { return (0, 0, 0) }
        let m = rules.minors
        let lands = lands(of: k, in: state)
        let warriors = warriors(of: k, in: state)
        let garrisons = lands.reduce(0) { $0 + (garrisoned($1, in: state) ? state.armies[$1]!.units.total : 0) }
        return (lands.count * m.annexGoldPerLand + warriors * m.annexGoldPerWarrior,
                warriors * m.annexRatio, garrisons + troopsNextTo(kingdom: k, for: civ, in: state))
    }

    /// Whether `civ` could annex the vassal holding a territory now.
    public func canAnnex(_ territory: TerritoryID, for civ: CivilizationID, in state: GameState) -> Bool {
        guard overlord(of: territory, in: state) == civ, annexWait(territory, in: state) == 0 else { return false }
        let terms = annexTerms(territory, for: civ, in: state)
        return (state.civs[civ]?.gold ?? 0) >= terms.gold && terms.troops >= terms.troopsNeeded
    }

    func annex(_ territory: TerritoryID, _ state: inout GameState) throws -> [GameEvent] {
        let civ = state.activePlayer
        guard overlord(of: territory, in: state) == civ, let k = kingdom(at: territory, in: state) else {
            throw GameError.notVassal(territory)
        }
        guard annexWait(territory, in: state) == 0 else { throw GameError.tooSoon(territory) }
        let terms = annexTerms(territory, for: civ, in: state)
        guard terms.troops >= terms.troopsNeeded else { throw GameError.insufficientUnits(territory) }
        let gold = state.civs[civ]!.gold
        guard gold >= terms.gold else { throw GameError.insufficientGold(needed: terms.gold, available: gold) }
        state.civs[civ]!.gold -= terms.gold
        _ = absorb(k, into: civ, joinPercent: 100, settled: true, &state)
        var events: [GameEvent] = [.annexed(civ: civ, territory: territory)]
        events += checkDomination(civ, &state)
        return events
    }

    func checkDomination(_ civ: CivilizationID, _ state: inout GameState) -> [GameEvent] {
        guard state.winner == nil,
              state.territories(of: civ).count * 100 >= map.territories.count * rules.victory.territoryPercent else { return [] }
        return declareVictory(civ, .domination, &state)
    }

    // MARK: The kingdoms' round

    /// Once a round, each kingdom acts on its own.
    func minorsRound(_ state: inout GameState) -> [GameEvent] {
        let m = rules.minors
        var events: [GameEvent] = []
        for k in state.kingdoms.keys.sorted() {
            guard let kingdom = state.kingdoms[k] else { continue }
            let held = lands(of: k, in: state)
            // Conquered, overrun or won over: the kingdom is gone.
            guard !held.isEmpty, let people = people(of: k, in: state) else {
                if let lord = kingdom.overlord { events.append(.vassalFreed(civ: lord, territory: kingdom.homeland)) }
                state.kingdoms[k] = nil
                continue
            }
            // Feelings fade back toward their nature.
            let base = baseAttitude(of: k, in: state)
            for (civ, a) in kingdom.attitude.sorted(by: { $0.key < $1.key }) {
                state.kingdoms[k]!.attitude[civ] = a > base ? max(base, a - m.drift) : min(base, a + m.drift)
            }
            // Warriors grow back, land by land.
            if state.turn % max(1, m.growthRounds) == 0 {
                for t in held where warriors(at: t, in: state) < naturalStrength(t) + m.growthCap {
                    if state.stationed[t] != nil { state.stationed[t]!.warriors += 1 }
                    else if state.armies[t]?.owner == k { state.armies[t]!.units.infantry += 1 }
                }
            }
            if let lord = kingdom.overlord {
                // A vassal with none of its overlord's troops at hand, or whose overlord has
                // fallen, may throw off the yoke.
                let fallen = state.civs[lord]?.eliminated ?? true
                let watched = troopsNextTo(kingdom: k, for: lord, in: state) > 0 || held.contains { garrisoned($0, in: state) }
                if fallen || (!watched && Int(state.rng.next() % 100) < m.breakFreePercent) {
                    state.kingdoms[k]!.overlord = nil
                    state.kingdoms[k]!.vassalSince = nil
                    if !fallen { changeAttitude(of: k, toward: lord, by: -30, &state) }
                    events.append(.vassalFreed(civ: lord, territory: kingdom.homeland))
                }
                continue
            }
            events += expand(k, people.temperament, &state)
            if people.temperament == .warlike { events += raid(from: k, &state) }
            events += comeOver(k, &state)
        }
        return events
    }

    /// How many warriors a land supports on its own (as at the start of the game).
    func naturalStrength(_ t: TerritoryID) -> Int {
        rules.start.natives.tribe(in: map.territory(t)!, island: map.landNeighbors(of: t).isEmpty)
    }

    /// A kingdom grows: from its strongest land, it takes one weakly held land next door.
    private func expand(_ k: CivilizationID, _ temperament: Temperament, _ state: inout GameState) -> [GameEvent] {
        let m = rules.minors
        guard Int(state.rng.next() % 100) < (m.expandPercent[temperament] ?? 0) else { return [] }
        let bold = temperament == .warlike || temperament == .proud
        let seats = Set(state.players.compactMap { seat(of: $0, in: state) })
        var best: (from: TerritoryID, to: TerritoryID, score: Int)?
        for from in lands(of: k, in: state) where !garrisoned(from, in: state) && state.armies[from]?.owner == k {
            let band = warriors(at: from, in: state) - 1
            guard band + 1 >= m.expandMinWarriors else { continue }
            for to in map.landNeighbors(of: from).sorted() {
                guard !seats.contains(to), kingdom(at: to, in: state) != k, overlord(of: to, in: state) == nil,
                      !spared(to, state) else { continue }
                let owner = state.owner(of: to)
                if let owner {
                    // Empires' land: only the warlike, and only from empires they hate.
                    guard temperament == .warlike, state.isPlayer(owner),
                          attitude(of: k, toward: owner, in: state) <= m.raidAttitude else { continue }
                } else if let army = state.armies[to] {
                    // Tribes and other kingdoms: only the bold. An empire's army camped there:
                    // only the warlike, and only one they hate.
                    guard bold else { continue }
                    if state.isPlayer(army.owner) {
                        guard temperament == .warlike, attitude(of: k, toward: army.owner, in: state) <= m.raidAttitude else { continue }
                    }
                }
                let held = defenders(of: to, against: k, state).map { $0.army.units.total + $0.levy } ?? 0
                guard band * 100 >= m.expandRatioPercent * held, band > 0 else { continue }
                let score = map.territory(to)!.grain * 2 - held
                if best.map({ score > $0.score || (score == $0.score && to < $0.to) }) ?? true {
                    best = (from, to, score)
                }
            }
        }
        guard let (from, to, _) = best else { return [] }
        let band = warriors(at: from, in: state) - 1
        state.armies[from]!.units.infantry -= band
        let previous = state.owner(of: to) ?? kingdom(at: to, in: state) ?? state.armies[to]?.owner
        let events = raid(k, UnitCounts(infantry: band), into: to, fallback: from, &state)
        if kingdom(at: to, in: state) == k {
            return events + [.kingdomExpanded(kingdom: k, territory: to, from: previous)]
        }
        return events
    }

    /// A warlike kingdom falls on the weakest land of an empire it hates, carries off what it
    /// can and goes home.
    private func raid(from k: CivilizationID, _ state: inout GameState) -> [GameEvent] {
        let m = rules.minors
        guard let home = lands(of: k, in: state).filter({ state.armies[$0]?.owner == k })
            .max(by: { (warriors(at: $0, in: state), $1) < (warriors(at: $1, in: state), $0) }) else { return [] }
        let warriors = warriors(at: home, in: state)
        guard warriors >= m.raidMinWarriors else { return [] }
        let band = warriors / 2 + 1
        let targets = map.landNeighbors(of: home).sorted().filter { t in
            guard let owner = state.owner(of: t), state.isPlayer(owner), !spared(t, state),
                  attitude(of: k, toward: owner, in: state) <= m.raidAttitude else { return false }
            let held = defenders(of: t, against: k, state).map { $0.army.units.total + $0.levy } ?? 0
            return held * 2 < band
        }
        guard !targets.isEmpty, Int(state.rng.next() % 100) < m.raidPercent else { return [] }
        let target = targets[Int(state.rng.next() % UInt64(targets.count))]
        let victim = state.owner(of: target)!
        state.armies[home]!.units.infantry -= band
        var events: [GameEvent] = []
        var survivors = UnitCounts(infantry: band)
        var won = true
        if defenders(of: target, against: k, state) != nil {
            let result = fight(k, survivors, general: nil, plan: BattlePlan(), at: target, approach: .overland, &state)
            events += result.events
            survivors = result.survivors
            won = result.won
        }
        var gold = 0
        if won {
            gold = min(m.raidGold, state.civs[victim]!.gold)
            state.civs[victim]!.gold -= gold
            state.land[target]!.population = max(rules.economy.minPopulation, state.population(of: target) - 1)
        }
        state.armies[home]!.units += survivors
        events.append(.peopleRaided(people: home, territory: target, civ: victim, gold: gold, won: won))
        return events
    }

    /// A kingdom that loves a neighbouring empire may ask to join it.
    private func comeOver(_ k: CivilizationID, _ state: inout GameState) -> [GameEvent] {
        let m = rules.minors
        let held = lands(of: k, in: state)
        let suitors = state.players.filter { civ in
            !(state.civs[civ]?.eliminated ?? true) && attitude(of: k, toward: civ, in: state) >= m.joinAttitude
                && held.contains { map.landNeighbors(of: $0).contains { state.owner(of: $0) == civ } }
        }.sorted { (attitude(of: k, toward: $0, in: state), $1) > (attitude(of: k, toward: $1, in: state), $0) }
        guard let civ = suitors.first, Int(state.rng.next() % 100) < m.joinPercent else { return [] }
        let home = state.kingdoms[k]!.homeland
        let first = held.contains(home) ? home : held[0]
        let warriors = absorb(k, into: civ, joinPercent: rules.tribes.warriorsJoinPercent, settled: false, &state)
        return [.peopleJoined(civ: civ, territory: first, warriors: warriors)] + checkDomination(civ, &state)
    }
}
