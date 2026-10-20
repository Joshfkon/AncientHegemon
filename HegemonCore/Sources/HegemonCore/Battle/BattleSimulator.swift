/// Resolves land battles on the 5×5 board (DESIGN §5). Deterministic: the same setup and seed
/// always give the same report. The simulator only reads rules; it never touches game state.
public struct BattleSimulator: Sendable {
    public let rules: Rules

    public init(rules: Rules) {
        self.rules = rules
    }

    private static let size = 5

    private struct Block {
        let id: Int
        let side: BattleSide
        let type: UnitType
        var position: GridPoint
        var hp: Int
        let maxHp: Int
        var morale: Int
        var status: BlockStatus = .fighting
        var charged = false
        /// A holding block that has been struck stops holding and engages.
        var provoked = false
        /// Drawn forward by a feigned retreat and caught out of order: takes extra damage.
        var disordered = false
        /// Stands on a wing of its formation (outer columns), for a flanking march.
        var onWing = false
        var levy = false
        var order: BlockOrder?
    }

    // MARK: Land battle

    public func resolve(_ setup: BattleSetup) -> BattleReport {
        let b = rules.battle
        let terrain = b.terrain[setup.terrain]!
        let impassable = Set(terrain.impassable)
        let range = terrain.archerRange ?? b.archerRange
        var rng = SeededRNG(seed: setup.seed)
        var day: [BattleSide: Int] = [:]
        for side in [BattleSide.attacker, .defender] {
            day[side] = 100 + Int(rng.next() % UInt64(2 * b.dayFortunePercent + 1)) - b.dayFortunePercent
        }

        var blocks = deployBoth(setup, impassable)
        let plans = b.plans
        let startHp: [BattleSide: Int] = [
            .attacker: blocks.filter { $0.side == .attacker }.reduce(0) { $0 + $1.maxHp },
            .defender: blocks.filter { $0.side == .defender }.reduce(0) { $0 + $1.maxHp },
        ]
        var frames = [BattleFrame(round: 0, blocks: blocks.map(snapshot), strikes: [])]
        var round = 0

        func fighting(_ side: BattleSide) -> Bool {
            blocks.contains { $0.side == side && $0.status == .fighting }
        }

        while round < b.maxRounds, fighting(.attacker), fighting(.defender) {
            round += 1

            // Movement interleaves the sides, and who moves first alternates each round,
            // so neither side gets a systematic head start.
            let before = blocks.map(\.position)
            for i in moveOrder(blocks, attackerFirst: round % 2 == 1) where blocks[i].status == .fighting {
                let army = blocks[i].side == .attacker ? setup.attacker : setup.defender
                let formation = b.formation(army.formation) ?? b.formation(b.defaultFormation)!
                var advances = formation.advance[blocks[i].type] ?? true || blocks[i].provoked
                    || (blocks[i].side == .attacker && round > b.attackerHoldRounds)
                // A block's own orders outrank its formation's.
                switch blocks[i].order {
                case .advance?: advances = true
                case .hold?: advances = blocks[i].provoked
                case nil: break
                }
                switch army.stratagem {
                case _ where blocks[i].order != nil:
                    break  // its own orders stand, whatever the stratagem
                case .standFast?:
                    advances = blocks[i].provoked
                case .shieldWall? where blocks[i].type == .infantry && round % 2 == 1:
                    continue  // locked shields: the infantry moves every other round
                case .feignedRetreat? where round == 1:
                    // The cavalry turns and rides back; everyone else waits for the pursuit.
                    if blocks[i].type == .cavalry {
                        let back = GridPoint(blocks[i].position.col,
                                             blocks[i].position.row + (blocks[i].side == .attacker ? -1 : 1))
                        if (0..<Self.size).contains(back.row), !impassable.contains(back),
                           !blocks.contains(where: { $0.status == .fighting && $0.position == back }) {
                            blocks[i].position = back
                        }
                    }
                    if !blocks[i].provoked { continue }
                default:
                    break
                }
                for _ in 0..<b.speed[blocks[i].type]! {
                    if !enemies(of: i, blocks, within: 1).isEmpty { break }
                    // Archers stop to shoot once in range, unless ordered to close in.
                    if blocks[i].type == .archers, blocks[i].order != .advance,
                       !enemies(of: i, blocks, within: range).isEmpty { break }
                    guard advances, let step = step(for: i, blocks, impassable) else { break }
                    blocks[i].position = step
                }
            }

            // Against a feigned retreat, whoever pursues in the opening rounds falls into disorder.
            for side in [BattleSide.attacker, .defender] where army(side, setup).stratagem == .feignedRetreat {
                for i in blocks.indices where blocks[i].side != side && blocks[i].status == .fighting {
                    if round <= plans.feignedRetreatRounds, blocks[i].position != before[i] { blocks[i].disordered = true }
                    if round > plans.feignedRetreatRounds + 1 { blocks[i].disordered = false }
                }
            }

            // Strikes are computed from positions after movement, then applied together.
            var fortune: [BattleSide: Int] = [:]
            for side in [BattleSide.attacker, .defender] {
                fortune[side] = (100 + Int(rng.next() % UInt64(2 * b.fortunePercent + 1)) - b.fortunePercent) * day[side]! / 100
            }
            var strikes: [BattleStrike] = []
            for i in blocks.indices where blocks[i].status == .fighting {
                let adjacent = enemies(of: i, blocks, within: 1)
                let ranged: Bool
                let candidates: [Int]
                if !adjacent.isEmpty {
                    (ranged, candidates) = (false, adjacent)
                } else if blocks[i].type == .archers {
                    (ranged, candidates) = (true, enemies(of: i, blocks, within: range))
                } else {
                    continue
                }
                guard let target = candidates.min(by: { x, y in
                    let dx = blocks[i].position.distance(to: blocks[x].position)
                    let dy = blocks[i].position.distance(to: blocks[y].position)
                    if dx != dy { return dx < dy }
                    return blocks[x].hp != blocks[y].hp ? blocks[x].hp < blocks[y].hp : x < y
                }) else { continue }
                let damage = self.damage(from: blocks[i], to: blocks[target], ranged: ranged,
                                         setup: setup, rng: &rng) * fortune[blocks[i].side]! / 100
                if !ranged, blocks[i].type == .cavalry { blocks[i].charged = true }
                strikes.append(BattleStrike(from: blocks[i].id, to: blocks[target].id,
                                            damage: damage, ranged: ranged))
            }

            var moraleLoss = [Int](repeating: 0, count: blocks.count)
            var attackers = [Int](repeating: 0, count: blocks.count)
            for s in strikes {
                blocks[s.to].hp -= s.damage
                blocks[s.to].provoked = true
                moraleLoss[s.to] += s.damage * 100 / blocks[s.to].maxHp
                attackers[s.to] += 1
            }
            for i in blocks.indices where blocks[i].status == .fighting {
                if attackers[i] >= 2 { moraleLoss[i] += b.flankMoraleLoss }
                blocks[i].morale -= moraleLoss[i]
                if blocks[i].hp <= 0 {
                    blocks[i].hp = 0
                    blocks[i].status = .destroyed
                } else if blocks[i].morale <= 0 {
                    blocks[i].status = .routed
                }
            }

            // An army that has lost too much of its strength breaks and flees.
            for side in [BattleSide.attacker, .defender] {
                let left = blocks.filter { $0.side == side && $0.status == .fighting }.reduce(0) { $0 + $1.hp }
                if (startHp[side]! - left) * 100 >= startHp[side]! * b.breakPercent {
                    for i in blocks.indices where blocks[i].side == side && blocks[i].status == .fighting {
                        blocks[i].status = .routed
                    }
                }
            }
            frames.append(BattleFrame(round: round, blocks: blocks.map(snapshot), strikes: strikes))
        }

        // If both armies broke in the same round, the one with more strength left holds the field.
        func strength(_ side: BattleSide) -> Int {
            blocks.filter { $0.side == side }.reduce(0) { $0 + $1.hp } * 1000 / max(1, startHp[side]!)
        }
        let winner: BattleSide
        switch (fighting(.attacker), fighting(.defender)) {
        case (true, false): winner = .attacker
        case (false, false): winner = strength(.attacker) > strength(.defender) ? .attacker : .defender
        default: winner = .defender
        }
        var survivors: [BattleSide: UnitCounts] = [.attacker: .zero, .defender: .zero]
        var levyLeft = 0
        for block in blocks where block.status != .destroyed {
            if block.levy { levyLeft += units(block) } else { survivors[block.side]![block.type] += units(block) }
        }
        let loser: BattleSide = winner == .attacker ? .defender : .attacker
        // The rout. A winner who gives chase cuts down a share of the fleeing (more with cavalry
        // to run them down); archers covering the retreat sting the pursuers. Holding the field
        // lets the beaten army go.
        var pursuit: Pursuit?
        if army(winner, setup).pursue {
            let cavalry = survivors[winner]!.cavalry > 0
            let percent = b.pursuitPercent + (cavalry ? b.pursuitCavalryPercent : 0)
            var routed = 0
            for type in UnitType.allCases {
                let lost = survivors[loser]![type] * percent / 100
                survivors[loser]![type] -= lost
                routed += lost
            }
            if loser == .defender {
                let lost = levyLeft * percent / 100
                levyLeft -= lost
                routed += lost
            }
            var stung = survivors[loser]!.archers / max(1, b.rearguardArchersPerLoss)
            var pursuersLost = 0
            for type in [UnitType.cavalry, .infantry, .archers] where stung > 0 {
                let n = min(stung, survivors[winner]![type])
                survivors[winner]![type] -= n
                stung -= n
                pursuersLost += n
            }
            pursuit = Pursuit(routed: routed, pursuersLost: pursuersLost)
        }

        let attackerKilled = generalDies(setup.attacker.general, won: winner == .attacker, &rng)
        let defenderKilled = generalDies(setup.defender.general, won: winner == .defender, &rng)
        return BattleReport(setup: setup, impassable: terrain.impassable, frames: frames, winner: winner,
                            rounds: round, attackerSurvivors: survivors[.attacker]!,
                            defenderSurvivors: survivors[.defender]!,
                            attackerGeneralKilled: attackerKilled, defenderGeneralKilled: defenderKilled,
                            defenderLevySurvivors: levyLeft, pursuit: pursuit)
    }

    // MARK: Deployment

    /// How the two armies would stand before the first blow: frame 0 of the battle, without
    /// fighting it. Deployment rolls nothing, so this is exactly what `resolve` starts from.
    public func deployment(_ setup: BattleSetup) -> BattleFrame {
        let impassable = Set(rules.battle.terrain[setup.terrain]!.impassable)
        return BattleFrame(round: 0, blocks: deployBoth(setup, impassable).map(snapshot), strikes: [])
    }

    private func deployBoth(_ setup: BattleSetup, _ impassable: Set<GridPoint>) -> [Block] {
        var blocks = deploy(setup.attacker, side: .attacker, firstID: 0)
        blocks += deploy(setup.defender, side: .defender, firstID: blocks.count)
        // A flanking march: the wings start a rank further forward, where the square is free.
        for side in [BattleSide.attacker, .defender] where army(side, setup).stratagem == .flankingMarch {
            let forward = side == .attacker ? 1 : -1
            for i in blocks.indices where blocks[i].side == side && blocks[i].onWing {
                let ahead = GridPoint(blocks[i].position.col, blocks[i].position.row + forward)
                if !impassable.contains(ahead), !blocks.contains(where: { $0.position == ahead }) {
                    blocks[i].position = ahead
                }
            }
        }
        return blocks
    }

    /// Splits an army into at most `maxBlocks` single-type blocks and places them by formation.
    private func deploy(_ army: BattleArmy, side: BattleSide, firstID: Int) -> [Block] {
        let b = rules.battle
        let present = UnitType.allCases.filter { army.units[$0] > 0 }
        var blockCount = Dictionary(uniqueKeysWithValues: present.map { ($0, 1) })
        let target = min(b.maxBlocks, army.units.total)
        while blockCount.values.reduce(0, +) < target {
            // Give the next block to the type with the most units per block.
            guard let type = present.filter({ army.units[$0] > blockCount[$0]! }).max(by: { x, y in
                army.units[x] * blockCount[y]! < army.units[y] * blockCount[x]!
            }) else { break }
            blockCount[type]! += 1
        }

        let formation = b.formation(army.formation) ?? b.formation(b.defaultFormation)!
        let morale = 100 + army.morale + (army.general.map { g in
            rules.generals.presentMorale + (rules.generals.traits[g.trait]?.moralePercent ?? 0)
        } ?? 0) + (army.stratagem == .standFast ? b.plans.standFastMorale : 0)
        var taken = Set<GridPoint>()
        var blocks: [Block] = []
        let order = formation.order + UnitType.allCases.filter { !formation.order.contains($0) }
        for type in order where blockCount[type] != nil {
            let n = blockCount[type]!
            var preferred = (formation.slots[type] ?? []) + b.fallbackSlots
            if army.depth == .wide {
                // Everyone in the front rank, center outward, before anyone stands behind.
                let front = (formation.slots[type] ?? []).map { GridPoint($0.col, 0) }
                preferred = front + [2, 1, 3, 0, 4].map { GridPoint($0, 0) } + preferred
            }
            for k in 0..<n {
                let count = army.units[type] / n + (k < army.units[type] % n ? 1 : 0)
                let slot = preferred.first { !taken.contains($0) }!
                taken.insert(slot)
                let hp = count * b.hpPerUnit
                blocks.append(Block(id: firstID + blocks.count, side: side, type: type,
                                    position: boardPoint(slot, side), hp: hp, maxHp: hp, morale: morale,
                                    onWing: slot.col == 0 || slot.col == Self.size - 1))
            }
        }
        // The levy: townsfolk in a block or two, wherever there's room, shakier than soldiers.
        if army.levy > 0 {
            let n = min(2, army.levy)
            let preferred = (formation.slots[.infantry] ?? []) + b.fallbackSlots
            for k in 0..<n {
                let count = army.levy / n + (k < army.levy % n ? 1 : 0)
                guard let slot = preferred.first(where: { !taken.contains($0) }) else { break }
                taken.insert(slot)
                let hp = count * b.hpPerUnit
                blocks.append(Block(id: firstID + blocks.count, side: side, type: .infantry,
                                    position: boardPoint(slot, side), hp: hp, maxHp: hp,
                                    morale: morale - b.levy.moralePenalty,
                                    onWing: slot.col == 0 || slot.col == Self.size - 1, levy: true))
            }
        }
        // Hand placements: each to its chosen square in the army's own two ranks (trading places
        // with whoever stood there); then single blocks' orders.
        let ranks = side == .attacker ? 0...1 : 3...4
        for (k, square) in (army.placements ?? [:]).sorted(by: { $0.key < $1.key }) {
            guard k < blocks.count, ranks.contains(square.row), (0..<Self.size).contains(square.col) else { continue }
            if let other = blocks.indices.first(where: { $0 != k && blocks[$0].position == square }) {
                blocks[other].position = blocks[k].position
            }
            blocks[k].position = square
        }
        for (k, order) in army.orders ?? [:] where k < blocks.count { blocks[k].order = order }
        return blocks
    }

    /// Converts a formation slot (`[col, rank]`) to a board square. The defender faces the
    /// attacker, so its columns are mirrored.
    private func boardPoint(_ slot: GridPoint, _ side: BattleSide) -> GridPoint {
        side == .attacker
            ? GridPoint(slot.col, slot.row == 0 ? 1 : 0)
            : GridPoint(Self.size - 1 - slot.col, slot.row == 0 ? 3 : 4)
    }

    // MARK: Movement

    private func moveOrder(_ blocks: [Block], attackerFirst: Bool) -> [Int] {
        var a = blocks.indices.filter { blocks[$0].side == .attacker }
        var d = blocks.indices.filter { blocks[$0].side == .defender }
        if !attackerFirst { swap(&a, &d) }
        var order: [Int] = []
        for k in 0..<max(a.count, d.count) {
            if k < a.count { order.append(a[k]) }
            if k < d.count { order.append(d[k]) }
        }
        return order
    }

    private func enemies(of i: Int, _ blocks: [Block], within range: Int) -> [Int] {
        blocks.indices.filter {
            blocks[$0].side != blocks[i].side && blocks[$0].status == .fighting
                && blocks[$0].position.distance(to: blocks[i].position) <= range
        }
    }

    /// One square toward the nearest enemy, if any free square gets closer.
    private func step(for i: Int, _ blocks: [Block], _ impassable: Set<GridPoint>) -> GridPoint? {
        let me = blocks[i]
        let foes = blocks.indices.filter { blocks[$0].side != me.side && blocks[$0].status == .fighting }
        guard let target = foes.min(by: { x, y in
            let dx = me.position.distance(to: blocks[x].position)
            let dy = me.position.distance(to: blocks[y].position)
            return dx != dy ? dx < dy : x < y
        }) else { return nil }
        let goal = blocks[target].position
        let occupied = Set(blocks.filter { $0.status == .fighting }.map(\.position))
        let forward = me.side == .attacker ? 1 : -1
        // Forward, then the side's own left and right (mirrored for the defender), then back.
        let moves = [GridPoint(0, forward), GridPoint(-forward, 0), GridPoint(forward, 0), GridPoint(0, -forward)]
        let current = me.position.distance(to: goal)
        return moves
            .map { GridPoint(me.position.col + $0.col, me.position.row + $0.row) }
            .filter { (0..<Self.size).contains($0.col) && (0..<Self.size).contains($0.row) }
            .filter { !impassable.contains($0) && !occupied.contains($0) }
            .filter { $0.distance(to: goal) < current }
            .first
    }

    // MARK: Damage

    private func army(_ side: BattleSide, _ setup: BattleSetup) -> BattleArmy {
        side == .attacker ? setup.attacker : setup.defender
    }

    private func units(_ block: Block) -> Int {
        (block.hp + rules.battle.hpPerUnit - 1) / rules.battle.hpPerUnit
    }

    private func damage(from attacker: Block, to target: Block, ranged: Bool,
                        setup: BattleSetup, rng: inout SeededRNG) -> Int {
        let b = rules.battle
        let terrain = b.terrain[setup.terrain]!
        let army = attacker.side == .attacker ? setup.attacker : setup.defender
        let targetArmy = target.side == .attacker ? setup.attacker : setup.defender

        var percents = [b.matchupPercent[attacker.type]![target.type]!]
        if attacker.type == .archers, !ranged { percents.append(b.archerMeleePercent) }
        if attacker.type == .cavalry, !ranged, !attacker.charged { percents.append(100 + b.chargeBonusPercent) }
        if attacker.levy {
            // Farmers with spears: no drill, no bronze.
            percents.append(b.levy.damagePercent)
            percents.append(100 + (terrain.unitPercent[attacker.type] ?? 0))
        } else {
            percents.append(100 + (terrain.unitPercent[attacker.type] ?? 0) + (army.unitPercent[attacker.type] ?? 0))
            percents.append(100 + b.bronzeBonusPercent * army.bronzePercent / 100)
        }
        if let g = army.general {
            let fx = rules.generals.traits[g.trait]
            percents.append(100 + (fx?.attackPercent ?? 0) + (fx?.unitPercent?[attacker.type] ?? 0)
                            + min(g.renown * rules.generals.renownAttackPercent,
                                  rules.generals.maxRenownAttackPercent))
        }
        if attacker.side == .attacker, setup.approach != .overland {
            percents.append(100 - (b.crossingPenaltyPercent[setup.approach.rawValue] ?? 0))
        }
        if target.disordered, army.stratagem == .feignedRetreat { percents.append(100 + b.plans.feignedRetreatPercent) }
        if ranged, target.type == .infantry, targetArmy.stratagem == .shieldWall {
            percents.append(100 - b.plans.shieldWallArrowPercent)
        }
        var defense = targetArmy.general.flatMap { rules.generals.traits[$0.trait]?.defensePercent } ?? 0
        if target.side == .defender { defense += b.homeGroundPercent + terrain.defensePercent + setup.fortification }
        percents.append(100 - defense)
        let spread = b.randomSpreadPercent
        percents.append(100 + Int(rng.next() % UInt64(2 * spread + 1)) - spread)

        var damage = units(attacker) * b.attack[attacker.type]!
        for p in percents { damage = damage * max(0, p) / 100 }
        return max(1, damage)
    }

    private func generalDies(_ general: General?, won: Bool, _ rng: inout SeededRNG) -> Bool {
        guard let general else { return false }
        let g = rules.generals
        let base = won ? g.deathChanceOnVictoryPercent : g.deathChanceOnDefeatPercent
        let chance = base * (g.traits[general.trait]?.deathChanceMultiplier ?? 1)
        return Int(rng.next() % 100) < chance
    }

    private func snapshot(_ block: Block) -> BlockSnapshot {
        BlockSnapshot(id: block.id, side: block.side, type: block.type, position: block.position,
                      units: units(block), morale: max(0, block.morale), status: block.status, levy: block.levy,
                      order: block.order)
    }

    // MARK: Naval battle (auto-resolve only)

    public func resolveNaval(attacker: CivilizationID, attackerShips: Int,
                             defender: CivilizationID, defenderShips: Int, seed: UInt64,
                             attackerPercent: Int = 100, defenderPercent: Int = 100) -> NavalReport {
        let n = rules.naval
        var rng = SeededRNG(seed: seed)
        var hpA = attackerShips * n.hpPerShip
        var hpD = defenderShips * n.hpPerShip
        func ships(_ hp: Int) -> Int { (max(0, hp) + n.hpPerShip - 1) / n.hpPerShip }
        func broken(_ hp: Int, _ start: Int) -> Bool {
            ships(hp) == 0 || (start - ships(hp)) * 100 >= start * n.retreatPercent
        }
        func roll(_ shipsLeft: Int, _ skill: Int) -> Int {
            let spread = n.randomSpreadPercent
            let pct = 100 + Int(rng.next() % UInt64(2 * spread + 1)) - spread
            return shipsLeft * n.attackPerShip * pct / 100 * skill / 100
        }

        var round = 0
        while round < n.maxRounds, !broken(hpA, attackerShips), !broken(hpD, defenderShips) {
            round += 1
            let toD = roll(ships(hpA), attackerPercent)
            let toA = roll(ships(hpD), defenderPercent)
            hpD -= toD
            hpA -= toA
        }
        let attackerBroken = broken(hpA, attackerShips)
        let defenderBroken = broken(hpD, defenderShips)
        let winner: BattleSide = defenderBroken && !attackerBroken ? .attacker : .defender
        return NavalReport(attacker: attacker, defender: defender, attackerShips: attackerShips,
                           defenderShips: defenderShips, winner: winner, rounds: round,
                           attackerShipsLeft: ships(hpA), defenderShipsLeft: ships(hpD))
    }
}
