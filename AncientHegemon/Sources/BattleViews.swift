import HegemonCore
import SwiftUI

struct BattleListView: View {
    let session: GameSession

    var body: some View {
        NavigationStack {
            List(session.battles) { entry in
                NavigationLink {
                    BattleReplayView(entry: entry, state: session.state, map: session.engine.map)
                } label: {
                    BattleRow(entry: entry, state: session.state, map: session.engine.map)
                }
            }
            .overlay {
                if session.battles.isEmpty {
                    ContentUnavailableView("No battles yet", systemImage: "shield",
                                           description: Text("Play a few rounds on the World tab."))
                }
            }
            .navigationTitle("Battles")
        }
    }
}

private struct BattleRow: View {
    let entry: BattleEntry
    let state: GameState
    let map: GameMap

    var body: some View {
        let a = entry.report.setup.attacker, d = entry.report.setup.defender
        let won = entry.report.winner == .attacker
        VStack(alignment: .leading, spacing: 3) {
            Text("Battle of \(map.territory(entry.territory)?.name ?? entry.territory)").font(.headline)
            HStack(spacing: 6) {
                Circle().fill(Palette.color(a.civ, state)).frame(width: 8, height: 8)
                Text("\(Palette.name(a.civ, state)) \(a.units.total)")
                Text("vs").foregroundStyle(.secondary)
                Circle().fill(Palette.color(d.civ, state)).frame(width: 8, height: 8)
                Text("\(Palette.name(d.civ, state)) \(d.units.total)")
            }
            .font(.callout)
            Text("Round \(entry.round) · \(won ? "attacker won" : "defender held") · \(entry.report.rounds) battle rounds")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Plays a battle back frame by frame on the 5×5 board.
struct BattleReplayView: View {
    let entry: BattleEntry
    let state: GameState
    let map: GameMap
    @State private var frame = 0
    @State private var playing = false

    private var report: BattleReport { entry.report }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                board
                    .aspectRatio(1, contentMode: .fit)
                    .padding(.horizontal, 8)
                controls
                if frame == report.frames.count - 1 { outcome }
            }
            .padding()
        }
        .navigationTitle(map.territory(entry.territory)?.name ?? "Battle")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: playing) {
            guard playing else { return }
            if frame >= report.frames.count - 1 { frame = 0 }
            while playing, frame < report.frames.count - 1 {
                try? await Task.sleep(for: .milliseconds(900))
                withAnimation(.easeInOut(duration: 0.5)) { frame += 1 }
            }
            playing = false
        }
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
            Text("\(army.units.infantry) inf · \(army.units.archers) arc · \(army.units.cavalry) cav")
                .font(.caption.monospacedDigit())
            Text(army.formation.replacingOccurrences(of: "_", with: " ").capitalized
                 + (army.general.map { " · \($0.name)" } ?? ""))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var board: some View {
        GeometryReader { geo in
            let cell = geo.size.width / 5
            let current = report.frames[frame]
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
                // Strikes this round.
                Path { path in
                    for strike in current.strikes {
                        guard let a = current.blocks.first(where: { $0.id == strike.from }),
                              let b = current.blocks.first(where: { $0.id == strike.to }) else { continue }
                        path.move(to: center(a.position, cell))
                        path.addLine(to: center(b.position, cell))
                    }
                }
                .stroke(Color.red.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                // Blocks.
                ForEach(current.blocks.filter { $0.status != .destroyed }, id: \.id) { block in
                    BlockView(block: block,
                              color: Palette.color(block.side == .attacker ? report.setup.attacker.civ
                                                   : report.setup.defender.civ, state))
                        .frame(width: cell * 0.82, height: cell * 0.82)
                        .position(center(block.position, cell))
                        .opacity(block.status == .routed ? 0.3 : 1)
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
            Text(frame == 0 ? "Deployment" : "Round \(frame) of \(report.rounds)")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    private var outcome: some View {
        let won = report.winner == .attacker
        let winner = won ? report.setup.attacker.civ : report.setup.defender.civ
        return VStack(spacing: 4) {
            Text("\(Palette.name(winner, state)) \(won ? "wins the field" : "holds the field")").font(.headline)
            Text("Losses: attacker \(report.attackerLosses.total), defender \(report.defenderLosses.total)")
                .font(.callout)
            if report.attackerGeneralKilled || report.defenderGeneralKilled {
                Text("A general fell in the fighting.").font(.callout).foregroundStyle(.red)
            }
        }
    }
}

private struct BlockView: View {
    let block: BlockSnapshot
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(color)
            .overlay {
                VStack(spacing: 1) {
                    Text(symbol).font(.system(size: 15, weight: .black))
                    Text("\(block.units)").font(.system(size: 11, weight: .bold).monospacedDigit())
                }
                .foregroundStyle(.white)
            }
            .overlay(alignment: .bottom) {
                GeometryReader { g in
                    Capsule().fill(Color.white.opacity(0.9))
                        .frame(width: g.size.width * CGFloat(min(100, block.morale)) / 100, height: 3)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
                .padding(4)
            }
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.black.opacity(0.5), lineWidth: 1))
    }

    private var symbol: String {
        switch block.type {
        case .infantry: "I"
        case .archers: "A"
        case .cavalry: "C"
        }
    }
}
