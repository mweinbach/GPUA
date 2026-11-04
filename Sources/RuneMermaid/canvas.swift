// Ported from: crates/rune-mermaid/src/canvas.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Vector canvas, text measurement, geometry primitives and scene assembly for [`render`].

#if canImport(Darwin)
import Darwin
#elseif canImport(Android)
import Android
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(CRT)
import CRT
#elseif canImport(WASILibc)
import WASILibc
#endif

import Rune

// MARK: - Cross-Platform Math Helpers

@inline(__always)
func mSin(_ x: Float) -> Float {
    Float(sin(Double(x)))
}

@inline(__always)
func mCos(_ x: Float) -> Float {
    Float(cos(Double(x)))
}

@inline(__always)
func mAtan2(_ y: Float, _ x: Float) -> Float {
    Float(atan2(Double(y), Double(x)))
}

@inline(__always)
func mPow(_ x: Float, _ y: Float) -> Float {
    Float(pow(Double(x), Double(y)))
}

@inline(__always)
func mPowD(_ x: Double, _ y: Double) -> Double {
    pow(x, y)
}

@inline(__always)
func mLog10D(_ x: Double) -> Double {
    log10(x)
}

@inline(__always)
func mHypot(_ x: Float, _ y: Float) -> Float {
    (x * x + y * y).squareRoot()
}

@inline(__always)
func clampF(_ x: Float, _ lo: Float, _ hi: Float) -> Float {
    if x < lo { return lo }
    if x > hi { return hi }
    return x
}

@inline(__always)
func clampD(_ x: Double, _ lo: Double, _ hi: Double) -> Double {
    if x < lo { return lo }
    if x > hi { return hi }
    return x
}

@inline(__always)
func clampInt(_ x: Int, _ lo: Int, _ hi: Int) -> Int {
    if x < lo { return lo }
    if x > hi { return hi }
    return x
}

@inline(__always)
func degToRad(_ deg: Float) -> Float {
    deg * (.pi / 180.0)
}

@inline(__always)
func totalLess(_ a: Float, _ b: Float) -> Bool {
    if a.isNaN { return false }
    if b.isNaN { return true }
    if a == 0.0 && b == 0.0 {
        return a.sign == .minus && b.sign == .plus
    }
    return a < b
}

// MARK: - Dual-Engine Vector Scene Snapshot

// PORT NOTE: Exposed publicly for dual-engine `GPUAUI` vector inspection and rendering alongside `Rune`'s `El` tree.
public enum DiagramDrawOp: Sendable, Equatable {
    case fill(points: [[Float]], color: Color)
    case stroke(points: [[Float]], closed: Bool, width: Float, cap: LineCap, color: Color)
}

// PORT NOTE: Exposed publicly for dual-engine `GPUAUI` vector inspection and rendering.
public struct DiagramLabel: Sendable, Equatable {
    public var text: String
    public var at: [Float]
    public var size: [Float]
    public var font: TextStyle
    public var color: Color
    public var wrap: Bool
    public var align: Align

    public init(
        text: String,
        at: [Float],
        size: [Float],
        font: TextStyle,
        color: Color,
        wrap: Bool,
        align: Align
    ) {
        self.text = text
        self.at = at
        self.size = size
        self.font = font
        self.color = color
        self.wrap = wrap
        self.align = align
    }
}

// PORT NOTE: Exposed publicly for dual-engine `GPUAUI` vector inspection and rendering.
public struct DiagramScene: Sendable, Equatable {
    public var title: String?
    public var size: [Float]
    public var full: [Float]
    public var scale: Float
    public var ops: [DiagramDrawOp]
    public var labels: [DiagramLabel]

    public init(
        title: String?,
        size: [Float],
        full: [Float],
        scale: Float,
        ops: [DiagramDrawOp],
        labels: [DiagramLabel]
    ) {
        self.title = title
        self.size = size
        self.full = full
        self.scale = scale
        self.ops = ops
        self.labels = labels
    }
}

// MARK: - Canvas & Scene

/// The card's padding on each side.
private let CARD_PAD: Float = 16.0

/// The widest a diagram's drawing can be for its card to fit `paint.maxWidth`.
func room(_ paint: DiagramStyle) -> Float {
    paint.maxWidth - 2.0 * CARD_PAD - 2.0
}

/// How much a canvas `width` points wide is drawn at to fit its card in `paint.maxWidth`.
private func fit(_ width: Float, _ paint: DiagramStyle) -> Float {
    if width <= room(paint) { 1.0 } else { max(room(paint) / width, 0.6) }
}

/// Text measured for a diagram: its size, and whether it wraps at `WRAP`.
struct Measured: Sendable, Equatable {
    var text: String = ""
    var size: [Float] = [0.0, 0.0]
    var wrap: Bool = false
}

/// Labels wider than this wrap.
private let WRAP: Float = 200.0

func measure(_ s: String, _ font: TextStyle) -> Measured {
    measureWrap(s, font, WRAP)
}

func measureWrap(_ s: String, _ font: TextStyle, _ maxW: Float) -> Measured {
    if s.isEmpty {
        return Measured()
    }
    let (w, h) = Rune.measure(s, [], font, nil)
    if w <= maxW {
        return Measured(text: s, size: [w, h], wrap: false)
    }
    let (ww, hh) = Rune.measure(s, [], font, maxW)
    return Measured(text: s, size: [ww, hh], wrap: true)
}

/// `measure`, wrapped to the narrowest width that takes as few lines, so the lines come out
/// even and none is a lone word.
func measureBalanced(_ s: String, _ font: TextStyle) -> Measured {
    var m = measure(s, font)
    if !m.wrap {
        return m
    }
    var lo: Float = 0.0
    var hi: Float = m.size[0]
    while hi - lo > 1.0 {
        let mid = (lo + hi) / 2.0
        let (w, h) = Rune.measure(s, [], font, mid)
        if h > m.size[1] + 0.5 {
            lo = mid
        } else {
            hi = mid
            m.size[0] = w
        }
    }
    return m
}

/// Straight-alpha `top` composited over `bottom` in linear sRGB.
func overColor(_ top: Color, _ bottom: Color) -> Color {
    let a = top.a + bottom.a * (1.0 - top.a)
    if a <= 1e-6 {
        return Color.TRANSPARENT
    }
    func m(_ t: Float, _ b: Float) -> Float {
        (t * top.a + b * bottom.a * (1.0 - top.a)) / a
    }
    return Color(r: m(top.r, bottom.r), g: m(top.g, bottom.g), b: m(top.b, bottom.b), a: a)
}

/// The outline of a group (a subgraph, a block group, a participant box): the nodes' outline,
/// quieter, so a group reads as a region behind its nodes rather than another node.
func groupBorder(_ paint: DiagramStyle) -> Color {
    paint.nodeBorder.alpha(paint.nodeBorder.a * 0.7)
}

enum Op: Sendable, Equatable {
    case fill([[Float]], Color)
    case stroke(points: [[Float]], closed: Bool, width: Float, cap: LineCap, color: Color)
}

struct Label: Sendable, Equatable {
    var text: String
    var at: [Float]
    var size: [Float]
    var font: TextStyle
    var color: Color
    var wrap: Bool
    var align: Align
}

/// Drawing in a diagram's own points; `Canvas.finish` moves it to the origin and scales it.
struct Canvas {
    var ops: [Op] = []
    var labels: [Label] = []
    /// Per node: its outline, where hovering it lights up its traces (empty when not drawn).
    var regions: [[[Float]]] = []
    /// Per edge: its ends and its drawing in the hover colour.
    var traces: [Trace] = []
    var hover: (Hover, Color)? = nil
    /// Where each node, edge and frame's drawing starts (`Canvas.part`), and their names.
    var marks: [Mark] = []
    var names: Names = Names()
    /// A horizontal diagram turned vertical to fit: its edges are keyed apart from the
    /// horizontal ones'.
    var turned: Bool = false

    mutating func fill(_ points: [[Float]], _ color: Color) {
        if points.count >= 3 {
            ops.append(.fill(points, color))
        }
    }

    mutating func stroke(_ points: [[Float]], _ closed: Bool, _ width: Float, _ color: Color) {
        if points.count >= 2 {
            ops.append(.stroke(points: points, closed: closed, width: width, cap: .round, color: color))
        }
    }

    /// A filled outline.
    mutating func shape(_ points: [[Float]], _ fillCol: Color, _ border: Color, _ width: Float) {
        fill(points, fillCol)
        stroke(points, true, width, border)
    }

    mutating func dashed(_ points: [[Float]], _ width: Float, _ color: Color, _ on: Float, _ off: Float) {
        guard points.count >= 2 else { return }
        var dash: [[Float]] = []
        var drawing = true
        var left = on
        // Bounded so a huge or non-finite length (where `t += step` stops advancing) can't spin.
        var budget = 20_000
        for idx in 0..<(points.count - 1) {
            let a = points[idx]
            let b = points[idx + 1]
            let len = dist(a, b)
            if !len.isFinite {
                continue
            }
            var t: Float = 0.0
            while t < len {
                if budget == 0 {
                    return
                }
                budget -= 1
                let step = min(left, len - t)
                let p0 = lerp(a, b, t / len)
                let p1 = lerp(a, b, (t + step) / len)
                if drawing {
                    if dash.isEmpty {
                        dash.append(p0)
                    }
                    dash.append(p1)
                }
                t += step
                left -= step
                if left <= 1e-3 {
                    if drawing && dash.count >= 2 {
                        ops.append(.stroke(points: dash, closed: false, width: width, cap: .butt, color: color))
                    }
                    dash.removeAll(keepingCapacity: true)
                    drawing.toggle()
                    left = drawing ? on : off
                }
            }
        }
        if dash.count >= 2 {
            ops.append(.stroke(points: dash, closed: false, width: width, cap: .butt, color: color))
        }
    }

    /// `m` centred on `center`.
    mutating func label(_ m: Measured, _ center: [Float], _ font: TextStyle, _ color: Color, _ align: Align) {
        if m.text.isEmpty {
            return
        }
        let at = [center[0] - m.size[0] / 2.0, center[1] - m.size[1] / 2.0]
        labelAt(m, at, font, color, align)
    }

    mutating func labelAt(_ m: Measured, _ at: [Float], _ font: TextStyle, _ color: Color, _ align: Align) {
        if !m.text.isEmpty {
            labels.append(Label(text: m.text, at: at, size: m.size, font: font, color: color, wrap: m.wrap, align: align))
        }
    }

    /// Draws `other` over this.
    mutating func append(_ other: Canvas) {
        let base = ops.count
        let shift = labels.count
        marks.append((base, shift, nil))
        for (o, l, p) in other.marks {
            marks.append((o + base, l + shift, p))
        }
        ops.append(contentsOf: other.ops)
        labels.append(contentsOf: other.labels)
        for var t in other.traces {
            if let (i, g) = t.label {
                t.label = (i + shift, g)
            }
            traces.append(t)
        }
    }

    /// The bounding box of everything drawn: `[x0, y0, x1, y1]`.
    func bounds() -> [Float] {
        var b: [Float] = [.greatestFiniteMagnitude, .greatestFiniteMagnitude, -.greatestFiniteMagnitude, -.greatestFiniteMagnitude]
        func add(_ p: [Float], _ r: Float) {
            b[0] = min(b[0], p[0] - r)
            b[1] = min(b[1], p[1] - r)
            b[2] = max(b[2], p[0] + r)
            b[3] = max(b[3], p[1] + r)
        }
        for op in ops {
            switch op {
            case .fill(let points, _):
                for p in points { add(p, 0.0) }
            case .stroke(let points, _, let width, _, _):
                for p in points { add(p, width / 2.0) }
            }
        }
        for l in labels {
            add(l.at, 0.0)
            add([l.at[0] + l.size[0], l.at[1] + l.size[1]], 0.0)
        }
        return b[0] > b[2] ? [0.0, 0.0, 0.0, 0.0] : b
    }

    func width() -> Float {
        let b = bounds()
        return b[2] - b[0]
    }

    /// What `finish` draws: the bounds, from no further in than a streaming build's
    /// last corner (`steady.origin`).
    private func drawn() -> [Float] {
        let b = bounds()
        let orig = steady.origin(b, turned)
        return [orig[0], orig[1], b[2], b[3]]
    }

    func finishFit(_ paint: DiagramStyle) -> Scene? {
        let b = drawn()
        let scale = fit(b[2] - b[0], paint)
        return finish(scale, paint)
    }

    func finish(_ scale: Float, _ paintStyle: DiagramStyle) -> Scene? {
        if ops.isEmpty && labels.isEmpty {
            return nil
        }
        var copy = self
        ink.flatten(&copy.ops, &copy.traces, paintStyle.surface)
        let b = copy.drawn()
        // Drawn at full size and shrunk whole by `scale` (see `Scene.el`), so a diagram
        // growing past the room it has springs smaller instead of each label jumping a size.
        // Lines thin no further than 80%.
        let pad: Float = 1.0 / scale
        let map: ([Float]) -> [Float] = { p in
            [p[0] - b[0] + pad, p[1] - b[1] + pad]
        }
        let strokeFn: (Float) -> Float = { w in
            w * max(scale, 0.8) / scale
        }
        let paintFn: (Shape, Op) -> Shape = { shape, op in
            switch op {
            case .fill(let points, let color):
                return shape.fill(points.map(map), color)
            case .stroke(let points, let closed, let width, let cap, let color):
                return shape.strokeWith(points.map(map), closed, strokeFn(width), cap, color)
            }
        }
        let (builtPieces, builtLabelKeys) = partsPieces(copy, map, strokeFn)
        let builtHovers = copy.hovers(map, paintFn)
        let mappedLabels = copy.labels.map { l -> Label in
            var nl = l
            nl.at = map(l.at)
            return nl
        }
        let mappedDrawOps: [DiagramDrawOp] = copy.ops.map { op in
            switch op {
            case .fill(let points, let color):
                return .fill(points: points.map(map), color: color)
            case .stroke(let points, let closed, let width, let cap, let color):
                return .stroke(points: points.map(map), closed: closed, width: strokeFn(width), cap: cap, color: color)
            }
        }
        let full: [Float] = [b[2] - b[0] + 2.0 * pad, b[3] - b[1] + 2.0 * pad]
        let size: [Float] = [full[0] * scale, full[1] * scale]
        let lit = copy.hover?.1 ?? Color.TRANSPARENT
        return Scene(
            title: nil,
            size: size,
            full: full,
            scale: scale,
            pieces: builtPieces,
            labels: mappedLabels,
            labelKeys: builtLabelKeys,
            hovers: builtHovers,
            lit: lit,
            ops: copy.ops,
            drawOps: mappedDrawOps
        )
    }
}

/// A laid-out diagram, drawn the same way every build.
final class Scene {
    var title: String?
    /// The size it's drawn at: `full` times `scale`.
    var size: [Float]
    /// The size its pieces, labels and hovers are laid out in, before it shrinks to fit.
    var full: [Float]
    /// How much it shrinks to fit the room it has.
    var scale: Float
    /// Each node, edge and frame's drawing, and the rest, in drawing order.
    var pieces: [Piece]
    var labels: [Label]
    var labelKeys: [LabelKey]
    /// The hover groups over edges, edge labels and nodes, and what each lights up.
    var hovers: [Spot]
    /// The hover colour.
    var lit: Color
    /// What the pieces draw, in the diagram's own points.
    var ops: [Op]
    /// Mapped draw ops in `full` coordinates for `DiagramScene`.
    var drawOps: [DiagramDrawOp]

    init(
        title: String?,
        size: [Float],
        full: [Float],
        scale: Float,
        pieces: [Piece],
        labels: [Label],
        labelKeys: [LabelKey],
        hovers: [Spot],
        lit: Color,
        ops: [Op],
        drawOps: [DiagramDrawOp]
    ) {
        self.title = title
        self.size = size
        self.full = full
        self.scale = scale
        self.pieces = pieces
        self.labels = labels
        self.labelKeys = labelKeys
        self.hovers = hovers
        self.lit = lit
        self.ops = ops
        self.drawOps = drawOps
    }

    func withTitle(_ title: String?) -> Scene {
        if let t = title, !t.trimmed().isEmpty {
            self.title = t
        }
        return self
    }

    func diagramScene() -> DiagramScene {
        DiagramScene(
            title: title,
            size: size,
            full: full,
            scale: scale,
            ops: drawOps,
            labels: labels.map { l in
                DiagramLabel(
                    text: l.text,
                    at: l.at,
                    size: l.size,
                    font: l.font,
                    color: l.color,
                    wrap: l.wrap,
                    align: l.align
                )
            }
        )
    }

    /// The diagram card. `streaming`: its source is still arriving, so each node, edge and frame
    /// new since the last build comes in on its own (`PartKind.enter`); otherwise
    /// everything shows the frame it mounts.
    func el(_ paint: DiagramStyle, _ streaming: Bool) -> El {
        let w = full[0]
        let h = full[1]
        let still: (Transition) -> Transition = { t in
            streaming ? t : Transition.none()
        }
        var body = Rune.el()
            .key("fit")
            .absolute(0.0, 0.0)
            .size(w, h)
            .origin(0.0, 0.0)
            .scale(scale)
            .transition(Transition.none())
        for p in pieces {
            body = body.child(p.el(streaming))
        }
        let labelEl: (Label, Color) -> El = { l, col in
            // A point of slack so rounding never breaks a measured line.
            let t = text(l.text).font(l.font).color(col).align(l.align).w(l.size[0] + 2.0)
            return l.wrap ? t.wrap() : t
        }
        // Labels and hover groups are placed by offset, as pieces are (`Piece.el`).
        for (l, (key, kind)) in zip(labels, labelKeys) {
            let (enter, delay) = kind.map { $0.labelEnter() } ?? (Transition.opacity(), 0.0)
            // PORT NOTE: Placed via `.absolute(...).animateLayout()` because `Sources/Rune` does not yet
            // forward `El.offset` (`vis.offset`) into `RuneMotion.Scene`.
            var t = labelEl(l, l.color)
                .absolute(l.at[0] - 1.0, l.at[1])
                .animateLayout()
                .key(key)
                .transition(still(enter))
            if streaming && delay > 0.0 {
                t = t.enterDelay(delay)
            }
            body = body.child(t)
        }
        // Over the labels, so a lit label's backing covers the one it lights. Unlit until
        // hovered, so they never animate in and their drawing moves at once. One a streaming
        // rebuild drops fades out, unseen, rather than cutting.
        // PORT NOTE: `Sources/Rune` currently gates `P_HOVER` on `vis.hover.a > 0` rather than `vis.hoverGroup`,
        // and does not yet wire `vis.cold.groupOpacity` into `buildFramePaint`. Using `.inert()` + `.liveOpacity`
        // on `glow` alongside `.hoverGroup().hover(...)` + `.onHoverChange` on the spot preserves exact hover
        // lighting and hit-testing without triggering layout commits (`tx.liveOnly()`).
        for s in hovers {
            let r = s.rect
            let glowLive = streaming ? scenes.hoverLive(s.key) : Live<Float>(0.0)
            var glow = Rune.el()
                .inert()
                .absolute(-r[0], -r[1])
                .size(w, h)
                .groupOpacity(0.0, 1.0)
                .liveOpacity(glowLive)
                .instantChanges()
                .transition(Transition.none())
                .child(canvas(s.lit).key("lit").absolute(0.0, 0.0).size(w, h).transition(Transition.none()))
            for i in s.labels {
                if i < labels.count {
                    let l = labels[i]
                    glow = glow.child(
                        labelEl(l, lit)
                            .absolute(l.at[0] - 1.0, l.at[1])
                            .key("t\(i)")
                            .transition(Transition.none())
                    )
                }
            }
            let exit: Transition
            if streaming {
                var tr = Transition.opacity()
                tr.insertion = Effect.identity
                exit = tr
            } else {
                exit = Transition.none()
            }
            body = body.child(
                Rune.el()
                    .key(s.key)
                    .absolute(r[0], r[1])
                    .animateLayout()
                    .size(r[2], r[3])
                    .hoverGroup()
                    .hover(Color(r: 0.0, g: 0.0, b: 0.0, a: 1e-6))
                    .onHoverChange { (_: inout Any, inside: Bool, tx: inout Tx) in
                        glowLive.set(inside ? 1.0 : 0.0)
                        tx.liveOnly()
                    }
                    .transition(exit)
                    .child(glow)
            )
        }
        var card = col()
            .wFull()
            .itemsCenter()
            .padding(CARD_PAD)
            .radius(6.0)
            .fill(paint.surface)
            .border(0.5, paint.surfaceBorder)
            .clipRounded(6.0)
            .animateLayout()
            .transition(still(Transition.opacity()))
        if let title = title {
            var tf = paint.font
            tf.size = paint.font.size + 1.0
            tf.lineHeight = paint.font.lineHeight + 2.0
            tf.weight = 600.0
            card = card.gap(12.0).child(
                text(title)
                    .key("title")
                    .font(tf)
                    .color(paint.text)
                    .transition(still(Transition.opacity()))
            )
        }
        return card.child(
            Rune.el()
                .key("diagram")
                .size(size[0], size[1])
                .transition(still(Transition.opacity()))
                .child(body)
        )
    }
}

// MARK: - Geometry Primitives

@inline(__always)
func dist(_ a: [Float], _ b: [Float]) -> Float {
    let dx = b[0] - a[0]
    let dy = b[1] - a[1]
    return (dx * dx + dy * dy).squareRoot()
}

@inline(__always)
func lerp(_ a: [Float], _ b: [Float], _ t: Float) -> [Float] {
    [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t]
}

@inline(__always)
func unit(_ a: [Float], _ b: [Float]) -> [Float] {
    let d = max(dist(a, b), 1e-6)
    return [(b[0] - a[0]) / d, (b[1] - a[1]) / d]
}

/// A rectangle with corners of radius `r`, as a polygon.
func roundedRect(_ x0: Float, _ y0: Float, _ x1: Float, _ y1: Float, _ rRaw: Float) -> [[Float]] {
    let r = max(min(min(rRaw, (x1 - x0) / 2.0), (y1 - y0) / 2.0), 0.0)
    if r < 0.5 {
        return [[x0, y0], [x1, y0], [x1, y1], [x0, y1]]
    }
    let steps = 6
    var pts: [[Float]] = []
    pts.reserveCapacity(4 * (steps + 1))
    let corners: [([Float], Float)] = [
        ([x1 - r, y0 + r], -90.0),
        ([x1 - r, y1 - r], 0.0),
        ([x0 + r, y1 - r], 90.0),
        ([x0 + r, y0 + r], 180.0),
    ]
    for (c, start) in corners {
        for i in 0...steps {
            let a = degToRad(start + 90.0 * Float(i) / Float(steps))
            pts.append([c[0] + r * mCos(a), c[1] + r * mSin(a)])
        }
    }
    return pts
}

/// An ellipse's arc from `a0` to `a1` degrees (clockwise on screen), as points.
func arc(_ c: [Float], _ rx: Float, _ ry: Float, _ a0: Float, _ a1: Float, _ steps: Int) -> [[Float]] {
    guard steps > 0 else { return [[c[0] + rx * mCos(degToRad(a0)), c[1] + ry * mSin(degToRad(a0))]] }
    var pts: [[Float]] = []
    pts.reserveCapacity(steps + 1)
    for i in 0...steps {
        let a = degToRad(a0 + (a1 - a0) * Float(i) / Float(steps))
        pts.append([c[0] + rx * mCos(a), c[1] + ry * mSin(a)])
    }
    return pts
}

func ellipse(_ c: [Float], _ rx: Float, _ ry: Float) -> [[Float]] {
    var pts = arc(c, rx, ry, 0.0, 360.0, 48)
    _ = pts.popLast()
    return pts
}

/// A filled arrowhead with its tip at `tip`, pointing along `dir` (a unit vector).
func arrowhead(_ tip: [Float], _ dir: [Float], _ len: Float, _ width: Float) -> [[Float]] {
    let base = [tip[0] - dir[0] * len, tip[1] - dir[1] * len]
    let n = [-dir[1] * width / 2.0, dir[0] * width / 2.0]
    return [tip, [base[0] + n[0], base[1] + n[1]], [base[0] - n[0], base[1] - n[1]]]
}

/// A diamond head (for UML composition and aggregation) with its tip at `tip`, along `dir`.
func diamondHead(_ tip: [Float], _ dir: [Float], _ len: Float, _ width: Float) -> [[Float]] {
    let mid = [tip[0] - dir[0] * len / 2.0, tip[1] - dir[1] * len / 2.0]
    let tail = [tip[0] - dir[0] * len, tip[1] - dir[1] * len]
    let n = [-dir[1] * width / 2.0, dir[0] * width / 2.0]
    return [tip, [mid[0] + n[0], mid[1] + n[1]], tail, [mid[0] - n[0], mid[1] - n[1]]]
}

/// A smooth curve through `pts` (Catmull-Rom, as flattened cubics).
func smooth(_ pts: [[Float]]) -> [[Float]] {
    if pts.count < 3 {
        return pts
    }
    let n = pts.count
    func tangent(_ i: Int) -> [Float] {
        let a: [Float]
        let b: [Float]
        if i == 0 {
            (a, b) = (pts[0], pts[1])
        } else if i == n - 1 {
            (a, b) = (pts[n - 2], pts[n - 1])
        } else {
            (a, b) = (pts[i - 1], pts[i + 1])
        }
        let k: Float = (i == 0 || i == n - 1) ? 1.0 : 0.5
        return [(b[0] - a[0]) * k, (b[1] - a[1]) * k]
    }
    var out: [[Float]] = [pts[0]]
    for i in 0..<(n - 1) {
        let a = pts[i]
        let b = pts[i + 1]
        let ta = tangent(i)
        let tb = tangent(i + 1)
        let c1 = [a[0] + ta[0] / 3.0, a[1] + ta[1] / 3.0]
        let c2 = [b[0] - tb[0] / 3.0, b[1] - tb[1] / 3.0]
        let rawSteps = ((dist(a, c1) + dist(c1, c2) + dist(c2, b)) / 4.0).rounded(.up)
        let steps = Int(clampF(rawSteps, 2.0, 48.0))
        for s in 1...steps {
            let t = Float(s) / Float(steps)
            let u = 1.0 - t
            let b0 = u * u * u
            let b1 = 3.0 * u * u * t
            let b2 = 3.0 * u * t * t
            let b3 = t * t * t
            out.append([
                b0 * a[0] + b1 * c1[0] + b2 * c2[0] + b3 * b[0],
                b0 * a[1] + b1 * c1[1] + b2 * c2[1] + b3 * b[1],
            ])
        }
    }
    return out
}
