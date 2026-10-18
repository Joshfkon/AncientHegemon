import HegemonCore
import SwiftUI

/// Plays a battle back round by round on the 5×5 board: who is winning, what is happening, and
/// at the end whether the winner gives chase.
struct BattleReplayView: View {
    let entry: BattleEntry
    let state: GameState
    let map: GameMap
    /// Start playing as soon as the replay opens (for battles just fought).
    var autoplay = false
    /// Whose side the player is on: "we" and "they", and the closing horn call.
    var perspective: CivilizationID?
    /// Sound the horn when it starts (the battlefield has already roared the charge).
    var horn = true
    /// Shown full screen with its own Done button (instead of pushed in a navigation stack).
    var done: (() -> Void)?
    @State private var frame = 0
    @State private var playing = false
    /// The last round is over and the beaten army is running (or being let go).
    @State private var chased = false

    private var report: BattleReport { entry.report }
    private var last: Int { report.frames.count - 1 }
    /// The frame on screen, always a valid index.
    private var shown: Int { min(max(0, frame), last) }
    private var title: String { map.territory(entry.territory).map { "Battle of \($0.name)" } ?? "Battle" }
    private var story: BattleStory { BattleStory(report: report, state: state, perspective: perspective) }

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 6) {
                BattleBoard(setup: report.setup, impassable: report.impassable, frame: report.frames[shown],
                            previous: shown > 0 ? report.frames[shown - 1].blocks : [], tick: shown,
                            chase: chased ? (report.winner, report.pursuit != nil) : nil, state: state)
                    .overlay(alignment: .bottom) { caption }
                    .overlay { if chased { resultBanner.transition(.scale(scale: 1.6).combined(with: .opacity)) } }
            }
            .padding(8)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let done {
                        HStack {
                            Text(title).font(.title3.weight(.bold)).fontDesign(.serif)
                            Spacer()
                            SoundToggle()
                            Button("Done", action: done).bold().padding(.leading, 8)
                        }
                    }
                    header
                    MomentumBar(story: story, frame: report.frames[shown], state: state, over: chased)
                    controls
                    if chased { outcome }
                }
                .padding(.top, 10)
            }
            .frame(width: 340)
        }
        .padding(.horizontal)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Parchment())
        .animation(.spring(duration: 0.5, bounce: 0.4), value: chased)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(done == nil ? .automatic : .hidden, for: .navigationBar)
        .toolbar {
            if done == nil { ToolbarItem(placement: .topBarLeading) { SoundToggle() } }
        }
        .onAppear {
            if autoplay {
                if horn { SoundBoard.shared.play(.horn, volume: 0.7) }
                playing = true
            }
        }
        .onChange(of: shown) { old, new in
            if new == old + 1 { announce(report.frames[new]) }
            if new < last { chased = false }
        }
        // Once the last round is fought, a beat, then the rout.
        .task(id: shown == last) {
            guard shown == last, !chased else { return }
            do { try await Task.sleep(for: .milliseconds(shown == 0 ? 300 : 900)) } catch { return }
            chase()
        }
        .task(id: playing) {
            guard playing else { return }
            if frame >= last { frame = 0; chased = false }
            while playing, frame < last {
                // A cancelled sleep throws at once: stop, rather than racing to the end.
                do { try await Task.sleep(for: .milliseconds(1100)) } catch { return }
                withAnimation(.easeInOut(duration: 0.55)) { frame = min(frame + 1, last) }
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

    /// The beaten army runs; hooves if the winner rides them down, then the horn.
    private func chase() {
        withAnimation(.easeIn(duration: 1.1)) { chased = true }
        if report.pursuit != nil {
            SoundBoard.shared.play(story.winnerHasCavalry ? .gallop : .roar, volume: 0.7)
        }
        let won = report.winner == .attacker ? report.setup.attacker.civ : report.setup.defender.civ
        let good = perspective.map { $0 == won } ?? true
        Task {
            try? await Task.sleep(for: .milliseconds(report.pursuit != nil ? 700 : 200))
            SoundBoard.shared.play(good ? .victory : .defeat, volume: 0.8)
            if perspective != nil { Feedback.outcome(good) }
        }
    }

    /// What is happening this round, across the bottom of the field.
    private var caption: some View {
        let text = chased ? story.chaseLine : story.line(for: shown)
        return Text(text)
            .font(.callout.weight(.semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(.black.opacity(0.6)))
            .padding(10)
            .id(chased ? -1 : shown)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .animation(.easeOut(duration: 0.3), value: shown)
            .opacity(chased ? 0 : 1)
    }

    private var header: some View {
        let s = report.setup
        return VStack(spacing: 4) {
            HStack(alignment: .top) {
                ArmySide(army: s.defender, label: "Defending", state: state)
                Spacer()
                ArmySide(army: s.attacker, label: "Attacking", state: state)
            }
            Text("\(s.terrain.rawValue.capitalized)\(s.approach == .overland ? "" : " · \(s.approach.rawValue) crossing")")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// A big banner over the field when the battle ends.
    private var resultBanner: some View {
        let won = report.winner == .attacker
        let winner = won ? report.setup.attacker.civ : report.setup.defender.civ
        let good = perspective.map { $0 == winner } ?? true
        return VStack(spacing: 2) {
            Text(perspective == nil ? (won ? "TAKEN" : "HELD") : (good ? "VICTORY" : "DEFEAT"))
                .font(.system(size: 34, weight: .black, design: .serif))
                .tracking(4)
            Text(Palette.name(winner, state) + (won ? " take the field" : " hold the field"))
                .font(.callout.bold())
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 28).padding(.vertical, 10)
        .background(BannerRibbon().fill(good ? Palette.color(perspective ?? winner, state) : Color(red: 0.35, green: 0.08, blue: 0.08))
            .overlay(BannerRibbon().stroke(Bronze.gradient, lineWidth: 2)))
        .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
    }

    private var controls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 20) {
                Button { frame = max(0, frame - 1) } label: { Image(systemName: "backward.frame.fill") }
                    .disabled(frame == 0)
                Button { playing.toggle() } label: {
                    Image(systemName: playing ? "pause.circle.fill" : "play.circle.fill").font(.largeTitle)
                }
                Button { frame = min(last, frame + 1) } label: { Image(systemName: "forward.frame.fill") }
                    .disabled(frame == last)
            }
            Text(shown == 0 ? "Deployment" : "Round \(shown) of \(report.rounds)")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var outcome: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(story.chaseLine).font(.callout.bold())
            Text(story.lossText).font(.callout)
            if report.attackerGeneralKilled || report.defenderGeneralKilled {
                Text("A general fell in the fighting.").font(.callout).foregroundStyle(.red)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Mutes and unmutes the battle sounds.
struct SoundToggle: View {
    @AppStorage(SoundBoard.enabledKey) private var soundOn = true

    var body: some View {
        Button { soundOn.toggle() } label: {
            Image(systemName: soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
        }
        .accessibilityLabel(soundOn ? "Mute" : "Sound on")
        .onChange(of: soundOn) { _, on in if !on { SoundBoard.shared.stop(.wardrums, fade: 0.2) } }
    }
}

/// The battlefield's parchment backdrop.
struct Parchment: View {
    var body: some View {
        LinearGradient(colors: [Color(red: 0.93, green: 0.88, blue: 0.76), Color(red: 0.84, green: 0.76, blue: 0.6)],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

/// One side of a battle: whose, how many of what, how they fight.
struct ArmySide: View {
    let army: BattleArmy
    let label: String
    let state: GameState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 5) {
                Circle().fill(Palette.color(army.civ, state)).frame(width: 9, height: 9)
                Text(Palette.name(army.civ, state)).font(.headline)
            }
            UnitRow(units: army.units, showZero: true).font(.caption)
            if army.levy > 0 { Text("+ \(army.levy) militia").font(.caption) }
            Text(army.formation.replacingOccurrences(of: "_", with: " ").capitalized
                 + (army.general.map { " · \($0.name)" } ?? ""))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// The field itself: ground, river, blocks and the blows between them. Used for the muster
/// (deployment only) and the replay.
struct BattleBoard: View {
    let setup: BattleSetup
    let impassable: [GridPoint]
    let frame: BattleFrame
    /// The blocks a round earlier, to show what each lost.
    let previous: [BlockSnapshot]
    /// Changes every round, to retrigger hit effects.
    let tick: Int
    /// After the battle: who won, and whether they chased the beaten army off the field.
    var chase: (winner: BattleSide, pursue: Bool)?
    let state: GameState

    var body: some View {
        GeometryReader { geo in
            let cell = geo.size.width / 5
            let rocks = Set(impassable)
            ZStack(alignment: .topLeading) {
                // Squares: the defender's rows at the top, the attacker's at the bottom.
                ForEach(0..<25, id: \.self) { i in
                    let col = i % 5, row = 4 - i / 5
                    let rock = rocks.contains(GridPoint(col, row))
                    ZStack {
                        Rectangle().fill(rock ? Self.rockColor : Self.ground(setup.terrain, row: row, col: col))
                        if rock {
                            Image(systemName: "mountain.2.fill").font(.system(size: cell * 0.4)).foregroundStyle(.white.opacity(0.35))
                        } else if let glyph = Self.groundMark(setup.terrain), (col + row) % 3 == 0 {
                            Image(systemName: glyph).font(.system(size: cell * 0.22)).foregroundStyle(.black.opacity(0.12))
                                .offset(x: cell * 0.25, y: cell * 0.25)
                        }
                    }
                    .overlay(Rectangle().stroke(Color.black.opacity(0.12), lineWidth: 0.5))
                    .frame(width: cell, height: cell)
                    .offset(x: CGFloat(col) * cell, y: CGFloat(4 - row) * cell)
                }
                // A river crossing runs across the middle of the field.
                if setup.approach == .river || setup.approach == .strait, cell > 1 {
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: cell * 2.5))
                        for x in stride(from: 0, through: cell * 5, by: cell / 4) {
                            p.addLine(to: CGPoint(x: x, y: cell * 2.5 + sin(x / cell * 3) * cell * 0.12))
                        }
                    }
                    .stroke(Color(red: 0.2, green: 0.45, blue: 0.85).opacity(0.65), lineWidth: cell * 0.18)
                }
                // Strikes this round, drawn from striker to target.
                StrikeLines(lines: frame.strikes.compactMap { strike in
                    guard let a = frame.blocks.first(where: { $0.id == strike.from }),
                          let b = frame.blocks.first(where: { $0.id == strike.to }) else { return nil }
                    return (center(a.position, cell), center(b.position, cell), strike.ranged)
                })
                .id(tick)
                // Blocks: they shake and flash when hit, and shrink away when destroyed.
                ForEach(frame.blocks.filter { $0.status != .destroyed }, id: \.id) { block in
                    let lost = (previous.first { $0.id == block.id }?.units ?? block.units) - block.units
                    BlockView(block: block,
                              color: Palette.color(block.side == .attacker ? setup.attacker.civ : setup.defender.civ, state),
                              hit: lost > 0 ? tick : nil)
                        .frame(width: cell * 0.82, height: cell * 0.82)
                        .background { if lost > 0 { DustPuff().id(tick) } }
                        .overlay { if lost > 0 { LossMarker(lost: lost).id(tick) } }
                        .position(center(block.position, cell))
                        .opacity(block.status == .routed ? 0.3 : 1)
                        .offset(y: chaseOffset(block, cell))
                        .opacity(fled(block) ? 0 : 1)
                        .transition(.scale(scale: 0.2).combined(with: .opacity))
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.32, green: 0.24, blue: 0.15)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Bronze.gradient, lineWidth: 3))
        .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
    }

    /// The beaten run for their own edge of the field; pursuers follow a little way.
    private func chaseOffset(_ block: BlockSnapshot, _ cell: CGFloat) -> CGFloat {
        guard let chase else { return 0 }
        // The defender's edge is the top (negative y), the attacker's the bottom.
        let home: CGFloat = block.side == .defender ? -1 : 1
        if block.side != chase.winner { return home * cell * 2.2 }
        return chase.pursue ? -home * cell * (block.type == .cavalry ? 1.6 : 0.6) : 0
    }

    private func fled(_ block: BlockSnapshot) -> Bool {
        guard let chase else { return false }
        return block.side != chase.winner || (chase.pursue && block.type == .cavalry)
    }

    private func center(_ p: GridPoint, _ cell: CGFloat) -> CGPoint {
        CGPoint(x: (CGFloat(p.col) + 0.5) * cell, y: (CGFloat(4 - p.row) + 0.5) * cell)
    }

    // MARK: Look

    static let rockColor = Color(red: 0.36, green: 0.33, blue: 0.3)

    /// The field's ground for the battle's terrain, lightly chequered.
    static func ground(_ terrain: Terrain, row: Int, col: Int) -> Color {
        let base: (Double, Double, Double) = switch terrain {
        case .plains: (0.62, 0.74, 0.42)
        case .hills: (0.55, 0.66, 0.4)
        case .forest: (0.36, 0.52, 0.3)
        case .mountains: (0.6, 0.6, 0.52)
        case .desert: (0.88, 0.76, 0.5)
        }
        let k = (row + col) % 2 == 0 ? 1.0 : 0.94
        return Color(red: base.0 * k, green: base.1 * k, blue: base.2 * k)
    }

    static func groundMark(_ terrain: Terrain) -> String? {
        switch terrain {
        case .forest: "tree.fill"
        case .hills: "triangle.fill"
        case .desert: "sun.dust.fill"
        case .plains: "leaf.fill"
        case .mountains: nil
        }
    }
}

/// "Are we winning?": each side's fighting strength (men still in the line, weighted by their
/// nerve) as a tug of war, with the officers' word for it.
struct MomentumBar: View {
    let story: BattleStory
    let frame: BattleFrame
    let state: GameState
    /// The battle is over: the bar swings to the winner.
    var over = false

    var body: some View {
        let ours = story.strength(story.us, in: frame), theirs = story.strength(story.us.other, in: frame)
        let won = story.report.winner == story.us
        let share = over ? (won ? 0.9 : 0.1) : ours + theirs > 0 ? ours / (ours + theirs) : 0.5
        let (word, color) = over ? Self.result(won, story) : Self.verdict(share, story.perspective != nil)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(story.perspective == nil ? "The fight" : "Are we winning?").font(.caption.bold())
                Spacer()
                Text(word).font(.subheadline.bold()).foregroundStyle(color)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.color(story.civ(story.us.other), state))
                    Capsule().fill(Palette.color(story.civ(story.us), state))
                        .frame(width: max(6, g.size.width * share))
                    Rectangle().fill(.white).frame(width: 3, height: 16)
                        .offset(x: g.size.width * share - 1.5)
                        .shadow(radius: 2)
                }
            }
            .frame(height: 12)
            .overlay(Capsule().stroke(Bronze.gradient, lineWidth: 1.5))
            HStack {
                Text(story.name(story.us)).font(.caption2)
                Spacer()
                Text(story.name(story.us.other)).font(.caption2)
            }
            .foregroundStyle(.secondary)
        }
        .animation(.easeInOut(duration: 0.6), value: share)
    }

    static func result(_ won: Bool, _ story: BattleStory) -> (String, Color) {
        if story.perspective == nil { return ("\(story.name(story.report.winner)) win", .primary) }
        return won ? ("The field is ours", .green) : ("We are beaten", .red)
    }

    static func verdict(_ share: Double, _ personal: Bool) -> (String, Color) {
        switch share {
        case 0.68...: (personal ? "We are winning" : "One side is winning", .green)
        case 0.56..<0.68: (personal ? "We have the upper hand" : "One side presses", .green)
        case 0.44..<0.56: ("In the balance", .orange)
        case 0.32..<0.44: (personal ? "We are pressed hard" : "One side is pressed", .red)
        default: (personal ? "We are losing" : "One side is breaking", .red)
        }
    }
}

/// Tells a battle as it goes: what happened each round, from the player's side when they fought.
struct BattleStory {
    let report: BattleReport
    let state: GameState
    let perspective: CivilizationID?

    /// The side told as "we" (the attacker when the player wasn't there).
    var us: BattleSide { perspective == report.setup.defender.civ ? .defender : .attacker }
    func civ(_ side: BattleSide) -> CivilizationID { side == .attacker ? report.setup.attacker.civ : report.setup.defender.civ }
    func name(_ side: BattleSide) -> String { Palette.name(civ(side), state) }

    /// "Our" / "Their", or the civ's name when the player is watching someone else's battle.
    private func whose(_ side: BattleSide) -> String {
        perspective == nil ? name(side) : (side == us ? "Our" : "Their")
    }
    private func who(_ side: BattleSide) -> String {
        perspective == nil ? "The " + name(side) : (side == us ? "We" : "They")
    }

    /// Men still standing in the line, weighted by nerve: a shaken block counts for less.
    func strength(_ side: BattleSide, in frame: BattleFrame) -> Double {
        // Blocks that broke still count a little: they may rally, and a tie needs breaking.
        frame.blocks.filter { $0.side == side && $0.status != .destroyed }.reduce(0) { sum, b in
            sum + Double(b.units) * (b.levy ? 0.5 : 1) * (b.status == .routed ? 0.15 : 1)
                * (0.4 + 0.6 * Double(min(100, max(0, b.morale))) / 100)
        }
    }

    private func noun(_ b: BlockSnapshot) -> String { b.levy ? "militia" : b.type.rawValue }

    func line(for index: Int) -> String {
        let frames = report.frames
        guard index > 0, index < frames.count else {
            let t = report.setup.terrain
            let ground = (t == .desert || t == .forest ? "in the " : "on the ") + t.rawValue
            return report.setup.approach == .overland ? "The armies draw up \(ground)."
                : "The attackers must cross the \(report.setup.approach == .amphibious ? "shore" : report.setup.approach.rawValue) under the enemy's eyes."
        }
        let now = frames[index], before = frames[index - 1]
        let old = Dictionary(uniqueKeysWithValues: before.blocks.map { ($0.id, $0) })
        // A block breaking is the biggest news.
        if let broke = now.blocks.first(where: { $0.status == .routed && old[$0.id]?.status == .fighting }) {
            return "\(whose(broke.side)) \(noun(broke)) break and run!"
        }
        if let fell = now.blocks.first(where: { $0.status == .destroyed && old[$0.id]?.status != .destroyed }) {
            return "\(whose(fell.side)) \(noun(fell)) are cut down to the last man."
        }
        let lost = { (side: BattleSide) in
            now.blocks.filter { $0.side == side }.reduce(0) { $0 + (old[$1.id]?.units ?? $1.units) - $1.units }
        }
        let a = lost(us), b = lost(us.other)
        let tally = a + b > 0 ? " (\(perspective == nil ? name(us) : "us") −\(a), \(perspective == nil ? name(us.other) : "them") −\(b))" : ""
        let melee = now.strikes.contains { !$0.ranged }
        let firstMelee = melee && !frames[1..<index].contains { $0.strikes.contains { !$0.ranged } }
        if firstMelee { return "The lines crash together!" + tally }
        if !melee, !now.strikes.isEmpty {
            let shooters = Set(now.strikes.compactMap { s in now.blocks.first { $0.id == s.from }?.side })
            if shooters.count == 1, let side = shooters.first { return "\(whose(side)) archers loose a volley." + tally }
            return "Arrows fly both ways." + tally
        }
        if now.strikes.isEmpty { return "The armies close in." }
        if b > a * 2 { return "\(who(us)) drive into \(perspective == nil ? "the " + name(us.other) : "them")!" + tally }
        if a > b * 2 { return "\(who(us.other)) push \(perspective == nil ? "the " + name(us) : "us") back!" + tally }
        return "The fighting is hard on both sides." + tally
    }

    var winnerHasCavalry: Bool {
        report.frames.last?.blocks.contains { $0.side == report.winner && $0.type == .cavalry && $0.status == .fighting } ?? false
    }

    /// The rout, or the winner letting the beaten go.
    var chaseLine: String {
        let winner = report.winner, loser = report.winner.other
        guard let p = report.pursuit else {
            return "\(who(winner)) hold the field and let \(perspective == nil ? "them" : winner == us ? "them" : "us") go."
        }
        var text = winnerHasCavalry ? "\(whose(winner)) horsemen ride down the fleeing" : "\(who(winner)) give chase"
        text += p.routed > 0 ? ": \(p.routed) cut down in the rout."
            : ", but \(perspective == nil ? "the " + name(loser) : loser == us ? "we" : "they") get away."
        if p.pursuersLost > 0 { text += " \(whose(loser)) archers cover the retreat, felling \(p.pursuersLost)." }
        return text
    }

    /// "Losses: …", or that a side was routed when it fled rather than fell.
    var lossText: String {
        let a = report.attackerLosses.total, d = report.defenderLosses.total
        if a == 0 && d == 0 {
            return "\(name(report.winner.other)) broke and fled; nobody fell."
        }
        return "Losses: \(name(.attacker)) \(a), \(name(.defender)) \(d)"
    }
}

extension BattleSide {
    var other: BattleSide { self == .attacker ? .defender : .attacker }
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

/// A puff of dust kicked up around a block that was hit.
private struct DustPuff: View {
    @State private var out = false
    var body: some View {
        ZStack {
            ForEach(0..<5, id: \.self) { i in
                let angle = Double(i) / 5 * 2 * .pi + 0.4
                Circle()
                    .fill(Color(red: 0.75, green: 0.65, blue: 0.5))
                    .frame(width: 18, height: 18)
                    .offset(x: out ? cos(angle) * 30 : 0, y: out ? sin(angle) * 30 : 0)
                    .scaleEffect(out ? 1.6 : 0.4)
                    .opacity(out ? 0 : 0.8)
            }
        }
        .onAppear { withAnimation(.easeOut(duration: 0.7).delay(0.2)) { out = true } }
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
