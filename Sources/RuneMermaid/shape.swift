// Ported from: crates/rune-mermaid/src/shape.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Flowchart node shapes: every Mermaid v11 shape, its size around a label, its outline (what
//! edges meet and hovering lights up) and its drawing.

import Rune

enum NodeShape: Sendable, Equatable, Hashable {
    case rect
    case round
    case stadium
    case subroutine
    case cylinder
    case circle
    case doubleCircle
    case asymmetric
    case diamond
    case hexagon
    /// `[/text/]`
    case leanRight
    /// `[\text\]`
    case leanLeft
    /// `[/text\]`, wider at the bottom.
    case trapBottom
    /// `[\text/]`, wider at the top.
    case trapTop
    case smallCircle
    case filledCircle
    case framedCircle
    case crossedCircle
    case bang
    case cloud
    case card
    case hourglass
    case bolt
    case braceLeft
    case braceRight
    case braces
    case delay
    case hCylinder
    case linedCylinder
    case curvedTrapezoid
    case dividedRect
    case document
    case linedDocument
    case documents
    case taggedDocument
    case triangle
    case flippedTriangle
    case fork
    case windowPane
    case linedRect
    case notchedPentagon
    case slopedRect
    case stackedRect
    case flag
    case bowRect
    case taggedRect
    case text
    /// A sticky note with a folded corner, in the note colours.
    case note

    /// The shape a Mermaid `@{ shape: … }` name stands for, by short name or alias.
    static func named(_ name: String) -> NodeShape? {
        switch name {
        case "rect", "proc", "process", "rectangle", "icon", "image": return .rect
        case "rounded", "event": return .round
        case "stadium", "pill", "terminal": return .stadium
        case "fr-rect", "framed-rectangle", "subproc", "subprocess", "subroutine": return .subroutine
        case "cyl", "cylinder", "database", "db": return .cylinder
        case "circle", "circ": return .circle
        case "dbl-circ", "double-circle": return .doubleCircle
        case "odd": return .asymmetric
        case "diam", "decision", "diamond", "question": return .diamond
        case "hex", "hexagon", "prepare": return .hexagon
        case "lean-r", "lean-right", "in-out": return .leanRight
        case "lean-l", "lean-left", "out-in": return .leanLeft
        case "trap-b", "priority", "trapezoid", "trapezoid-bottom": return .trapBottom
        case "trap-t", "inv-trapezoid", "manual", "trapezoid-top": return .trapTop
        case "sm-circ", "small-circle", "start": return .smallCircle
        case "f-circ", "filled-circle", "junction": return .filledCircle
        case "fr-circ", "framed-circle", "stop": return .framedCircle
        case "cross-circ", "crossed-circle", "summary": return .crossedCircle
        case "bang": return .bang
        case "cloud": return .cloud
        case "notch-rect", "card", "notched-rectangle": return .card
        case "hourglass", "collate": return .hourglass
        case "bolt", "com-link", "lightning-bolt": return .bolt
        case "brace", "brace-l", "comment": return .braceLeft
        case "brace-r": return .braceRight
        case "braces": return .braces
        case "delay", "half-rounded-rectangle": return .delay
        case "h-cyl", "das", "horizontal-cylinder": return .hCylinder
        case "lin-cyl", "disk", "lined-cylinder": return .linedCylinder
        case "curv-trap", "curved-trapezoid", "display": return .curvedTrapezoid
        case "div-rect", "div-proc", "divided-process", "divided-rectangle": return .dividedRect
        case "doc", "document": return .document
        case "lin-doc", "lined-document": return .linedDocument
        case "docs", "documents", "st-doc", "stacked-document": return .documents
        case "tag-doc", "tagged-document": return .taggedDocument
        case "tri", "extract", "triangle": return .triangle
        case "flip-tri", "flipped-triangle", "manual-file": return .flippedTriangle
        case "fork", "join": return .fork
        case "win-pane", "internal-storage", "window-pane": return .windowPane
        case "lin-rect", "lin-proc", "lined-process", "lined-rectangle", "shaded-process": return .linedRect
        case "notch-pent", "loop-limit", "notched-pentagon": return .notchedPentagon
        case "sl-rect", "manual-input", "sloped-rectangle": return .slopedRect
        case "st-rect", "processes", "procs", "stacked-rectangle": return .stackedRect
        case "flag", "paper-tape": return .flag
        case "bow-rect", "bow-tie-rectangle", "stored-data": return .bowRect
        case "tag-rect", "tag-proc", "tagged-process", "tagged-rectangle": return .taggedRect
        case "text": return .text
        default: return nil
        }
    }

    /// Markers too small to hold their label, which they don't draw.
    func unlabelled() -> Bool {
        switch self {
        case .smallCircle, .filledCircle, .framedCircle, .crossedCircle, .fork:
            return true
        default:
            return false
        }
    }

    /// Shapes whose side facing the next rank is straight, so edges can meet it anywhere along it.
    func flat() -> Bool {
        switch self {
        case .stadium, .cylinder, .circle, .doubleCircle, .diamond, .hexagon,
             .leanRight, .leanLeft, .trapBottom, .trapTop, .smallCircle, .filledCircle,
             .framedCircle, .crossedCircle, .bang, .cloud, .linedCylinder, .triangle, .flippedTriangle:
            return false
        default:
            return true
        }
    }
}

private let PAD: [Float] = [30.0, 22.0]
private let GLYPH: Float = 32.0
/// How far a stacked shape's back copies sit up and to the right.
private let STACK: Float = 5.0
/// How far a lined cylinder's second rim sits below its first.
private let LINED: Float = 6.0

func nodeSize(_ shape: NodeShape, _ t: [Float]) -> [Float] {
    let w = t[0] + PAD[0]
    let h = max(t[1] + PAD[1], 40.0)
    let rect = max(w, 60.0)
    switch shape {
    case .rect, .round, .taggedRect, .note:
        return [rect, h]
    case .stadium, .hexagon:
        return [w + h / 2.0, h]
    case .subroutine, .linedRect, .card:
        return [w + 16.0, h]
    case .asymmetric:
        return [w + h / 3.0, h]
    case .cylinder:
        return [rect, h + 3.0 * shapeRim(rect)]
    case .linedCylinder:
        return [rect, h + 3.0 * shapeRim(rect) + LINED]
    case .hCylinder:
        return [w + 24.0, h]
    case .leanRight, .leanLeft, .trapBottom, .trapTop:
        return [w + h * 0.6, h]
    case .circle:
        return circleSize(t, 20.0)
    case .doubleCircle:
        return circleSize(t, 30.0)
    case .diamond:
        let a = t[0] / 2.0 + t[1] + 12.0
        let b = t[1] / 2.0 * a / (t[1] + 12.0) + 10.0
        return [2.0 * a, max(2.0 * b, 40.0)]
    case .smallCircle, .filledCircle:
        return [14.0, 14.0]
    case .framedCircle:
        return [20.0, 20.0]
    case .crossedCircle:
        return [30.0, 30.0]
    case .fork:
        return [70.0, 10.0]
    case .bang:
        return [w * 1.5, h * 1.7]
    case .cloud:
        return [w * 1.35, h * 1.55]
    case .hourglass, .bolt:
        return [max(t[0], GLYPH), t[1] > 0.0 ? GLYPH + 6.0 + t[1] : GLYPH]
    case .braceLeft, .braceRight:
        return [w + 6.0, h]
    case .braces:
        return [w + 18.0, h]
    case .delay, .curvedTrapezoid, .bowRect:
        return [w + h / 2.0, h]
    case .dividedRect:
        return [rect, h + 10.0]
    case .document, .linedDocument, .taggedDocument, .flag, .slopedRect:
        return [rect + 8.0, h + 12.0]
    case .documents:
        return [rect + 8.0 + 2.0 * STACK, h + 12.0 + 2.0 * STACK]
    case .stackedRect:
        return [rect + 2.0 * STACK, h + 2.0 * STACK]
    case .triangle, .flippedTriangle:
        let tw = 1.6 * (t[0] + 16.0)
        return [max(tw, 60.0), max(0.7 * tw, 3.0 * t[1] + 16.0)]
    case .windowPane:
        return [rect + 10.0, h + 10.0]
    case .notchedPentagon:
        return [w + 24.0, h]
    case .text:
        return [t[0] + 12.0, t[1] + 12.0]
    }
}

/// How deep a cylinder `w` wide draws its rims: half their height, in Mermaid's proportion.
func shapeRim(_ w: Float) -> Float {
    w / 2.0 / (2.5 + w / 50.0)
}

private func circleSize(_ t: [Float], _ pad: Float) -> [Float] {
    let d = max((t[0] * t[0] + t[1] * t[1]).squareRoot() + pad, 48.0)
    return [d, d]
}

/// Where the line from `c` toward `toward` leaves a node of `shape` and `size` centred at `c`.
func boundary(_ shape: NodeShape, _ c: [Float], _ size: [Float], _ toward: [Float]) -> [Float] {
    let dx = toward[0] - c[0]
    let dy = toward[1] - c[1]
    if abs(dx) < 1e-3 && abs(dy) < 1e-3 {
        return c
    }
    let a = size[0] / 2.0
    let b = size[1] / 2.0
    func rectT() -> Float {
        let tx: Float = abs(dx) > 1e-3 ? a / abs(dx) : .greatestFiniteMagnitude
        let ty: Float = abs(dy) > 1e-3 ? b / abs(dy) : .greatestFiniteMagnitude
        return min(tx, ty)
    }
    let rawT: Float
    switch shape {
    case .circle, .doubleCircle, .smallCircle, .filledCircle, .framedCircle, .crossedCircle:
        let qa = dx / a
        let qb = dy / b
        rawT = 1.0 / (qa * qa + qb * qb).squareRoot()
    case .diamond:
        rawT = 1.0 / (abs(dx) / a + abs(dy) / b)
    case .rect, .round, .subroutine, .asymmetric, .stadium, .hexagon, .cylinder,
         .leanRight, .leanLeft, .trapBottom, .trapTop, .hourglass, .bolt,
         .braceLeft, .braceRight, .braces, .text:
        rawT = rectT()
    default:
        rawT = rayExit(outline(shape, c, size), c, [dx, dy]) ?? rectT()
    }
    let t = min(rawT, 1.0)
    return [c[0] + dx * t, c[1] + dy * t]
}

/// The furthest `t` at which `c + t·d` crosses `poly`.
private func rayExit(_ poly: [[Float]], _ c: [Float], _ d: [Float]) -> Float? {
    guard !poly.isEmpty else { return nil }
    var best: Float? = nil
    for i in 0..<poly.count {
        let p = poly[i]
        let q = poly[(i + 1) % poly.count]
        let e = [q[0] - p[0], q[1] - p[1]]
        let den = d[0] * e[1] - d[1] * e[0]
        if abs(den) < 1e-9 {
            continue
        }
        let w = [p[0] - c[0], p[1] - c[1]]
        let t = (w[0] * e[1] - w[1] * e[0]) / den
        let u = (w[0] * d[1] - w[1] * d[0]) / den
        if t > 0.0 && u >= 0.0 && u <= 1.0 && (best == nil || t > best!) {
            best = t
        }
    }
    return best
}

private func shapeBounds(_ c: [Float], _ s: [Float]) -> (Float, Float, Float, Float) {
    (c[0] - s[0] / 2.0, c[1] - s[1] / 2.0, c[0] + s[0] / 2.0, c[1] + s[1] / 2.0)
}

private func shapeRect(_ x0: Float, _ y0: Float, _ x1: Float, _ y1: Float) -> [[Float]] {
    [[x0, y0], [x1, y0], [x1, y1], [x0, y1]]
}

/// A wavy line from `x0` to `x1` around `y`, one and a half periods long.
private func wave(_ x0: Float, _ x1: Float, _ y: Float, _ amp: Float) -> [[Float]] {
    let n = 24
    let tau: Float = 2.0 * .pi
    return (0...n).map { i in
        let f = Float(i) / Float(n)
        return [x0 + (x1 - x0) * f, y + amp * mSin(f * tau * 1.5)]
    }
}

/// A quadratic Bézier from `a` through control `k` to `b`, as points.
private func quad(_ a: [Float], _ k: [Float], _ b: [Float]) -> [[Float]] {
    (0...8).map { i in
        let t = Float(i) / 8.0
        let m = 1.0 - t
        return [
            m * m * a[0] + 2.0 * m * t * k[0] + t * t * b[0],
            m * m * a[1] + 2.0 * m * t * k[1] + t * t * b[1],
        ]
    }
}

/// A curly brace down the line `x` from `y0` to `y1`, its point toward `side` (-1 left, 1 right).
private func brace(_ x: Float, _ y0: Float, _ y1: Float, _ side: Float) -> [[Float]] {
    let r: Float = 6.0
    let cy = (y0 + y1) / 2.0
    var p = quad([x - side * r, y0], [x, y0], [x, y0 + r])
    p.append(contentsOf: quad([x, cy - r], [x, cy], [x + side * r, cy]))
    p.append(contentsOf: quad([x + side * r, cy], [x, cy], [x, cy + r]))
    p.append(contentsOf: quad([x, y1 - r], [x, y1], [x - side * r, y1]))
    return p
}

/// A document's outline: a box whose bottom edge waves.
private func documentPoly(_ x0: Float, _ y0: Float, _ x1: Float, _ y1: Float) -> [[Float]] {
    var p: [[Float]] = [[x0, y0], [x1, y0]]
    p.append(contentsOf: wave(x1, x0, y1 - 6.0, 5.0))
    return p
}

/// The glyph's box for shapes drawn as a glyph over their label.
private func glyphBox(_ c: [Float], _ s: [Float]) -> (Float, Float, Float, Float) {
    let y0 = c[1] - s[1] / 2.0
    return (c[0] - GLYPH / 2.0, y0, c[0] + GLYPH / 2.0, y0 + GLYPH)
}

func outline(_ shape: NodeShape, _ c: [Float], _ s: [Float]) -> [[Float]] {
    let (x0, y0, x1, y1) = shapeBounds(c, s)
    let h = s[1]
    let cy = c[1]
    switch shape {
    case .rect, .subroutine, .dividedRect, .linedRect, .windowPane, .taggedRect:
        return roundedRect(x0, y0, x1, y1, 3.0)
    case .round:
        return roundedRect(x0, y0, x1, y1, 10.0)
    case .stadium:
        return roundedRect(x0, y0, x1, y1, h / 2.0)
    case .circle, .doubleCircle, .smallCircle, .filledCircle, .framedCircle, .crossedCircle:
        return ellipse(c, s[0] / 2.0, s[1] / 2.0)
    case .diamond:
        return [[c[0], y0], [x1, cy], [c[0], y1], [x0, cy]]
    case .hexagon:
        let i = h / 4.0
        return [[x0 + i, y0], [x1 - i, y0], [x1, cy], [x1 - i, y1], [x0 + i, y1], [x0, cy]]
    case .asymmetric:
        return [[x0, y0], [x1, y0], [x1, y1], [x0, y1], [x0 + h / 3.0, cy]]
    case .leanRight:
        return [[x0 + h * 0.3, y0], [x1, y0], [x1 - h * 0.3, y1], [x0, y1]]
    case .leanLeft:
        return [[x0, y0], [x1 - h * 0.3, y0], [x1, y1], [x0 + h * 0.3, y1]]
    case .trapBottom:
        return [[x0 + h * 0.3, y0], [x1 - h * 0.3, y0], [x1, y1], [x0, y1]]
    case .trapTop:
        return [[x0, y0], [x1, y0], [x1 - h * 0.3, y1], [x0 + h * 0.3, y1]]
    case .cylinder, .linedCylinder:
        let rx = s[0] / 2.0
        let ry = shapeRim(s[0])
        var pts = arc([c[0], y0 + ry], rx, ry, 180.0, 360.0, 20)
        pts.append(contentsOf: arc([c[0], y1 - ry], rx, ry, 0.0, 180.0, 20))
        return pts
    case .hCylinder:
        let rx: Float = 8.0
        let ry = h / 2.0
        var pts = arc([x1 - rx, cy], rx, ry, -90.0, 90.0, 20)
        pts.append(contentsOf: arc([x0 + rx, cy], rx, ry, 90.0, 270.0, 20))
        return pts
    case .bang:
        return (0..<28).map { i in
            let a = degToRad(Float(i) * 360.0 / 28.0)
            let r: Float = (i % 2 == 0) ? 1.0 : 0.8
            return [c[0] + s[0] / 2.0 * r * mCos(a), cy + s[1] / 2.0 * r * mSin(a)]
        }
    case .cloud:
        return (0..<120).map { i in
            let a = degToRad(Float(i) * 3.0)
            let r: Float = 0.84 + 0.16 * abs(mSin(5.0 * a)).squareRoot()
            return [c[0] + s[0] / 2.0 * r * mCos(a), cy + s[1] / 2.0 * r * mSin(a)]
        }
    case .card:
        return [[x0 + 12.0, y0], [x1, y0], [x1, y1], [x0, y1], [x0, y0 + 12.0]]
    case .note:
        return [[x0, y0], [x1 - 10.0, y0], [x1, y0 + 10.0], [x1, y1], [x0, y1]]
    case .notchedPentagon:
        return [[x0 + 12.0, y0], [x1 - 12.0, y0], [x1, y0 + 12.0], [x1, y1], [x0, y1], [x0, y0 + 12.0]]
    case .slopedRect:
        return [[x0, y0 + 12.0], [x1, y0], [x1, y1], [x0, y1]]
    case .delay:
        var p: [[Float]] = [[x0, y0]]
        p.append(contentsOf: arc([x1 - h / 2.0, cy], h / 2.0, h / 2.0, -90.0, 90.0, 16))
        p.append([x0, y1])
        return p
    case .curvedTrapezoid:
        let k = h / 4.0
        var p: [[Float]] = [[x0 + k, y0]]
        p.append(contentsOf: arc([x1 - h / 2.0, cy], h / 2.0, h / 2.0, -90.0, 90.0, 16))
        p.append(contentsOf: quad([x0 + k, y1], [x0, y1], [x0, cy]))
        p.append(contentsOf: quad([x0, cy], [x0, y0], [x0 + k, y0]))
        return p
    case .bowRect:
        let rx = h / 4.0
        var p = arc([x1, cy], rx, h / 2.0, 270.0, 90.0, 16)
        p.append(contentsOf: arc([x0 + rx, cy], rx, h / 2.0, 90.0, 270.0, 16))
        return p
    case .document, .linedDocument, .taggedDocument:
        return documentPoly(x0, y0, x1, y1)
    case .documents:
        return documentPoly(x0, y0 + 2.0 * STACK, x1 - 2.0 * STACK, y1)
    case .stackedRect:
        return shapeRect(x0, y0 + 2.0 * STACK, x1 - 2.0 * STACK, y1)
    case .flag:
        var p = wave(x0, x1, y0 + 6.0, 5.0)
        p.append(contentsOf: wave(x1, x0, y1 - 6.0, 5.0))
        return p
    case .triangle:
        return [[c[0], y0], [x1, y1], [x0, y1]]
    case .flippedTriangle:
        return [[x0, y0], [x1, y0], [c[0], y1]]
    case .fork:
        return roundedRect(x0, y0, x1, y1, 2.0)
    case .hourglass, .bolt, .braceLeft, .braceRight, .braces, .text:
        return shapeRect(x0, y0, x1, y1)
    }
}

/// A cylinder's open end, a shade off its side so the shape reads even without an outline.
private func lid(_ fill: Color, _ paint: DiagramStyle) -> Color {
    overColor(paint.text.alpha(0.06), fill)
}

/// Draws a node of `shape` at `ctr` with its label, in `fill`, `border` and `text` colours.
func drawShape(
    _ c: inout Canvas,
    _ shape: NodeShape,
    _ label: Measured,
    _ ctr: [Float],
    _ size: [Float],
    _ colors: [Color],
    _ paint: DiagramStyle
) {
    let fill = colors[0]
    let border = colors[1]
    let textCol = colors[2]
    let (x0, y0, x1, y1) = shapeBounds(ctr, size)
    let h = size[1]
    func line(_ c: inout Canvas, _ pts: [[Float]]) {
        c.stroke(pts, false, 1.0, border)
    }
    var at = ctr
    switch shape {
    case .text:
        break
    case .braceLeft:
        c.stroke(brace(x0 + 6.0, y0 + 2.0, y1 - 2.0, -1.0), false, 1.25, border)
        at[0] += 3.0
    case .braceRight:
        c.stroke(brace(x1 - 6.0, y0 + 2.0, y1 - 2.0, 1.0), false, 1.25, border)
        at[0] -= 3.0
    case .braces:
        c.stroke(brace(x0 + 6.0, y0 + 2.0, y1 - 2.0, -1.0), false, 1.25, border)
        c.stroke(brace(x1 - 6.0, y0 + 2.0, y1 - 2.0, 1.0), false, 1.25, border)
    case .filledCircle, .fork:
        c.fill(outline(shape, ctr, size), paint.line)
    case .framedCircle:
        c.shape(outline(shape, ctr, size), fill, paint.line, 1.5)
        c.fill(ellipse(ctr, 5.5, 5.5), paint.line)
    case .hourglass:
        let (g0, gy0, g1, gy1) = glyphBox(ctr, size)
        let mid = [ctr[0], (gy0 + gy1) / 2.0]
        c.shape([[g0, gy0], [g1, gy0], mid, [g1, gy1], [g0, gy1], mid], fill, border, 1.0)
        at[1] = gy1 + 6.0 + label.size[1] / 2.0
    case .bolt:
        let (g0, gy0, _, _) = glyphBox(ctr, size)
        func p(_ x: Float, _ y: Float) -> [Float] { [g0 + x * GLYPH, gy0 + y * GLYPH] }
        c.shape([p(0.6, 0.0), p(0.15, 0.58), p(0.45, 0.58), p(0.35, 1.0), p(0.85, 0.4), p(0.55, 0.4), p(0.75, 0.0)], fill, border, 1.0)
        at[1] = gy0 + GLYPH + 6.0 + label.size[1] / 2.0
    case .documents:
        for k: Float in [2.0, 1.0] {
            let d = k * STACK
            c.shape(documentPoly(x0 + d, y0 + 2.0 * STACK - d, x1 - 2.0 * STACK + d, y1 - d), fill, border, 1.0)
        }
        c.shape(outline(shape, ctr, size), fill, border, 1.0)
        at = [ctr[0] - STACK, ctr[1] + STACK - 3.0]
    case .stackedRect:
        for k: Float in [2.0, 1.0] {
            let d = k * STACK
            c.shape(shapeRect(x0 + d, y0 + 2.0 * STACK - d, x1 - 2.0 * STACK + d, y1 - d), fill, border, 1.0)
        }
        c.shape(outline(shape, ctr, size), fill, border, 1.0)
        at = [ctr[0] - STACK, ctr[1] + STACK]
    case .note:
        c.shape(outline(shape, ctr, size), paint.noteFill, paint.noteBorder, 1.0)
        c.stroke([[x1 - 10.0, y0], [x1 - 10.0, y0 + 10.0], [x1, y0 + 10.0]], false, 1.0, paint.noteBorder)
    default:
        c.shape(outline(shape, ctr, size), fill, border, 1.0)
        switch shape {
        case .subroutine:
            line(&c, [[x0 + 8.0, y0], [x0 + 8.0, y1]])
            line(&c, [[x1 - 8.0, y0], [x1 - 8.0, y1]])
        case .cylinder:
            let ry = shapeRim(size[0])
            c.shape(ellipse([ctr[0], y0 + ry], size[0] / 2.0, ry), lid(fill, paint), border, 1.0)
            at[1] += ry / 2.0
        case .linedCylinder:
            let ry = shapeRim(size[0])
            c.shape(ellipse([ctr[0], y0 + ry], size[0] / 2.0, ry), lid(fill, paint), border, 1.0)
            line(&c, arc([ctr[0], y0 + ry + LINED], size[0] / 2.0, ry, 0.0, 180.0, 24))
            at[1] += (ry + LINED) / 2.0
        case .hCylinder:
            c.shape(ellipse([x1 - 8.0, ctr[1]], 8.0, h / 2.0), lid(fill, paint), border, 1.0)
            at[0] -= 4.0
        case .doubleCircle:
            c.stroke(ellipse(ctr, size[0] / 2.0 - 5.0, size[1] / 2.0 - 5.0), true, 1.0, border)
        case .crossedCircle:
            let frac1Sqrt2: Float = 0.70710678
            let r = size[0] / 2.0 * frac1Sqrt2
            line(&c, [[ctr[0] - r, ctr[1] - r], [ctr[0] + r, ctr[1] + r]])
            line(&c, [[ctr[0] - r, ctr[1] + r], [ctr[0] + r, ctr[1] - r]])
        case .dividedRect:
            line(&c, [[x0, y0 + 10.0], [x1, y0 + 10.0]])
            at[1] += 5.0
        case .linedRect:
            line(&c, [[x0 + 8.0, y0], [x0 + 8.0, y1]])
            at[0] += 4.0
        case .windowPane:
            line(&c, [[x0 + 10.0, y0], [x0 + 10.0, y1]])
            line(&c, [[x0, y0 + 10.0], [x1, y0 + 10.0]])
            at = [at[0] + 5.0, at[1] + 5.0]
        case .taggedRect:
            line(&c, [[x1 - 12.0, y1], [x1, y1 - 12.0]])
        case .linedDocument:
            line(&c, [[x0 + 8.0, y0], [x0 + 8.0, y1 - 6.0]])
            at = [at[0] + 4.0, at[1] - 3.0]
        case .taggedDocument:
            line(&c, [[x1 - 14.0, y1 - 4.0], [x1, y1 - 16.0]])
            at[1] -= 3.0
        case .document:
            at[1] -= 3.0
        case .slopedRect:
            at[1] += 6.0
        case .curvedTrapezoid:
            at[0] -= h / 8.0
        case .delay:
            at[0] -= h / 6.0
        case .card:
            at[0] += 4.0
        case .triangle:
            at[1] = y0 + 0.68 * h
        case .flippedTriangle:
            at[1] = y0 + 0.32 * h
        default:
            break
        }
    }
    if !shape.unlabelled() {
        c.label(label, at, paint.font, textCol, .center)
    }
}
