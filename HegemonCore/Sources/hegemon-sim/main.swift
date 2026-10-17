import HegemonCore

// Headless runner. Until the real AI exists (build step 5), every civ plays a placeholder
// "land grab" policy: recruit infantry at the capital when affordable, then march every ready
// unit into an adjacent territory it doesn't own (skipping enemy-held ones, since battles
// arrive in step 4). Useful for eyeballing the economy numbers.
//
// usage: hegemon-sim [seed] [turns]

let args = CommandLine.arguments.dropFirst().compactMap { UInt64($0) }
let seed = args.first ?? 1
let turns = Int(args.dropFirst().first ?? 30)

let engine = try Engine.bundled()
var state = try engine.newGame(seed: seed)
var starvationTurns: [CivilizationID: Int] = [:]

func playLandGrab(_ civ: CivilizationID, _ state: inout GameState) {
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
        if case let .starvation(civ, _, _) = event { starvationTurns[civ, default: 0] += 1 }
    }
}

print("seed \(seed), \(turns) turns (placeholder land-grab policy)")
print("civ          land  pop  units  gold  granary  starved")
for civ in state.players {
    let c = state.civs[civ]!
    let row = [civ.padding(toLength: 12, withPad: " ", startingAt: 0),
               String(state.territories(of: civ).count), String(state.totalPopulation(of: civ)),
               String(state.totalUnits(of: civ).total), String(c.gold), String(c.granary),
               String(starvationTurns[civ] ?? 0)]
    print(row.enumerated().map { $0 == 0 ? $1 : $1.leftPad(to: [5, 5, 7, 6, 9, 9][$0 - 1]) }.joined())
}

extension String {
    func leftPad(to width: Int) -> String {
        String(repeating: " ", count: max(0, width - count)) + self
    }
}
