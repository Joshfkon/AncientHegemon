import Foundation
@testable import HegemonCore

extension Engine {
    /// The bundled rules with chance taken out of government: no random events, no ruler deaths,
    /// no rebellions, no generals' pay and no ruler-trait effects. For tests that expect exact numbers.
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
            let traits = json["rulerTraits"] as! [String: Any]
            json["rulerTraits"] = traits.mapValues { _ in [String: Any]() }
        }
    }

    /// Calm rules, minus starting heartlands and native garrisons: every civ starts with just its
    /// capital and everything else is empty. Scenario tests build their own geography on top.
    static func bare() throws -> Engine {
        let calm = try calm()
        return try calm.modified { json in
            var start = json["start"] as! [String: Any]
            start["realms"] = [String: [String]]()
            start["natives"] = ["base": 0, "grainPerUnit": 1_000_000]
            json["start"] = start
        }
    }

    private static func modified(_ change: (inout [String: Any]) -> Void) throws -> Engine {
        try Engine(map: .bundled(), rules: .bundled()).modified(change)
    }

    private func modified(_ change: (inout [String: Any]) -> Void) throws -> Engine {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(rules)) as! [String: Any]
        change(&json)
        return Engine(map: map, rules: try Rules(json: JSONSerialization.data(withJSONObject: json)))
    }
}
