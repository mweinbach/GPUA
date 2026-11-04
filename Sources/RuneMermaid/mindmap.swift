// Ported from: crates/rune-mermaid/src/mindmap.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Mindmaps (`mindmap`): a tree nested by indentation, drawn from its root out to both sides with
//! each top-level branch in its own colour. Node shapes are `[square]`, `(rounded)`,
//! `((circle))`, `))bang((`, `)cloud(` and `{{hexagon}}`; a bare line is a plain node.

import Rune

enum mindmap {
    enum Look: Equatable, Sendable {
        case plain
        case square
        case rounded
        case circle
        case bang
        case cloud
        case hexagon
    }

    struct Node {
        var text: String
        var look: Look
        var depth: Int
        var children: [Int]
    }

    /// Nodes in source order; the first is the root.
    struct Mindmap {
        var nodes: [Node]
    }

    static func parse(_ body: [String], _ indents: [Int]) -> Mindmap? {
        var nodes: [Node] = []
        var stack: [(Int, Int)] = []
        for (i, line) in body.enumerated() {
            let l = String(line.trimmed())
            if l.hasPrefix("::icon(") || l.hasPrefix(":::") || l.hasPrefix("accTitle") || l.hasPrefix("accDescr") {
                continue
            }
            guard let (text, nodeLook) = node(l) else { continue }
            if nodes.count >= MAX_ITEMS {
                return nil
            }
            let indent = i < indents.count ? indents[i] : 0
            let id = nodes.count
            if id == 0 {
                nodes.append(Node(text: text, look: nodeLook, depth: 0, children: []))
                stack.append((indent, 0))
                continue
            }
            // A line no deeper than the root still hangs off it: there is one root.
            while stack.count > 1, let last = stack.last, last.0 >= indent {
                _ = stack.popLast()
            }
            let parent = stack.last?.1 ?? 0
            let depth = nodes[parent].depth + 1
            if depth > MAX_DEPTH {
                return nil
            }
            nodes[parent].children.append(id)
            nodes.append(Node(text: text, look: nodeLook, depth: depth, children: []))
            stack.append((indent, id))
        }
        return nodes.isEmpty ? nil : Mindmap(nodes: nodes)
    }

    private static let SHAPES: [(String, String, Look)] = [
        ("((", "))", .circle),
        ("))", "((", .bang),
        ("{{", "}}", .hexagon),
        (")", "(", .cloud),
        ("(", ")", .rounded),
        ("[", "]", .square),
        ("{", "}", .rounded),
    ]

    /// `id[text]`, `id((text))`, … or a bare line. An opener without its closer reads as written.
    private static func node(_ lIn: String) -> (String, Look)? {
        let l: String
        if let (before, after) = lIn.rsplitOnce(":::"),
           !after.contains(where: { $0 == ")" || $0 == "]" || $0 == "}" })
        {
            l = String(before.trimmed())
        } else {
            l = lIn
        }
        if l.isEmpty {
            return nil
        }
        if let p = l.firstIndex(where: { $0 == "[" || $0 == "(" || $0 == ")" || $0 == "{" }) {
            let rest = l[p...]
            for (open, close, shapeLook) in SHAPES {
                if let afterOpen = rest.stripPrefix(open),
                   let inner = afterOpen.stripSuffix(close),
                   !inner.isEmpty
                {
                    return (cleanQuoted(String(inner)), shapeLook)
                }
            }
        }
        return (cleanQuoted(l), .plain)
    }

    private static let GAP_X: Float = 40.0
    private static let GAP_Y: Float = 10.0
    private static let WRAP: Float = 150.0

    private struct Placed {
        var label: Measured
        var size: [Float]
        /// -1 left of the root, 1 right, 0 the root.
        var side: Float
        /// The top-level branch it's on.
        var branch: Int
        var at: [Float]
    }

    static func draw(_ m: Mindmap, _ paint: DiagramStyle) -> Scene? {
        let n = m.nodes.count
        func font(_ i: Int) -> TextStyle {
            i == 0 ? chart.bold(paint.font) : paint.font
        }
        var placed: [Placed] = (0..<n).map { i in
            let nd = m.nodes[i]
            let label = measureWrap(nd.text, font(i), WRAP)
            return Placed(label: label, size: size(look(i, nd.look), label.size), side: 0.0, branch: 0, at: [0.0, 0.0])
        }
        var block = Array(repeating: Float(0.0), count: n)
        for i in (0..<n).reversed() {
            let kids = m.nodes[i].children
            let stacked = kids.reduce(Float(0.0)) { $0 + block[$1] } + GAP_Y * Float(max(kids.count - 1, 0))
            block[i] = max(placed[i].size[1], stacked)
        }

        // Top-level branches fill the right side in order until it holds half the height.
        let top = m.nodes[0].children
        let total = top.reduce(Float(0.0)) { $0 + block[$1] }
        var right: [Int] = []
        var left: [Int] = []
        var held: Float = 0.0
        for k in top {
            if right.isEmpty || held + block[k] / 2.0 <= total / 2.0 {
                held += block[k]
                right.append(k)
            } else {
                left.append(k)
            }
        }
        for (b, k) in top.enumerated() {
            mark(m, &placed, k, b, right.contains(k) ? 1.0 : -1.0)
        }

        // Each depth on each side is a column as wide as its widest node.
        var cols: [[Float]] = [
            Array(repeating: 0.0, count: MAX_DEPTH + 1),
            Array(repeating: 0.0, count: MAX_DEPTH + 1),
        ]
        if n > 1 {
            for i in 1..<n {
                let p = placed[i]
                let sideIdx = p.side > 0.0 ? 1 : 0
                let d = m.nodes[i].depth
                cols[sideIdx][d] = max(cols[sideIdx][d], p.size[0])
            }
        }
        for (kids, side) in [(right, Float(1.0)), (left, Float(-1.0))] {
            let col = cols[side > 0.0 ? 1 : 0]
            let height = kids.reduce(Float(0.0)) { $0 + block[$1] } + GAP_Y * Float(max(kids.count - 1, 0))
            var y = -height / 2.0
            for k in kids {
                place(m, &placed, block, col, k, y)
                y += block[k] + GAP_Y
            }
        }

        var c = Canvas()
        for (i, nd) in m.nodes.enumerated() {
            let p = placed[i]
            for k in nd.children {
                let q = placed[k]
                let a = [p.at[0] + q.side * p.size[0] / 2.0, p.at[1]]
                let b = [q.at[0] - q.side * q.size[0] / 2.0, q.at[1]]
                let width = max(3.5 - Float(nd.depth) * 0.75, 1.25)
                c.stroke(chart.sCurve(a, b, false), false, width, chart.solid(paint, branchHue(q.branch)))
            }
        }
        for (i, nd) in m.nodes.enumerated() {
            let p = placed[i]
            let h = branchHue(p.branch)
            let fill: Color
            let border: Color
            switch nd.depth {
            case 0:
                fill = chart.solid(paint, chart.hue(0))
                border = chart.strong(paint, chart.hue(0))
            case 1:
                fill = chart.soft(paint, h)
                border = chart.strong(paint, h)
            default:
                fill = overColor(chart.soft(paint, h).alpha(0.55), paint.surface)
                border = chart.strong(paint, h).alpha(0.7)
            }
            let text = nd.depth == 0 ? chart.ink(fill) : paint.text
            drawNode(&c, look(i, nd.look), p, [fill, border, text], font(i))
        }
        return c.finishFit(paint)
    }

    /// A plain root is drawn rounded, so it reads as the centre.
    private static func look(_ i: Int, _ l: Look) -> Look {
        (i == 0 && l == .plain) ? .rounded : l
    }

    /// Branch `b`'s hue; the root keeps the first.
    private static func branchHue(_ b: Int) -> Float {
        chart.hue(b + 1)
    }

    private static func mark(_ m: Mindmap, _ placed: inout [Placed], _ i: Int, _ branch: Int, _ side: Float) {
        placed[i].side = side
        placed[i].branch = branch
        for k in m.nodes[i].children {
            mark(m, &placed, k, branch, side)
        }
    }

    /// Places `i`'s subtree in a band of its block height from `top`.
    private static func place(
        _ m: Mindmap,
        _ placed: inout [Placed],
        _ block: [Float],
        _ col: [Float],
        _ i: Int,
        _ top: Float
    ) {
        let nd = m.nodes[i]
        let side = placed[i].side
        var innerSum: Float = 0.0
        if nd.depth > 1 {
            for d in 1..<nd.depth {
                innerSum += col[d] + GAP_X
            }
        }
        let inner = innerSum + placed[0].size[0] / 2.0 + GAP_X
        placed[i].at = [side * (inner + placed[i].size[0] / 2.0), top + block[i] / 2.0]
        let stacked = nd.children.reduce(Float(0.0)) { $0 + block[$1] } + GAP_Y * Float(max(nd.children.count - 1, 0))
        var y = top + (block[i] - stacked) / 2.0
        for k in nd.children {
            place(m, &placed, block, col, k, y)
            y += block[k] + GAP_Y
        }
    }

    private static func asShape(_ l: Look) -> NodeShape? {
        switch l {
        case .circle: return .circle
        case .bang: return .bang
        case .cloud: return .cloud
        case .hexagon: return .hexagon
        default: return nil
        }
    }

    private static func size(_ l: Look, _ t: [Float]) -> [Float] {
        if let s = asShape(l) {
            let sz = nodeSize(s, t)
            return l == .hexagon ? [sz[0], max(t[1] + 16.0, 34.0)] : sz
        }
        return [t[0] + 24.0, max(t[1] + 14.0, 32.0)]
    }

    private static func drawNode(
        _ c: inout Canvas,
        _ l: Look,
        _ p: Placed,
        _ colors: [Color],
        _ font: TextStyle
    ) {
        let fill = colors[0]
        let border = colors[1]
        let text = colors[2]
        let x = p.at[0]
        let y = p.at[1]
        let w = p.size[0]
        let h = p.size[1]
        let x0 = x - w / 2.0
        let y0 = y - h / 2.0
        let x1 = x + w / 2.0
        let y1 = y + h / 2.0
        switch l {
        case .plain:
            c.fill(roundedRect(x0, y0, x1, y1, 4.0), fill)
            c.stroke([[x0, y1], [x1, y1]], false, 2.0, border)
        case .square:
            c.shape(roundedRect(x0, y0, x1, y1, 0.0), fill, border, 1.0)
        case .rounded:
            c.shape(roundedRect(x0, y0, x1, y1, 10.0), fill, border, 1.0)
        default:
            if let s = asShape(l) {
                c.shape(outline(s, p.at, p.size), fill, border, 1.0)
            }
        }
        c.label(p.label, p.at, font, text, .center)
    }
}
