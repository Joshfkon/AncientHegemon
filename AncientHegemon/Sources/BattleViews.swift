import HegemonCore
import SwiftUI

/// Plays a battle back frame by frame on the 5×5 board.
struct BattleReplayView: View {
    let entry: BattleEntry
    let state: GameState
    let map: GameMap
    /// Start playing as soon as the replay opens (for battles just fought).
    var autoplay = false
    /// Whose side the player is on, for the closing horn call.
    var perspective: CivilizationID?
    @State private var frame = 0
    @State private var playing = false
    @AppStorage(SoundBoard.enabledKey) private var soundOn = true

    private var report: BattleReport { entry.report }
    /// The frame on screen, always a valid index.
    private var shown: Int { min(max(0, frame), report.frames.count - 1) }

    var body: some View {
        HStack(spacing: 16) {
            board
                .aspectRatio(1, contentMode: .fit)
                .padding(8)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    controls
                    if shown == report.frames.count - 1 { outcome }
                }
                .padding(.vertical)
            }
            .frame(width: 300)
        }
        .padding(.horizontal)
        .navigationTitle(map.territory(entry.territory)?.name ?? "Battle")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { soundOn.toggle() } label: {
                    Image(systemName: soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
                }
                .accessibilityLabel(soundOn ? "Mute" : "Sound on")
            }
        }
        .onAppear {
            if autoplay {
                SoundBoard.shared.play(.horn, volume: 0.7)
                playing = true
            }
        }
        .onChange(of: shown) { old, new in
            if new == old + 1 { announce(report.frames[new]) }
            if new == report.frames.count - 1, new != old { finale() }
        }
        .task(id: playing) {
            guard playing else { return }
            if frame >= report.frames.count - 1 { frame = 0 }
            while playing, frame < report.frames.count - 1 {
                // A cancelled sleep throws at once: stop, rather than racing to the end.
                do { try await Task.sleep(for: .milliseconds(900)) } catch { return }
                withAnimation(.easeInOut(duration: 0.5)) { frame = min(frame + 1, report.frames.count - 1) }
            }
            playing = false
        }
    }

    /// Sound and a jolt for a round of fighting, as hard as the blows.
    private func announce(_ frame: BattleFrame) {
        guard !frame.strikes.isEmpty else { return }
        let ranged = frame.strikes.filter(\.ranged).reduce(0) { $0 + $1.damage }
        let melee = frame.strikes.filter { !$0.ranged }.reduce(0) { $0 + $1.damage }
        let scale = Float(max(1, report.setup.attacker.units.total + report.setup.defender.units.total) * 6)
        if ranged > 0 { SoundBoard.shared.play(.arrows, volume: 0.4 + Float(ranged) / scale) }
        if melee > 0 { SoundBoard.shared.play(.clash, volume: 0.4 + Float(melee) / scale) }
        Feedback.impact(CGFloat(ranged + melee) / CGFloat(scale) * 3)
    }

    private func finale() {
        let won = report.winner == .attacker ? report.setup.attacker.civ : report.setup.defender.civ
        let good = perspective.map { $0 == won } ?? true
        SoundBoard.shared.play(good ? .victory : .defeat, volume: 0.8)
        if perspective != nil { Feedback.outcome(good) }
    }

    private var header: some View {
        let s = report.setup
        return VStack(spacing: 4) {
            HStack {
                side(s.defender, label: "Defending")
                Spacer()
                side(s.attacker, label: "Attacking")
            }
            Text("\(s.terrain.rawValue.capitalized)\(s.approach == .overland ? "" : " · \(s.approach.rawValue) crossing")")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func side(_ army: BattleArmy, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 5) {
                Circle().fill(Palette.color(army.civ, state)).frame(width: 9, height: 9)
                Text(Palette.name(army.civ, state)).font(.headline)
            }
            UnitRow(units: army.units, showZero: true).font(.caption)
            Text(army.formation.replacingOccurrences(of: "_", with: " ").capitalized
                 + (army.general.map { " · \($0.name)" } ?? ""))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var board: some View {
        GeometryReader { geo in
            let cell = geo.size.width / 5
            let current = report.frames[shown]
            let rocks = Set(report.impassable)
            ZStack(alignment: .topLeading) {
                // Squares: the defender's rows at the top, the attacker's at the bottom.
                ForEach(0..<25, id: \.self) { i in
                    let col = i % 5, row = 4 - i / 5
                    Rectangle()
                        .fill(rocks.contains(GridPoint(col, row)) ? Color(white: 0.35)
                              : row == 2 ? Color(red: 0.86, green: 0.82, blue: 0.70) : Color(red: 0.78, green: 0.85, blue: 0.66))
                        .border(Color.black.opacity(0.15))
                        .frame(width: cell, height: cell)
                        .offset(x: CGFloat(col) * cell, y: CGFloat(4 - row) * cell)
                }
                // Strikes this round, drawn from striker to target.
                StrikeLines(lines: current.strikes.compactMap { strike in
                    guard let a = current.blocks.first(where: { $0.id == strike.from }),
                          let b = current.blocks.first(where: { $0.id == strike.to }) else { return nil }
                    return (center(a.position, cell), center(b.position, cell), strike.ranged)
                })
                .id(shown)
                // Blocks: they shake and flash when hit, and shrink away when destroyed.
                let previous = shown > 0 ? report.frames[shown - 1].blocks : []
                ForEach(current.blocks.filter { $0.status != .destroyed }, id: \.id) { block in
                    let lost = (previous.first { $0.id == block.id }?.units ?? block.units) - block.units
                    BlockView(block: block,
                              color: Palette.color(block.side == .attacker ? report.setup.attacker.civ
                                                   : report.setup.defender.civ, state),
                              hit: lost > 0 ? shown : nil)
                        .frame(width: cell * 0.82, height: cell * 0.82)
                        .overlay { if lost > 0 { LossMarker(lost: lost).id(shown) } }
                        .position(center(block.position, cell))
                        .opacity(block.status == .routed ? 0.3 : 1)
                        .transition(.scale(scale: 0.2).combined(with: .opacity))
                }
            }
        }
    }

    private func center(_ p: GridPoint, _ cell: CGFloat) -> CGPoint {
        CGPoint(x: (CGFloat(p.col) + 0.5) * cell, y: (CGFloat(4 - p.row) + 0.5) * cell)
    }

    private var controls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 20) {
                Button { frame = max(0, frame - 1) } label: { Image(systemName: "backward.frame.fill") }
                    .disabled(frame == 0)
                Button { playing.toggle() } label: {
                    Image(systemName: playing ? "pause.circle.fill" : "play.circle.fill").font(.largeTitle)
                }
                Button { frame = min(report.frames.count - 1, frame + 1) } label: { Image(systemName: "forward.frame.fill") }
                    .disabled(frame == report.frames.count - 1)
            }
            Text(shown == 0 ? "Deployment" : "Round \(shown) of \(report.rounds)")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    private var outcome: some View {
        let won = report.winner == .attacker
        let winner = won ? report.setup.attacker.civ : report.setup.defender.civ
        return VStack(spacing: 4) {
            Text("\(won ? "Victory" : "Held") · \(Palette.name(winner, state))").font(.headline)
            Text("Losses: attacker \(report.attackerLosses.total), defender \(report.defenderLosses.total)")
                .font(.callout)
            if report.attackerGeneralKilled || report.defenderGeneralKilled {
                Text("A general fell in the fighting.").font(.callout).foregroundStyle(.red)
            }
        }
    }
}

/// Strike lines that draw themselves from striker to target: dashed arcs for arrows, solid for blows.
private struct StrikeLines: View {
    let lines: [(CGPoint, CGPoint, Bool)]
    @State private var progress: CGFloat = 0

    var body: some View {
        ZStack {
            ForEach(lines.indices, id: \.self) { i in
                let (a, b, ranged) = lines[i]
                Path { path in
                    path.move(to: a)
                    if ranged {
                        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 - abs(b.y - a.y) * 0.25 - 12)
                        path.addQuadCurve(to: b, control: mid)
                    } else {
                        path.addLine(to: b)
                    }
                }
                .trim(from: 0, to: progress)
                .stroke(ranged ? Color.orange : Color.red,
                        style: StrokeStyle(lineWidth: ranged ? 1.8 : 3, lineCap: .round, dash: ranged ? [4, 3] : []))
                .opacity(0.85)
            }
        }
        .onAppear { withAnimation(.easeOut(duration: 0.35)) { progress = 1 } }
        .allowsHitTesting(false)
    }
}

/// "−2" rising and fading over a block that lost units.
private struct LossMarker: View {
    let lost: Int
    @State private var shown = false

    var body: some View {
        Text("−\(lost)")
            .font(.system(size: 15, weight: .black).monospacedDigit())
            .foregroundStyle(.white)
            .shadow(color: .red, radius: 2)
            .offset(y: shown ? -28 : -6)
            .opacity(shown ? 0 : 1)
            .onAppear { withAnimation(.easeOut(duration: 0.9).delay(0.2)) { shown = true } }
            .allowsHitTesting(false)
    }
}

private struct BlockView: View {
    let block: BlockSnapshot
    let color: Color
    /// The frame in which the block was hit, to trigger its shake and flash.
    var hit: Int?

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(block.levy ? color.opacity(0.55) : color)
            .overlay {
                GeometryReader { g in
                    VStack(spacing: 1) {
                        UnitIcon(type: block.type, color: .white).frame(width: g.size.width * 0.5, height: g.size.width * 0.5)
                        Text("\(block.units)").font(.system(size: max(9, g.size.width * 0.22), weight: .bold).monospacedDigit())
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .foregroundStyle(.white)
                }
            }
            .overlay(alignment: .bottom) {
                GeometryReader { g in
                    Capsule().fill(Color.white.opacity(0.9))
                        .frame(width: g.size.width * CGFloat(min(100, block.morale)) / 100, height: 3)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
                .padding(4)
            }
            .overlay(RoundedRectangle(cornerRadius: 6)
                .stroke(Color.black.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: block.levy ? [3, 2] : [])))
            .overlay(alignment: .top) {
                if block.levy { Text("militia").font(.system(size: 7, weight: .bold)).foregroundStyle(.white).padding(.top, 1) }
            }
            .keyframeAnimator(initialValue: HitState(), trigger: hit) { view, value in
                view
                    .offset(x: value.shake)
                    .overlay(RoundedRectangle(cornerRadius: 6).fill(Color.red.opacity(value.flash)))
            } keyframes: { _ in
                KeyframeTrack(\.shake) {
                    LinearKeyframe(0, duration: 0.2)
                    LinearKeyframe(-4, duration: 0.05)
                    LinearKeyframe(4, duration: 0.08)
                    LinearKeyframe(-3, duration: 0.08)
                    LinearKeyframe(0, duration: 0.06)
                }
                KeyframeTrack(\.flash) {
                    LinearKeyframe(0, duration: 0.2)
                    LinearKeyframe(0.5, duration: 0.05)
                    LinearKeyframe(0, duration: 0.35)
                }
            }
    }
}

private struct HitState {
    var shake: CGFloat = 0
    var flash: Double = 0

}
