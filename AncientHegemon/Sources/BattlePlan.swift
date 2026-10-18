import HegemonCore
import SwiftUI

/// Choosing a battle plan: formation, line depth and stratagem. Each formation is a card with a
/// deployment diagram of the army going in, what it does and (when attacking) the odds it gives.
/// Locked formations and stratagems stay visible, greyed, with what would unlock them. Everything
/// is optional: the army's standing plan is preselected.
struct BattlePlanEditor: View {
    let engine: Engine
    let civ: CivilizationID
    let state: GameState
    let units: UnitCounts
    /// The general who would lead this fight, whose trait can unlock options.
    let general: General?
    @Binding var plan: BattlePlan
    /// Chance of victory with each formation under the current depth and stratagem (attacks only).
    var odds: [FormationID: Double] = [:]

    private var formation: FormationID { plan.formation ?? engine.rules.battle.defaultFormation }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(engine.rules.battle.formations) { f in
                        let open = engine.formationAvailable(f.id, civ, general: general, in: state)
                        formationCard(f, open: open)
                            .onTapGesture {
                                guard open else { return }
                                plan.formation = f.id
                                Feedback.select()
                            }
                    }
                }
                .padding(.vertical, 2)
            }
            HStack {
                Text("Line").font(.caption.bold())
                Picker("Line", selection: $plan.depth) {
                    Text("Deep").tag(LineDepth.deep)
                    Text("Wide").tag(LineDepth.wide)
                }
                .pickerStyle(.segmented)
            }
            Text(plan.depth == .deep ? "Two ranks: the rear steps into gaps as the front falls."
                                     : "Everyone in the front rank: hard to outflank, but no reserve.")
                .font(.caption2).foregroundStyle(.secondary)
            Text("Stratagem").font(.caption.bold())
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    stratagemCard(nil, open: true)
                    ForEach(Stratagem.allCases, id: \.self) { s in
                        let open = engine.stratagemAvailable(s, civ, general: general, in: state)
                            && (s != .feignedRetreat || units.cavalry > 0)
                        stratagemCard(s, open: open)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func formationCard(_ f: Formation, open: Bool) -> some View {
        let chosen = f.id == formation
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                if !open { Image(systemName: "lock.fill").font(.caption2) }
                Text(f.name).font(.caption.bold()).lineLimit(1)
                Spacer(minLength: 0)

            }
            FormationDiagram(formation: f, units: units, depth: plan.depth)
                .frame(height: 46)
            Text(open ? Self.summary(f.id) : Self.needs(engine.requirement(for: f.id), engine))
                .font(.caption2).foregroundStyle(.secondary)
                .lineLimit(3, reservesSpace: true)
            if open, let p = odds[f.id] {
                let outlook = Outlook(p)
                Text(outlook.word).font(.caption.bold()).foregroundStyle(outlook.color)
            }
        }
        .padding(8)
        .frame(width: 128)
        .background(RoundedRectangle(cornerRadius: 10).fill(chosen ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(chosen ? Color.accentColor : .clear, lineWidth: 2))
        .opacity(open ? 1 : 0.5)
        .contentShape(Rectangle())
    }

    private func stratagemCard(_ s: Stratagem?, open: Bool) -> some View {
        let chosen = s == plan.stratagem
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                if !open { Image(systemName: "lock.fill").font(.caption2) }
                Image(systemName: Self.symbol(s)).font(.caption)
                Text(Self.name(s)).font(.caption.bold()).lineLimit(1)
            }
            Text(open ? Self.summary(s) : s == .feignedRetreat && engine.stratagemAvailable(.feignedRetreat, civ, general: general, in: state)
                 ? "Needs cavalry to feign with." : Self.needs(s.flatMap { engine.requirement(for: $0) }, engine))
                .font(.caption2).foregroundStyle(.secondary)
                .lineLimit(3, reservesSpace: true)
        }
        .padding(8)
        .frame(width: 128, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(chosen ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(chosen ? Color.accentColor : .clear, lineWidth: 2))
        .opacity(open ? 1 : 0.5)
        .contentShape(Rectangle())
        .onTapGesture {
            guard open else { return }
            plan.stratagem = s
            Feedback.select()
        }
    }

    // MARK: Words

    static func summary(_ id: FormationID) -> String {
        switch id {
        case "phalanx": "Infantry line advances; archers shoot from behind; cavalry guards the flanks."
        case "hammer_and_anvil": "Infantry holds the center while the cavalry rides round the wings."
        case "skirmish_screen": "Archers in front thin the enemy; infantry waits; cavalry strikes."
        case "refused_flank": "Strength massed on one wing; the other hangs back with the archers."
        case "wedge": "A cavalry spearhead drives at the center, infantry close behind."
        default: ""
        }
    }

    static func name(_ s: Stratagem?) -> String {
        switch s {
        case nil: "Straight fight"
        case .standFast?: "Stand fast"
        case .feignedRetreat?: "Feigned retreat"
        case .shieldWall?: "Shield wall"
        case .flankingMarch?: "Flanking march"
        }
    }

    static func summary(_ s: Stratagem?) -> String {
        switch s {
        case nil: "No tricks: fight as the formation is drawn."
        case .standFast?: "Nobody advances unless struck. Steadier morale."
        case .feignedRetreat?: "Cavalry falls back; pursuers are caught in disorder."
        case .shieldWall?: "Infantry shrugs off arrows, but moves slowly."
        case .flankingMarch?: "The wings start a rank forward, on the enemy's flanks."
        }
    }

    static func symbol(_ s: Stratagem?) -> String {
        switch s {
        case nil: "arrow.up"
        case .standFast?: "hand.raised.fill"
        case .feignedRetreat?: "arrow.uturn.backward"
        case .shieldWall?: "shield.fill"
        case .flankingMarch?: "arrow.up.left.and.arrow.down.right"
        }
    }

    /// "Needs Chariots or a Cavalry Commander leading."
    static func needs(_ r: PlanRequirement?, _ engine: Engine) -> String {
        guard let r else { return "" }
        var options: [String] = []
        if let field = r.field { options.append(engine.levelName(field, r.level ?? 1) ?? field.rawValue.capitalized) }
        if let trait = r.trait { options.append("a \(traitName(trait)) leading") }
        return "Needs " + options.joined(separator: " or ") + "."
    }
}

/// The front two ranks of a formation (front at the top), filled the way the battle will fill
/// them: each unit type claims its preferred squares in the formation's order. Arrows mark the
/// types that advance.
struct FormationDiagram: View {
    let formation: Formation
    let units: UnitCounts
    var depth: LineDepth = .deep

    var body: some View {
        GeometryReader { geo in
            let cell = min(geo.size.width / 5, geo.size.height / 2)
            let left = (geo.size.width - cell * 5) / 2
            ZStack(alignment: .topLeading) {
                ForEach(0..<10, id: \.self) { i in
                    let col = i % 5, rank = i / 5
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(red: 0.78, green: 0.85, blue: 0.66).opacity(0.6))
                        .frame(width: cell - 2, height: cell - 2)
                        .offset(x: left + CGFloat(col) * cell + 1, y: CGFloat(rank) * cell + 1)
                }
                ForEach(placed, id: \.slot) { item in
                    ZStack(alignment: .topTrailing) {
                        UnitIcon(type: item.type)
                            .padding(cell * 0.12)
                        if formation.advance[item.type] == true {
                            Image(systemName: "arrowtriangle.up.fill")
                                .font(.system(size: cell * 0.28))
                                .foregroundStyle(.red)
                        }
                    }
                    .frame(width: cell, height: cell)
                    .offset(x: left + CGFloat(item.slot.col) * cell, y: CGFloat(item.slot.row) * cell)
                }
            }
        }
    }

    private struct Placed { let slot: GridPoint; let type: UnitType }

    /// One marker per square the army would occupy.
    private var placed: [Placed] {
        var taken: Set<GridPoint> = []
        var out: [Placed] = []
        for type in formation.order where units[type] > 0 {
            var preferred = formation.slots[type] ?? []
            if depth == .wide {
                preferred = preferred.map { GridPoint($0.col, 0) } + [2, 1, 3, 0, 4].map { GridPoint($0, 0) } + preferred
            }
            var placed = 0
            for slot in preferred where placed < units[type] && !taken.contains(slot) {
                taken.insert(slot)
                out.append(Placed(slot: slot, type: type))
                placed += 1
            }
        }
        return out
    }
}

/// How a fight looks to the officers, in words rather than numbers: war is chancy, and the
/// player shouldn't know their odds to the percent.
struct Outlook {
    let word: String
    let color: Color

    init(_ p: Double) {
        switch p {
        case 0.8...: (word, color) = ("Confident", .green)
        case 0.6..<0.8: (word, color) = ("Favourable", .green)
        case 0.4..<0.6: (word, color) = ("Uncertain", .orange)
        case 0.2..<0.4: (word, color) = ("Risky", .red)
        default: (word, color) = ("Desperate", .red)
        }
    }
}

/// Small touches of feel: haptics on choices and battle hits.
enum Feedback {
    @MainActor static func select() {
        UISelectionFeedbackGenerator().selectionChanged()
        SoundBoard.shared.play(.click, volume: 0.5)
    }
    @MainActor static func impact(_ weight: CGFloat) {
        UIImpactFeedbackGenerator(style: weight > 0.6 ? .heavy : .medium).impactOccurred(intensity: max(0.3, min(1, weight)))
    }
    @MainActor static func outcome(_ good: Bool) {
        UINotificationFeedbackGenerator().notificationOccurred(good ? .success : .error)
    }
}
