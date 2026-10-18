import HegemonCore
import SwiftUI

/// The knowledge tree: seven fields, three levels each. Nobody picks what to learn; the tree
/// fills in where the realm has experience. Known levels are lit, the next one shows its
/// progress, later ones stay locked, and fields the realm has never touched show only a hint of
/// what would reveal them.
struct TechTreeView: View {
    let civ: CivilizationID
    let state: GameState
    let engine: Engine

    private var levels: [Int] { engine.rules.knowledge.levels }
    private var revealed: Set<KnowledgeField> { Set(engine.revealedFields(of: civ, in: state)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                practice
                VStack(spacing: 8) {
                    ForEach(KnowledgeField.allCases, id: \.self) { field in
                        if revealed.contains(field) { row(field) } else { hidden(field) }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Knowledge")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Where new knowledge is going this turn: the realm's recent experience, as shares.
    private var practice: some View {
        let experience = state.civs[civ]?.experience ?? [:]
        let total = max(1, experience.values.reduce(0, +))
        let fields = KnowledgeField.allCases.filter { (experience[$0] ?? 0) > 0 }
            .sorted { (experience[$0] ?? 0) > (experience[$1] ?? 0) }
        return VStack(alignment: .leading, spacing: 6) {
            Text("What your people are learning from").font(.subheadline.bold())
            if fields.isEmpty {
                Text("Nothing yet. Farm, mine, sail, fight and trade, and knowledge will follow.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(fields, id: \.self) { field in
                            Self.color(field)
                                .frame(width: max(2, geo.size.width * CGFloat(experience[field] ?? 0) / CGFloat(total) - 2))
                        }
                    }
                }
                .frame(height: 10)
                .clipShape(Capsule())
                HStack(spacing: 12) {
                    ForEach(fields.prefix(5), id: \.self) { field in
                        HStack(spacing: 4) {
                            Circle().fill(Self.color(field)).frame(width: 8, height: 8)
                            Text("\(field.rawValue.capitalized) \((experience[field] ?? 0) * 100 / total)%")
                        }
                    }
                }
                .font(.caption)
                Text("New knowledge flows into each field in proportion to recent practice. Neighbors and trade partners who know more pass some of it on.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ field: KnowledgeField) -> some View {
        let progress = state.civs[civ]?.knowledge[field] ?? 0
        let level = engine.level(field, of: civ, in: state)
        return HStack(spacing: 8) {
            fieldLabel(field, known: true)
            ForEach(1...levels.count, id: \.self) { n in
                connector(lit: n <= level)
                levelCard(field, n, level: level, progress: progress)
            }
        }
    }

    private func hidden(_ field: KnowledgeField) -> some View {
        HStack(spacing: 8) {
            fieldLabel(field, known: false)
            HStack(spacing: 6) {
                Image(systemName: "lock.fill").foregroundStyle(.secondary)
                Text("Undiscovered. Revealed by \(Self.hint(field)).")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 62)
            .background(RoundedRectangle(cornerRadius: 10).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(.secondary.opacity(0.5)))
        }
    }

    private func fieldLabel(_ field: KnowledgeField, known: Bool) -> some View {
        VStack(spacing: 4) {
            Self.icon(field)
                .frame(width: 26, height: 26)
                .foregroundStyle(known ? Self.color(field) : .secondary)
            Text(known ? field.rawValue.capitalized : "?")
                .font(.caption2.bold())
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(width: 84)
    }

    private func connector(lit: Bool) -> some View {
        Rectangle()
            .fill(lit ? Color.accentColor : Color.secondary.opacity(0.3))
            .frame(width: 10, height: 3)
    }

    @ViewBuilder
    private func levelCard(_ field: KnowledgeField, _ n: Int, level: Int, progress: Int) -> some View {
        let known = n <= level
        let next = n == level + 1
        let color = Self.color(field)
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                if known { Image(systemName: "checkmark.seal.fill").foregroundStyle(color) }
                if !known && !next { Image(systemName: "lock.fill").foregroundStyle(.secondary) }
                Text(known || next ? engine.levelName(field, n) ?? "" : "Level \(n)")
                    .font(.footnote.bold())
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            Text(known || next ? KnowledgeView.effect(field, n) : "Further along this road")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if next {
                let from = n == 1 ? 0 : levels[n - 2]
                ProgressView(value: Double(max(0, progress - from)), total: Double(levels[n - 1] - from))
                    .tint(color)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(known ? color.opacity(0.18) : Color(.secondarySystemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(next ? color : .clear, lineWidth: 1.5))
        .opacity(known || next ? 1 : 0.55)
    }

    // MARK: Look

    static func color(_ field: KnowledgeField) -> Color {
        switch field {
        case .agriculture: Color(red: 0.36, green: 0.62, blue: 0.22)
        case .metallurgy: Color(red: 0.72, green: 0.45, blue: 0.20)
        case .horsemanship: Color(red: 0.55, green: 0.38, blue: 0.26)
        case .seafaring: Color(red: 0.20, green: 0.46, blue: 0.80)
        case .construction: Color(red: 0.50, green: 0.50, blue: 0.56)
        case .warfare: Color(red: 0.78, green: 0.22, blue: 0.20)
        case .administration: Color(red: 0.55, green: 0.32, blue: 0.70)
        }
    }

    @ViewBuilder static func icon(_ field: KnowledgeField) -> some View {
        switch field {
        case .agriculture: Image(systemName: "leaf.fill").resizable().scaledToFit()
        case .metallurgy: Image(systemName: "hammer.fill").resizable().scaledToFit()
        case .horsemanship: UnitShape(type: .cavalry).fill()
        case .seafaring: Image(systemName: "sailboat.fill").resizable().scaledToFit()
        case .construction: Image(systemName: "building.columns.fill").resizable().scaledToFit()
        case .warfare: UnitShape(type: .infantry).fill()
        case .administration: Image(systemName: "scroll.fill").resizable().scaledToFit()
        }
    }

    static func hint(_ field: KnowledgeField) -> String {
        switch field {
        case .agriculture: "working the land"
        case .metallurgy: "casting bronze and mining ore"
        case .horsemanship: "raising horses and fighting on horseback"
        case .seafaring: "building ships and trading by sea"
        case .construction: "quarrying stone and building"
        case .warfare: "fighting battles"
        case .administration: "trade and running a large, rich realm"
        }
    }
}
