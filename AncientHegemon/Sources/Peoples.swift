import HegemonCore
import SwiftUI

/// Words for the minor peoples: their natures and their moods.
enum PeopleText {
    static func temperament(_ t: Temperament) -> String {
        switch t {
        case .warlike: "warlike raiders"
        case .proud: "proud"
        case .mercantile: "merchants"
        case .peaceable: "peaceable"
        }
    }

    static func mood(_ attitude: Int) -> String {
        switch attitude {
        case 60...: "devoted to you"
        case 30..<60: "friendly to you"
        case 10..<30: "warm toward you"
        case -10..<10: "indifferent to you"
        case -30 ..< -10: "wary of you"
        case -60 ..< -30: "hostile to you"
        default: "hate you"
        }
    }

    static func moodColor(_ attitude: Int) -> Color {
        attitude >= 30 ? .green : attitude >= -10 ? .white.opacity(0.75) : attitude >= -30 ? .orange : .red
    }
}
