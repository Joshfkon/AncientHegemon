import HegemonCore
import SwiftUI

/// The title screen: the painted board drifting behind a bronze title, and each empire as a
/// hanging banner. Choosing one plays a short flourish before the game begins.
struct CivPickerView: View {
    let session: GameSession
    @State private var drift = false
    @State private var chosen: CivilizationID?
    @State private var appeared = false
    @State private var showWalkthrough = false
    /// First time on the title screen: the How to play button pulses.
    @AppStorage("walkthroughSeen") private var walkthroughSeen = false

    private var engine: Engine { session.engine }

    var body: some View {
        ZStack {
            backdrop
            VStack(spacing: 14) {
                VStack(spacing: 4) {
                    Text("ANCIENT HEGEMON")
                        .font(.system(size: 40, weight: .black, design: .serif))
                        .tracking(6)
                        .foregroundStyle(Bronze.gradient)
                        .shadow(color: .black.opacity(0.6), radius: 6, y: 3)
                    Text("THE END OF THE BRONZE AGE · 1200 BC")
                        .font(.system(size: 12, weight: .semibold, design: .serif))
                        .tracking(4)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : -20)

                HStack(spacing: 14) {
                    ForEach(Array(engine.map.civilizations.enumerated()), id: \.element.id) { i, civ in
                        CivBanner(civ: civ, engine: engine, state: session.state)
                            .scaleEffect(chosen == civ.id ? 1.08 : 1)
                            .opacity(chosen == nil || chosen == civ.id ? 1 : 0.25)
                            .offset(y: appeared ? 0 : 60)
                            .opacity(appeared ? 1 : 0)
                            .animation(.spring(duration: 0.6).delay(0.1 + Double(i) * 0.08), value: appeared)
                            .onTapGesture { choose(civ.id) }
                    }
                }
                .padding(.horizontal, 24)

                HStack(spacing: 12) {
                    if let game = session.saved {
                        Button { session.resume() } label: {
                            VStack(spacing: 1) {
                                Text("Continue as \(Palette.name(game.human, game.state))").font(.headline)
                                Text("Round \(game.state.turn) · saved \(game.savedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption2)
                            }
                            .padding(.horizontal, 18).padding(.vertical, 8)
                            .background(Bronze.gradient, in: Capsule())
                            .foregroundStyle(.black)
                        }
                        .buttonStyle(.plain)
                    }
                    Button { showWalkthrough = true } label: {
                        Label("How to play", systemImage: "book.fill")
                            .font(.callout.bold())
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().stroke(Bronze.gradient, lineWidth: walkthroughSeen ? 0 : 2))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce, options: .repeat(walkthroughSeen ? 0 : 3), value: appeared)
                    Button { session.start(as: nil) } label: {
                        Label("Watch the empires", systemImage: "eye")
                            .font(.callout.bold())
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                }
                .opacity(appeared ? 1 : 0)
            }
            .padding(.vertical)
        }
        .fullScreenCover(isPresented: $showWalkthrough) {
            WalkthroughView {
                walkthroughSeen = true
                showWalkthrough = false
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) { appeared = true }
            drift = true
            #if DEBUG
            // Launch with -autoWatch YES to watch a whole AI game unattended.
            if UserDefaults.standard.bool(forKey: "autoWatch") {
                session.start(as: nil)
                session.playing = true
            }
            #endif
        }
    }

    /// The board, darkened, drifting slowly.
    private var backdrop: some View {
        GeometryReader { geo in
            MapView(state: boardOnly, map: engine.map)
                .allowsHitTesting(false)
                .frame(width: geo.size.width * 1.25, height: geo.size.height * 1.25)
                .offset(x: drift ? -geo.size.width * 0.2 : 0, y: drift ? -geo.size.height * 0.15 : -geo.size.height * 0.05)
                .animation(.easeInOut(duration: 40).repeatForever(autoreverses: true), value: drift)
                .overlay(
                    LinearGradient(colors: [.black.opacity(0.75), .black.opacity(0.35), .black.opacity(0.8)],
                                   startPoint: .top, endPoint: .bottom)
                )
        }
        .background(Color(red: 0.08, green: 0.07, blue: 0.06))
        .ignoresSafeArea()
    }

    /// The board with its empires' colours but no armies or fleets.
    private var boardOnly: GameState {
        var s = session.state
        s.armies = [:]
        s.fleets = []
        return s
    }

    private func choose(_ civ: CivilizationID) {
        guard chosen == nil else { return }
        Feedback.impact(0.7)
        SoundBoard.shared.play(.horn, volume: 0.6)
        withAnimation(.spring(duration: 0.4)) { chosen = civ }
        Task {
            try? await Task.sleep(for: .milliseconds(650))
            session.start(as: civ)
            chosen = nil
        }
    }
}

/// Bronze, for titles and highlights.
enum Bronze {
    static let gradient = LinearGradient(colors: [Color(red: 0.98, green: 0.82, blue: 0.52),
                                                  Color(red: 0.80, green: 0.55, blue: 0.25),
                                                  Color(red: 0.55, green: 0.34, blue: 0.14)],
                                         startPoint: .top, endPoint: .bottom)
}

/// An empire as a hanging banner: emblem, name, and what kind of game it is.
struct CivBanner: View {
    let civ: Civilization
    let engine: Engine
    let state: GameState

    var body: some View {
        let color = Palette.color(civ.id, state)
        VStack(spacing: 6) {
            Self.emblem(civ.id)
                .frame(width: 40, height: 40)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                .padding(.top, 14)
            Text(civ.name.uppercased())
                .font(.system(size: 16, weight: .black, design: .serif))
                .tracking(2)
                .foregroundStyle(.white)
            Rectangle().fill(.white.opacity(0.5)).frame(width: 40, height: 1)
            Text(Self.tagline(civ.id))
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
            Spacer(minLength: 2)
            if let g = engine.rules.start.generals[civ.id] {
                Text("\(g.name) · \(traitName(g.trait))")
                    .font(.caption2.bold())
                    .foregroundStyle(.white.opacity(0.75))
            }
            Text(civ.government == .republic ? "Republic" : "Monarchy")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
                .padding(.bottom, 26)
        }
        .frame(maxWidth: .infinity, minHeight: 210)
        .background(
            BannerShape()
                .fill(Color(red: 0.1, green: 0.08, blue: 0.06))
                .overlay(BannerShape().fill(LinearGradient(colors: [color, color.opacity(0.8), color.opacity(0.45)],
                                                           startPoint: .top, endPoint: .bottom)))
                .overlay(BannerShape().stroke(Bronze.gradient, lineWidth: 2))
                .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
        )
        .overlay(alignment: .top) {
            // The rod it hangs from.
            Capsule().fill(Bronze.gradient).frame(height: 6).padding(.horizontal, -6).offset(y: -3)
        }
        .contentShape(BannerShape())
    }

    @ViewBuilder static func emblem(_ civ: CivilizationID) -> some View {
        switch civ {
        case "greece": UnitShape(type: .infantry).fill()
        case "egypt": Image(systemName: "eye.fill").resizable().scaledToFit()
        case "italia":
            HStack(spacing: -4) {
                Image(systemName: "laurel.leading").resizable().scaledToFit()
                Image(systemName: "laurel.trailing").resizable().scaledToFit()
            }
        case "mesopotamia": Image(systemName: "crown.fill").resizable().scaledToFit()
        default: Image(systemName: "flag.fill").resizable().scaledToFit()
        }
    }

    static func tagline(_ civ: CivilizationID) -> String {
        switch civ {
        case "greece": "Masters of the sea on poor, rocky land. The hardest road."
        case "egypt": "The Nile's endless grain, and chariots."
        case "italia": "Rugged and seaborne, ready to expand."
        case "mesopotamia": "Rich river valleys at the crossroads of the world."
        default: ""
        }
    }
}

/// A banner with a swallowtail hem.
struct BannerShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY - 18))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}
