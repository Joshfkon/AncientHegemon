import HegemonCore
import SwiftUI

/// Choosing a battle plan: every formation as a card with a little deployment diagram of the
/// army actually going in, what the plan does, and (when attacking) the odds it gives. Picking one
/// is optional; the army's standing formation is preselected.
struct FormationPicker: View {
    let engine: Engine
    let units: UnitCounts
    @Binding var selection: FormationID
    /// Chance of victory with each formation, when known (attacks only).
    var odds: [FormationID: Double] = [:]

    var body: some View {
        let best = odds.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(engine.rules.battle.formations) { formation in
                    card(formation, best: odds.count > 1 && formation.id == best)
                        .onTapGesture {
                            selection = formation.id
                            Feedback.select()
                        }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func card(_ formation: Formation, best: Bool) -> some View {
        let chosen = formation.id == selection
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text(formation.name).font(.caption.bold()).lineLimit(1)
                Spacer(minLength: 0)
                if best {
                    Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow)
                        .accessibilityLabel("Best odds")
                }
            }
            FormationDiagram(formation: formation, units: units)
                .frame(height: 46)
            Text(Self.summary(formation.id))
                .font(.caption2).foregroundStyle(.secondary)
                .lineLimit(3, reservesSpace: true)
            if let p = odds[formation.id] {
                let percent = Int((p * 100).rounded())
                Text("\(percent)% to win")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(percent >= 65 ? .green : percent >= 40 ? .orange : .red)
            }
        }
        .padding(8)
        .frame(width: 128)
        .background(RoundedRectangle(cornerRadius: 10).fill(chosen ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(chosen ? Color.accentColor : .clear, lineWidth: 2))
        .contentShape(Rectangle())
    }

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
}

/// The front two ranks of a formation (front at the top), filled the way the battle will fill
/// them: each unit type claims its preferred squares in the formation's order. Arrows mark the
/// types that advance.
struct FormationDiagram: View {
    let formation: Formation
    let units: UnitCounts

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
            for slot in (formation.slots[type] ?? []).prefix(units[type]) where !taken.contains(slot) {
                taken.insert(slot)
                out.append(Placed(slot: slot, type: type))
            }
        }
        return out
    }
}

/// Small touches of feel: haptics on choices and battle hits.
enum Feedback {
    @MainActor static func select() { UISelectionFeedbackGenerator().selectionChanged() }
    @MainActor static func impact(_ weight: CGFloat) {
        UIImpactFeedbackGenerator(style: weight > 0.6 ? .heavy : .medium).impactOccurred(intensity: max(0.3, min(1, weight)))
    }
    @MainActor static func outcome(_ good: Bool) {
        UINotificationFeedbackGenerator().notificationOccurred(good ? .success : .error)
    }
}
