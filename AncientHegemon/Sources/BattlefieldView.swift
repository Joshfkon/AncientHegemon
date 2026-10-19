import HegemonCore
import SwiftUI

/// An attack the player has ordered, drawn up on the field before the first blow.
struct Muster: Identifiable, Equatable {
    let from: TerritoryID
    let to: TerritoryID
    let units: UnitCounts
    let general: Bool
    var id: String { from + ">" + to }
}

/// The battlefield before the battle: both armies drawn up as they would stand, the scouts'
/// word, and the plan (formation, line, stratagem, whether to chase), changed with the deployment
/// moving to match. Charge, and the battle plays out on the same field.
struct BattlefieldView: View {
    let session: GameSession
    let muster: Muster

    @State private var plan = BattlePlan()
    @State private var odds: [FormationID: Double] = [:]
    /// The battle once fought, played on the same field.
    @State private var fought: BattleEntry?
    @State private var charging = false

    private var engine: Engine { session.engine }
    private var state: GameState { session.state }
    private var human: CivilizationID { session.human! }
    private var general: General? {
        guard muster.general, let g = state.general(of: human, at: muster.from),
              !state.generalsMoved.contains(g.id) else { return nil }
        return g
    }
    private var setup: BattleSetup? {
        engine.attackSetup(human, units: muster.units, into: muster.to, from: muster.from, plan: plan,
                           general: general, in: state)
    }
    private var place: String { engine.map.territory(muster.to)?.name ?? muster.to }

    var body: some View {
        NavigationStack {
            Group {
                if let fought {
                    BattleReplayView(entry: fought, state: state, map: engine.map, autoplay: true,
                                     perspective: human, horn: false) {
                        session.replay = nil
                        session.muster = nil
                    }
                } else if let setup {
                    field(setup)
                } else {
                    // The defenders are gone (or the order no longer stands).
                    ContentUnavailableView("Nobody holds \(place)", systemImage: "flag")
                        .toolbar { Button("Back") { session.muster = nil } }
                }
            }
        }
        .onAppear {
            session.message = nil
            if let army = state.armies[muster.from] {
                plan = army.plan
                if plan.stratagem == .standFast { plan.stratagem = nil }
            }
            SoundBoard.shared.loop(.wardrums, volume: 0.55)
            updateOdds()
        }
        .onDisappear { SoundBoard.shared.stop(.wardrums) }
        .onChange(of: plan) { _, _ in updateOdds() }
    }

    private func field(_ setup: BattleSetup) -> some View {
        let frame = BattleSimulator(rules: engine.rules).deployment(setup)
        let impassable = engine.rules.battle.terrain[setup.terrain]?.impassable ?? []
        return HStack(spacing: 14) {
            BattleBoard(setup: setup, impassable: impassable, frame: frame, previous: [], tick: 0, state: state)
                .overlay(alignment: .bottom) {
                    Text(charging ? "Charge!" : "Your army below · theirs above")
                        .font(charging ? .title2.weight(.black) : .caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(.black.opacity(0.6)))
                        .padding(10)
                }
                .scaleEffect(charging ? 1.04 : 1)
                .animation(.spring(duration: 0.45, bounce: 0.3), value: frame.blocks.map(\.position))
                .padding(8)
            VStack(spacing: 8) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Battle of \(place)").font(.title3.weight(.bold)).fontDesign(.serif)
                            Spacer()
                            SoundToggle()
                        }
                        HStack(alignment: .top) {
                            ArmySide(army: setup.defender, label: "Defending", state: state,
                                     rank: state.armies[muster.to].map { engine.rank(of: $0) })
                            Spacer()
                            ArmySide(army: setup.attacker, label: "Attacking", state: state,
                                     rank: state.armies[muster.from].map { engine.rank(of: $0) })
                        }
                        scouts
                        Divider()
                        Text("Battle plan").font(.headline)
                        BattlePlanEditor(engine: engine, civ: human, state: state, units: muster.units,
                                         general: general, plan: $plan, odds: odds)
                        if let message = session.message {
                            Label(message, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption).foregroundStyle(.red)
                        }
                    }
                    .padding(.top, 10)
                }
                HStack {
                    Button("Withdraw") {
                        Feedback.select()
                        session.muster = nil
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    Button(action: charge) {
                        Label("Charge!", systemImage: "flag.2.crossed.fill").font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(charging || !session.isHumanTurn)
                }
                .padding(.bottom, 8)
            }
            .frame(width: 340)
        }
        .padding(.horizontal)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Parchment())
        .toolbar(.hidden, for: .navigationBar)
    }

    private var scouts: some View {
        let p = odds[plan.formation ?? engine.rules.battle.defaultFormation] ?? 0
        let outlook = Outlook(p)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Scouts' report").font(.subheadline.bold())
                Spacer()
                Text(outlook.word).font(.title3.bold()).foregroundStyle(outlook.color)
                    .contentTransition(.numericText())
                    .animation(.default, value: outlook.word)
            }
            ForEach(Scouts.report(engine: engine, state: state, civ: human, units: muster.units, plan: plan,
                                  general: general, to: muster.to, from: muster.from), id: \.self) { line in
                Text("• " + line).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func updateOdds() {
        var result: [FormationID: Double] = [:]
        for f in engine.rules.battle.formations where engine.formationAvailable(f.id, human, general: general, in: state) {
            result[f.id] = engine.attackOdds(human, units: muster.units, into: muster.to, from: muster.from,
                                             formation: f.id, depth: plan.depth, stratagem: plan.stratagem,
                                             general: general, in: state) ?? 0
        }
        odds = result
    }

    /// The battle cry, then the battle, played out on this field.
    private func charge() {
        charging = true
        SoundBoard.shared.stop(.wardrums, fade: 0.3)
        SoundBoard.shared.play(.roar, volume: 0.9)
        Feedback.impact(1)
        Task {
            try? await Task.sleep(for: .milliseconds(650))
            if state.armies[muster.from]?.plan != plan {
                session.order(.setBattlePlan(territory: muster.from, plan: plan))
            }
            let moved = session.order(.move(from: muster.from, to: muster.to, units: muster.units, general: muster.general))
            charging = false
            if moved, let entry = session.replay {
                withAnimation(.easeInOut(duration: 0.3)) { fought = entry }
            } else if moved {
                session.muster = nil
            }
        }
    }
}

/// The scouts' report: how the numbers compare, what favours the defender. Deliberately no
/// percentages.
enum Scouts {
    static func report(engine: Engine, state: GameState, civ: CivilizationID, units: UnitCounts, plan: BattlePlan,
                       general leader: General?, to: TerritoryID, from: TerritoryID?) -> [String] {
        guard let d = engine.defenders(of: to, against: civ, state) else { return [] }
        let defender = d.army
        var lines: [String] = []
        // Militia count for half: they're many but they're farmers.
        let ours = Double(max(1, units.total)), theirs = Double(max(1, defender.units.total)) + Double(d.levy) / 2
        let ratio = ours / theirs
        let numbers = switch ratio {
        case ..<0.5: "They greatly outnumber us."
        case 0.5..<0.8: "They outnumber us."
        case 0.8...1.25: "Their numbers are roughly the same as ours."
        case 1.25..<2: "We outnumber them."
        default: "We greatly outnumber them."
        }
        lines.append(numbers)
        if ratio < 1.6 { lines.append("Defenders hold the edge in an even fight.") }
        // How the two armies compare as they would actually fight.
        let ourArmy = engine.battleArmy(civ, units, plan: plan, general: leader, state)
        if let theirArmy = engine.defendingArmy(of: to, against: civ, state) {
            if theirArmy.bronzePercent >= ourArmy.bronzePercent + 30 { lines.append("Their troops are better armed with bronze.") }
            if ourArmy.bronzePercent >= theirArmy.bronzePercent + 30 { lines.append("Our bronze gives us the edge.") }
            let ourDrill = ourArmy.unitPercent.values.reduce(0, +) + ourArmy.morale
            let theirDrill = theirArmy.unitPercent.values.reduce(0, +) + theirArmy.morale
            if theirDrill > ourDrill + 10 { lines.append("Their soldiers are better trained.") }
            if ourDrill > theirDrill + 10 { lines.append("Our soldiers are better trained.") }
            if theirArmy.units.archers > 0, units.cavalry == 0 { lines.append("Their archers will thin our ranks, and we have no cavalry.") }
            if theirArmy.general != nil, leader == nil { lines.append("A general leads them; none leads us.") }
            if leader != nil, theirArmy.general == nil { lines.append("Our general leads; they have none.") }
        }
        let ourRank = from.flatMap { state.armies[$0] }.map { engine.rank(of: $0) } ?? .green
        let theirRank = engine.rank(of: defender)
        if theirRank > ourRank { lines.append("Their troops are \(theirRank.name.lowercased()) soldiers, hardened by battle.") }
        if ourRank > theirRank { lines.append("Our \(ourRank.name.lowercased()) soldiers have seen more fighting.") }
        if d.levy > 0 {
            lines.append(defender.units.total == 0 ? "No soldiers, but the people will take up arms." : "The people will take up arms beside them.")
        }
        if engine.fortification(at: to, state) > 0 { lines.append("They are behind walls.") }
        let terrain = engine.map.territory(to)!.terrain
        if (engine.rules.battle.terrain[terrain]?.defensePercent ?? 0) > 0 {
            lines.append(terrain == .forest || terrain == .desert ? "The \(terrain.rawValue) favours the defender."
                                                                  : "The \(terrain.rawValue) favour the defender.")
        }
        if let from {
            if let crossing = engine.map.crossing(between: from, and: to) { lines.append("We must cross a \(crossing.rawValue).") }
        } else {
            lines.append("We must fight our way ashore.")
        }
        return lines
    }
}
