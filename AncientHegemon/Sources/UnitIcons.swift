import HegemonCore
import SwiftUI

/// Unit icons, drawn as vector shapes so they stay crisp at any size: a Corinthian helmet for
/// infantry, a recurve bow for archers, a horse's head for cavalry.
struct UnitIcon: View {
    let type: UnitType
    var color: Color = .primary

    var body: some View {
        UnitShape(type: type).fill(color)
            .aspectRatio(1, contentMode: .fit)
    }
}

/// An icon with a count beside it, e.g. a helmet and "3".
struct UnitCount: View {
    let type: UnitType
    let count: Int
    var size: CGFloat = 14

    var body: some View {
        HStack(spacing: 2) {
            UnitIcon(type: type).frame(width: size, height: size)
            Text("\(count)").monospacedDigit()
        }
    }
}

/// A row of unit counts, skipping types with none.
struct UnitRow: View {
    let units: UnitCounts
    var size: CGFloat = 13
    var showZero = false

    var body: some View {
        HStack(spacing: 8) {
            ForEach(UnitType.allCases, id: \.self) { type in
                if showZero || units[type] > 0 { UnitCount(type: type, count: units[type], size: size) }
            }
        }
    }
}

struct UnitShape: Shape {
    let type: UnitType

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height)
        let origin = CGPoint(x: rect.midX - s / 2, y: rect.midY - s / 2)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: origin.x + x * s, y: origin.y + y * s) }
        switch type {
        case .infantry: return helmet(p, s)
        case .archers: return bow(p, s)
        case .cavalry: return horse(p, s)
        }
    }

    /// A Corinthian helmet from the front: crest, dome, cheek guards, and the T of eye slits and
    /// face opening (cut out with an even-odd fill).
    private func helmet(_ p: (CGFloat, CGFloat) -> CGPoint, _ s: CGFloat) -> Path {
        // Crest: a horsehair fan standing on the dome.
        var crest = Path()
        crest.move(to: p(0.30, 0.30))
        crest.addCurve(to: p(0.50, 0.00), control1: p(0.28, 0.12), control2: p(0.40, 0.02))
        crest.addCurve(to: p(0.70, 0.30), control1: p(0.60, 0.02), control2: p(0.72, 0.12))
        crest.closeSubpath()
        // Dome and cheek guards, with the face opening between them.
        var dome = Path()
        dome.move(to: p(0.20, 0.96))
        dome.addLine(to: p(0.16, 0.58))
        dome.addCurve(to: p(0.50, 0.20), control1: p(0.14, 0.34), control2: p(0.30, 0.20))
        dome.addCurve(to: p(0.84, 0.58), control1: p(0.70, 0.20), control2: p(0.86, 0.34))
        dome.addLine(to: p(0.80, 0.96))
        dome.addLine(to: p(0.59, 0.96))
        dome.addLine(to: p(0.56, 0.70))
        dome.addLine(to: p(0.44, 0.70))
        dome.addLine(to: p(0.41, 0.96))
        dome.closeSubpath()
        // Eye slits, angled like the bronze originals.
        var eyes = Path()
        eyes.move(to: p(0.24, 0.50))
        eyes.addLine(to: p(0.46, 0.54))
        eyes.addLine(to: p(0.46, 0.63))
        eyes.addLine(to: p(0.26, 0.60))
        eyes.closeSubpath()
        eyes.move(to: p(0.76, 0.50))
        eyes.addLine(to: p(0.54, 0.54))
        eyes.addLine(to: p(0.54, 0.63))
        eyes.addLine(to: p(0.74, 0.60))
        eyes.closeSubpath()
        return crest.union(dome).subtracting(eyes)
    }

    /// A recurve bow, drawn, with an arrow on the string.
    private func bow(_ p: (CGFloat, CGFloat) -> CGPoint, _ s: CGFloat) -> Path {
        var lines = Path()
        // The bow: recurved tips, a deep belly.
        lines.move(to: p(0.40, 0.06))
        lines.addQuadCurve(to: p(0.30, 0.16), control: p(0.30, 0.06))
        lines.addCurve(to: p(0.30, 0.84), control1: p(0.06, 0.36), control2: p(0.06, 0.64))
        lines.addQuadCurve(to: p(0.40, 0.94), control: p(0.30, 0.94))
        var bow = lines.strokedPath(StrokeStyle(lineWidth: s * 0.09, lineCap: .round, lineJoin: .round))
        var parts: [Path] = []
        // String, drawn back to the arrow's nock.
        var string = Path()
        string.move(to: p(0.31, 0.15))
        string.addLine(to: p(0.66, 0.50))
        string.addLine(to: p(0.31, 0.85))
        parts.append(string.strokedPath(StrokeStyle(lineWidth: s * 0.035, lineCap: .round, lineJoin: .round)))
        // Arrow shaft.
        var shaft = Path()
        shaft.move(to: p(0.12, 0.50))
        shaft.addLine(to: p(0.84, 0.50))
        parts.append(shaft.strokedPath(StrokeStyle(lineWidth: s * 0.05, lineCap: .round)))
        // Arrowhead, pointing left past the bow.
        var head = Path()
        head.move(to: p(0.02, 0.50))
        head.addLine(to: p(0.16, 0.42))
        head.addLine(to: p(0.16, 0.58))
        head.closeSubpath()
        parts.append(head)
        // Fletching.
        var fletch = Path()
        fletch.move(to: p(0.70, 0.50))
        fletch.addLine(to: p(0.82, 0.40))
        fletch.addLine(to: p(0.92, 0.40))
        fletch.addLine(to: p(0.82, 0.50))
        fletch.addLine(to: p(0.92, 0.60))
        fletch.addLine(to: p(0.82, 0.60))
        fletch.closeSubpath()
        parts.append(fletch)
        for part in parts { bow = bow.union(part) }
        return bow
    }

    /// A horse's head and neck, facing left, with an eye cut out.
    private func horse(_ p: (CGFloat, CGFloat) -> CGPoint, _ s: CGFloat) -> Path {
        var path = Path()
        path.move(to: p(0.58, 0.04))                                              // ear tip
        path.addLine(to: p(0.50, 0.20))                                           // front of ear
        path.addCurve(to: p(0.10, 0.58), control1: p(0.36, 0.22), control2: p(0.14, 0.44)) // forehead, nose
        path.addCurve(to: p(0.22, 0.74), control1: p(0.04, 0.68), control2: p(0.12, 0.76)) // muzzle
        path.addCurve(to: p(0.44, 0.62), control1: p(0.32, 0.72), control2: p(0.38, 0.64)) // jaw
        path.addCurve(to: p(0.50, 0.96), control1: p(0.50, 0.72), control2: p(0.46, 0.86)) // throat
        path.addLine(to: p(0.94, 0.96))                                           // chest to withers
        path.addCurve(to: p(0.72, 0.22), control1: p(0.96, 0.62), control2: p(0.86, 0.34)) // mane
        path.addLine(to: p(0.66, 0.06))                                           // back of ear
        path.closeSubpath()
        // Mane: a ridge of tufts along the back of the neck.
        var mane = Path()
        mane.move(to: p(0.68, 0.18))
        mane.addCurve(to: p(0.94, 0.80), control1: p(0.88, 0.28), control2: p(1.00, 0.56))
        mane.addLine(to: p(0.86, 0.70))
        mane.addCurve(to: p(0.70, 0.26), control1: p(0.88, 0.50), control2: p(0.80, 0.34))
        mane.closeSubpath()
        let eye = Path(ellipseIn: CGRect(x: p(0.34, 0.32).x, y: p(0.34, 0.32).y, width: s * 0.08, height: s * 0.07))
        return path.union(mane).subtracting(eye)
    }
}
