import HegemonCore
import SwiftUI

/// "How to play": a short illustrated walkthrough, page by page, of what to tap to do each thing.
/// Optional: offered on the title screen and in the game's menu.
struct WalkthroughView: View {
    let done: () -> Void
    @State private var page = 0

    struct Page {
        let title: String
        let picture: AnyView
        let steps: [String]
    }

    private let pages: [Page] = [
        Page(title: "Your goal", picture: AnyView(Picture.goal), steps: [
            "It is 1200 BC. You lead one of four empires as the Bronze Age falls apart.",
            "Hold 60% of the land, dominate trade, or have the most prestige when the age ends at round 50.",
            "You start with your capital alone. Everything else is held by tribes, or by your rivals.",
        ]),
        Page(title: "Armies and marching", picture: AnyView(Picture.march), steps: [
            "Your army is the token in your colour (★ means a general leads it). Tap it.",
            "The land it can reach glows. Tap one, choose how many go, and tap March.",
            "Each soldier moves once a turn, or twice along roads through your own land. Empty land is yours as soon as one soldier walks in.",
        ]),
        Page(title: "Battle", picture: AnyView(Picture.battle), steps: [
            "Tap land with enemies or a tribe in it to attack. Choose who goes, then tap To the battlefield.",
            "On the field you see both armies drawn up. Pick a formation and a stratagem, and whether to chase them if they break.",
            "Tap Charge! and watch. The bar shows who is winning.",
        ]),
        Page(title: "Raising troops", picture: AnyView(Picture.recruit), steps: [
            "Tap one of your territories and use Raise infantry, archers or cavalry.",
            "Each soldier costs gold and one of that land's people. Cavalry also need horses.",
            "After that each soldier eats 1 🌾 grain a turn, and every 4 soldiers cost 1 gold a turn in pay. Run out of gold and some go home.",
        ]),
        Page(title: "Grain and supply", picture: AnyView(Picture.grain), steps: [
            "Land grows 🌾 grain. People and soldiers eat it; run short and they starve or desert.",
            "Grain carted overland gets eaten on the way: armies 3+ land steps out eat extra. Roads and ships carry it free. Land cut off from the capital can't recruit.",
            "Tap the grain or gold at the top left to see where it comes from.",
        ]),
        Page(title: "Crossing the sea", picture: AnyView(Picture.sea), steps: [
            "Ships are built in a sea next to your coast: tap a coastal territory and use Build a ship. Each ship needs gold and a 🪵 timber, and carries 2 troops.",
            "Select your army on that coast: coasts your ships can reach glow blue with a ⛵.",
            "Tap one, choose who goes, and they board, sail and land in one order. Enemy ships at sea must be beaten first.",
        ]),
        Page(title: "Neighbours", picture: AnyView(Picture.diplomacy), steps: [
            "Tribes next to you can be won with gifts, or made to submit if your army at their border is big enough.",
            "Empires at peace that can reach each other trade automatically: copper, tin, horses, timber and more.",
            "Peace, war and offers are on the Rivals tab.",
        ]),
        Page(title: "Ending your turn", picture: AnyView(Picture.endTurn), steps: [
            "When you're done, tap End turn. Each rival moves in turn, and you see what they did on the map.",
            "From round 12 the world grows harsher: Sea Peoples, droughts and earthquakes. Wall your coasts.",
            "The menu (•••) has this walkthrough and a full reference any time.",
        ]),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { i in
                    pageView(pages[i]).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            HStack {
                Button("Skip", action: done).foregroundStyle(.secondary)
                Spacer()
                Button {
                    if page < pages.count - 1 { withAnimation { page += 1 } } else { done() }
                } label: {
                    Text(page < pages.count - 1 ? "Next" : "Start playing")
                        .font(.headline)
                        .padding(.horizontal, 22).padding(.vertical, 8)
                        .background(Bronze.gradient, in: Capsule())
                        .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 28).padding(.bottom, 12)
        }
        .background(Parchment())
        .onChange(of: page) { _, _ in Feedback.select() }
    }

    private func pageView(_ p: Page) -> some View {
        HStack(spacing: 28) {
            p.picture
                .frame(width: 230, height: 190)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(red: 0.24, green: 0.45, blue: 0.75)))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Bronze.gradient, lineWidth: 3))
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
            VStack(alignment: .leading, spacing: 12) {
                Text(p.title).font(.system(.title, design: .serif).weight(.bold))
                ForEach(p.steps.indices, id: \.self) { i in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(i + 1)")
                            .font(.callout.bold())
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Bronze.gradient))
                        Text(p.steps[i]).font(.callout).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: 440, alignment: .leading)
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Little scenes drawn from the map's own pieces.
private enum Picture {
    static let land = Color(red: 0.55, green: 0.72, blue: 0.42)
    static let desert = Color(red: 0.9, green: 0.72, blue: 0.4)
    static let mine = Color(red: 0.56, green: 0.26, blue: 0.70)
    static let enemy = Color(red: 0.80, green: 0.20, blue: 0.20)

    static func token(_ text: String, _ color: Color, size: CGFloat = 40) -> some View {
        Text(text)
            .font(.system(size: size * 0.42, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(color))
            .overlay(Circle().stroke(.black.opacity(0.6), lineWidth: 1))
    }

    static func patch(_ color: Color, _ w: CGFloat, _ h: CGFloat, glow: Bool = false) -> some View {
        RoundedRectangle(cornerRadius: 10).fill(color)
            .frame(width: w, height: h)
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(glow ? .white : .black.opacity(0.5), style: StrokeStyle(lineWidth: glow ? 3 : 1, dash: glow ? [6, 4] : [])))
    }

    static func arrow(_ color: Color = .white) -> some View {
        Image(systemName: "arrow.right").font(.title.bold()).foregroundStyle(color).shadow(radius: 2)
    }

    static var goal: some View {
        VStack(spacing: 10) {
            Image(systemName: "crown.fill").font(.system(size: 54)).foregroundStyle(Bronze.gradient)
            HStack(spacing: 8) {
                ForEach([Color(red: 0.2, green: 0.42, blue: 0.85), mine, enemy, Color(red: 0.18, green: 0.62, blue: 0.35)], id: \.self) {
                    Circle().fill($0).frame(width: 22, height: 22).overlay(Circle().stroke(.white, lineWidth: 1.5))
                }
            }
            Text("Round 1 → 50").font(.caption.bold()).foregroundStyle(.white)
        }
    }

    static var march: some View {
        HStack(spacing: 6) {
            patch(land, 80, 120).overlay(token("5★", mine))
            arrow()
            patch(land, 80, 120, glow: true).overlay(Image(systemName: "hand.tap.fill").font(.title).foregroundStyle(.white))
        }
    }

    static var battle: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(0..<3) { _ in RoundedRectangle(cornerRadius: 5).fill(enemy).frame(width: 34, height: 34)
                    .overlay(UnitIcon(type: .infantry, color: .white).padding(7)) }
            }
            Image(systemName: "flag.2.crossed.fill").font(.title2).foregroundStyle(.white)
            HStack(spacing: 6) {
                ForEach([UnitType.cavalry, .infantry, .archers], id: \.self) { t in
                    RoundedRectangle(cornerRadius: 5).fill(mine).frame(width: 34, height: 34)
                        .overlay(UnitIcon(type: t, color: .white).padding(7))
                }
            }
            Capsule().fill(LinearGradient(colors: [mine, mine, enemy], startPoint: .leading, endPoint: .trailing))
                .frame(width: 150, height: 10)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(land))
    }

    static var recruit: some View {
        VStack(spacing: 10) {
            token("3", mine, size: 54).overlay(alignment: .topTrailing) {
                Text("+1").font(.caption.bold()).foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(.green)).offset(x: 14, y: -8)
            }
            HStack(spacing: 6) {
                UnitIcon(type: .infantry, color: .white).frame(width: 22)
                Text("2 gold · 1 👥").font(.caption.bold()).foregroundStyle(.white)
            }
        }
    }

    static var grain: some View {
        HStack(spacing: 14) {
            VStack { Text("🌾").font(.system(size: 44)); Text("grows").font(.caption.bold()).foregroundStyle(.white) }
            arrow()
            VStack { Text("👥").font(.system(size: 44)); Text("eat").font(.caption.bold()).foregroundStyle(.white) }
        }
    }

    static var sea: some View {
        HStack(spacing: 4) {
            patch(land, 54, 110).overlay(token("4", mine, size: 34))
            VStack(spacing: 2) {
                Image(systemName: "sailboat.fill").font(.system(size: 36)).foregroundStyle(.white)
                Text("+2").font(.caption.bold()).foregroundStyle(.white)
            }
            .frame(width: 70)
            patch(desert, 54, 70, glow: true).overlay(token("2", enemy, size: 30))
        }
    }

    static var diplomacy: some View {
        HStack(spacing: 18) {
            VStack { Image(systemName: "gift.fill").font(.system(size: 38)); Text("tribes").font(.caption.bold()) }
            VStack { Image(systemName: "arrow.left.arrow.right").font(.system(size: 38)); Text("trade").font(.caption.bold()) }
        }
        .foregroundStyle(.white)
    }

    static var endTurn: some View {
        Label("End turn", systemImage: "hourglass")
            .font(.title3.bold())
            .padding(.horizontal, 18).padding(.vertical, 12)
            .background(Capsule().fill(Color.accentColor))
            .foregroundStyle(.white)
    }
}
