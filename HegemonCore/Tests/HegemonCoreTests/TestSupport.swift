import Foundation
@testable import HegemonCore

extension Engine {
    /// The bundled map and rules, minus starting heartlands and native garrisons: every civ starts
    /// with just its capital and everything else is empty. Scenario tests build their own
    /// geography on top of this.
    static func bare() throws -> Engine {
        let data = try JSONEncoder().encode(Rules.bundled())
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        var start = json["start"] as! [String: Any]
        start["realms"] = [String: [String]]()
        start["natives"] = ["base": 0, "grainPerUnit": 1_000_000]
        json["start"] = start
        let rules = try Rules(json: JSONSerialization.data(withJSONObject: json))
        return Engine(map: try .bundled(), rules: rules)
    }
}
