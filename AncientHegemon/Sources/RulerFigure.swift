import HegemonCore
import SwiftUI

/// A ruler in person, Civilization-style: seated, breathing, blinking, speaking, with a face
/// that shows how their court regards you. Drawn, not pictured, in each realm's own dress:
/// Egypt's pharaoh in the striped nemes with the false beard, Mesopotamia's king with his tall
/// cap and long curled beard, the Greek in a bronze helmet pushed back, the Italian in a laurel,
/// the Hittite Great King (an expansion empire) clean-shaven in his tall cap, with the lituus.
struct RulerFigure: View {
    enum Mood { case pleased, neutral, stern, angry, wary }

    let civ: CivilizationID
    let state: GameState
    var mood: Mood = .neutral
    /// Changes whenever they begin to speak (the mouth moves for a couple of seconds).
    var speaking: Int = 0
    /// How they dress, when not as their empire does: the minor kingdoms' rulers ("hatti",
    /// "libyan", "north", "chief", or an empire's style).
    var look: String? = nil

    private var style: String { look ?? civ }

    @State private var spokeAt = Date.distantPast

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate
                let talk = max(0, 1 - tl.date.timeIntervalSince(spokeAt) / 2.6)
                draw(&ctx, size, t: t, talk: talk)
            }
        }
        .aspectRatio(200 / 320, contentMode: .fit)
        .onAppear { spokeAt = .now }
        .onChange(of: speaking) { _, _ in spokeAt = .now }
        .accessibilityLabel("\(state.civs[civ]?.ruler.name ?? "The ruler") of \(Palette.name(civ, state))")
    }

    // MARK: Look

    private var robe: Color { Palette.color(civ, state) }
    private var skin: Color {
        switch style {
        case "egypt": Color(red: 0.62, green: 0.42, blue: 0.27)
        case "mesopotamia": Color(red: 0.66, green: 0.47, blue: 0.32)
        case "hatti": Color(red: 0.74, green: 0.53, blue: 0.37)
        case "libyan": Color(red: 0.52, green: 0.34, blue: 0.21)
        case "north": Color(red: 0.92, green: 0.76, blue: 0.64)
        default: Color(red: 0.86, green: 0.67, blue: 0.5)
        }
    }
    private var hair: Color {
        switch style {
        case "greece": Color(red: 0.32, green: 0.22, blue: 0.14)
        case "italia": Color(red: 0.25, green: 0.17, blue: 0.11)
        case "north": Color(red: 0.55, green: 0.3, blue: 0.13)
        case "chief": Color(red: 0.2, green: 0.14, blue: 0.1)
        default: Color(red: 0.1, green: 0.08, blue: 0.07)
        }
    }
    private let gold = Color(red: 0.92, green: 0.74, blue: 0.3)
    private let ink = Color.black.opacity(0.75)

    // MARK: Drawing (in a 200 × 320 frame; feet on the bottom edge)

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize, t: Double, talk: Double) {
        ctx.scaleBy(x: size.width / 200, y: size.height / 320)
        drawThrone(&ctx)
        let breathe = sin(t * 1.7)
        let lean: Double = switch mood { case .angry: 4; case .stern: 1.5; case .wary: -2; default: 0 }
        let tilt = sin(t * 0.6) * 2 + (mood == .angry ? sin(t * 2.4) * 1.2 : 0)

        // Body and robe, rising and falling with each breath.
        var body = ctx
        body.translateBy(x: 0, y: CGFloat(-breathe * 1.2))
        drawBody(&body, t: t, talk: talk)

        // Head, nodding and leaning with the mood.
        var head = ctx
        head.translateBy(x: 100, y: 112 - CGFloat(breathe * 1.6) + CGFloat(lean))
        head.rotate(by: .degrees(tilt))
        head.translateBy(x: -100, y: -112)
        drawHead(&head, t: t, talk: talk)
    }

    /// The throne behind and beneath them: a tall back, arms, and legs on the floor.
    private func drawThrone(_ ctx: inout GraphicsContext) {
        let wood = Color(red: 0.45, green: 0.28, blue: 0.13)
        let back = Path(roundedRect: CGRect(x: 44, y: 54, width: 112, height: 200), cornerRadius: 14)
        ctx.fill(back, with: .linearGradient(Gradient(colors: [gold, Color(red: 0.62, green: 0.45, blue: 0.16)]),
                                             startPoint: CGPoint(x: 44, y: 54), endPoint: CGPoint(x: 156, y: 254)))
        ctx.stroke(back, with: .color(ink), lineWidth: 1.5)
        let panel = Path(roundedRect: CGRect(x: 54, y: 64, width: 92, height: 180), cornerRadius: 10)
        ctx.fill(panel, with: .color(robe.opacity(0.55)))
        ctx.fill(panel, with: .color(.black.opacity(0.25)))
        if style == "hatti" {
            // The winged sun of the Great King, above his head.
            ctx.fill(Path(ellipseIn: CGRect(x: 92, y: 66, width: 16, height: 16)), with: .color(gold))
            for side in [-1.0, 1] {
                var wing = Path()
                wing.move(to: CGPoint(x: 100 + side * 9, y: 72))
                wing.addQuadCurve(to: CGPoint(x: 100 + side * 42, y: 66), control: CGPoint(x: 100 + side * 26, y: 60))
                wing.addQuadCurve(to: CGPoint(x: 100 + side * 9, y: 78), control: CGPoint(x: 100 + side * 28, y: 80))
                ctx.fill(wing, with: .color(gold.opacity(0.9)))
                ctx.stroke(wing, with: .color(ink.opacity(0.6)), lineWidth: 0.8)
            }
        }
        // Arms and legs.
        for x in [26.0, 152] {
            let arm = Path(roundedRect: CGRect(x: x, y: 226, width: 22, height: 12), cornerRadius: 5)
            ctx.fill(arm, with: .color(gold))
            ctx.stroke(arm, with: .color(ink), lineWidth: 1)
            let leg = Path(roundedRect: CGRect(x: x + 4, y: 236, width: 12, height: 82), cornerRadius: 3)
            ctx.fill(leg, with: .color(wood))
            ctx.stroke(leg, with: .color(ink), lineWidth: 1)
            ctx.fill(Path(ellipseIn: CGRect(x: x + 1, y: 308, width: 18, height: 10)), with: .color(gold))
        }
    }

    private func drawBody(_ ctx: inout GraphicsContext, t: Double, talk: Double) {
        // Shoulders, the robe over the lap, and the hem down to the feet.
        var robePath = Path()
        robePath.move(to: CGPoint(x: 52, y: 168))
        robePath.addQuadCurve(to: CGPoint(x: 148, y: 168), control: CGPoint(x: 100, y: 156))
        robePath.addQuadCurve(to: CGPoint(x: 160, y: 236), control: CGPoint(x: 166, y: 190))
        robePath.addLine(to: CGPoint(x: 150, y: 250))
        robePath.addLine(to: CGPoint(x: 142, y: 306))
        robePath.addLine(to: CGPoint(x: 58, y: 306))
        robePath.addLine(to: CGPoint(x: 50, y: 250))
        robePath.addLine(to: CGPoint(x: 40, y: 236))
        robePath.addQuadCurve(to: CGPoint(x: 52, y: 168), control: CGPoint(x: 34, y: 190))
        robePath.closeSubpath()
        ctx.fill(robePath, with: .linearGradient(Gradient(colors: [robe, robe.opacity(0.78)]),
                                                 startPoint: CGPoint(x: 100, y: 160), endPoint: CGPoint(x: 100, y: 306)))
        ctx.stroke(robePath, with: .color(ink), lineWidth: 1.5)
        // The lap's edge, a belt, and folds falling to the hem.
        var lap = Path()
        lap.move(to: CGPoint(x: 44, y: 240))
        lap.addQuadCurve(to: CGPoint(x: 156, y: 240), control: CGPoint(x: 100, y: 250))
        ctx.stroke(lap, with: .color(.black.opacity(0.25)), lineWidth: 2)
        ctx.fill(Path(roundedRect: CGRect(x: 58, y: 212, width: 84, height: 7), cornerRadius: 3), with: .color(gold))
        for x in [76.0, 100, 124] {
            var fold = Path()
            fold.move(to: CGPoint(x: x, y: 252))
            fold.addLine(to: CGPoint(x: x + (x - 100) * 0.15, y: 304))
            ctx.stroke(fold, with: .color(.black.opacity(0.18)), lineWidth: 2)
        }
        // Feet below the hem.
        for x in [72.0, 108] {
            let foot = Path(ellipseIn: CGRect(x: x, y: 302, width: 22, height: 12))
            ctx.fill(foot, with: .color(Color(red: 0.4, green: 0.25, blue: 0.12)))
            ctx.stroke(foot, with: .color(ink), lineWidth: 1)
        }
        // The left hand resting on the throne's arm.
        let rest = Path(roundedRect: CGRect(x: 30, y: 216, width: 18, height: 13), cornerRadius: 6)
        ctx.fill(rest, with: .color(skin))
        ctx.stroke(rest, with: .color(ink), lineWidth: 1)
        // Collar: a broad gold collar in Egypt, a gold-edged neckline elsewhere; a toga's band in
        // Italy; a gold torc in the north.
        switch style {
        case "egypt":
            for (i, r) in [36.0, 30, 24].enumerated() {
                var collar = Path()
                collar.addArc(center: CGPoint(x: 100, y: 156), radius: r, startAngle: .degrees(20), endAngle: .degrees(160), clockwise: false)
                ctx.stroke(collar, with: .color(i == 1 ? Color(red: 0.15, green: 0.45, blue: 0.6) : gold), lineWidth: 6)
            }
        case "italia":
            var band = Path()
            band.move(to: CGPoint(x: 64, y: 168))
            band.addQuadCurve(to: CGPoint(x: 150, y: 250), control: CGPoint(x: 120, y: 180))
            ctx.stroke(band, with: .color(Color(red: 0.45, green: 0.12, blue: 0.4)), lineWidth: 9)
            ctx.stroke(band, with: .color(.white.opacity(0.85)), style: StrokeStyle(lineWidth: 2, dash: [1, 0]))
        case "north":
            var torc = Path()
            torc.addArc(center: CGPoint(x: 100, y: 150), radius: 22, startAngle: .degrees(25), endAngle: .degrees(155), clockwise: false)
            ctx.stroke(torc, with: .color(gold), style: StrokeStyle(lineWidth: 6, lineCap: .round))
            for x in [78.0, 122] { ctx.fill(Path(ellipseIn: CGRect(x: x - 5, y: 156, width: 10, height: 10)), with: .color(gold)) }
        default:
            var neck = Path()
            neck.move(to: CGPoint(x: 78, y: 166))
            neck.addQuadCurve(to: CGPoint(x: 122, y: 166), control: CGPoint(x: 100, y: 186))
            ctx.stroke(neck, with: .color(gold), lineWidth: 4)
        }
        // A sceptre in the right hand, raised as they speak sharply.
        let raise: Double = mood == .angry ? 10 + sin(t * 3) * 2 : talk * 6
        var staff = Path()
        staff.move(to: CGPoint(x: 162, y: 312))
        staff.addLine(to: CGPoint(x: 168, y: 150 - CGFloat(raise)))
        ctx.stroke(staff, with: .color(Color(red: 0.55, green: 0.38, blue: 0.16)), lineWidth: 4.5)
        if style == "hatti" {
            // The lituus: the Hittite kings' crook, curled back at the top.
            var crook = Path()
            crook.move(to: CGPoint(x: 168, y: 152 - CGFloat(raise)))
            crook.addCurve(to: CGPoint(x: 154, y: 132 - CGFloat(raise)), control1: CGPoint(x: 170, y: 132 - CGFloat(raise)),
                           control2: CGPoint(x: 160, y: 124 - CGFloat(raise)))
            crook.addQuadCurve(to: CGPoint(x: 160, y: 142 - CGFloat(raise)), control: CGPoint(x: 150, y: 142 - CGFloat(raise)))
            ctx.stroke(crook, with: .color(gold), style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
        } else {
            ctx.fill(Path(ellipseIn: CGRect(x: 161, y: 140 - CGFloat(raise), width: 14, height: 14)), with: .color(gold))
            ctx.stroke(Path(ellipseIn: CGRect(x: 161, y: 140 - CGFloat(raise), width: 14, height: 14)), with: .color(ink), lineWidth: 1)
        }
        let hand = CGRect(x: 156, y: 206 - CGFloat(raise * 0.5), width: 18, height: 14)
        ctx.fill(Path(roundedRect: hand, cornerRadius: 6), with: .color(skin))
        ctx.stroke(Path(roundedRect: hand, cornerRadius: 6), with: .color(ink), lineWidth: 1)
        // Neck.
        let neck = Path(roundedRect: CGRect(x: 86, y: 140, width: 28, height: 26), cornerRadius: 6)
        ctx.fill(neck, with: .color(skin))
    }

    private func drawHead(_ ctx: inout GraphicsContext, t: Double, talk: Double) {
        // Behind the head: the nemes' lappets, the Mesopotamian's hair.
        if style == "egypt" { nemes(&ctx, back: true) }
        if style == "mesopotamia" {
            ctx.fill(Path(roundedRect: CGRect(x: 64, y: 96, width: 72, height: 66), cornerRadius: 14), with: .color(hair))
        }
        // Long hair to the shoulders: the Hittites' and the northerners'.
        if style == "hatti" || style == "north" {
            ctx.fill(Path(roundedRect: CGRect(x: 60, y: 90, width: 80, height: style == "north" ? 86 : 70), cornerRadius: 18), with: .color(hair))
        }
        // Ears and face.
        for x in [62.0, 128] {
            ctx.fill(Path(ellipseIn: CGRect(x: x, y: 104, width: 12, height: 20)), with: .color(skin))
            ctx.stroke(Path(ellipseIn: CGRect(x: x, y: 104, width: 12, height: 20)), with: .color(ink), lineWidth: 1)
        }
        let face = Path(ellipseIn: CGRect(x: 68, y: 70, width: 64, height: 82))
        ctx.fill(face, with: .color(skin))
        ctx.fill(face, with: .radialGradient(Gradient(colors: [.white.opacity(0.12), .clear]),
                                             center: CGPoint(x: 92, y: 96), startRadius: 2, endRadius: 40))
        ctx.stroke(face, with: .color(ink), lineWidth: 1.5)

        // Hair on top (Greece and Italy).
        if ["greece", "italia", "north", "libyan", "chief"].contains(style) {
            var crown = Path()
            crown.move(to: CGPoint(x: 68, y: 104))
            crown.addQuadCurve(to: CGPoint(x: 132, y: 104), control: CGPoint(x: 100, y: 52))
            crown.addQuadCurve(to: CGPoint(x: 68, y: 104), control: CGPoint(x: 100, y: 78))
            ctx.fill(crown, with: .color(hair))
            for x in stride(from: 74.0, through: 126, by: 9) {
                ctx.fill(Path(ellipseIn: CGRect(x: x - 5, y: 78 + abs(x - 100) * 0.35, width: 11, height: 11)), with: .color(hair))
            }
        }

        // Eyes, with a blink every few seconds; kohl in Egypt.
        let blink = (t.truncatingRemainder(dividingBy: 3.7)) < 0.13
        let wary = mood == .wary
        for (x, side) in [(86.0, -1.0), (114.0, 1.0)] {
            let eye = CGRect(x: x - 7, y: 106 - (wary ? 1 : 0), width: 14, height: blink ? 1.5 : (wary ? 8 : 7))
            ctx.fill(Path(ellipseIn: eye), with: .color(.white))
            if !blink {
                let look = sin(t * 0.5) * 1.5
                ctx.fill(Path(ellipseIn: CGRect(x: x - 3 + look, y: 107, width: 6, height: 6)), with: .color(Color(red: 0.2, green: 0.13, blue: 0.08)))
            }
            ctx.stroke(Path(ellipseIn: eye), with: .color(ink), lineWidth: 1.2)
            if style == "egypt" {
                var kohl = Path()
                kohl.move(to: CGPoint(x: x + 7 * side, y: 109))
                kohl.addLine(to: CGPoint(x: x + 14 * side, y: 106))
                ctx.stroke(kohl, with: .color(.black), lineWidth: 2)
            }
            // Brows: knitted in anger, raised when pleased or wary.
            let (inner, outer): (Double, Double) = switch mood {
            case .angry: (101, 95)
            case .stern: (99, 97)
            case .pleased: (95, 96)
            case .wary: (94, 97)
            case .neutral: (97, 97)
            }
            var brow = Path()
            brow.move(to: CGPoint(x: x - 8 * side, y: inner))   // the inner end, toward the nose
            brow.addLine(to: CGPoint(x: x + 9 * side, y: outer))
            ctx.stroke(brow, with: .color(hair), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
        // Nose.
        var nose = Path()
        nose.move(to: CGPoint(x: 100, y: 110))
        nose.addQuadCurve(to: CGPoint(x: 96, y: 126), control: CGPoint(x: 104, y: 122))
        nose.addLine(to: CGPoint(x: 102, y: 127))
        ctx.stroke(nose, with: .color(ink), lineWidth: 1.2)

        // Beard (all but Italy's clean-shaven ruler), drawn before the mouth.
        beard(&ctx)

        // Mouth: smiling, set, or turned down; moving while they speak.
        let open = talk > 0 ? abs(sin(t * 13)) * 5 * talk : 0
        let curve: Double = switch mood { case .pleased: 5; case .angry: -4; case .stern: -2; case .wary: -1; case .neutral: 1 }
        var mouth = Path()
        mouth.move(to: CGPoint(x: 90, y: 135))
        mouth.addQuadCurve(to: CGPoint(x: 110, y: 135), control: CGPoint(x: 100, y: 135 + curve))
        if open > 0.3 {
            mouth.addQuadCurve(to: CGPoint(x: 90, y: 135), control: CGPoint(x: 100, y: 135 + curve + CGFloat(open) * 2))
            ctx.fill(mouth, with: .color(Color(red: 0.35, green: 0.1, blue: 0.08)))
        }
        ctx.stroke(mouth, with: .color(Color(red: 0.4, green: 0.15, blue: 0.12)), style: StrokeStyle(lineWidth: 2, lineCap: .round))

        // Headdress.
        switch style {
        case "egypt": nemes(&ctx, back: false)
        case "mesopotamia": polos(&ctx)
        case "greece": helmet(&ctx)
        case "italia": laurel(&ctx)
        case "hatti": conicalCap(&ctx)
        case "libyan": feathers(&ctx)
        case "north": braids(&ctx)
        default: crownBand(&ctx)
        }
    }

    // MARK: Dress

    /// The striped nemes headcloth, with the cobra at the brow.
    private func nemes(_ ctx: inout GraphicsContext, back: Bool) {
        let blue = Color(red: 0.13, green: 0.32, blue: 0.62)
        if back {
            for x in [58.0, 122] {
                var lappet = Path()
                lappet.move(to: CGPoint(x: x, y: 100))
                lappet.addLine(to: CGPoint(x: x + 20, y: 100))
                lappet.addLine(to: CGPoint(x: x + 18 + (x < 100 ? 2 : -2), y: 170))
                lappet.addLine(to: CGPoint(x: x + (x < 100 ? 4 : -4), y: 170))
                lappet.closeSubpath()
                ctx.fill(lappet, with: .color(gold))
                for y in stride(from: 108.0, to: 170, by: 10) {
                    ctx.fill(Path(CGRect(x: x + 2, y: y, width: 16, height: 4)), with: .color(blue))
                }
                ctx.stroke(lappet, with: .color(ink), lineWidth: 1)
            }
            return
        }
        var cloth = Path()
        cloth.move(to: CGPoint(x: 62, y: 104))
        cloth.addQuadCurve(to: CGPoint(x: 138, y: 104), control: CGPoint(x: 100, y: 40))
        cloth.addLine(to: CGPoint(x: 132, y: 92))
        cloth.addQuadCurve(to: CGPoint(x: 68, y: 92), control: CGPoint(x: 100, y: 80))
        cloth.closeSubpath()
        ctx.fill(cloth, with: .color(gold))
        ctx.drawLayer { layer in
            layer.clip(to: cloth)
            for k in 0..<10 {
                var stripe = Path()
                let a = 62.0 + Double(k) * 8
                stripe.move(to: CGPoint(x: a, y: 104))
                stripe.addLine(to: CGPoint(x: 100 + (a - 100) * 0.4, y: 50))
                layer.stroke(stripe, with: .color(blue), lineWidth: 3.5)
            }
        }
        ctx.stroke(cloth, with: .color(ink), lineWidth: 1.2)
        // Uraeus.
        var cobra = Path()
        cobra.move(to: CGPoint(x: 100, y: 88))
        cobra.addQuadCurve(to: CGPoint(x: 100, y: 72), control: CGPoint(x: 92, y: 80))
        ctx.stroke(cobra, with: .color(gold), lineWidth: 4)
        ctx.fill(Path(ellipseIn: CGRect(x: 96, y: 68, width: 8, height: 7)), with: .color(gold))
    }

    /// Mesopotamia's tall, horned cap.
    private func polos(_ ctx: inout GraphicsContext) {
        var cap = Path()
        cap.move(to: CGPoint(x: 70, y: 88))
        cap.addLine(to: CGPoint(x: 76, y: 40))
        cap.addQuadCurve(to: CGPoint(x: 124, y: 40), control: CGPoint(x: 100, y: 32))
        cap.addLine(to: CGPoint(x: 130, y: 88))
        cap.addQuadCurve(to: CGPoint(x: 70, y: 88), control: CGPoint(x: 100, y: 94))
        ctx.fill(cap, with: .color(Color(red: 0.5, green: 0.12, blue: 0.1)))
        for y in [52.0, 64, 76] {
            var horn = Path()
            horn.move(to: CGPoint(x: 74, y: y))
            horn.addQuadCurve(to: CGPoint(x: 126, y: y), control: CGPoint(x: 100, y: y - 8))
            ctx.stroke(horn, with: .color(gold), lineWidth: 2.5)
        }
        ctx.stroke(cap, with: .color(ink), lineWidth: 1.2)
    }

    /// A Corinthian helmet pushed back on the head, crest and all.
    private func helmet(_ ctx: inout GraphicsContext) {
        var crest = Path()
        crest.move(to: CGPoint(x: 72, y: 66))
        crest.addQuadCurve(to: CGPoint(x: 130, y: 70), control: CGPoint(x: 96, y: 20))
        crest.addQuadCurve(to: CGPoint(x: 72, y: 66), control: CGPoint(x: 100, y: 44))
        ctx.fill(crest, with: .color(Color(red: 0.72, green: 0.14, blue: 0.1)))
        for x in stride(from: 80.0, through: 124, by: 6) {
            var hairline = Path()
            hairline.move(to: CGPoint(x: x, y: 64))
            hairline.addLine(to: CGPoint(x: x + 3, y: 40 + abs(x - 102) * 0.6))
            ctx.stroke(hairline, with: .color(.black.opacity(0.25)), lineWidth: 1)
        }
        var bowl = Path()
        bowl.move(to: CGPoint(x: 66, y: 92))
        bowl.addQuadCurve(to: CGPoint(x: 134, y: 92), control: CGPoint(x: 100, y: 46))
        bowl.addQuadCurve(to: CGPoint(x: 66, y: 92), control: CGPoint(x: 100, y: 80))
        ctx.fill(bowl, with: .linearGradient(Gradient(colors: [Color(red: 0.95, green: 0.75, blue: 0.4), Color(red: 0.62, green: 0.42, blue: 0.16)]),
                                             startPoint: CGPoint(x: 80, y: 56), endPoint: CGPoint(x: 120, y: 92)))
        ctx.stroke(bowl, with: .color(ink), lineWidth: 1.2)
    }

    private func laurel(_ ctx: inout GraphicsContext) {
        let green = Color(red: 0.35, green: 0.55, blue: 0.22)
        for side in [-1.0, 1] {
            // Leaves along the brow, from the temples to a gap at the front.
            for k in 0..<7 {
                let a = 0.25 + Double(k) / 6 * 1.2
                let x = 100 + side * 33 * sin(a), y = 100 - 28 * cos(a)
                var leaf = Path(ellipseIn: CGRect(x: -7, y: -3.5, width: 14, height: 7))
                leaf = leaf.applying(CGAffineTransform(rotationAngle: CGFloat(side * (a + 0.4))))
                    .applying(CGAffineTransform(translationX: x, y: y))
                ctx.fill(leaf, with: .color(green))
                ctx.stroke(leaf, with: .color(.black.opacity(0.35)), lineWidth: 0.6)
            }
        }
    }

    /// The Hittite kings' tall pointed cap, banded in gold.
    private func conicalCap(_ ctx: inout GraphicsContext) {
        var cap = Path()
        cap.move(to: CGPoint(x: 70, y: 94))
        cap.addQuadCurve(to: CGPoint(x: 104, y: 6), control: CGPoint(x: 76, y: 40))
        cap.addQuadCurve(to: CGPoint(x: 130, y: 94), control: CGPoint(x: 126, y: 46))
        cap.addQuadCurve(to: CGPoint(x: 70, y: 94), control: CGPoint(x: 100, y: 84))
        ctx.fill(cap, with: .linearGradient(Gradient(colors: [robe.opacity(0.95), robe.opacity(0.7)]),
                                            startPoint: CGPoint(x: 80, y: 20), endPoint: CGPoint(x: 126, y: 94)))
        ctx.stroke(cap, with: .color(ink), lineWidth: 1.4)
        for y in [86.0, 62] {
            var band = Path()
            band.move(to: CGPoint(x: 72 + (94 - y) * 0.12, y: y))
            band.addQuadCurve(to: CGPoint(x: 128 - (94 - y) * 0.1, y: y), control: CGPoint(x: 100, y: y + 6))
            ctx.stroke(band, with: .color(gold), lineWidth: 4)
        }
    }

    /// Two tall feathers in a headband, and a sidelock: the Libyan chiefs, as the Egyptians drew them.
    private func feathers(_ ctx: inout GraphicsContext) {
        ctx.fill(Path(roundedRect: CGRect(x: 68, y: 82, width: 64, height: 8), cornerRadius: 3), with: .color(Color(red: 0.8, green: 0.25, blue: 0.15)))
        for (x, lean) in [(92.0, -0.18), (108.0, 0.12)] {
            var f = Path(ellipseIn: CGRect(x: -7, y: -38, width: 14, height: 46))
            f = f.applying(CGAffineTransform(rotationAngle: CGFloat(lean))).applying(CGAffineTransform(translationX: x, y: 64))
            ctx.fill(f, with: .color(Color(white: 0.95)))
            ctx.stroke(f, with: .color(ink), lineWidth: 1)
            var spine = Path()
            spine.move(to: CGPoint(x: x, y: 82)); spine.addLine(to: CGPoint(x: x + CGFloat(lean) * 60, y: 30))
            ctx.stroke(spine, with: .color(.black.opacity(0.35)), lineWidth: 1)
        }
        var lock = Path()
        lock.move(to: CGPoint(x: 66, y: 98))
        lock.addQuadCurve(to: CGPoint(x: 62, y: 150), control: CGPoint(x: 56, y: 124))
        ctx.stroke(lock, with: .color(hair), style: StrokeStyle(lineWidth: 7, lineCap: .round))
    }

    /// Braids falling either side of the face, and a plain gold band.
    private func braids(_ ctx: inout GraphicsContext) {
        for x in [64.0, 136] {
            for k in 0..<6 {
                ctx.fill(Path(ellipseIn: CGRect(x: x - 6, y: 112 + Double(k) * 10, width: 12, height: 12)), with: .color(hair))
                ctx.stroke(Path(ellipseIn: CGRect(x: x - 6, y: 112 + Double(k) * 10, width: 12, height: 12)), with: .color(.black.opacity(0.3)), lineWidth: 0.8)
            }
        }
        crownBand(&ctx)
    }

    private func crownBand(_ ctx: inout GraphicsContext) {
        ctx.fill(Path(roundedRect: CGRect(x: 68, y: 80, width: 64, height: 10), cornerRadius: 3), with: .color(gold))
    }

    private func beard(_ ctx: inout GraphicsContext) {
        switch style == "north" || style == "libyan" || style == "chief" ? "greece" : style {
        case "egypt":
            // The pharaoh's plaited false beard.
            let b = Path(roundedRect: CGRect(x: 94, y: 146, width: 12, height: 26), cornerRadius: 4)
            ctx.fill(b, with: .color(Color(red: 0.13, green: 0.32, blue: 0.62)))
            for y in stride(from: 150.0, to: 172, by: 5) {
                ctx.fill(Path(CGRect(x: 94, y: y, width: 12, height: 1.5)), with: .color(gold))
            }
            ctx.stroke(b, with: .color(ink), lineWidth: 1)
        case "mesopotamia":
            // Long, square-cut and curled in rows.
            var b = Path()
            b.move(to: CGPoint(x: 72, y: 118))
            b.addQuadCurve(to: CGPoint(x: 128, y: 118), control: CGPoint(x: 100, y: 150))
            b.addLine(to: CGPoint(x: 120, y: 182))
            b.addLine(to: CGPoint(x: 80, y: 182))
            b.closeSubpath()
            ctx.fill(b, with: .color(hair))
            for y in stride(from: 142.0, to: 182, by: 7) {
                for x in stride(from: 84.0, to: 118, by: 7) {
                    ctx.stroke(Path(ellipseIn: CGRect(x: x, y: y, width: 5, height: 4)), with: .color(.white.opacity(0.18)), lineWidth: 1)
                }
            }
        case "greece":
            var b = Path()
            b.move(to: CGPoint(x: 70, y: 116))
            b.addQuadCurve(to: CGPoint(x: 100, y: 166), control: CGPoint(x: 72, y: 160))
            b.addQuadCurve(to: CGPoint(x: 130, y: 116), control: CGPoint(x: 128, y: 160))
            b.addQuadCurve(to: CGPoint(x: 70, y: 116), control: CGPoint(x: 100, y: 142))
            ctx.fill(b, with: .color(hair))
            // Moustache.
            var m = Path()
            m.move(to: CGPoint(x: 88, y: 131))
            m.addQuadCurve(to: CGPoint(x: 112, y: 131), control: CGPoint(x: 100, y: 125))
            ctx.stroke(m, with: .color(hair), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
        default:
            break
        }
    }
}
