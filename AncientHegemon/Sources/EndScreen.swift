import HegemonCore
import SwiftUI

/// The end of a game: victory or defeat, how it was won, the borders growing round by round,
/// and the final standings.
struct EndScreen: View {
    let session: GameSession
    let victory: Victory
    let close: () -> Void
    @State private var step = 0
    @State private var shown = false
    @State private var graphs = false

    private var engine: Engine { session.engine }
    private var state: GameState { session.state }
    private var winner: CivilizationID { victory.standings[0] }
    private var won: Bool { session.human == nil || session.human == winner }

    var body: some View {
        ZStack {
            Color(red: 0.07, green: 0.06, blue: 0.05).ignoresSafeArea()
            HStack(spacing: 20) {
                replay
                    .aspectRatio(BoardArt.frame.width / BoardArt.frame.height, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Bronze.gradient, lineWidth: 2))
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
        .task {
            // Play the borders round by round, then hold on the end.
            let rounds = session.history.count
            guard rounds > 1 else { return }
            for i in 0..<rounds {
                step = i
                try? await Task.sleep(for: .milliseconds(max(60, 2400 / rounds)))
            }
        }
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
                Text("Round \(min(step + 1, max(1, session.history.count)))")
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
