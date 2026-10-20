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

/// A kingdom's land picked for an audience with its ruler.
struct KingdomAudience: Identifiable, Equatable {
    let territory: TerritoryID
    var id: TerritoryID { territory }
}

/// Words a kingdom's ruler says to you, by how their people feel and what they are.
enum KingdomVoice {
    static func line(attitude: Int, temperament: Temperament, vassal: Bool, rng: Int) -> String {
        let pick = { (lines: [String]) in lines[abs(rng) % lines.count] }
        if vassal { return pick(["We keep faith with our overlord.", "Our spears are yours, as sworn.", "Our tribute is ready, as every year."]) }
        switch attitude {
        case 60...: return pick(["Our hearth is your hearth, friend.", "Say the word and our people are yours."])
        case 30..<60: return pick(["You are welcome among us.", "Your envoys bring good gifts and better words."])
        case 10..<30: return pick(["We have heard good things of you.", "Speak. We are listening."])
        case -10..<10:
            switch temperament {
            case .warlike: return pick(["Why does a stranger come armed to our land?", "Our young men grow restless. Choose your words."])
            case .proud: return pick(["Our fathers ruled here before your kings were born.", "We bow to no one. Speak."])
            case .mercantile: return pick(["Have you come to trade? Our harbours are open.", "Gold speaks every tongue."])
            case .peaceable: return pick(["We want only to till our fields in peace.", "Be welcome, and leave us as you found us."])
            }
        case -30 ..< -10: return pick(["Keep your soldiers on your side of the border.", "We watch your armies, and we remember."])
        case -60 ..< -30: return pick(["You are not welcome here.", "Your gifts will not wash out the blood."])
        default: return pick(["Our sons will avenge what you did.", "Leave, while you still can."])
        }
    }

    static func mood(_ attitude: Int, vassal: Bool) -> RulerFigure.Mood {
        if vassal { return .pleased }
        switch attitude {
        case 30...: return .pleased
        case -10..<30: return .neutral
        case -40 ..< -10: return .stern
        default: return .angry
        }
    }

    /// The empire whose halls theirs resemble.
    static func hall(_ look: String?) -> String {
        switch look {
        case "greece": "greece"
        case "libyan": "egypt"
        case "hatti", "mesopotamia": "mesopotamia"
        default: "italia"
        }
    }
}

/// An audience with a minor kingdom's ruler: in their own hall, dressed as their people dress,
/// with a face and words that show how they feel about you, and what you can offer them.
struct KingdomAudienceView: View {
    let session: GameSession
    let territory: TerritoryID
    let close: () -> Void
    @State private var spoken = 0

    private var engine: Engine { session.engine }
    private var state: GameState { session.state }

    var body: some View {
        if let human = session.human, let k = engine.kingdom(at: territory, in: state),
           let kingdom = state.kingdoms[k], let people = engine.people(of: k, in: state) {
            let attitude = engine.attitude(of: k, toward: human, in: state)
            let vassal = kingdom.overlord == human
            HStack(spacing: 0) {
                ZStack(alignment: .bottom) {
                    Hall(civ: k, decorations: [], trophies: [], ruler: kingdom.ruler, state: state, emptyThrone: false,
                         look: KingdomVoice.hall(people.look))
                    GeometryReader { g in
                        let h = g.size.height * 0.66
                        RulerFigure(civ: k, state: state, mood: KingdomVoice.mood(attitude, vassal: vassal), speaking: spoken,
                                    look: people.look ?? "chief")
                            .frame(height: h)
                            .position(x: g.size.width / 2, y: g.size.height * 0.74 - h / 2)
                    }
                }
                .ignoresSafeArea()
                speech(human, k, kingdom, people, attitude: attitude, vassal: vassal)
                    .frame(width: 340)
                    .background(Wood.gradient.ignoresSafeArea())
                    .overlay(alignment: .leading) { Rectangle().fill(Bronze.gradient).frame(width: 2).ignoresSafeArea() }
                    .environment(\.colorScheme, .dark)
            }
            .background(Color.black)
            .onAppear { SoundBoard.shared.play(.horn, volume: 0.4) }
        }
    }

    private func speech(_ human: CivilizationID, _ k: CivilizationID, _ kingdom: Kingdom, _ people: People,
                        attitude: Int, vassal: Bool) -> some View {
        let lands = engine.lands(of: k, in: state)
        let warriors = engine.warriors(of: k, in: state)
        let canTalk = session.isHumanTurn && engine.tribe(at: territory, for: human, in: state) != nil
            && !state.parleyed.contains(territory)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardTitle(text: kingdom.name.capitalizedFirst)
                Spacer()
                Button(action: close) { Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.white.opacity(0.6)) }
                    .accessibilityLabel("Leave")
            }
            Text("\(kingdom.ruler), ruler of \(kingdom.name) · \(PeopleText.temperament(people.temperament))")
                .font(.caption).foregroundStyle(.white.opacity(0.7))
            Text("“\(KingdomVoice.line(attitude: attitude, temperament: people.temperament, vassal: vassal, rng: state.turn + lands.count))”")
                .font(.system(.title3, design: .serif).italic()).foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(lands.count) land\(lands.count == 1 ? "" : "s") (\(lands.map { engine.map.territory($0)?.name ?? $0 }.joined(separator: ", "))) · \(warriors) warriors"
                 + (vassal ? " · your vassal" : kingdom.overlord.map { " · vassal of \(Palette.name($0, state))" } ?? " · \(PeopleText.mood(attitude))"))
                .font(.caption).foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            if canTalk {
                let cost = engine.giftCost(at: territory, in: state)
                let gold = state.civs[human]?.gold ?? 0
                Button("Send gifts · \(cost) gold") { act(.gifts) }
                    .buttonStyle(BronzeButtonStyle()).disabled(gold < cost)
                Text(TribeTalks.likelihood(engine.giftChance(at: territory, for: human, in: state)).capitalizedFirst
                     + ". Even refused, gifts are remembered kindly.")
                    .font(.caption2).foregroundStyle(.white.opacity(0.6))
                Button(engine.wouldSwear(territory, to: human, in: state) ? "Offer protection: they will swear" : "Offer protection") { act(.vassalage) }
                    .font(.callout.bold())
                Button(engine.demandWorks(at: territory, for: human, in: state) ? "Demand they submit: they will bow" : "Demand they submit") { act(.demand) }
                    .font(.callout.bold())
            } else if !vassal, kingdom.overlord == nil, session.isHumanTurn {
                Text(state.parleyed.contains(territory) ? "You have spoken with them this turn."
                     : "Your land must border theirs before your envoys can treat with them.")
                    .font(.caption).foregroundStyle(.white.opacity(0.6))
            }
            Button("Take your leave", action: close).font(.callout.bold()).padding(.top, 4)
        }
        .padding(20)
    }

    private func act(_ kind: Parley) {
        if session.order(.parley(territory: territory, kind)) {
            spoken += 1
            if engine.kingdom(at: territory, in: state) == nil || kind == .vassalage { close() }
        }
    }
}
