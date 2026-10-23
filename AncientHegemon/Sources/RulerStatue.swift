import HegemonCore
import SwiftUI

/// The statue of the ruler in the throne room, carved the way each realm carved its kings:
/// Egypt's striding pharaoh in sandstone against a back pillar, Mesopotamia's king in dark
/// diorite with hands clasped in prayer, the Greek in painted marble with spear and shield,
/// the Italian cast in bronze, arm raised to address the crowd. On a plinth carved with the name.
struct RulerStatue: View {
    let civ: CivilizationID
    let ruler: String

    var body: some View {
        Canvas { ctx, size in
            ctx.scaleBy(x: size.width / 120, y: size.height / 260)
            draw(ctx)
        }
        .aspectRatio(120 / 260, contentMode: .fit)
        .accessibilityLabel("A statue of \(ruler)")
    }

    // MARK: Materials

    struct Stone {
        let light: Color, base: Color, dark: Color
    }

    private var stone: Stone {
        switch civ {
        case "egypt": Stone(light: Color(red: 0.95, green: 0.84, blue: 0.64), base: Color(red: 0.84, green: 0.7, blue: 0.5),
                            dark: Color(red: 0.6, green: 0.46, blue: 0.3))
        case "mesopotamia": Stone(light: Color(red: 0.5, green: 0.52, blue: 0.55), base: Color(red: 0.3, green: 0.31, blue: 0.34),
                                  dark: Color(red: 0.14, green: 0.15, blue: 0.17))
        case "hatti": Stone(light: Color(red: 0.6, green: 0.58, blue: 0.55), base: Color(red: 0.4, green: 0.38, blue: 0.36),
                            dark: Color(red: 0.2, green: 0.19, blue: 0.18))
        case "greece": Stone(light: Color(white: 0.99), base: Color(red: 0.9, green: 0.88, blue: 0.84),
                             dark: Color(red: 0.66, green: 0.64, blue: 0.62))
        default: Stone(light: Color(red: 0.93, green: 0.72, blue: 0.4), base: Color(red: 0.6, green: 0.4, blue: 0.2),
                       dark: Color(red: 0.3, green: 0.19, blue: 0.1))
        }
    }

    private var plinth: Stone {
        civ == "mesopotamia" ? stone
            : Stone(light: Color(red: 0.86, green: 0.83, blue: 0.78), base: Color(red: 0.72, green: 0.69, blue: 0.64),
                    dark: Color(red: 0.5, green: 0.47, blue: 0.43))
    }

    /// Rounded with light from the left, and a fine chisel line around the edge.
    private func carve(_ ctx: GraphicsContext, _ path: Path, _ m: Stone? = nil) {
        let m = m ?? stone
        let r = path.boundingRect
        ctx.fill(path, with: .linearGradient(Gradient(colors: [m.light, m.base, m.dark]),
                                             startPoint: CGPoint(x: r.minX, y: r.minY),
                                             endPoint: CGPoint(x: r.maxX, y: r.minY)))
        ctx.stroke(path, with: .color(m.dark.opacity(0.55)), lineWidth: 0.7)
    }

    private func line(_ ctx: GraphicsContext, _ points: [CGPoint], width: CGFloat = 0.8, opacity: Double = 0.5) {
        var p = Path()
        p.addLines(points)
        ctx.stroke(p, with: .color(stone.dark.opacity(opacity)), lineWidth: width)
    }

    private func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, r: CGFloat = 3) -> Path {
        Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r)
    }

    private func poly(_ points: [(CGFloat, CGFloat)]) -> Path {
        var p = Path()
        p.addLines(points.map { CGPoint(x: $0.0, y: $0.1) })
        p.closeSubpath()
        return p
    }

    /// Blank stone eyes, a nose and a closed mouth: a carved face, calm and a little stern.
    private func face(_ ctx: GraphicsContext, _ cx: CGFloat, _ y: CGFloat, paint: Color? = nil) {
        for dx in [-4.5, 4.5] as [CGFloat] {
            let eye = Path(ellipseIn: CGRect(x: cx + dx - 2.5, y: y, width: 5, height: 2.4))
            ctx.fill(eye, with: .color(paint ?? stone.dark.opacity(0.6)))
            line(ctx, [CGPoint(x: cx + dx - 3.5, y: y - 2.5), CGPoint(x: cx + dx + 3, y: y - 3)], width: 0.9, opacity: 0.6)
        }
        line(ctx, [CGPoint(x: cx, y: y + 1), CGPoint(x: cx + 1.5, y: y + 7), CGPoint(x: cx - 1, y: y + 8)], opacity: 0.55)
        line(ctx, [CGPoint(x: cx - 3, y: y + 11.5), CGPoint(x: cx + 3, y: y + 11.5)], width: 1, opacity: 0.6)
    }

    // MARK: Drawing (in a 120 × 260 frame; the plinth's foot on the bottom edge)

    private func draw(_ ctx: GraphicsContext) {
        switch civ {
        case "egypt": pharaoh(ctx)
        case "mesopotamia", "hatti": king(ctx)
        case "greece": warrior(ctx)
        default: orator(ctx)
        }
        base(ctx)
    }

    /// A stepped plinth, the ruler's name cut into its face.
    private func base(_ ctx: GraphicsContext) {
        carve(ctx, rect(30, 198, 60, 9, r: 1), plinth)
        carve(ctx, rect(36, 207, 48, 40, r: 1), plinth)
        carve(ctx, rect(26, 247, 68, 13, r: 1), plinth)
        ctx.stroke(rect(40, 214, 40, 26, r: 1), with: .color(plinth.dark.opacity(0.6)), lineWidth: 0.8)
        let name = ruler.uppercased()
        ctx.draw(Text(name).font(.system(size: name.count > 9 ? 4.2 : name.count > 7 ? 5 : 6.5, weight: .bold, design: .serif))
                    .foregroundColor(plinth.dark),
                 at: CGPoint(x: 60, y: 227))
    }

    /// Striding forward against a back pillar, the nemes headcloth and false beard, the kilt.
    private func pharaoh(_ ctx: GraphicsContext) {
        let paintBlue = Color(red: 0.2, green: 0.4, blue: 0.62).opacity(0.75)
        let paintGold = Color(red: 0.86, green: 0.66, blue: 0.24).opacity(0.85)
        // The back pillar, with a column of hieroglyphs.
        carve(ctx, rect(46, 40, 28, 158, r: 1), Stone(light: stone.base, base: stone.dark, dark: stone.dark))
        for y in stride(from: 120, through: 186, by: 11) {
            line(ctx, [CGPoint(x: 70, y: CGFloat(y)), CGPoint(x: 72, y: CGFloat(y) + 4)], opacity: 0.4)
        }
        // Legs, the left a stride ahead.
        carve(ctx, rect(48, 140, 10, 56, r: 4))
        carve(ctx, rect(62, 140, 10, 54, r: 4))
        carve(ctx, rect(42, 192, 18, 7, r: 3))
        carve(ctx, rect(61, 191, 15, 6, r: 3))
        // Arms straight at the sides, fists closed.
        carve(ctx, rect(35, 66, 9, 50, r: 4))
        carve(ctx, rect(76, 66, 9, 50, r: 4))
        carve(ctx, Path(ellipseIn: CGRect(x: 34, y: 112, width: 11, height: 11)))
        carve(ctx, Path(ellipseIn: CGRect(x: 75, y: 112, width: 11, height: 11)))
        // Bare chest, the broad collar painted.
        carve(ctx, poly([(40, 62), (80, 62), (74, 110), (46, 110)]))
        var collar = Path()
        collar.addArc(center: CGPoint(x: 60, y: 58), radius: 15, startAngle: .degrees(20), endAngle: .degrees(160), clockwise: false)
        ctx.stroke(collar, with: .color(paintBlue), lineWidth: 4)
        ctx.stroke(collar, with: .color(paintGold), lineWidth: 1.5)
        // The kilt, pleated, with a belt.
        carve(ctx, poly([(45, 108), (75, 108), (80, 142), (40, 142)]))
        ctx.fill(rect(45, 107, 30, 4, r: 1), with: .color(paintGold))
        for x in stride(from: 46, through: 74, by: 4) {
            line(ctx, [CGPoint(x: CGFloat(x), y: 112), CGPoint(x: CGFloat(x) + (CGFloat(x) - 60) * 0.25, y: 141)], width: 0.6, opacity: 0.4)
        }
        carve(ctx, poly([(56, 111), (64, 111), (66, 138), (54, 138)]))
        // Neck, nemes, face, false beard, the cobra on the brow.
        carve(ctx, rect(55, 52, 10, 10, r: 2))
        let nemes = poly([(47, 40), (48, 28), (54, 22), (66, 22), (72, 28), (73, 40), (79, 74), (69, 74), (67, 52),
                          (53, 52), (51, 74), (41, 74)])
        carve(ctx, nemes)
        for y in stride(from: 30, through: 72, by: 5) {
            let yy = CGFloat(y)
            ctx.stroke(Path { p in p.move(to: CGPoint(x: 42 + (74 - yy) * 0.12, y: yy)); p.addLine(to: CGPoint(x: 52, y: yy)) },
                       with: .color(paintBlue), lineWidth: 1.6)
            ctx.stroke(Path { p in p.move(to: CGPoint(x: 68, y: yy)); p.addLine(to: CGPoint(x: 78 - (74 - yy) * 0.12, y: yy)) },
                       with: .color(paintBlue), lineWidth: 1.6)
        }
        carve(ctx, Path(ellipseIn: CGRect(x: 51, y: 29, width: 18, height: 24)))
        face(ctx, 60, 38, paint: Color.black.opacity(0.7))
        carve(ctx, rect(57, 52, 6, 11, r: 2))
        ctx.fill(Path(ellipseIn: CGRect(x: 58, y: 22, width: 4, height: 7)), with: .color(paintGold))
    }

    /// Hands clasped before the chest, the long fringed robe, a tall cap, a long curled beard.
    private func king(_ ctx: GraphicsContext) {
        // Hair falling behind the shoulders.
        carve(ctx, rect(46, 36, 28, 30, r: 6))
        // The robe, to the feet, wrapped in fringed tiers.
        let robe = poly([(42, 60), (78, 60), (82, 90), (86, 198), (34, 198), (38, 90)])
        carve(ctx, robe)
        for y in stride(from: 118, through: 190, by: 16) {
            let yy = CGFloat(y)
            let half = 22 + (yy - 90) * 0.04
            line(ctx, [CGPoint(x: 60 - half, y: yy), CGPoint(x: 60 + half, y: yy - 6)], width: 1, opacity: 0.6)
            for k in 0..<9 {
                let x = 60 - half + CGFloat(k) * half / 4.5
                let y0 = yy - CGFloat(k) * 6 / 9
                line(ctx, [CGPoint(x: x, y: y0), CGPoint(x: x, y: y0 + 4)], width: 0.6, opacity: 0.45)
            }
        }
        // The fringed edge thrown over the left shoulder.
        line(ctx, [CGPoint(x: 44, y: 62), CGPoint(x: 78, y: 112)], width: 1.4, opacity: 0.6)
        // Feet peeping out under the hem.
        carve(ctx, Path(ellipseIn: CGRect(x: 46, y: 194, width: 12, height: 6)))
        carve(ctx, Path(ellipseIn: CGRect(x: 62, y: 194, width: 12, height: 6)))
        // Forearms folded, hands clasped.
        carve(ctx, rect(42, 90, 36, 12, r: 6))
        carve(ctx, Path(ellipseIn: CGRect(x: 53, y: 86, width: 14, height: 16)))
        line(ctx, [CGPoint(x: 56, y: 92), CGPoint(x: 64, y: 92)], width: 0.6, opacity: 0.5)
        // Face, then the beard in rows of curls, then the cap.
        carve(ctx, Path(ellipseIn: CGRect(x: 50, y: 30, width: 20, height: 24)))
        face(ctx, 60, 38)
        var beard = Path()
        beard.move(to: CGPoint(x: 51, y: 47))
        beard.addQuadCurve(to: CGPoint(x: 69, y: 47), control: CGPoint(x: 60, y: 54))
        beard.addLine(to: CGPoint(x: 70, y: 80)); beard.addLine(to: CGPoint(x: 50, y: 80)); beard.closeSubpath()
        carve(ctx, beard)
        for row in 0..<4 {
            for k in 0..<4 {
                let c = CGRect(x: 52.5 + CGFloat(k) * 4, y: 56 + CGFloat(row) * 6, width: 3, height: 3)
                ctx.stroke(Path(ellipseIn: c), with: .color(stone.light.opacity(0.5)), lineWidth: 0.6)
            }
        }
        // Moustache.
        line(ctx, [CGPoint(x: 55, y: 48), CGPoint(x: 60, y: 46.5), CGPoint(x: 65, y: 48)], width: 1.2, opacity: 0.7)
        carve(ctx, rect(49, 14, 22, 18, r: 4))
        carve(ctx, rect(47, 28, 26, 5, r: 2))
        line(ctx, [CGPoint(x: 49, y: 20), CGPoint(x: 71, y: 20)], width: 0.8, opacity: 0.5)
    }

    /// Painted marble: crested helmet, cuirass and greaves, spear raised, round shield.
    private func warrior(_ ctx: GraphicsContext) {
        let bronze = Stone(light: Color(red: 0.95, green: 0.78, blue: 0.45), base: Color(red: 0.72, green: 0.5, blue: 0.25),
                           dark: Color(red: 0.42, green: 0.27, blue: 0.12))
        let crest = Color(red: 0.62, green: 0.18, blue: 0.14)
        // The spear, held upright.
        ctx.stroke(Path { p in p.move(to: CGPoint(x: 92, y: 14)); p.addLine(to: CGPoint(x: 92, y: 198)) },
                   with: .color(Color(red: 0.45, green: 0.3, blue: 0.18)), lineWidth: 2.4)
        carve(ctx, poly([(92, 2), (95.5, 14), (92, 18), (88.5, 14)]), bronze)
        // Legs with greaves.
        carve(ctx, rect(48, 136, 10, 58, r: 4))
        carve(ctx, rect(62, 136, 10, 58, r: 4))
        carve(ctx, rect(47.5, 160, 11, 30, r: 4), bronze)
        carve(ctx, rect(61.5, 160, 11, 30, r: 4), bronze)
        carve(ctx, rect(44, 192, 15, 6, r: 3))
        carve(ctx, rect(61, 192, 15, 6, r: 3))
        // Right arm up to the spear.
        carve(ctx, poly([(74, 62), (82, 60), (96, 52), (90, 46)]))
        carve(ctx, Path(ellipseIn: CGRect(x: 87, y: 43, width: 10, height: 11)))
        // The linen skirt of strips, then the cuirass with its muscles.
        carve(ctx, poly([(44, 108), (76, 108), (80, 138), (40, 138)]))
        for x in stride(from: 45, through: 75, by: 5) {
            line(ctx, [CGPoint(x: CGFloat(x), y: 110), CGPoint(x: CGFloat(x) + (CGFloat(x) - 60) * 0.2, y: 137)], width: 0.7, opacity: 0.5)
        }
        carve(ctx, poly([(41, 60), (79, 60), (75, 112), (45, 112)]), bronze)
        line(ctx, [CGPoint(x: 60, y: 66), CGPoint(x: 60, y: 108)], opacity: 0.5)
        for (x0, x1) in [(48.0, 58.0), (62.0, 72.0)] {
            var pec = Path()
            pec.move(to: CGPoint(x: x0, y: 78)); pec.addQuadCurve(to: CGPoint(x: x1, y: 78), control: CGPoint(x: (x0 + x1) / 2, y: 84))
            ctx.stroke(pec, with: .color(bronze.dark.opacity(0.6)), lineWidth: 0.8)
        }
        // Neck, face, short beard, helmet pushed back, the horsehair crest.
        carve(ctx, rect(55, 50, 10, 12, r: 2))
        carve(ctx, Path(ellipseIn: CGRect(x: 51, y: 28, width: 18, height: 24)))
        face(ctx, 60, 37, paint: Color(red: 0.25, green: 0.3, blue: 0.45))
        carve(ctx, Path(ellipseIn: CGRect(x: 53, y: 44, width: 14, height: 10)))
        line(ctx, [CGPoint(x: 57, y: 48.5), CGPoint(x: 63, y: 48.5)], width: 1, opacity: 0.6)
        var helmet = Path()
        helmet.addArc(center: CGPoint(x: 60, y: 32), radius: 12, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        helmet.closeSubpath()
        carve(ctx, helmet, bronze)
        var plume = Path()
        plume.move(to: CGPoint(x: 46, y: 30))
        plume.addQuadCurve(to: CGPoint(x: 76, y: 34), control: CGPoint(x: 58, y: 0))
        plume.addQuadCurve(to: CGPoint(x: 46, y: 30), control: CGPoint(x: 58, y: 10))
        ctx.fill(plume, with: .color(crest))
        // Left arm behind the great round shield, painted with a ram's head of a spiral.
        carve(ctx, rect(35, 64, 9, 34, r: 4))
        let shield = Path(ellipseIn: CGRect(x: 18, y: 78, width: 42, height: 42))
        carve(ctx, shield, bronze)
        ctx.stroke(Path(ellipseIn: CGRect(x: 22, y: 82, width: 34, height: 34)), with: .color(bronze.dark.opacity(0.6)), lineWidth: 1)
        var spiral = Path()
        for k in 0..<40 {
            let a = Double(k) * 0.42, r = 1.0 + Double(k) * 0.32
            let p = CGPoint(x: 39 + cos(a) * r, y: 99 + sin(a) * r)
            if k == 0 { spiral.move(to: p) } else { spiral.addLine(to: p) }
        }
        ctx.stroke(spiral, with: .color(crest), lineWidth: 1.6)
    }

    /// Cast in bronze: wrapped in a toga, a laurel wreath, right arm raised to the crowd.
    private func orator(_ ctx: GraphicsContext) {
        let leaf = Color(red: 0.35, green: 0.5, blue: 0.4)
        // The toga, down to the feet, and its folds.
        let toga = poly([(42, 60), (78, 60), (84, 100), (82, 198), (38, 198), (36, 100)])
        carve(ctx, toga)
        for k in 0..<5 {
            let o = CGFloat(k) * 9
            var fold = Path()
            fold.move(to: CGPoint(x: 42 + o * 0.3, y: 64 + o))
            fold.addQuadCurve(to: CGPoint(x: 82, y: 110 + o), control: CGPoint(x: 56 + o, y: 104 + o))
            ctx.stroke(fold, with: .color(stone.dark.opacity(0.65)), lineWidth: 1.1)
        }
        for x in [46.0, 54.0, 64.0, 72.0] {
            line(ctx, [CGPoint(x: x, y: 150), CGPoint(x: x + (x - 60) * 0.1, y: 196)], width: 0.9, opacity: 0.55)
        }
        carve(ctx, Path(ellipseIn: CGRect(x: 44, y: 193, width: 13, height: 6)))
        carve(ctx, Path(ellipseIn: CGRect(x: 63, y: 193, width: 13, height: 6)))
        // Left arm under the drape, holding a scroll.
        carve(ctx, rect(34, 66, 10, 44, r: 5))
        carve(ctx, rect(31, 106, 16, 6, r: 3))
        // Right arm raised, palm open.
        carve(ctx, poly([(74, 64), (82, 60), (100, 36), (94, 32)]))
        carve(ctx, rect(93, 22, 9, 13, r: 4))
        // Neck, face, short hair, the laurel.
        carve(ctx, rect(55, 50, 10, 12, r: 2))
        carve(ctx, Path(ellipseIn: CGRect(x: 50, y: 26, width: 20, height: 26)))
        face(ctx, 60, 36)
        carve(ctx, Path { p in
            p.addArc(center: CGPoint(x: 60, y: 33), radius: 10.5, startAngle: .degrees(195), endAngle: .degrees(-15), clockwise: false)
            p.closeSubpath()
        })
        // Leaves all round the brow, pointing up to meet at the crown.
        for k in 0..<11 {
            let a = Angle.degrees(185 + Double(k) * 17).radians
            let c = CGPoint(x: 60 + cos(a) * 10.5, y: 31 + sin(a) * 10.5)
            var l = Path(ellipseIn: CGRect(x: -3.2, y: -1.5, width: 6.4, height: 3))
            l = l.applying(CGAffineTransform(rotationAngle: a + (k < 5 ? -.pi / 2.6 : .pi / 2.6)))
                .applying(CGAffineTransform(translationX: c.x, y: c.y))
            ctx.fill(l, with: .color(leaf))
        }
    }
}

#Preview {
    HStack(spacing: 30) {
        ForEach(["egypt", "mesopotamia", "greece", "italia"], id: \.self) { civ in
            RulerStatue(civ: civ, ruler: "Ramesses").frame(height: 260)
        }
    }
    .padding()
    .background(Color(red: 0.86, green: 0.74, blue: 0.52))
}
