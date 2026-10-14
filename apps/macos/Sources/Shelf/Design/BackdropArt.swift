import SwiftUI

/// Line art that sprouts from the top-right corner of a page, drawn in the
/// accent at low strength and fading out with the glow. Every style is
/// strokes only, so it stays crisp, quiet and recolors with the accent.
enum BackdropArt: String, CaseIterable, Identifiable {
    case warli, mandala, gothic, seigaiha, deco, topographic, constellation, bloom, none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .warli: "Warli"
        case .mandala: "Mandala"
        case .gothic: "Gothic"
        case .seigaiha: "Seigaiha"
        case .deco: "Art Deco"
        case .topographic: "Topographic"
        case .constellation: "Constellation"
        case .bloom: "Bloom"
        case .none: "None"
        }
    }

    /// The art as one path, centered on `c` (the corner) with reach `r`.
    func path(corner c: CGPoint, radius r: CGFloat) -> Path {
        switch self {
        case .warli: Self.warli(c, r)
        case .mandala: Self.mandala(c, r)
        case .gothic: Self.gothic(c, r)
        case .deco: Self.deco(c, r)
        case .topographic: Self.topographic(c, r)
        case .constellation: Self.constellation(c, r)
        case .bloom: Self.bloom(c, r)
        case .seigaiha, .none: Path()   // seigaiha draws itself (it needs occlusion)
        }
    }
}

// MARK: - Drawing

private extension BackdropArt {
    static func point(_ c: CGPoint, _ radius: CGFloat, _ angle: Double) -> CGPoint {
        CGPoint(x: c.x + radius * CGFloat(cos(angle)), y: c.y + radius * CGFloat(sin(angle)))
    }

    static func circle(_ p: inout Path, _ center: CGPoint, _ radius: CGFloat) {
        p.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }

    /// Warli: rings of dancers holding hands around a sun, heads outward.
    static func warli(_ c: CGPoint, _ r: CGFloat) -> Path {
        var p = Path()
        // The sun.
        circle(&p, c, r * 0.10)
        for k in 0..<16 {
            let a = Double(k) / 16 * 2 * .pi
            p.move(to: point(c, r * 0.14, a))
            p.addLine(to: point(c, r * 0.21, a))
        }
        // Dancers stand upright, as Warli figures are always painted, in
        // arcs around the sun (only the arcs inside the page are drawn).
        // Inner rings are shorter, so their dancers are smaller. Spacing is
        // generous (1.3 h): on the diagonal, neighbors also sit at different
        // heights, and arms must never reach into the next dancer.
        for (ringR, h) in [(r * 0.30, r * 0.10), (r * 0.54, r * 0.13), (r * 0.80, r * 0.16)] {
            let arc = 0.5 * .pi * ringR
            let count = max(2, Int(arc / (h * 1.3)))
            for k in 0..<count {
                let a = .pi / 2 + (Double(k) + 0.5) / Double(count) * (.pi / 2)
                dancer(&p, feet: point(c, ringR, a), height: h, step: k)
            }
        }
        return p
    }

    /// One Warli figure standing at `feet`: circle head, two triangles
    /// meeting at the waist, arms out to the neighbors, legs mid-step.
    static func dancer(_ p: inout Path, feet f: CGPoint, height h: CGFloat, step: Int) {
        func at(_ up: CGFloat, _ across: CGFloat) -> CGPoint { CGPoint(x: f.x + across, y: f.y - up) }
        circle(&p, at(h * 0.90, 0), h * 0.085)
        // Torso: inverted triangle on top, upright triangle below.
        p.move(to: at(h * 0.76, -h * 0.15)); p.addLine(to: at(h * 0.76, h * 0.15)); p.addLine(to: at(h * 0.50, 0)); p.closeSubpath()
        p.move(to: at(h * 0.50, 0)); p.addLine(to: at(h * 0.30, -h * 0.13)); p.addLine(to: at(h * 0.30, h * 0.13)); p.closeSubpath()
        // Arms: elbows out, hands reaching for the neighbors.
        p.move(to: at(h * 0.74, -h * 0.15)); p.addLine(to: at(h * 0.62, -h * 0.25)); p.addLine(to: at(h * 0.68, -h * 0.33))
        p.move(to: at(h * 0.74, h * 0.15)); p.addLine(to: at(h * 0.62, h * 0.25)); p.addLine(to: at(h * 0.68, h * 0.33))
        // Legs, alternating mid-step.
        let lift: CGFloat = step.isMultiple(of: 2) ? 0.05 : -0.05
        p.move(to: at(h * 0.30, -h * 0.09)); p.addLine(to: at(h * 0.15, -h * (0.16 + lift))); p.addLine(to: at(0, -h * 0.12))
        p.move(to: at(h * 0.30, h * 0.09)); p.addLine(to: at(h * 0.15, h * (0.16 - lift))); p.addLine(to: at(0, h * 0.12))
    }

    /// Mandala: rings of petals, a ring of dots and a scalloped edge.
    static func mandala(_ c: CGPoint, _ r: CGFloat) -> Path {
        var p = Path()
        for f in [0.16, 0.32, 0.54, 0.78, 0.98] { circle(&p, c, r * f) }
        func petals(_ n: Int, _ inner: CGFloat, _ outer: CGFloat, _ offset: Double, width: Double) {
            for k in 0..<n {
                let a = (Double(k) + offset) / Double(n) * 2 * .pi
                let half = .pi / Double(n) * width
                let mid = (inner + outer) / 2
                p.move(to: point(c, inner, a))
                p.addQuadCurve(to: point(c, outer, a), control: point(c, mid, a - half * 1.6))
                p.addQuadCurve(to: point(c, inner, a), control: point(c, mid, a + half * 1.6))
            }
        }
        petals(12, r * 0.16, r * 0.32, 0, width: 1)
        petals(24, r * 0.32, r * 0.54, 0.5, width: 0.9)
        for k in 0..<36 {
            circle(&p, point(c, r * 0.60, Double(k) / 36 * 2 * .pi), r * 0.008)
        }
        petals(36, r * 0.64, r * 0.78, 0, width: 0.8)
        for k in 0..<30 {   // scallops along the edge
            let a0 = Double(k) / 30 * 2 * .pi, a1 = Double(k + 1) / 30 * 2 * .pi
            p.move(to: point(c, r * 0.78, a0))
            p.addQuadCurve(to: point(c, r * 0.78, a1), control: point(c, r * 0.96, (a0 + a1) / 2))
        }
        return p
    }

    /// Gothic: a rose window of lancet arches, spokes and a quatrefoil hub.
    static func gothic(_ c: CGPoint, _ r: CGFloat) -> Path {
        var p = Path()
        for f in [0.22, 0.27, 0.93, 0.98] { circle(&p, c, r * f) }
        let n = 16
        for k in 0..<n {
            let a = Double(k) / Double(n) * 2 * .pi
            let w = .pi / Double(n) * 0.78
            p.move(to: point(c, r * 0.27, a + .pi / Double(n)))
            p.addLine(to: point(c, r * 0.93, a + .pi / Double(n)))
            // A pointed lancet arch in each bay.
            p.move(to: point(c, r * 0.34, a - w))
            p.addLine(to: point(c, r * 0.62, a - w))
            p.addQuadCurve(to: point(c, r * 0.86, a), control: point(c, r * 0.80, a - w))
            p.addQuadCurve(to: point(c, r * 0.62, a + w), control: point(c, r * 0.80, a + w))
            p.addLine(to: point(c, r * 0.34, a + w))
            circle(&p, point(c, r * 0.70, a), r * 0.035)   // a small oculus
        }
        for k in 0..<4 { circle(&p, point(c, r * 0.11, Double(k) / 4 * 2 * .pi), r * 0.08) }
        return p
    }

    /// Art Deco: a sunburst of rays with fanned, stepped arcs.
    static func deco(_ c: CGPoint, _ r: CGFloat) -> Path {
        var p = Path()
        let rays = 22
        for k in 0...rays {
            let a = .pi / 2 + Double(k) / Double(rays) * (.pi / 2)
            p.move(to: point(c, r * 0.12, a))
            p.addLine(to: point(c, r * (k.isMultiple(of: 2) ? 0.98 : 0.82), a))
        }
        for f in [0.12, 0.30, 0.48, 0.66] {
            p.addArc(center: c, radius: r * f, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        }
        for k in 0..<rays {   // fans between rays
            let a0 = .pi / 2 + Double(k) / Double(rays) * (.pi / 2)
            let a1 = .pi / 2 + Double(k + 1) / Double(rays) * (.pi / 2)
            p.move(to: point(c, r * 0.48, a0))
            p.addQuadCurve(to: point(c, r * 0.48, a1), control: point(c, r * 0.56, (a0 + a1) / 2))
        }
        return p
    }

    /// Topographic: wobbly contour lines rippling out from the corner.
    static func topographic(_ c: CGPoint, _ r: CGFloat) -> Path {
        var p = Path()
        for ring in 0..<9 {
            let base = r * CGFloat(0.12 + 0.11 * Double(ring))
            let phase = Double(ring) * 0.7
            for step in 0...180 {
                let t = Double(step) / 180 * 2 * .pi
                let wobble = 1 + 0.07 * sin(3 * t + phase) + 0.04 * sin(5 * t - phase * 1.3)
                let q = point(c, base * CGFloat(wobble), t)
                if step == 0 { p.move(to: q) } else { p.addLine(to: q) }
            }
            p.closeSubpath()
        }
        return p
    }

    /// Constellation: small stars, each joined to its nearest neighbors.
    static func constellation(_ c: CGPoint, _ r: CGFloat) -> Path {
        var p = Path()
        var rng = SeededRandom(seed: 7)
        var stars: [CGPoint] = []
        for _ in 0..<26 {
            let a = Double.pi / 2 + rng.next() * (Double.pi / 2)
            let d = r * CGFloat(0.12 + 0.86 * sqrt(rng.next()))
            stars.append(point(c, d, a))
        }
        for (i, s) in stars.enumerated() {
            let size = r * CGFloat(0.010 + 0.012 * rng.next())
            p.move(to: CGPoint(x: s.x, y: s.y - size)); p.addLine(to: CGPoint(x: s.x, y: s.y + size))
            p.move(to: CGPoint(x: s.x - size, y: s.y)); p.addLine(to: CGPoint(x: s.x + size, y: s.y))
            let nearest = stars.enumerated().filter { $0.offset != i }
                .sorted { hypot($0.element.x - s.x, $0.element.y - s.y) < hypot($1.element.x - s.x, $1.element.y - s.y) }
            for n in nearest.prefix(i.isMultiple(of: 3) ? 2 : 1) where n.offset > i {
                p.move(to: s); p.addLine(to: n.element)
            }
        }
        return p
    }

    /// Bloom: the Shelf flower as contour lines.
    static func bloom(_ c: CGPoint, _ r: CGFloat) -> Path {
        var p = Path()
        for ring in 0..<5 {
            let scale = 1 - 0.78 * pow(Double(ring) / 5, 0.85)
            for step in 0...240 {
                let t = Double(step) / 240 * 2 * .pi
                let petal = 0.5 + 0.5 * cos(5 * t)
                let shape = 0.62 + 0.38 * pow(petal, 0.8)
                let ripple = 0.035 * sin(3 * t + Double(ring) * 0.9)
                let q = point(c, r * 0.9 * CGFloat(scale * shape * (1 + ripple)), t - .pi / 2)
                if step == 0 { p.move(to: q) } else { p.addLine(to: q) }
            }
            p.closeSubpath()
        }
        return p
    }
}

/// Small deterministic generator, so constellations don't reshuffle.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 }
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53)
    }
}

// MARK: - View

/// Draws the chosen art from the top-right corner of its frame, with a
/// faint glow under fine lines, fading out with distance from the corner.
struct BackdropArtLayer: View {
    let art: BackdropArt
    var intensity: Double = 1
    var reach: CGFloat?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            let r = reach ?? min(560, max(280, geo.size.width * 0.5))
            let corner = CGPoint(x: geo.size.width, y: 0)
            let line = (scheme == .dark ? 0.26 : 0.20) * intensity
            let accent = Color.accent
            Canvas { context, _ in
                let width = max(0.9, r / 420)
                if art == .seigaiha {
                    Self.drawSeigaiha(&context, corner: corner, radius: r, color: accent.opacity(line), width: width)
                    return
                }
                let path = art.path(corner: corner, radius: r)
                context.drawLayer { glow in
                    glow.addFilter(.blur(radius: 3))
                    glow.stroke(path, with: .color(accent.opacity(line * 0.55)), lineWidth: width * 3)
                }
                context.stroke(path, with: .color(accent.opacity(line)),
                               style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            }
            .mask(
                RadialGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black.opacity(0.75), location: 0.35),
                        .init(color: .clear, location: 1),
                    ],
                    center: .topTrailing, startRadius: 0, endRadius: r * 1.02
                )
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Overlapping fans of concentric arcs; each row hides the one behind.
    static func drawSeigaiha(_ context: inout GraphicsContext, corner: CGPoint, radius r: CGFloat,
                             color: Color, width: CGFloat) {
        let s = max(36, r * 0.16)
        var y = corner.y - s
        var row = 0
        while y < corner.y + r {
            var x = corner.x - r - s + (row.isMultiple(of: 2) ? 0 : s / 2)
            while x < corner.x + s {
                let center = CGPoint(x: x, y: y + s / 2)
                let fan = Path { p in
                    p.addArc(center: center, radius: s / 2, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
                    p.closeSubpath()
                }
                context.blendMode = .destinationOut
                context.fill(fan, with: .color(.black))
                context.blendMode = .normal
                for f in [0.5, 0.36, 0.22] {
                    let arc = Path { p in
                        p.addArc(center: center, radius: s * f, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
                    }
                    context.stroke(arc, with: .color(color), lineWidth: width)
                }
                x += s
            }
            y += s / 4
            row += 1
        }
    }
}
