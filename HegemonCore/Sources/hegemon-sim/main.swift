import HegemonCore

// Headless runner. Until the real AI exists (build step 5), every civ plays a placeholder
// "land grab" policy: recruit infantry at the capital when affordable, then march every ready
// unit into an adjacent territory it doesn't own (skipping enemy-held ones, since battles
// arrive in step 4). With --peace, every civ also offers and accepts peace with everyone,
// so trade routes form. Useful for eyeballing the economy numbers.
//
// usage: hegemon-sim [seed] [turns] [--peace]

let rawArgs = CommandLine.arguments.dropFirst()
let peaceful = rawArgs.contains("--peace")
let args = rawArgs.compactMap { UInt64($0) }
let seed = args.first ?? 1
let turns = Int(args.dropFirst().first ?? 30)

let engine = try Engine.bundled()
var state = try engine.newGame(seed: seed)
var starvationTurns: [CivilizationID: Int] = [:]
var attritionLosses: [CivilizationID: Int] = [:]

func playLandGrab(_ civ: CivilizationID, _ state: inout GameState) {
    if peaceful {
        for other in state.players where other != civ {
            _ = try? engine.apply(.acceptPeace(from: other), to: &state)
            _ = try? engine.apply(.offerPeace(to: other), to: &state)
        }
    }
    let capital = engine.map.civilization(civ)!.capital
    if state.owner(of: capital) == civ {
        while (try? engine.apply(.recruit(territory: capital, unit: .infantry, count: 1), to: &state)) != nil {}
    }
    for (from, units) in state.armies(of: civ) {
        var left = units
        for to in engine.map.landNeighbors(of: from) where state.owner(of: to) != civ && left.infantry > 1 {
            let order = UnitCounts(infantry: 1)
            if (try? engine.apply(.move(from: from, to: to, units: order), to: &state)) != nil {
                left -= order
            }
        }
    }
}

while state.turn <= turns, state.winner == nil {
    playLandGrab(state.activePlayer, &state)
    for event in try engine.apply(.endTurn, to: &state) {
        switch event {
        case let .starvation(civ, _, _): starvationTurns[civ, default: 0] += 1
        case let .outOfSupply(civ, _, lost): attritionLosses[civ, default: 0] += lost
        default: break
        }
    }
}

let routes = engine.tradeRoutes(in: state)
print("seed \(seed), \(turns) turns (placeholder land-grab policy\(peaceful ? ", everyone at peace" : ""))")
print("civ          land  pop  units  gold  granary  bronze  routes  starved  attrition")
let widths = [5, 5, 7, 6, 9, 8, 8, 9, 11]
for civ in state.players {
    let c = state.civs[civ]!
    let row = [civ.padding(toLength: 12, withPad: " ", startingAt: 0),
               String(state.territories(of: civ).count), String(state.totalPopulation(of: civ)),
               String(state.totalUnits(of: civ).total), String(c.gold), String(c.granary),
               String(c.bronze), String(routes.filter { $0.involves(civ) }.count),
               String(starvationTurns[civ] ?? 0), String(attritionLosses[civ] ?? 0)]
    print(row.enumerated().map { $0 == 0 ? $1 : $1.leftPad(to: widths[$0 - 1]) }.joined())
}
for route in routes {
    let via = route.chokepoints.isEmpty ? "" : " via \(route.chokepoints.joined(separator: ", "))"
    let tolls = route.tolls.isEmpty ? "" : " (tolls to \(route.tolls.joined(separator: ", ")))"
    print("route \(route.partners.a) ↔ \(route.partners.b)\(via)\(tolls)")
}

extension String {
    func leftPad(to width: Int) -> String {
        String(repeating: " ", count: max(0, width - count)) + self
    }
}
