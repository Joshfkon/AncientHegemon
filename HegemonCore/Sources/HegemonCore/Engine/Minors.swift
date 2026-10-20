/// Minor kingdoms (Josh: "making the smaller regions have their own AIs and personalities… not
/// playable for users"). Every native land that isn't a barbarian homeland is home to a named
/// people with a ruler and a temperament. They remember how each empire treats them: gifts warm
/// them, attacks and threats chill them, and their neighbours take fright. Each round they act:
/// their warriors grow back, warlike peoples raid empires they hate, mercantile ones trade with
/// their friends, and a people that loves an empire may come over of its own accord.
///
/// Vassals (Josh: "an option to have a conquered country be a vassal state. lots of
/// advantages"). A people overawed by your troops, or fond enough of you, can swear to you
/// instead of being conquered. A vassal keeps its land and warriors and needs no garrison, so it
/// causes no unrest; it pays tribute every turn, sends warriors when you levy them, adds to your
/// prestige, and is shielded from anyone at peace with you. After some loyal rounds you may annex
/// it peacefully. Leave it without troops nearby and it may break free.

public enum Temperament: String, Codable, Sendable, CaseIterable, CodingKeyRepresentable {
    case warlike, proud, mercantile, peaceable
}

public struct People: Codable, Sendable, Equatable {
    public let name: String
    public let ruler: String
    public let temperament: Temperament
}

public struct MinorRules: Codable, Sendable, Equatable {
    public let peoples: [TerritoryID: People]
    /// Where a people's feelings toward each empire start, and drift back to.
    public let baseAttitude: [Temperament: Int]
    /// Gifts warm them even when they don't bow; threats and refused terms chill them.
    public let giftAttitude: Int
    public let demandRefusedAttitude: Int
    public let vassalRefusedAttitude: Int
    /// Attacked: the people itself, and (fear) every people next door.
    public let attackedAttitude: Int
    public let fearAttitude: Int
    /// Attitudes move this much a round back toward the temperament's base.
    public let drift: Int
    /// A warrior grows back every so many rounds, up to this many beyond the people's start.
    public let growthRounds: Int
    public let growthCap: Int
    /// Warlike peoples raid empires they feel this badly about, with this chance a round, when
    /// they have enough warriors and the target land is weakly held. A raid carries off gold.
    public let raidAttitude: Int
    public let raidPercent: Int
    public let raidMinWarriors: Int
    public let raidGold: Int
    /// Mercantile peoples pay this much gold a turn to each empire they're friendly with.
    public let friendAttitude: Int
    public let friendGold: Int
    /// A people this fond of a neighbouring empire may come over, with this chance a round.
    public let joinAttitude: Int
    public let joinPercent: Int
    /// They swear as vassals when your troops next door outnumber them this many times, or
    /// when they like you this much.
    public let vassalRatio: Int
    public let vassalAttitude: Int
    /// Tribute a turn: base, plus one gold for every so much of the land's grain.
    public let tributeBase: Int
    public let tributeGrainPerGold: Int
    /// Rounds between levies, and loyal rounds before a vassal can be annexed.
    public let levyRounds: Int
    public let annexRounds: Int
    /// Chance a round that a vassal with none of its overlord's troops next door breaks free.
    public let breakFreePercent: Int
    public let vassalPrestige: Int
}

/// What a people remembers.
public struct MinorState: Codable, Sendable, Equatable {
    public var attitude: [CivilizationID: Int] = [:]
    public var overlord: CivilizationID?
    public var vassalSince: Int?
    public var lastLevy: Int?
    /// Warriors at the start of the game; they grow back to a little beyond this.
    public var startWarriors: Int
    /// While the overlord's troops are stationed here, the people's own warriors (they stand
    /// with the garrison and fight beside it).
    public var stationed: Int?

    public init(startWarriors: Int) {
        self.startWarriors = startWarriors
    }
}

extension Engine {
    // MARK: Who they are and how they feel

    /// The people living in an unclaimed territory, if a minor kingdom holds it: their warriors
    /// hold it, or their overlord's garrison stands with them.
    public func people(at territory: TerritoryID, in state: GameState) -> People? {
        guard let minor = state.minors[territory], state.owner(of: territory) == nil else { return nil }
        let holder = state.armies[territory]?.owner
        let held = minor.stationed != nil ? holder == nil || holder == minor.overlord : holder == nativesID
        return held ? rules.minors.peoples[territory] : nil
    }

    /// The people's own warriors, whether they hold the land alone or beside a garrison.
    public func warriors(at territory: TerritoryID, in state: GameState) -> Int {
        state.minors[territory]?.stationed ?? state.armies[territory].map { $0.owner == nativesID ? $0.units.total : 0 } ?? 0
    }

    /// Whether the overlord's troops are stationed in a vassal's land.
    public func garrisoned(_ territory: TerritoryID, in state: GameState) -> Bool {
        state.minors[territory]?.stationed != nil && state.armies[territory]?.owner == state.minors[territory]?.overlord
    }

    /// The overlord's troops march into a vassal's land to defend it: the people's warriors
    /// stand with them.
    func station(_ units: UnitCounts, battles: Int, in territory: TerritoryID, by civ: CivilizationID, _ state: inout GameState) {
        if state.minors[territory]!.stationed == nil {
            state.minors[territory]!.stationed = warriors(at: territory, in: state)
            state.armies[territory] = nil
        }
        join(units, battles: battles, to: territory, owner: civ, &state)
        state.moved[territory, default: .zero] += units
    }

    /// Once the last of a garrison has gone, the people hold their land alone again.
    func settleGarrisons(_ state: inout GameState) {
        for (t, minor) in state.minors where minor.stationed != nil {
            if state.armies[t] == nil {
                let w = minor.stationed!
                state.armies[t] = w > 0 ? Army(owner: nativesID, units: UnitCounts(infantry: w)) : nil
                state.minors[t]!.stationed = nil
            } else if state.armies[t]?.owner != minor.overlord {
                state.minors[t]!.stationed = nil
            }
        }
    }

    public func baseAttitude(_ territory: TerritoryID) -> Int {
        rules.minors.peoples[territory].map { rules.minors.baseAttitude[$0.temperament] ?? 0 } ?? 0
    }

    /// How a people feels about an empire, from −100 to 100.
    public func attitude(of territory: TerritoryID, toward civ: CivilizationID, in state: GameState) -> Int {
        state.minors[territory]?.attitude[civ] ?? baseAttitude(territory)
    }

    func changeAttitude(of territory: TerritoryID, toward civ: CivilizationID, by delta: Int, _ state: inout GameState) {
        guard state.minors[territory] != nil else { return }
        let now = attitude(of: territory, toward: civ, in: state)
        state.minors[territory]!.attitude[civ] = max(-100, min(100, now + delta))
    }

    /// Whose vassal a territory is, if any.
    public func overlord(of territory: TerritoryID, in state: GameState) -> CivilizationID? {
        people(at: territory, in: state) != nil ? state.minors[territory]?.overlord : nil
    }

    public func vassals(of civ: CivilizationID, in state: GameState) -> [TerritoryID] {
        state.minors.keys.filter { overlord(of: $0, in: state) == civ }.sorted()
    }

    /// A vassal shielded from `civ`: its own, or the vassal of an empire at peace with it.
    public func shielded(_ territory: TerritoryID, from civ: CivilizationID, in state: GameState) -> Bool {
        guard let lord = overlord(of: territory, in: state) else { return false }
        return lord == civ || state.atPeace(lord, civ)
    }

    /// Whether the people would swear to `civ` as vassals now.
    public func wouldSwear(_ territory: TerritoryID, to civ: CivilizationID, in state: GameState) -> Bool {
        let m = rules.minors
        return troopsNextTo(territory, for: civ, in: state) >= m.vassalRatio * max(1, warriors(at: territory, in: state))
            || attitude(of: territory, toward: civ, in: state) >= m.vassalAttitude
    }

    public func tribute(of territory: TerritoryID) -> Int {
        rules.minors.tributeBase + (map.territory(territory)?.grain ?? 0) / max(1, rules.minors.tributeGrainPerGold)
    }

    /// Gold a turn from vassals' tribute and from trading with friendly mercantile peoples.
    public func peoplesGold(of civ: CivilizationID, in state: GameState) -> (tribute: Int, trade: Int) {
        let m = rules.minors
        let tribute = vassals(of: civ, in: state).reduce(0) { $0 + tribute(of: $1) }
        let coasts = Set(state.territories(of: civ).flatMap { map.seas(bordering: $0) })
        let trade = state.minors.keys.filter { t in
            guard people(at: t, in: state)?.temperament == .mercantile, state.minors[t]?.overlord == nil,
                  attitude(of: t, toward: civ, in: state) >= m.friendAttitude else { return false }
            // Within reach: next door, or across a sea the empire's coasts touch.
            return map.landNeighbors(of: t).contains { state.owner(of: $0) == civ }
                || map.seas(bordering: t).contains(where: coasts.contains)
        }.count * m.friendGold
        return (tribute, trade)
    }

    /// Rounds until a vassal may be levied again, or annexed (0: now).
    public func levyWait(_ territory: TerritoryID, in state: GameState) -> Int {
        guard let last = state.minors[territory]?.lastLevy else { return 0 }
        return max(0, last + rules.minors.levyRounds - state.turn)
    }

    public func annexWait(_ territory: TerritoryID, in state: GameState) -> Int {
        guard let since = state.minors[territory]?.vassalSince else { return rules.minors.annexRounds }
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

    // MARK: Being attacked

    /// An empire attacks a people: they hate it for it, and their neighbours fear it.
    func notePeopleAttacked(_ territory: TerritoryID, by civ: CivilizationID, _ state: inout GameState) {
        guard people(at: territory, in: state) != nil, state.isPlayer(civ) else { return }
        changeAttitude(of: territory, toward: civ, by: rules.minors.attackedAttitude, &state)
        for n in map.landNeighbors(of: territory) where people(at: n, in: state) != nil {
            changeAttitude(of: n, toward: civ, by: rules.minors.fearAttitude, &state)
        }
    }

    // MARK: Orders

    /// The people swears to `civ`: they keep their land and warriors.
    func swear(_ territory: TerritoryID, to civ: CivilizationID, _ state: inout GameState) -> [GameEvent] {
        state.minors[territory]!.overlord = civ
        state.minors[territory]!.vassalSince = state.turn
        state.minors[territory]!.lastLevy = nil
        state.minors[territory]!.attitude[civ] = max(attitude(of: territory, toward: civ, in: state), 50)
        return [.vassalSworn(civ: civ, territory: territory)]
    }

    /// Calls up half the vassal's warriors (keeping at least one at home) into neighbouring land
    /// of the overlord's. They arrive having marched.
    func levy(_ territory: TerritoryID, to: TerritoryID, _ state: inout GameState) throws -> [GameEvent] {
        let civ = state.activePlayer
        guard overlord(of: territory, in: state) == civ else { throw GameError.notVassal(territory) }
        guard map.areLandAdjacent(territory, to), state.owner(of: to) == civ,
              state.armies[to].map({ $0.owner == civ }) ?? true else { throw GameError.notAdjacent(territory, to) }
        guard levyWait(territory, in: state) == 0 else { throw GameError.tooSoon(territory) }
        let called = warriors(at: territory, in: state) / 2
        guard called > 0 else { throw GameError.insufficientUnits(territory) }
        if state.minors[territory]!.stationed != nil {
            state.minors[territory]!.stationed! -= called
        } else {
            state.armies[territory]!.units.infantry -= called
        }
        let units = UnitCounts(infantry: called)
        join(units, battles: 0, to: to, owner: civ, &state)
        state.moved[to, default: .zero] += units
        state.minors[territory]!.lastLevy = state.turn
        return [.levied(civ: civ, territory: territory, to: to, warriors: called)]
    }

    /// After loyal years, the vassal's land becomes the overlord's, quietly: no unrest, and its
    /// warriors take service.
    func annex(_ territory: TerritoryID, _ state: inout GameState) throws -> [GameEvent] {
        let civ = state.activePlayer
        guard overlord(of: territory, in: state) == civ else { throw GameError.notVassal(territory) }
        guard annexWait(territory, in: state) == 0 else { throw GameError.tooSoon(territory) }
        // The people's warriors take service, beside any garrison already there.
        let warriors = UnitCounts(infantry: warriors(at: territory, in: state))
        if garrisoned(territory, in: state) {
            state.armies[territory]!.units += warriors
        } else {
            state.armies[territory] = warriors.isEmpty ? nil : Army(owner: civ, units: warriors)
        }
        state.land[territory]!.owner = civ
        state.minors[territory] = nil
        var events: [GameEvent] = [.annexed(civ: civ, territory: territory)]
        if state.winner == nil,
           state.territories(of: civ).count * 100 >= map.territories.count * rules.victory.territoryPercent {
            events += declareVictory(civ, .domination, &state)
        }
        return events
    }

    // MARK: The peoples' round

    /// Once a round, each people acts on its own.
    func minorsRound(_ state: inout GameState) -> [GameEvent] {
        let m = rules.minors
        var events: [GameEvent] = []
        for t in state.minors.keys.sorted() {
            // Conquered, overrun or won over: the people is gone as a kingdom.
            guard let people = people(at: t, in: state) else {
                if let lord = state.minors[t]?.overlord, state.owner(of: t) != lord {
                    events.append(.vassalFreed(civ: lord, territory: t))
                }
                state.minors[t] = nil
                continue
            }
            // Feelings fade back toward their nature.
            for (civ, a) in state.minors[t]!.attitude.sorted(by: { $0.key < $1.key }) {
                let base = baseAttitude(t)
                state.minors[t]!.attitude[civ] = a > base ? max(base, a - m.drift) : min(base, a + m.drift)
            }
            // Warriors grow back.
            if state.turn % max(1, m.growthRounds) == 0,
               warriors(at: t, in: state) < state.minors[t]!.startWarriors + m.growthCap {
                if state.minors[t]!.stationed != nil { state.minors[t]!.stationed! += 1 }
                else if state.armies[t] != nil { state.armies[t]!.units.infantry += 1 }
            }
            if let lord = state.minors[t]!.overlord {
                // A vassal with none of its overlord's troops at hand, or whose overlord has
                // fallen, may throw off the yoke.
                let fallen = state.civs[lord]?.eliminated ?? true
                let watched = troopsNextTo(t, for: lord, in: state) > 0 || garrisoned(t, in: state)
                if fallen || (!watched && Int(state.rng.next() % 100) < m.breakFreePercent) {
                    state.minors[t]!.overlord = nil
                    state.minors[t]!.vassalSince = nil
                    if !fallen { changeAttitude(of: t, toward: lord, by: -30, &state) }
                    events.append(.vassalFreed(civ: lord, territory: t))
                }
                continue
            }
            switch people.temperament {
            case .warlike:
                events += raidFrom(t, &state)
            default:
                break
            }
            events += comeOver(t, &state)
        }
        return events
    }

    /// A warlike people falls on the weakest land of an empire it hates, carries off what it
    /// can and goes home.
    private func raidFrom(_ home: TerritoryID, _ state: inout GameState) -> [GameEvent] {
        let m = rules.minors
        let warriors = state.armies[home]!.units.total
        guard warriors >= m.raidMinWarriors else { return [] }
        let band = warriors / 2 + 1
        let targets = map.landNeighbors(of: home).sorted().filter { t in
            guard let owner = state.owner(of: t), state.isPlayer(owner),
                  attitude(of: home, toward: owner, in: state) <= m.raidAttitude else { return false }
            let held = defenders(of: t, against: nativesID, state).map { $0.army.units.total + $0.levy } ?? 0
            return held * 2 < band
        }
        guard !targets.isEmpty, Int(state.rng.next() % 100) < m.raidPercent else { return [] }
        let target = targets[Int(state.rng.next() % UInt64(targets.count))]
        let victim = state.owner(of: target)!
        state.armies[home]!.units.infantry -= band
        var events: [GameEvent] = []
        var survivors = UnitCounts(infantry: band)
        var won = true
        if defenders(of: target, against: nativesID, state) != nil {
            let result = fight(nativesID, survivors, general: nil, plan: BattlePlan(), at: target, approach: .overland, &state)
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

    /// A people that loves a neighbouring empire may ask to join it.
    private func comeOver(_ t: TerritoryID, _ state: inout GameState) -> [GameEvent] {
        let m = rules.minors
        let suitors = state.players.filter { civ in
            !(state.civs[civ]?.eliminated ?? true) && attitude(of: t, toward: civ, in: state) >= m.joinAttitude
                && map.landNeighbors(of: t).contains { state.owner(of: $0) == civ }
        }.sorted { (attitude(of: t, toward: $0, in: state), $1) > (attitude(of: t, toward: $1, in: state), $0) }
        guard let civ = suitors.first, Int(state.rng.next() % 100) < m.joinPercent else { return [] }
        let warriors = state.armies[t]!.units.total * rules.tribes.warriorsJoinPercent / 100
        state.armies[t] = warriors > 0 ? Army(owner: civ, units: UnitCounts(infantry: warriors)) : nil
        state.land[t]!.owner = civ
        state.minors[t] = nil
        var events: [GameEvent] = [.peopleJoined(civ: civ, territory: t, warriors: warriors)]
        if state.winner == nil,
           state.territories(of: civ).count * 100 >= map.territories.count * rules.victory.territoryPercent {
            events += declareVictory(civ, .domination, &state)
        }
        return events
    }
}
