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

/// Why the player stands before a rival ruler.
struct Audience: Identifiable, Equatable {
    enum Reason: Equatable { case visit, peaceOffer, war }
    let civ: CivilizationID
    let reason: Reason
    var id: String { "\(civ)-\(reason)" }
}

/// An audience with a rival ruler, Civilization-style: their own hall, the ruler on the throne,
/// what they say, and what you can do about it.
struct AudienceView: View {
    let session: GameSession
    let audience: Audience
    let close: () -> Void
    @State private var confirmWar = false
    /// Bumped when they speak, to move their lips.
    @State private var spoken = 0

    private var engine: Engine { session.engine }
    private var state: GameState { session.state }
    private var civ: CivilizationID { audience.civ }

    var body: some View {
        if let human = session.human, let cs = state.civs[civ] {
            HStack(spacing: 0) {
                ZStack(alignment: .bottom) {
                    Hall(civ: civ, decorations: cs.decorations, trophies: cs.trophies, ruler: cs.ruler.name, state: state,
                         emptyThrone: false)
                    // The ruler in person, before the throne.
                    GeometryReader { g in
                        // Seated on the throne, feet on the hall's floor.
                        let h = g.size.height * 0.66
                        RulerFigure(civ: civ, state: state, mood: mood(human), speaking: spoken)
                            .frame(height: h)
                            .position(x: g.size.width / 2, y: g.size.height * 0.74 - h / 2)
                    }
                }
                .ignoresSafeArea()
                speech(human, cs)
                    .frame(width: 340)
                    .background(Wood.gradient.ignoresSafeArea())
                    .overlay(alignment: .leading) { Rectangle().fill(Bronze.gradient).frame(width: 2).ignoresSafeArea() }
                    .environment(\.colorScheme, .dark)
            }
            .background(Color.black)
            .onAppear {
                SoundBoard.shared.play(audience.reason == .war ? .wardrums : .horn, volume: 0.5)
            }
        }
    }

    /// The ruler's face: how their court regards you right now.
    private func mood(_ human: CivilizationID) -> RulerFigure.Mood {
        if audience.reason == .war { return .angry }
        if audience.reason == .peaceOffer || state.peaceOffers.contains(PeaceOffer(from: civ, to: human)) { return .pleased }
        if engine.allied(human, civ, in: state) { return .pleased }
        if !state.atPeace(human, civ) { return .stern }
        let theirs = state.totalUnits(of: civ).total, ours = state.totalUnits(of: human).total
        if theirs * 4 < ours * 3 { return .wary }
        return .neutral
    }

    private func speech(_ human: CivilizationID, _ cs: CivState) -> some View {
        let peace = state.atPeace(human, civ)
        let offered = state.peaceOffers.contains(PeaceOffer(from: civ, to: human))
        let moment: RulerVoice.Moment = switch audience.reason {
        case .war: .war
        case .peaceOffer: .peace
        case .visit: offered ? .peace : peace ? (engine.allied(human, civ, in: state) ? .ally : .cordial) : .hostile
        }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardTitle(text: Palette.name(civ, state))
                Spacer()
                Button(action: close) { Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.white.opacity(0.6)) }
                    .accessibilityLabel("Leave")
            }
            Text("\(cs.ruler.name), \(cs.government == .republic ? "first of the republic" : "king"), \(RulerVoice.temperament(civ))")
                .font(.caption).foregroundStyle(.white.opacity(0.7))
            Text("“\(RulerVoice.line(moment, civ, state))”")
                .font(.system(.title3, design: .serif).italic()).foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text(standing(human, peace: peace)).font(.caption).foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            actions(human, peace: peace, offered: offered)
        }
        .padding(18)
    }

    /// Where things stand between the two realms, in a line.
    private func standing(_ human: CivilizationID, peace: Bool) -> String {
        let theirs = state.territories(of: civ).count, troops = state.totalUnits(of: civ).total
        let rel = engine.allied(human, civ, in: state) ? "Allies" : peace ? "At peace" : "At war"
        return "\(rel) · \(theirs) land\(theirs == 1 ? "" : "s") · \(troops) troops · \(engine.prestige(of: civ, in: state)) prestige"
    }

    @ViewBuilder private func actions(_ human: CivilizationID, peace: Bool, offered: Bool) -> some View {
        let isTurn = session.isHumanTurn
        VStack(alignment: .leading, spacing: 8) {
            if offered {
                Button("Accept peace") { act(.acceptPeace(from: civ)) }.buttonStyle(BronzeButtonStyle())
                Button("Decline") { act(.declinePeace(from: civ)) }
                    .font(.callout.bold()).foregroundStyle(.white.opacity(0.85))
                Text("Declining: they won't ask again for \(engine.rules.alliances.rebuffedRounds) rounds.")
                    .font(.caption2).foregroundStyle(.white.opacity(0.6))
            } else if !peace {
                if state.peaceOffers.contains(PeaceOffer(from: human, to: civ)) {
                    Text("Your envoys await their answer.").font(.callout).foregroundStyle(.white.opacity(0.8))
                } else {
                    Button("Offer peace") { act(.offerPeace(to: civ)) }.buttonStyle(BronzeButtonStyle())
                }
            } else {
                if !engine.allied(human, civ, in: state), !state.allianceOffers.contains(PeaceOffer(from: human, to: civ)) {
                    Button("Propose an alliance") { act(.offerAlliance(to: civ)) }.buttonStyle(BronzeButtonStyle())
                }
                Button(confirmWar ? "Break the peace (−\(-engine.rules.government.legitimacy.brokePeace) legitimacy)" : "Declare war") {
                    if confirmWar { act(.declareWar(on: civ)) } else { confirmWar = true }
                }
                .font(.callout.bold()).foregroundStyle(Color(red: 1, green: 0.55, blue: 0.45))
            }
            Button("Take your leave", action: close)
                .font(.callout.bold()).foregroundStyle(.white.opacity(0.7))
        }
        .disabled(!isTurn)
    }

    private func act(_ command: Command) {
        if session.order(command) { close() }
    }
}
