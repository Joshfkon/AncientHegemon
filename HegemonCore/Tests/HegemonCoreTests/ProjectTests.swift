import Foundation
import Testing
@testable import HegemonCore

private func own(_ s: inout GameState, _ civ: CivilizationID, _ territories: TerritoryID...) {
    for t in territories { s.land[t]!.owner = civ }
}

@Suite struct TaxTests {
    let engine = try! Engine.calm()

    @Test func higherTaxesMoreGoldLessLegitimacy() throws {
        var low = try engine.newGame(seed: 1, civilizations: ["mesopotamia"])
        var high = low
        try engine.apply(.setTaxRate(20), to: &low)
        try engine.apply(.setTaxRate(80), to: &high)
        let goldLow = low.civs["mesopotamia"]!.gold, goldHigh = high.civs["mesopotamia"]!.gold
        try engine.apply(.endTurn, to: &low)
        try engine.apply(.endTurn, to: &high)
        #expect(high.civs["mesopotamia"]!.gold - goldHigh > low.civs["mesopotamia"]!.gold - goldLow)
        #expect(high.civs["mesopotamia"]!.legitimacy < low.civs["mesopotamia"]!.legitimacy)
    }

    @Test func heavyTaxesSlowGrowth() throws {
        var normal = try engine.newGame(seed: 1, civilizations: ["mesopotamia"])
        var crushing = normal
        try engine.apply(.setTaxRate(100), to: &crushing)
        try engine.apply(.endTurn, to: &normal)
        try engine.apply(.endTurn, to: &crushing)
        #expect(normal.population(of: "mesopotamia") > crushing.population(of: "mesopotamia"))
    }

    @Test func taxRatesComeInTens() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["mesopotamia"])
        #expect(throws: GameError.invalidTaxRate) { try engine.apply(.setTaxRate(35), to: &s) }
        #expect(throws: GameError.invalidTaxRate) { try engine.apply(.setTaxRate(110), to: &s) }
    }
}

@Suite struct ProjectBuildTests {
    let engine = try! Engine.bare()

    private func rich(_ civ: CivilizationID) throws -> GameState {
        var s = try engine.newGame(seed: 1, civilizations: [civ])
        s.civs[civ]!.gold = 100
        s.civs[civ]!.stock = [.stone: 10, .timber: 10]
        return s
    }

    @Test func projectsCostAndTakeTime() throws {
        var s = try rich("egypt")
        try engine.apply(.build(territory: "egypt", project: .farm), to: &s)
        let cost = engine.rules.projects[.farm]!
        #expect(s.civs["egypt"]!.gold == 100 - cost.gold)
        #expect(s.civs["egypt"]!.stock[.timber] == 10 - cost.timber)
        #expect(throws: GameError.projectUnavailable("egypt", .walls)) {
            try engine.apply(.build(territory: "egypt", project: .walls), to: &s)  // one site at a time
        }
        for _ in 0..<cost.turns { try engine.apply(.endTurn, to: &s) }
        #expect(s.land["egypt"]!.improvements.contains(.farm))
        // Egypt is a river valley: its farm adds the larger bonus.
        #expect(engine.territoryYield(.grain, "egypt", s) == 10 + engine.rules.projectEffects.farmRiverValleyGrain)
    }

    @Test func projectsNeedStock() throws {
        var s = try rich("egypt")
        s.civs["egypt"]!.stock = [:]
        #expect(throws: GameError.insufficientStock(.stone, needed: engine.rules.projects[.walls]!.stone, available: 0)) {
            try engine.apply(.build(territory: "egypt", project: .walls), to: &s)
        }
    }

    @Test func minesNeedOreAndHarborsNeedCoast() throws {
        let s = try rich("mesopotamia")
        #expect(!engine.canBuild(.mine, in: "mesopotamia", s))     // no ore
        #expect(!engine.canBuild(.harbor, in: "sahara", s))        // no coast
        #expect(engine.canBuild(.mine, in: "britain", s))          // tin and iron
    }

    @Test func minesRaiseOre() throws {
        var s = try rich("egypt")
        own(&s, "egypt", "britain")
        s.land["britain"]!.improvements.insert(.mine)
        #expect(engine.territoryYield(.tin, "britain", s) == 2 + engine.rules.projectEffects.mineBonus)
        #expect(engine.territoryYield(.iron, "britain", s) == 1 + engine.rules.projectEffects.mineBonus)
    }

    @Test func roadsShortenSupplyLines() throws {
        var s = try rich("greece")
        own(&s, "greece", "macedonia", "thrace", "dacia")
        let before = engine.supplyDistances(of: "greece", in: s)["dacia"]!
        s.land["macedonia"]!.improvements.insert(.road)
        s.land["thrace"]!.improvements.insert(.road)
        #expect(engine.supplyDistances(of: "greece", in: s)["dacia"]! < before)
    }

    @Test func wallsHelpDefenders() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["mesopotamia", "greece"])
        own(&s, "greece", "persia")
        s.armies["persia"] = Army(owner: "greece", units: UnitCounts(infantry: 4))
        let open = engine.attackOdds("mesopotamia", units: UnitCounts(infantry: 6), into: "persia",
                                     from: "mesopotamia", samples: 40, in: s)!
        s.land["persia"]!.improvements.insert(.walls)
        let walled = engine.attackOdds("mesopotamia", units: UnitCounts(infantry: 6), into: "persia",
                                       from: "mesopotamia", samples: 40, in: s)!
        #expect(walled < open)
    }

    @Test func captureKeepsBuildingsButLosesSites() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["mesopotamia", "greece"])
        own(&s, "greece", "media")
        s.land["media"]!.improvements.insert(.farm)
        s.land["media"]!.construction = Construction(kind: .walls, turnsLeft: 2)
        try engine.apply(.move(from: "mesopotamia", to: "media", units: UnitCounts(infantry: 1)), to: &s)
        #expect(s.land["media"]!.improvements.contains(.farm))
        #expect(s.land["media"]!.construction == nil)
    }

    @Test func harborsMakeShipsCheaper() throws {
        var s = try rich("greece")
        own(&s, "greece", "macedonia")
        s.land["greece"]!.improvements.insert(.harbor)
        try engine.apply(.buildShips(territory: "greece", sea: "aegean", count: 1), to: &s)
        #expect(s.civs["greece"]!.gold == 100 - (engine.rules.ships.cost - engine.rules.projectEffects.harborShipDiscount))
    }
}

@Suite struct StockAndGoodsTests {
    let engine = try! Engine.calm()

    @Test func stockpilesFillAndCap() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["greece"])
        // Greece + Macedonia + Thrace: stone 1 + 1, timber 2.
        try engine.apply(.endTurn, to: &s)
        #expect(s.civs["greece"]!.stock[.stone] == 2)
        #expect(s.civs["greece"]!.stock[.timber] == 2)
        for _ in 0..<30 { try engine.apply(.endTurn, to: &s) }
        #expect(s.civs["greece"]!.stock[.stone] == engine.rules.economy.stockCap)
    }

    @Test func wineSellsAndSellsBetterAbroad() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["greece", "egypt"])
        s.land["syria"]!.owner = nil                 // without Syria, Egypt makes no wine
        let home = engine.homeNetwork(of: "greece", in: s)
        let alone = engine.wineGold("greece", home, [], s)
        s.peace.insert(CivPair("greece", "egypt"))
        let traded = engine.wineGold("greece", home, engine.tradeRoutes(in: s), s)
        #expect(alone > 0)
        #expect(traded > alone)
    }
}
