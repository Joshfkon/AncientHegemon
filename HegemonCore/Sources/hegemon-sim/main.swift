import HegemonCore

// Headless AI-vs-AI runner. Until the turn loop and AI exist (build steps 2 and 5),
// it loads the map, sets up a game, and prints a summary.

let map = try GameMap.bundled()
let seed = CommandLine.arguments.dropFirst().first.flatMap(UInt64.init) ?? 1
let state = try GameState(map: map, seed: seed)

print("map v\(map.version): \(map.territories.count) territories, \(map.seas.count) seas, "
    + "\(map.chokepoints.count) chokepoints")
print("seed \(seed), turn \(state.turn)")
for civ in state.players {
    print("  \(civ): \(state.territories(of: civ).joined(separator: ", "))")
}
