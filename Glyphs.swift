import SwiftUI

/// Simple vector drawings of a crab, lobster and fish (no image assets needed).
enum GlyphDrawing {
    static func point(_ rect: CGRect, _ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
    }

    // MARK: Crab (top view). Spine tips at (0.06, 0.50) and (0.94, 0.50).

    static func crabCarapace(_ r: CGRect) -> Path {
        var path = Path()
        path.move(to: point(r, 0.06, 0.50))
        path.addLine(to: point(r, 0.27, 0.43))
        path.addQuadCurve(to: point(r, 0.50, 0.33), control: point(r, 0.36, 0.33))
        path.addQuadCurve(to: point(r, 0.73, 0.43), control: point(r, 0.64, 0.33))
        path.addLine(to: point(r, 0.94, 0.50))
        path.addLine(to: point(r, 0.72, 0.53))
        path.addQuadCurve(to: point(r, 0.50, 0.68), control: point(r, 0.66, 0.67))
        path.addQuadCurve(to: point(r, 0.28, 0.53), control: point(r, 0.34, 0.67))
        path.closeSubpath()
        return path
    }

    static func crabLimbs(_ r: CGRect) -> Path {
        var path = Path()
        // arms to the claws
        path.move(to: point(r, 0.34, 0.41)); path.addLine(to: point(r, 0.23, 0.31)); path.addLine(to: point(r, 0.19, 0.24))
        path.move(to: point(r, 0.66, 0.41)); path.addLine(to: point(r, 0.77, 0.31)); path.addLine(to: point(r, 0.81, 0.24))
        // three walking legs and the swimming leg on each side
        let legs: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (0.30, 0.55, 0.14, 0.60, 0.08, 0.70),
            (0.32, 0.58, 0.18, 0.68, 0.14, 0.80),
            (0.36, 0.62, 0.25, 0.75, 0.23, 0.87),
            (0.42, 0.65, 0.39, 0.72, 0.375, 0.76),
        ]
        for leg in legs {
            path.move(to: point(r, leg.0, leg.1)); path.addLine(to: point(r, leg.2, leg.3)); path.addLine(to: point(r, leg.4, leg.5))
            path.move(to: point(r, 1 - leg.0, leg.1)); path.addLine(to: point(r, 1 - leg.2, leg.3)); path.addLine(to: point(r, 1 - leg.4, leg.5))
        }
        return path
    }

    /// Pincer claws plus the paddle-shaped swimming legs.
    static func crabClaws(_ r: CGRect) -> Path {
        var path = Path()
        for mirrored in [false, true] {
            func q(_ x: CGFloat, _ y: CGFloat) -> CGPoint { point(r, mirrored ? 1 - x : x, y) }
            path.move(to: q(0.13, 0.26))
            path.addQuadCurve(to: q(0.07, 0.05), control: q(0.05, 0.16))
            path.addQuadCurve(to: q(0.15, 0.15), control: q(0.13, 0.08))
            path.addQuadCurve(to: q(0.21, 0.03), control: q(0.17, 0.07))
            path.addQuadCurve(to: q(0.25, 0.21), control: q(0.27, 0.10))
            path.addQuadCurve(to: q(0.13, 0.26), control: q(0.21, 0.29))
            path.closeSubpath()
            let paddleX: CGFloat = mirrored ? 1 - 0.33 - 0.09 : 0.33
            path.addEllipse(in: CGRect(origin: point(r, paddleX, 0.74),
                                       size: CGSize(width: r.width * 0.09, height: r.height * 0.13)))
        }
        return path
    }

    // MARK: Fish (side view). Snout (0.06, 0.50), tail tip x = 0.95.

    static func fishBody(_ r: CGRect) -> Path {
        var path = Path()
        path.move(to: point(r, 0.06, 0.50))
        path.addQuadCurve(to: point(r, 0.70, 0.50), control: point(r, 0.36, 0.14))
        path.addQuadCurve(to: point(r, 0.06, 0.50), control: point(r, 0.36, 0.86))
        path.closeSubpath()
        // tail
        path.move(to: point(r, 0.66, 0.50))
        path.addLine(to: point(r, 0.95, 0.28))
        path.addQuadCurve(to: point(r, 0.95, 0.72), control: point(r, 0.85, 0.50))
        path.closeSubpath()
        // dorsal fin
        path.move(to: point(r, 0.30, 0.33))
        path.addQuadCurve(to: point(r, 0.55, 0.36), control: point(r, 0.40, 0.18))
        path.closeSubpath()
        return path
    }

    static func fishEye(_ r: CGRect) -> Path {
        Path(ellipseIn: CGRect(origin: point(r, 0.15, 0.42), size: CGSize(width: r.width * 0.06, height: r.width * 0.06)))
    }

    // MARK: Lobster (top view). Carapace from (0.17, 0.5) to (0.55, 0.5).

    static func lobsterBody(_ r: CGRect) -> Path {
        var path = Path()
        path.addEllipse(in: CGRect(origin: point(r, 0.15, 0.37), size: CGSize(width: r.width * 0.42, height: r.height * 0.26)))
        var x: CGFloat = 0.55
        var height: CGFloat = 0.22
        for _ in 0..<5 {
            path.addRoundedRect(in: CGRect(origin: point(r, x, 0.5 - height / 2),
                                           size: CGSize(width: r.width * 0.065, height: r.height * height)),
                                cornerSize: CGSize(width: 3, height: 3))
            x += 0.06
            height -= 0.02
        }
        path.move(to: point(r, 0.85, 0.50))
        path.addLine(to: point(r, 0.98, 0.36))
        path.addLine(to: point(r, 0.98, 0.64))
        path.closeSubpath()
        return path
    }

    static func lobsterAntennae(_ r: CGRect) -> Path {
        var path = Path()
        path.move(to: point(r, 0.17, 0.44)); path.addQuadCurve(to: point(r, 0.02, 0.06), control: point(r, 0.02, 0.36))
        path.move(to: point(r, 0.17, 0.56)); path.addQuadCurve(to: point(r, 0.02, 0.94), control: point(r, 0.02, 0.64))
        // legs
        for i in 0..<4 {
            let x = 0.26 + CGFloat(i) * 0.07
            path.move(to: point(r, x, 0.40)); path.addLine(to: point(r, x - 0.03, 0.24))
            path.move(to: point(r, x, 0.60)); path.addLine(to: point(r, x - 0.03, 0.76))
        }
        return path
    }

    // MARK: Stone crab claw (side view). Fixed finger tip (0.93, 0.60), first joint (0.30, 0.60).

    static func claw(_ r: CGRect) -> Path {
        var path = Path()
        // palm (propodus)
        path.move(to: point(r, 0.28, 0.40))
        path.addQuadCurve(to: point(r, 0.70, 0.36), control: point(r, 0.50, 0.24))
        path.addLine(to: point(r, 0.70, 0.56))
        path.addLine(to: point(r, 0.93, 0.60))     // fixed finger
        path.addQuadCurve(to: point(r, 0.62, 0.72), control: point(r, 0.80, 0.72))
        path.addQuadCurve(to: point(r, 0.28, 0.66), control: point(r, 0.42, 0.80))
        path.closeSubpath()
        // movable finger (dactyl)
        path.move(to: point(r, 0.68, 0.38))
        path.addQuadCurve(to: point(r, 0.94, 0.52), control: point(r, 0.88, 0.30))
        path.addLine(to: point(r, 0.70, 0.50))
        path.closeSubpath()
        // forearm stub
        path.addRect(CGRect(origin: point(r, 0.10, 0.46), size: CGSize(width: r.width * 0.19, height: r.height * 0.14)))
        return path
    }

    static func draw(_ group: SpeciesGroup, speciesID: String? = nil, in rect: CGRect,
                     context: inout GraphicsContext, color: Color, detail: Color) {
        let line = max(1.2, rect.width * 0.035)
        if speciesID == "stone_crab" && rect.width > 120 {
            context.fill(claw(rect), with: .color(color))
            return
        }
        switch group {
        case .crab:
            context.stroke(crabLimbs(rect), with: .color(color), style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round))
            context.fill(crabClaws(rect), with: .color(color))
            context.fill(crabCarapace(rect), with: .color(color))
        case .lobster:
            context.stroke(lobsterAntennae(rect), with: .color(color), style: StrokeStyle(lineWidth: line * 0.8, lineCap: .round))
            context.fill(lobsterBody(rect), with: .color(color))
        case .fish:
            context.fill(fishBody(rect), with: .color(color))
            context.fill(fishEye(rect), with: .color(detail))
        }
    }
}

/// Round species badge used in lists and cards.
struct SpeciesGlyph: View {
    let species: Species
    var size: CGFloat = 44
    var muted = false

    var body: some View {
        let tint = muted ? Color.gray.opacity(0.55) : species.color
        ZStack {
            Circle().fill(tint.opacity(muted ? 0.12 : 0.16))
            Canvas { context, canvasSize in
                let inset = canvasSize.width * 0.16
                let rect = CGRect(x: inset, y: inset, width: canvasSize.width - inset * 2, height: canvasSize.height - inset * 2)
                GlyphDrawing.draw(species.group, in: rect, context: &context, color: tint, detail: Color(.systemBackground))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Large "how to measure" diagram with the measuring line drawn on top.
struct MeasureDiagram: View {
    let species: Species
    var height: CGFloat = 150

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(x: 12, y: 8, width: size.width - 24, height: size.height - 16)
            let isClaw = species.measurement == .clawLength
            GlyphDrawing.draw(species.group, speciesID: isClaw ? "stone_crab" : nil, in: rect,
                              context: &context, color: species.color.opacity(0.85), detail: Color(.systemBackground))

            let ends: (CGPoint, CGPoint)
            switch species.measurement {
            case .carapaceWidth:
                ends = (GlyphDrawing.point(rect, 0.06, 0.50), GlyphDrawing.point(rect, 0.94, 0.50))
            case .carapaceLength:
                ends = (GlyphDrawing.point(rect, 0.17, 0.50), GlyphDrawing.point(rect, 0.55, 0.50))
            case .clawLength:
                ends = (GlyphDrawing.point(rect, 0.30, 0.86), GlyphDrawing.point(rect, 0.93, 0.86))
            case .totalLength:
                ends = (GlyphDrawing.point(rect, 0.06, 0.92), GlyphDrawing.point(rect, 0.95, 0.92))
            case .forkLength:
                ends = (GlyphDrawing.point(rect, 0.06, 0.92), GlyphDrawing.point(rect, 0.86, 0.92))
            }
            var arrow = Path()
            arrow.move(to: ends.0)
            arrow.addLine(to: ends.1)
            let tick: CGFloat = 9
            for end in [ends.0, ends.1] {
                arrow.move(to: CGPoint(x: end.x, y: end.y - tick))
                arrow.addLine(to: CGPoint(x: end.x, y: end.y + tick))
            }
            context.stroke(arrow, with: .color(Theme.measure), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            for end in [ends.0, ends.1] {
                context.fill(Path(ellipseIn: CGRect(x: end.x - 4, y: end.y - 4, width: 8, height: 8)), with: .color(Theme.measure))
            }
        }
        .frame(height: height)
        .accessibilityLabel("Diagram: \(species.measurementLabel)")
    }
}
