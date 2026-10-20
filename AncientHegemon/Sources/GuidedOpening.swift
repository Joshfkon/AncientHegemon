import HegemonCore
import SwiftUI

/// A guided start (Josh's brother: "the game started too abruptly"). For the first rounds the
/// world leaves the player alone (the engine's quiet opening) while the council walks them
/// through the basics, one small task at a time: meet your capital, raise soldiers, march out,
/// end the turn, read the harvest, meet a neighbouring ruler, build, choose a patron, and a
/// farewell as the rivals stir. Each task ticks off when done; the readings wait for Continue.
/// Progress is remembered per game; "Skip the tour" ends it.
struct GuideStep: Identifiable {
    enum Kind { case read, task }
    let id: String
    let role: Advisor.Role
    let kind: Kind
    let line: String
    /// What to do, for a task.
    let objective: String
    let go: AdvisorCall.Go?
}

/// What the player has done that the guide watches for.
struct GuideMemory: Codable {
    var game: String
    var step = 0
    var done: Set<String> = []
    var startRound = 1
    var finished = false

    static let key = "guideMemory"

    static func load(game: String) -> GuideMemory? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let m = try? JSONDecoder().decode(GuideMemory.self, from: data), m.game == game else { return nil }
        return m
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}

enum Guide {
    /// The tour's steps for the player's realm as it stands.
    @MainActor static func steps(_ session: GameSession) -> [GuideStep] {
        guard let civ = session.human else { return [] }
        let engine = session.engine, state = session.state, map = engine.map
        let seat = engine.seat(of: civ, in: state) ?? map.civilization(civ)?.capital ?? ""
        let capital = map.territory(seat)?.name ?? seat
        let ruler = state.civs[civ]?.ruler.name ?? "my lord"
        let quiet = state.quietUntil ?? 5
        let e = session.economy
        // The nearest kingdom: on our border if there is one.
        let neighbour = map.landNeighbors(of: seat).sorted().first { engine.kingdom(at: $0, in: state) != nil }
            ?? state.territories(of: civ).flatMap { map.landNeighbors(of: $0) }.sorted().first { engine.kingdom(at: $0, in: state) != nil }
        let neighbourName = neighbour.flatMap { engine.people(at: $0, in: state)?.name } ?? "our neighbours"
        let ruled = neighbour.flatMap { engine.people(at: $0, in: state)?.ruler } ?? "their ruler"
        return [
            GuideStep(id: "welcome", role: .steward, kind: .read,
                      line: "Welcome, \(ruler). It is 1200 BC, and the old world is cracking. Our realm is a single land, \(capital). Around it live kingdoms and tribes, and beyond them three rival empires. For a few seasons, until round \(quiet), the world will leave us be. Let us use them well.",
                      objective: "", go: .territory(seat)),
            GuideStep(id: "capital", role: .steward, kind: .task,
                      line: "This is \(capital), our capital. Everything we have grows from here. Tap it on the map to see what it holds and what we can do there.",
                      objective: "Tap \(capital) on the map", go: .territory(seat)),
            GuideStep(id: "recruit", role: .general, kind: .task,
                      line: "We need soldiers before we need anything else. In \(capital)'s orders, raise infantry. Each costs gold now, and grain and pay every turn after, so don't raise more than the land can feed.",
                      objective: "Raise soldiers in \(capital)", go: .territory(seat)),
            GuideStep(id: "march", role: .general, kind: .task,
                      line: "Now take land. Tap our army, then a glowing land beside it. Empty land is ours for a single soldier. A tribe or a kingdom will fight, so send enough men, and look at the odds before you strike.",
                      objective: "March an army into a neighbouring land", go: .territory(seat)),
            GuideStep(id: "endTurn", role: .steward, kind: .task,
                      line: "When the orders are given, end the turn. The rival empires move, and then our harvest is counted.",
                      objective: "End the turn", go: nil),
            GuideStep(id: "harvest", role: .steward, kind: .read,
                      line: "The harvest is in." + (e.map { " We grow \($0.grainProduced) grain and eat \($0.grainProduced - $0.grainBalance); what's left grows our people. Taxes bring \($0.taxes) gold, and the army's pay is \($0.pay)." } ?? "")
                        + " Grain and gold are the two numbers to watch, at the top left. The Realm explains where each comes from and lets you set taxes.",
                      objective: "", go: .realm),
            GuideStep(id: "neighbours", role: .envoy, kind: .task,
                      line: "Every land no empire holds belongs to a kingdom with its own ruler and a long memory. \(neighbourName.capitalizedFirst) are ruled by \(ruled). Tap their land and meet them. Gifts win friends, even when refused. With twice their warriors at the border, they may swear to us as vassals instead of fighting.",
                      objective: "Meet a neighbouring ruler", go: neighbour.map { .territory($0) }),
            GuideStep(id: "build", role: .steward, kind: .task,
                      line: "Gold in a vault builds nothing. Enter \(capital) and start a work: a farm to feed more mouths, walls against siege, a road to speed the army and the grain carts. Stone and timber come from our land and from trade.",
                      objective: "Start building in a town", go: .city(seat)),
            GuideStep(id: "knowledge", role: .priest, kind: .task,
                      line: "Our people learn by doing: farming teaches farming, war teaches war. But the court may pay the masters of one craft, and that knowledge grows far faster. Open the books and choose a patron.",
                      objective: "Choose what the court's scholars study", go: .knowledge),
            GuideStep(id: "farewell", role: .general, kind: .read,
                      line: "That is the heart of it. After round \(quiet) the rival empires will march where they see weakness, so keep garrisons on the borders, and make peace where it pays. The rest you'll learn as we go: we'll speak up whenever something needs you.",
                      objective: "", go: nil),
        ]
    }

    /// Whether a task is done.
    @MainActor static func isDone(_ step: GuideStep, _ memory: GuideMemory, _ session: GameSession) -> Bool {
        switch step.id {
        case "endTurn": session.state.turn > memory.startRound
        default: memory.done.contains(step.id)
        }
    }

    /// Notes what the player just did, for the guide's tasks.
    @MainActor static func note(_ events: [GameEvent], _ session: GameSession) {
        guard let human = session.human, var memory = session.guide, !memory.finished else { return }
        for event in events {
            switch event {
            case let .recruited(c, _, _, _) where c == human: memory.done.insert("recruit")
            case let .moved(c, _, _, _) where c == human: memory.done.insert("march")
            case let .projectStarted(c, _, _) where c == human: memory.done.insert("build")
            case let .projectQueued(c, _, _) where c == human: memory.done.insert("build")
            case let .patronageSet(c, f) where c == human && f != nil: memory.done.insert("knowledge")
            case let .tribeJoined(c, _, _, _) where c == human: memory.done.insert("neighbours")
            case let .tribeRefused(c, _, _) where c == human: memory.done.insert("neighbours")
            case let .vassalSworn(c, _) where c == human: memory.done.insert("neighbours")
            default: break
            }
        }
        if memory.done != session.guide?.done { session.guide = memory; memory.save() }
    }

    @MainActor static func mark(_ id: String, _ session: GameSession) {
        guard var memory = session.guide, !memory.finished, !memory.done.contains(id) else { return }
        memory.done.insert(id)
        session.guide = memory
        memory.save()
    }

    /// On to the next step, or the end of the tour.
    @MainActor static func advance(_ session: GameSession, finish: Bool = false) {
        guard var memory = session.guide else { return }
        memory.step += 1
        if finish || memory.step >= steps(session).count { memory.finished = true }
        session.guide = memory
        memory.save()
    }
}

/// The council's guide on screen: who speaks, what to do, and how far along the tour is.
struct GuideCard: View {
    let step: GuideStep
    let index: Int
    let count: Int
    let done: Bool
    let civ: CivilizationID
    let state: GameState
    let go: () -> Void
    let next: () -> Void
    let skip: () -> Void

    var body: some View {
        let names = Advisor.names(civ)
        HStack(alignment: .top, spacing: 12) {
            AdvisorBust(role: step.role, civ: civ, color: Palette.color(civ, state), mood: .calm)
                .frame(width: 50, height: 62)
                .background(RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.35)))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Bronze.gradient, lineWidth: 1))
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    CardTitle(text: names[step.role] ?? "")
                    Text("\(index + 1) of \(count)").font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.6))
                    Spacer(minLength: 0)
                    Button("Skip the tour", action: skip).font(.caption).foregroundStyle(.white.opacity(0.55))
                }
                Text("“\(step.line)”")
                    .font(.system(.caption, design: .serif))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    if step.kind == .task {
                        Label(step.objective, systemImage: done ? "checkmark.circle.fill" : "circle")
                            .font(.footnote.bold())
                            .foregroundStyle(done ? Color.green : Color(red: 0.95, green: 0.8, blue: 0.5))
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 0)
                    if step.go != nil, !done {
                        Button("Show me", action: go)
                            .font(.footnote.bold()).foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .overlay(Capsule().stroke(.white.opacity(0.4)))
                    }
                    if step.kind == .read || done {
                        Button(index + 1 == count ? "Begin" : "Continue", action: next).buttonStyle(BronzeButtonStyle())
                    }
                }
            }
        }
        .padding(10)
        .frame(width: 520)
        .woodPanel(RoundedRectangle(cornerRadius: 14), border: 2)
        .shadow(radius: 8)
    }
}
