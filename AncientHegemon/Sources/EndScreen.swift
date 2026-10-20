import HegemonCore
import SwiftUI

/// The end of a game: victory or defeat, how it was won, the borders growing round by round,
/// and the final standings.
struct EndScreen: View {
    let session: GameSession
    let victory: Victory
    let close: () -> Void
    /// Keep playing after the result.
    var playOn: (() -> Void)?
    @State private var step = 0
    @State private var shown = false
    @State private var graphs = false
    /// The replay plays itself; touching the slider takes over.
    @State private var playing = true

    private var engine: Engine { session.engine }
    private var state: GameState { session.state }
    private var winner: CivilizationID { victory.standings[0] }
    private var won: Bool { session.human == nil || session.human == winner }

    var body: some View {
        ZStack {
            Color(red: 0.07, green: 0.06, blue: 0.05).ignoresSafeArea()
            HStack(spacing: 20) {
                VStack(spacing: 8) {
                    replay
                        .aspectRatio(BoardArt.frame.width / BoardArt.frame.height, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Bronze.gradient, lineWidth: 2))
                    replayControls
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text(won ? "VICTORY" : "DEFEAT")
                        .font(.system(size: 38, weight: .black, design: .serif))
                        .tracking(6)
                        .foregroundStyle(won ? AnyShapeStyle(Bronze.gradient) : AnyShapeStyle(Color(red: 0.8, green: 0.3, blue: 0.25)))
                    Text("\(victory.grade.rawValue.capitalized) \(kindName) Victory")
                        .font(.title3.bold()).foregroundStyle(.white)
                    Text("\(Palette.name(winner, state)) · round \(victory.round)")
                        .font(.callout).foregroundStyle(.white.opacity(0.7))
                    Divider().overlay(.white.opacity(0.3))
                    ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(victory.standings.enumerated()), id: \.offset) { place, civ in
                        HStack(spacing: 8) {
                            Text("\(place + 1)").font(.headline.monospacedDigit()).foregroundStyle(.white.opacity(0.6)).frame(width: 20)
                            Circle().fill(Palette.color(civ, state)).frame(width: 10, height: 10)
                            Text(Palette.name(civ, state)).font(.callout.bold()).foregroundStyle(.white)
                            if civ == session.human { Text("you").font(.caption2.bold()).foregroundStyle(.black)
                                .padding(.horizontal, 5).padding(.vertical, 1).background(Bronze.gradient, in: Capsule()) }
                            Spacer()
                            Text(state.civs[civ]?.eliminated == true ? "fallen" : "\(engine.prestige(of: civ, in: state))")
                                .font(.callout.monospacedDigit()).foregroundStyle(.white.opacity(0.7))
                        }
                        .opacity(shown ? 1 : 0)
                        .offset(x: shown ? 0 : 30)
                        .animation(.spring(duration: 0.5).delay(0.6 + Double(place) * 0.15), value: shown)
                    }
                    }
                    }
                    HStack {
                        Button { graphs = true } label: {
                            Label("Graphs", systemImage: "chart.xyaxis.line").font(.headline).foregroundStyle(.white)
                                .padding(.horizontal, 18).padding(.vertical, 10)
                                .woodPanel(Capsule())
                        }
                        .buttonStyle(.plain)
                        if let playOn, session.human != nil, !(session.human.map { state.civs[$0]?.eliminated ?? true } ?? true) {
                            Button(action: playOn) {
                                Text("One more turn").font(.headline).foregroundStyle(.white)
                                    .padding(.horizontal, 18).padding(.vertical, 10)
                                    .woodPanel(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        Button(action: close) {
                            Text("Play again").font(.headline).foregroundStyle(.black)
                                .padding(.horizontal, 24).padding(.vertical, 10)
                                .background(Bronze.gradient, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: 320)
            }
            .padding(20)
        }
        .sheet(isPresented: $graphs) {
            NavigationStack {
                ScrollView {
                    EmpireGraphs(history: session.statsHistory, lastRound: state.turn,
                                 order: victory.standings, human: session.human, state: state, height: 260)
                        .padding()
                }
                .navigationTitle("How the age unfolded")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Done") { graphs = false } }
            }
        }
        .onAppear {
            shown = true
            SoundBoard.shared.play(won ? .victory : .defeat)
            Feedback.outcome(won)
        }
        .task(id: playing) {
            // Play the age round by round, from wherever it stands, then hold on the end.
            let rounds = session.history.count
            guard playing, rounds > 1 else { return }
            if step >= rounds - 1 { step = 0 }
            while playing, step < rounds - 1 {
                try? await Task.sleep(for: .milliseconds(380))
                if Task.isCancelled { return }
                withAnimation(.easeInOut(duration: 0.25)) { step += 1 }
            }
            playing = false
        }
    }

    /// The round shown at `step` (older saves begin part-way through).
    private var shownRound: Int { max(1, victory.round - session.history.count + 1 + step) }

    /// Play/pause, a slider through the rounds, and that round's great events.
    private var replayControls: some View {
        let rounds = session.history.count
        let lines = highlights(shownRound)
        return VStack(alignment: .leading, spacing: 4) {
            if rounds > 1 {
                HStack(spacing: 10) {
                    Button { playing.toggle() } label: {
                        Image(systemName: playing ? "pause.fill" : "play.fill")
                            .font(.callout.bold()).foregroundStyle(Bronze.gradient)
                            .frame(width: 30, height: 30).woodPanel(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(playing ? "Pause the replay" : "Play the replay")
                    Slider(value: Binding(get: { Double(step) }, set: { playing = false; step = Int($0.rounded()) }),
                           in: 0...Double(rounds - 1), step: 1)
                        .tint(Color(red: 0.84, green: 0.63, blue: 0.27))
                }
            }
            Text(lines.isEmpty ? " " : lines.joined(separator: " · "))
                .font(.caption).foregroundStyle(.white.opacity(0.85))
                .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                .animation(nil, value: step)
        }
    }

    /// The round's turning points from the chronicle: conquests, sacks, wonders, wars and peace.
    private func highlights(_ round: Int) -> [String] {
        let marks = ["takes", "seize", "sack", "rises in", "destroyed", "declares war", "Peace between", "CIVIL WAR",
                     "Iron Age", "splendour begins", "dominates"]
        return session.log.filter { $0.round == round && marks.contains(where: $0.text.contains) }
            .sorted { $0.id < $1.id }.prefix(2).map(\.text)
    }

    /// The map at `step`: everyone's land as it was that round.
    private var replay: some View {
        var s = state
        s.armies = [:]
        s.fleets = []
        if step < session.history.count, session.history.count > 1 {
            let owners = session.history[step]
            for t in s.land.keys { s.land[t]!.owner = owners[t] }
        }
        return MapView(state: s, map: engine.map)
            .allowsHitTesting(false)
            .overlay(alignment: .bottomLeading) {
                Text("Round \(shownRound)")
                    .font(.caption.bold().monospacedDigit())
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.black.opacity(0.6), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(10)
            }
    }

    private var kindName: String {
        switch victory.kind {
        case .domination: "Domination"
        case .trade: "Trade"
        case .legacy: "Legacy"
        case .lastStanding: "Conquest"
        }
    }
}
