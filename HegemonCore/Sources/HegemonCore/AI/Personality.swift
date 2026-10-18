/// Weights that give AI empires different temperaments (DESIGN §12).
public struct Personality: Codable, Sendable, Equatable {
    public let name: String
    /// Scales how much conquests are worth; higher attacks more readily.
    public let aggression: Double
    /// Garrison kept on a threatened border, as a share of the adjacent enemy strength.
    public let caution: Double
    /// Inclination toward peace and trade, 0–1.
    public let trade: Double
    /// Bonus for attacking civilizations that are already losing or fighting others.
    public let opportunism: Double

    public static let conqueror = Personality(name: "conqueror", aggression: 1.5, caution: 0.6, trade: 0.2, opportunism: 0.3)
    public static let merchant = Personality(name: "merchant", aggression: 0.8, caution: 0.9, trade: 0.9, opportunism: 0.2)
    public static let turtle = Personality(name: "turtle", aggression: 0.7, caution: 1.4, trade: 0.6, opportunism: 0.1)
    public static let opportunist = Personality(name: "opportunist", aggression: 1.1, caution: 0.8, trade: 0.4, opportunism: 1.0)

    public static let all: [Personality] = [.conqueror, .merchant, .turtle, .opportunist]

    public static func named(_ name: String) -> Personality? {
        all.first { $0.name == name }
    }

    /// Default temperaments for the starting civilizations.
    public static func `default`(for civ: CivilizationID) -> Personality {
        switch civ {
        case "greece": .merchant
        case "egypt": .turtle
        case "italia": .conqueror
        default: .opportunist
        }
    }
}
