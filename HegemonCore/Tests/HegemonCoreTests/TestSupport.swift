import Foundation
@testable import HegemonCore

extension Engine {
    /// The bundled rules with chance taken out of government: no random events, no ruler deaths,
    /// no rebellions, no storms or pirates, no moods or deeds of the minor peoples, no generals'
    /// pay and no ruler-trait effects. For tests that expect exact numbers.
    static func calm() throws -> Engine {
        try modified { json in
            var events = json["events"] as! [String: Any]
            events["chancePercent"] = 0
            json["events"] = events
            var collapse = json["collapse"] as! [String: Any]
            collapse["extraChancePercent"] = 0
            json["collapse"] = collapse
            var gov = json["government"] as! [String: Any]
            gov["baseDeathChance"] = 0
            gov["deathChancePerYear"] = 0
            gov["generalPay"] = 0
            gov["rebellionChancePerPoint"] = 0
            json["government"] = gov
            // No storms at sea and no pirates.
            var ships = json["ships"] as! [String: Any]
            ships["stormPercent"] = 0
            ships["stormMinPercent"] = 0
            json["ships"] = ships
            var pirates = json["pirates"] as! [String: Any]
            pirates["spawnPercent"] = 0
            json["pirates"] = pirates
            // Peoples who feel nothing in particular and never act on their own.
            var minors = json["minors"] as! [String: Any]
            minors["baseAttitude"] = ["warlike": 0, "proud": 0, "mercantile": 0, "peaceable": 0]
            for key in ["growthCap", "raidPercent", "joinPercent", "breakFreePercent"] { minors[key] = 0 }
            minors["expandPercent"] = ["warlike": 0, "proud": 0, "mercantile": 0, "peaceable": 0]
            // Vassals as sure as tests written before oaths could fail expect: they swear at
            // twice their warriors, answer every levy and never rise unless left unwatched.
            minors["vassalRatio"] = ["warlike": 2, "proud": 2, "mercantile": 2, "peaceable": 2]
            minors["swearChance"] = ["warlike": 100, "proud": 100, "mercantile": 100, "peaceable": 100]
            for (key, value) in ["vassalMuster": 0, "swearChanceMax": 100, "friendSwearChance": 100, "levyBaseChance": 100,
                                 "levyChanceMax": 100, "levyAttitude": 0, "rebelLegitimacy": 0, "rebelAttitudeStep": 1000,
                                 "renewChance": 100] { minors[key] = value }
            json["minors"] = minors
            // The empires start at war, as tests written before peaceful starts expect.
            var start = json["start"] as! [String: Any]
            start["atPeace"] = false
            json["start"] = start
            let traits = json["rulerTraits"] as! [String: Any]
            json["rulerTraits"] = traits.mapValues { _ in [String: Any]() }
        }
    }

    /// Calm rules, minus native garrisons and per-civ starts: every civ starts with just its
    /// capital and the standard army, and everything else is empty. Scenario tests build their own geography on top.
    static func bare() throws -> Engine {
        let calm = try calm()
        return try calm.modified { json in
            var start = json["start"] as! [String: Any]
            start["realms"] = [String: [String]]()
            start["natives"] = ["base": 0, "grainPerUnit": 1_000_000]
            // Same start for everyone: no per-civ armies, granaries, fleets or knowledge.
            for key in ["armies", "granaries", "fleets", "knowledge"] { start[key] = nil }
            json["start"] = start
        }
    }

    private static func modified(_ change: (inout [String: Any]) -> Void) throws -> Engine {
        try Engine(map: .bundled(), rules: .bundled()).modified(change)
    }

    func modified(_ change: (inout [String: Any]) -> Void) throws -> Engine {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(rules)) as! [String: Any]
        change(&json)
        return Engine(map: map, rules: try Rules(json: JSONSerialization.data(withJSONObject: json)))
    }
}

/// Runs `body` on a thread with a large stack. Swift Testing runs tests on small worker stacks,
/// and a whole AI game in a debug build (each turn forecasting the harvest on a copy of the
/// state) can run past them.
final class ResultBox<T>: @unchecked Sendable { var result: Result<T, Error>? }

func onLargeStack<T>(_ body: @escaping () throws -> T) throws -> T {
    let box = ResultBox<T>()
    let done = DispatchSemaphore(value: 0)
    let run = { box.result = Result { try body() }; done.signal() }
    let thread = Thread { run() }
    thread.stackSize = 64 << 20
    thread.start()
    done.wait()
    return try box.result!.get()
}

/// The engine's `playAIMatch`, on a large stack (this module's name shadows the library's).
func playAIMatch(engine: Engine, seed: UInt64, personalities: [CivilizationID: Personality],
                 civilizations: [CivilizationID]? = nil, maxTurns: Int) throws -> MatchRecord {
    try onLargeStack {
        try HegemonCore.playAIMatch(engine: engine, seed: seed, personalities: personalities,
                                    civilizations: civilizations, maxTurns: maxTurns)
    }
}

extension AIPlayer {
    /// `playTurn` on a large stack.
    func play(_ state: inout GameState) -> AITurn {
        let start = state
        let (turn, end) = try! onLargeStack { () -> (AITurn, GameState) in
            var s = start
            let turn = self.playTurn(&s)
            return (turn, s)
        }
        state = end
        return turn
    }
}
