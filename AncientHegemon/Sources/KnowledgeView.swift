import HegemonCore
import SwiftUI

/// The tax slider: gold to invest against growth and goodwill.
struct TaxesView: View {
    let session: GameSession
    let econ: EconomyReport
    @State private var rate: Double = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Taxes").font(.subheadline.bold())
                Spacer()
                Text("\(Int(rate))%").font(.callout.bold().monospacedDigit())
            }
            Slider(value: $rate, in: 0...100, step: 10) { editing in
                if !editing, Int(rate) != econ.taxRate { session.order(.setTaxRate(Int(rate))) }
            }
            .disabled(!session.isHumanTurn)
            Text("+\(econ.taxes) gold from taxes · \(econ.growthPercent)% of spare grain grows the people · "
                 + "legitimacy \(econ.taxLegitimacy >= 0 ? "+" : "")\(econ.taxLegitimacy) a turn")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { rate = Double(econ.taxRate) }
        .onChange(of: econ.taxRate) { _, new in rate = Double(new) }
    }
}

/// What the realm has learned, field by field. Only fields it has some experience of appear.
struct KnowledgeView: View {
    let civ: CivilizationID
    let state: GameState
    let engine: Engine

    var body: some View {
        let fields = engine.revealedFields(of: civ, in: state)
        let levels = engine.rules.knowledge.levels
        VStack(alignment: .leading, spacing: 6) {
            Text("Knowledge").font(.subheadline.bold())
            if fields.isEmpty {
                Text("Nothing yet. Knowledge grows from what your people do: farming, mining, sailing, fighting, trading.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(fields, id: \.self) { field in
                let progress = state.civs[civ]?.knowledge[field] ?? 0
                let lv = engine.level(field, of: civ, in: state)
                let from = lv == 0 ? 0 : levels[lv - 1]
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(field.rawValue.capitalized).font(.footnote.bold())
                        Text(engine.levelName(field, lv) ?? "—").font(.footnote)
                        Spacer(minLength: 4)
                        if lv < levels.count {
                            Text("next: \(engine.levelName(field, lv + 1) ?? "")").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .lineLimit(1)
                    if lv < levels.count {
                        ProgressView(value: Double(progress - from), total: Double(levels[lv] - from))
                    }
                    if lv > 0 {
                        Text((1...lv).map { Self.effect(field, $0) }.joined(separator: " · "))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            if fields.count < KnowledgeField.allCases.count {
                Text("\(KnowledgeField.allCases.count - fields.count) more field\(KnowledgeField.allCases.count - fields.count == 1 ? "" : "s") "
                     + "unknown to your people.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    static func effect(_ field: KnowledgeField, _ level: Int) -> String {
        let table: [KnowledgeField: [String]] = [
            .agriculture: ["+1 grain in river valleys", "granary holds 2 turns", "+1 grain from farms"],
            .metallurgy: ["+50% bronze", "iron is usable", "iron counts double"],
            .horsemanship: ["cavalry +15%", "2 cavalry per horse", "cavalry +15% more"],
            .seafaring: ["+1 troop per ship", "+30% at sea", "+30% more at sea"],
            .construction: ["projects a turn faster", "walls +15%", "projects cost less"],
            .warfare: ["infantry +10%", "archers +15%", "+10 morale"],
            .administration: ["+10 loyalty", "+20% taxes", "+1 legitimacy a turn"],
        ]
        return table[field]?[level - 1] ?? ""
    }

    /// What a discovery does, in a sentence, for the banner and the chronicle.
    static func benefit(_ field: KnowledgeField, _ level: Int) -> String {
        let table: [KnowledgeField: [String]] = [
            .agriculture: ["River-valley land grows 1 more grain.", "Granaries hold two turns of harvest.", "Farms grow 1 more grain."],
            .metallurgy: ["Copper and tin make half again as much bronze.", "Your smiths can use iron ore to arm troops.", "Steel: iron arms twice as many troops."],
            .horsemanship: ["Chariots: your cavalry fight 15% harder.", "Each horse lets you raise 2 cavalry a turn.", "Horse archers: cavalry 15% harder again."],
            .seafaring: ["Each ship carries 1 more troop.", "Your ships fight 30% better.", "Your ships fight 30% better again."],
            .construction: ["Building projects finish a turn sooner.", "Walls protect defenders 15% more.", "Building projects cost less."],
            .warfare: ["Drill: your infantry fight 10% harder.", "Better bows: your archers fight 15% harder.", "Tactics: all your troops hold 10 morale longer."],
            .administration: ["Writing: generals are 10 points more loyal.", "Coinage: taxes bring in 20% more.", "Your ruler gains 1 legitimacy a turn."],
        ]
        return table[field]?[level - 1] ?? effect(field, level).capitalizedFirst
    }
}

/// How far the Bronze Age world has fallen apart.
struct CollapseGauge: View {
    let pressure: Int

    var body: some View {
        HStack(spacing: 6) {
            Text("The age").font(.caption.bold())
            ProgressView(value: Double(pressure), total: 100).tint(pressure >= 67 ? .red : pressure >= 34 ? .orange : .yellow)
                .frame(width: 70)
            Text(pressure == 0 ? "calm" : pressure < 34 ? "unsettled" : pressure < 67 ? "troubled" : pressure < 100 ? "collapsing" : "in ruins")
                .font(.caption)
        }
        .help("From round 12 to 40 raids from the sea, droughts, earthquakes and broken trade grow more common.")
    }
}

func projectName(_ kind: ProjectKind) -> String {
    switch kind {
    case .road: "Road"
    case .walls: "Walls"
    case .farm: "Farm"
    case .mine: "Mine"
    case .harbor: "Harbor"
    case .granary: "Granary"
    }
}

func projectPurpose(_ kind: ProjectKind) -> String {
    switch kind {
    case .road: "free supply; troops on roads march twice"
    case .walls: "+35% defence here"
    case .farm: "+1 grain (+2 in a river valley)"
    case .mine: "+1 of each ore here"
    case .harbor: "+2 gold with trade, cheaper ships"
    case .granary: "stores 6 more grain against bad years"
    }
}
