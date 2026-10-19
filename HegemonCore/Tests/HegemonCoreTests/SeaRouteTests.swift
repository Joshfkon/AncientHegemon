import Testing
@testable import HegemonCore

@Suite struct SeaRouteTests {
    let engine = try! Engine.bare()

    @Test func shipsOffshoreOpenTheCoastsOfTheirSea() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["greece"])
        #expect(engine.seaRoutes(from: "greece", for: "greece", in: s).isEmpty || s.fleets.contains { $0.owner == "greece" })
        s.fleets = [Fleet(sea: "aegean", owner: "greece", ships: 2)]
        let routes = engine.seaRoutes(from: "greece", for: "greece", in: s)
        // Crete is on the Aegean: straight across, no sailing.
        let crete = try #require(routes["crete"])
        #expect(crete == SeaRoute(board: "aegean", land: "aegean", room: 2 * engine.shipCapacity("greece", s)))
        // Cyprus is one sea further (the eastern Mediterranean).
        #expect(routes["cyprus"]?.sails == true)
        // Land next door is for marching, not sailing.
        #expect(routes["macedonia"] == nil)
    }

    @Test func shipsThatSailedThisTurnCannotGoFurther() throws {
        var s = try engine.newGame(seed: 1, civilizations: ["greece"])
        s.fleets = [Fleet(sea: "aegean", owner: "greece", ships: 2, movedShips: 2)]
        let routes = engine.seaRoutes(from: "greece", for: "greece", in: s)
        #expect(routes["crete"] != nil)
        #expect(routes["cyprus"] == nil)
    }
}
