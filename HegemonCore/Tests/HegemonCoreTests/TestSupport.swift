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
            json["minors"] = minors
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
