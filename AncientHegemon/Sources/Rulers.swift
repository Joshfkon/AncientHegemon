import HegemonCore
import SwiftUI

/// Rival rulers as people: a portrait medallion, a temperament you learn over the game (it is
/// how their court really plays), and a voice for the moments that matter.
struct RulerPortrait: View {
    let civ: CivilizationID
    let state: GameState
    var size: CGFloat = 36

    var body: some View {
        let color = Palette.color(civ, state)
        ZStack {
            Circle().fill(LinearGradient(colors: [color, color.opacity(0.65)], startPoint: .top, endPoint: .bottom))
            CivBanner.emblem(civ).foregroundStyle(.white).padding(size * 0.24)
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(Bronze.gradient, lineWidth: max(1.5, size * 0.06)))
        .overlay(alignment: .top) {
            // A crown for kings; a laurel for a republic's chosen.
            Image(systemName: state.civs[civ]?.government == .republic ? "laurel.leading" : "crown.fill")
                .font(.system(size: size * 0.3)).foregroundStyle(Bronze.gradient)
                .offset(y: -size * 0.22)
        }
        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
    }
}

enum RulerVoice {
    enum Moment: Hashable {
        case war, peace, ally, refuse, covets, fears, friends, hostile, awed, cordial
    }

    /// How their court plays, in a few words.
    static func temperament(_ civ: CivilizationID) -> String {
        switch Personality.default(for: civ).name {
        case "conqueror": "hungry for land"
        case "merchant": "a trader at heart"
        case "turtle": "cautious, guards what he holds"
        case "opportunist": "strikes where others are weak"
        default: "unreadable"
        }
    }

    /// What the ruler says, in character, chosen steadily for the round so it doesn't flicker.
    static func line(_ moment: Moment, _ civ: CivilizationID, _ state: GameState) -> String {
        let lines = Self.lines(moment, Personality.default(for: civ).name)
        var h: UInt64 = 1469598103934665603
        for b in "\(civ)\(state.turn)\(moment)".utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return lines[Int(h % UInt64(lines.count))]
    }

    private static func lines(_ moment: Moment, _ temper: String) -> [String] {
        switch (moment, temper) {
        case (.war, "conqueror"): ["Your land is wasted on you. I will take it.", "Bronze decides what words cannot."]
        case (.war, "merchant"): ["You have closed the roads to my merchants. You leave me no choice.", "I would rather trade. You would rather not."]
        case (.war, "turtle"): ["You have come too close to my walls.", "I did not seek this. I will not run from it."]
        case (.war, _): ["You are weaker than you think.", "The gods have shown me your weakness."]
        case (.peace, "merchant"): ["Let the caravans move again. Both our treasuries will thank us.", "Peace pays better than war."]
        case (.peace, "conqueror"): ["Rest your spears. For now.", "Enough blood for one season."]
        case (.peace, _): ["Let there be peace between our houses.", "Our people have bled enough."]
        case (.ally, _): ["Your enemies are my enemies.", "Together, no one will dare."]
        case (.refuse, "turtle"): ["My walls are my allies.", "I will not bind my house to another's wars."]
        case (.refuse, _): ["What would I gain? I see no common foe.", "Not yet. Show me why I should."]
        case (.covets, _): ["Your borders are long and your garrisons thin.", "Such rich land, so poorly guarded."]
        case (.fears, _): ["Your armies are many. Let us not quarrel.", "We have no wish to test your soldiers."]
        case (.friends, _): ["The roads between us are full of wagons. Good.", "Our merchants grow fat on our friendship."]
        case (.hostile, "conqueror"): ["I count your towns already.", "Soon."]
        case (.hostile, _): ["We are at war. Do not expect kindness.", "Every border fort of yours is a target."]
        case (.awed, _): ["They say your hall shines like the sun.", "A court like yours is not lightly crossed."]
        case (.cordial, _): ["We watch, and we wait.", "Keep to your side of the river."]
        }
    }
}
