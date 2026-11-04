// Ported from: crates/rune-mermaid/src/connector.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Edges on layered diagrams: each routed through `Ctx`, broken where its label sits, with its
//! heads at both ends and a hover trace.

import Rune

enum connector {
    private static let ARROW: Float = 9.0

    /// The room a label takes on its edge: its text with a little air, where the line breaks off.
    static func labelBox(_ m: Measured) -> [Float] {
        [m.size[0] + 12.0, m.size[1] + 6.0]
    }

    /// A subgraph's title drawn from `at`, with a little air.
    static func titleBox(_ m: Measured, _ at: [Float]) -> [Float] {
        [at[0] - 4.0, at[1] - 4.0, at[0] + m.size[0] + 4.0, at[1] + m.size[1] + 4.0]
    }

    /// How far a head of kind `h` takes its end of the line back.
    static func inset(_ h: Head) -> Float {
        switch h {
        case .none: return 0.0
        case .arrow: return ARROW * 0.7
        case .circle: return 8.0
        case .contains: return 12.0
        case .cross: return 4.0
        case .openTriangle: return 10.0
        case .diamondFilled, .diamondOpen: return 12.0
        case .onlyOne, .zeroOrOne, .oneOrMore, .zeroOrMore: return 0.0
        }
    }

    /// The colour and width `e` draws in.
    private static func pen(_ e: Edge, _ paint: DiagramStyle) -> (Color, Float) {
        let width: Float = e.style.width ?? (e.line == .thick ? 2.5 : 1.25)
        let color: Color
        if let col = e.style.stroke {
            color = adaptStroke(paint.line, col, paint.nodeFill.toOklab()[0] < 0.5)
        } else {
            color = paint.line
        }
        return (color, width)
    }

    /// Every edge routed through `ctx`, with its label in a gap in the line (on a pill of `backs[i]`
    /// where it would cover a subgraph's border); each edge's drawing and label are kept as a trace
    /// so hovering either node, the edge or its label lights them up.
    static func edges(
        _ c: inout Canvas,
        _ ctx: Ctx,
        _ edgeList: [Edge],
        _ labels: [Measured?],
        _ backs: [Color],
        _ titles: [[Float]],
        _ flip: Bool,
        _ font: TextStyle,
        _ paint: DiagramStyle
    ) {
        let routes: [(Route, [Float]?)?] = (0..<edgeList.count).map { i in
            let e = edgeList[i]
            guard ctx.placed.paths[i].count > 1 else { return nil }
            let r = ctx.route(i, flip, [inset(e.start), inset(e.end)])
            let gap: [Float]?
            if let m = labels[i], let at = r.label {
                let s = labelBox(m)
                gap = [at[0] - s[0] / 2.0, at[1] - s[1] / 2.0, at[0] + s[0] / 2.0, at[1] + s[1] / 2.0]
            } else {
                gap = nil
            }
            return (r, gap)
        }

        for (i, e) in edgeList.enumerated() {
            c.part(.index(.edge, i))
            let start = c.ops.count
            let (color, _) = pen(e, paint)
            let back = i < backs.count ? backs[i] : paint.surface
            var litLabel: (Int, [Float], Color)? = nil
            if let (r, gap) = routes[i] {
                var runs: [[[Float]]] = [r.curve]
                var rects: [[Float]] = []
                if let g = gap { rects.append(g) }
                rects.append(contentsOf: titles)
                for (j, other) in routes.enumerated() where j != i {
                    if let g = other?.1 {
                        rects.append(g)
                    }
                }
                for rect in rects {
                    runs = runs.flatMap { outside($0, rect) }
                }
                drawConnector(&c, runs, [(r.tipStart, r.dirStart), (r.tipEnd, r.dirEnd)], e, paint)
                if let m = labels[i], let at = r.label, let g = gap {
                    // A label left on a subgraph's border hides it, as the line does around it.
                    if ctx.onBorder(g) {
                        c.fill(roundedRect(g[0], g[1], g[2], g[3], 4.0), back)
                    }
                    litLabel = (c.labels.count, g, back)
                    c.label(m, at, font, paint.muted, .center)
                }
            } else {
                let s = labels[i].map { labelBox($0)[0] } ?? 0.0
                let at = selfLoop(&c, e, ctx.screen(ctx.placed.centers[e.from]), ctx.sizes[e.from], paint)
                if let m = labels[i] {
                    let b = labelBox(m)
                    litLabel = (c.labels.count, [at[0], at[1] - b[1] / 2.0, at[0] + b[0], at[1] + b[1] / 2.0], back)
                    c.label(m, [at[0] + s / 2.0, at[1]], font, paint.muted, .center)
                }
            }
            // A label with no text draws nothing, so nothing lights.
            if let l = litLabel, l.0 >= c.labels.count {
                litLabel = nil
            }
            c.trace(e.from, e.to, start, color, litLabel)
        }
        c.part(nil)
    }

    /// The runs of `curve` outside `rect` (`[x0, y0, x1, y1]`), cut where they cross its edge.
    static func outside(_ curve: [[Float]], _ rect: [Float]) -> [[[Float]]] {
        guard curve.count >= 2 else { return [] }
        var runs: [[[Float]]] = [[]]
        for idx in 0..<(curve.count - 1) {
            let a = curve[idx]
            let b = curve[idx + 1]
            let lastIdx = runs.count - 1
            if runs[lastIdx].isEmpty {
                runs[lastIdx].append(a)
            }
            if let (t0, t1) = insideSpan(a, b, rect) {
                if t0 > 0.0 {
                    runs[lastIdx].append(lerp(a, b, t0))
                }
                var next: [[Float]] = []
                if t1 < 1.0 {
                    next.append(lerp(a, b, t1))
                    next.append(b)
                }
                runs.append(next)
            } else {
                runs[lastIdx].append(b)
            }
        }
        runs.removeAll { $0.count < 2 }
        return runs
    }

    /// The part of `a`→`b` inside `rect`, as a range of `t` (Liang–Barsky).
    private static func insideSpan(_ a: [Float], _ b: [Float], _ rect: [Float]) -> (Float, Float)? {
        let dx = b[0] - a[0]
        let dy = b[1] - a[1]
        var t0: Float = 0.0
        var t1: Float = 1.0
        let pairs: [(Float, Float)] = [
            (-dx, a[0] - rect[0]),
            (dx, rect[2] - a[0]),
            (-dy, a[1] - rect[1]),
            (dy, rect[3] - a[1]),
        ]
        for (p, q) in pairs {
            if abs(p) < 1e-9 {
                if q < 0.0 {
                    return nil
                }
            } else {
                let r = q / p
                if p < 0.0 {
                    t0 = max(t0, r)
                } else {
                    t1 = min(t1, r)
                }
            }
        }
        return t0 < t1 ? (t0, t1) : nil
    }

    /// Draws `e` along `runs` (its curve, broken where a label sits) with its heads at `tips`
    /// (`[start, end]`, each a tip and the unit direction it points).
    static func drawConnector(
        _ c: inout Canvas,
        _ runs: [[[Float]]],
        _ tips: [([Float], [Float])],
        _ e: Edge,
        _ paint: DiagramStyle
    ) {
        let (color, width) = pen(e, paint)
        for run in runs {
            switch e.line {
            case .invisible:
                return
            case .dotted:
                c.dashed(run, width, color, 3.0, 3.0)
            default:
                c.stroke(run, false, width, color)
            }
        }
        head(&c, e.end, tips[1].0, tips[1].1, width, color, paint)
        head(&c, e.start, tips[0].0, tips[0].1, width, color, paint)
    }

    private static func head(
        _ c: inout Canvas,
        _ h: Head,
        _ tip: [Float],
        _ d: [Float],
        _ width: Float,
        _ color: Color,
        _ paint: DiagramStyle
    ) {
        func back(_ by: Float) -> [Float] {
            [tip[0] - d[0] * by, tip[1] - d[1] * by]
        }
        switch h {
        case .none:
            break
        case .arrow:
            c.fill(arrowhead(tip, d, ARROW + width, 6.5 + width * 1.6), color)
        case .openTriangle:
            c.shape(arrowhead(tip, d, 10.0, 9.0), paint.nodeFill, color, width)
        case .diamondFilled:
            c.fill(diamondHead(tip, d, 12.0, 8.0), color)
        case .diamondOpen:
            c.shape(diamondHead(tip, d, 12.0, 8.0), paint.nodeFill, color, width)
        case .circle:
            c.shape(ellipse(back(4.0), 4.0, 4.0), paint.nodeFill, color, width)
        case .contains:
            let m = back(6.0)
            let n = [-d[1], d[0]]
            c.shape(ellipse(m, 6.0, 6.0), paint.nodeFill, color, width)
            c.stroke([back(0.0), back(12.0)], false, width, color)
            c.stroke([[m[0] + n[0] * 6.0, m[1] + n[1] * 6.0], [m[0] - n[0] * 6.0, m[1] - n[1] * 6.0]], false, width, color)
        case .cross:
            let m = back(4.0)
            let a = [d[0] + d[1], d[1] - d[0]]
            let b = [d[0] - d[1], d[1] + d[0]]
            let sqrt2: Float = 1.41421356
            let k: Float = 3.5 / sqrt2
            c.stroke([[m[0] - a[0] * k, m[1] - a[1] * k], [m[0] + a[0] * k, m[1] + a[1] * k]], false, width, color)
            c.stroke([[m[0] - b[0] * k, m[1] - b[1] * k], [m[0] + b[0] * k, m[1] + b[1] * k]], false, width, color)
        case .onlyOne, .zeroOrOne, .oneOrMore, .zeroOrMore:
            crow(&c, h, tip, d, width, color, paint)
        }
    }

    /// A crow's-foot cardinality at `tip`: a foot for many, a bar for one, a ring for zero, with the
    /// inner mark (minimum) furthest from the entity.
    private static func crow(
        _ c: inout Canvas,
        _ h: Head,
        _ tip: [Float],
        _ d: [Float],
        _ width: Float,
        _ color: Color,
        _ paint: DiagramStyle
    ) {
        func back(_ by: Float) -> [Float] {
            [tip[0] - d[0] * by, tip[1] - d[1] * by]
        }
        let n = [-d[1], d[0]]
        func bar(_ c: inout Canvas, _ at: [Float]) {
            c.stroke([[at[0] + n[0] * 6.0, at[1] + n[1] * 6.0], [at[0] - n[0] * 6.0, at[1] - n[1] * 6.0]], false, width, color)
        }
        let many = (h == .oneOrMore || h == .zeroOrMore)
        if many {
            let heel = back(12.0)
            for side: Float in [1.0, -1.0] {
                c.stroke([heel, [tip[0] + n[0] * 6.5 * side, tip[1] + n[1] * 6.5 * side]], false, width, color)
            }
        } else {
            bar(&c, back(5.0))
        }
        let inner: Float = many ? 16.0 : 10.0
        switch h {
        case .onlyOne, .oneOrMore:
            bar(&c, back(inner))
        default:
            c.shape(ellipse(back(inner + 4.0), 4.0, 4.0), paint.surface, color, width)
        }
    }

    /// A loop off the node's right side; returns the left middle of where its label goes.
    private static func selfLoop(
        _ c: inout Canvas,
        _ e: Edge,
        _ ctr: [Float],
        _ size: [Float],
        _ paint: DiagramStyle
    ) -> [Float] {
        let x = ctr[0] + size[0] / 2.0
        let a = [x, ctr[1] - size[1] / 4.0]
        let b = [x, ctr[1] + size[1] / 4.0]
        var path: [[Float]] = [a, [x + 18.0, a[1] - 4.0], [x + 26.0, ctr[1]], [x + 18.0, b[1] + 4.0], b]
        let n = path.count
        let dirEnd = unit(path[n - 2], path[n - 1])
        let dirStart = unit(path[1], path[0])
        let tipEnd = path[n - 1]
        let tipStart = path[0]
        path[n - 1] = [tipEnd[0] - dirEnd[0] * inset(e.end), tipEnd[1] - dirEnd[1] * inset(e.end)]
        path[0] = [tipStart[0] - dirStart[0] * inset(e.start), tipStart[1] - dirStart[1] * inset(e.start)]
        drawConnector(&c, [smooth(path)], [(tipStart, dirStart), (tipEnd, dirEnd)], e, paint)
        return [x + 30.0, ctr[1]]
    }
}
