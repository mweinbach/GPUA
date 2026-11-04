// Ported from: crates/rune-mermaid/src/block.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Block diagrams (`block-beta`, `block`): blocks in rows of `columns`, spanning cells with
//! `id:2`, gaps from `space`, nested `block … end` groups, block arrows `id<["label"]>(right)`,
//! and edges between blocks, laid out on a grid rather than by rank.

import Rune

enum block {
    enum Point: Sendable, Equatable {
        case right
        case left
        case up
        case down
        /// Both ways across.
        case x
        /// Both ways up and down.
        case y
    }

    enum Kind: Equatable {
        case node
        case space
        case arrow(Point)
        case group(columns: Int?, children: [Int])
    }

    struct Block {
        var id: String
        var label: String
        var shape: NodeShape
        var span: Int
        var kind: Kind
        var style: NodeStyle
    }

    /// Block 0 is the diagram itself: a group that isn't drawn.
    struct BlockDiagram {
        var blocks: [Block]
        var edges: [Edge]
    }

    private struct Item {
        var id: String
        var label: String?
        var shape: NodeShape?
        var arrow: Point?
        var span: Int
    }

    static func parse(_ body: [String]) -> BlockDiagram? {
        let root = Block(
            id: "",
            label: "",
            shape: .rect,
            span: 1,
            kind: .group(columns: nil, children: []),
            style: NodeStyle()
        )
        var p = Parser(
            d: BlockDiagram(blocks: [root], edges: []),
            ids: [:],
            stack: [0],
            styles: StyleSheet(),
            over: false
        )
        for line in body {
            for s in statements(line) {
                _ = p.statement(s)
                if p.over {
                    return nil
                }
            }
        }
        for (id, i) in p.ids {
            p.d.blocks[i].style = p.styles.get(id)
        }
        return p.d.blocks.count > 1 ? p.d : nil
    }

    private struct Parser {
        var d: BlockDiagram
        var ids: [String: Int]
        var stack: [Int]
        var styles: StyleSheet
        var over: Bool

        mutating func budget() -> Bool {
            if d.blocks.count + d.edges.count >= MAX_ITEMS {
                over = true
            }
            return !over
        }

        func currentGroup() -> Int {
            stack.last ?? 0
        }

        mutating func statement(_ s: String) -> Bool {
            if let rest = word(s, "columns") {
                let n = Int(rest).flatMap { $0 >= 0 ? clampInt($0, 1, 24) : nil }
                let g = currentGroup()
                if case .group(_, let children) = d.blocks[g].kind {
                    d.blocks[g].kind = .group(columns: n, children: children)
                }
            } else if s == "end" {
                if stack.count > 1 {
                    _ = stack.popLast()
                }
            } else if s == "block" || s.hasPrefix("block:") {
                var afterBlock = s.dropFirst("block".count)
                while afterBlock.first == ":" {
                    afterBlock = afterBlock.dropFirst()
                }
                let parts = afterBlock.split(separator: ":", omittingEmptySubsequences: false)
                let id = parts.first.map { String($0.trimmed()) } ?? ""
                let rawSpan = parts.count > 1 ? Int(String(parts[1].trimmed())) : nil
                let span = clampInt(rawSpan ?? 1, 1, 24)
                if stack.count > MAX_DEPTH {
                    over = true
                    return false
                }
                guard let i = add(Item(id: id, label: "", shape: nil, arrow: nil, span: span)) else {
                    return false
                }
                d.blocks[i].kind = .group(columns: nil, children: [])
                stack.append(i)
            } else if let rest = word(s, "classDef") {
                return styles.classDef(rest)
            } else if let rest = word(s, "class") {
                return styles.assignClasses(rest)
            } else if let rest = word(s, "style") {
                return styles.style(rest)
            } else if !edges(s) {
                return items(s)
            }
            return true
        }

        /// `a --> b -- "label" --> c`, read whole first so a line that isn't one adds nothing.
        mutating func edges(_ s: String) -> Bool {
            var c = Cur(s)
            guard let first = item(&c) else { return false }
            var refs = [first]
            var links: [flowchart.Link] = []
            while true {
                c.skipWs()
                if c.done() {
                    break
                }
                guard let lnk = flowchart.link(&c) else { return false }
                links.append(lnk)
                c.skipWs()
                guard let nxt = item(&c) else { return false }
                refs.append(nxt)
            }
            if links.isEmpty {
                return false
            }
            var ends: [Int] = []
            ends.reserveCapacity(refs.count)
            for r in refs {
                guard let idx = add(r) else { return false }
                ends.append(idx)
            }
            for i in 0..<links.count {
                guard budget() else { return false }
                let l = links[i]
                d.edges.append(
                    Edge(
                        from: ends[i],
                        to: ends[i + 1],
                        label: l.label,
                        line: l.line,
                        start: l.start,
                        end: l.end,
                        minlen: 1,
                        style: EdgeStyle(),
                        onCluster: [nil, nil]
                    )
                )
            }
            return true
        }

        /// `a b["label"]:2 space c`, read whole first.
        mutating func items(_ s: String) -> Bool {
            var c = Cur(s)
            var parsed: [Item] = []
            while true {
                c.skipWs()
                if c.done() {
                    break
                }
                guard let it = item(&c) else { return false }
                parsed.append(it)
            }
            for it in parsed {
                guard add(it) != nil else { return false }
            }
            return true
        }

        /// A block placed in the open group, or the one `id` already names (taking a new label or shape).
        mutating func add(_ it: Item) -> Int? {
            if let i = ids[it.id] {
                if let l = it.label {
                    d.blocks[i].label = l
                }
                if let s = it.shape {
                    d.blocks[i].shape = s
                }
                return i
            }
            guard budget() else { return nil }
            let kind: Kind
            if it.id == "space" {
                kind = .space
            } else if let p = it.arrow {
                kind = .arrow(p)
            } else {
                kind = .node
            }
            let label = it.label ?? it.id
            let i = d.blocks.count
            if kind != .space && !it.id.isEmpty {
                ids[it.id] = i
            }
            d.blocks.append(
                Block(
                    id: it.id,
                    label: label,
                    shape: it.shape ?? .rect,
                    span: it.span,
                    kind: kind,
                    style: NodeStyle()
                )
            )
            let g = currentGroup()
            if case .group(let columns, var children) = d.blocks[g].kind {
                children.append(i)
                d.blocks[g].kind = .group(columns: columns, children: children)
            }
            return i
        }
    }

    /// `id`, `id["label"]`, `id(round)`, `id<["label"]>(right)`, each with an optional `:span`.
    private static func item(_ c: inout Cur) -> Item? {
        guard let id = flowchart.ident(&c) else { return nil }
        var label: String? = nil
        var shapeOf: NodeShape? = nil
        var arrow: Point? = nil
        if c.eat("<[") {
            guard let (lblPart, afterBracket) = c.rest().splitOnce("]>") else { return nil }
            label = cleanQuoted(String(lblPart))
            c.i = afterBracket.startIndex
            guard c.eat("("), let (dirPart, afterParen) = c.rest().splitOnce(")") else { return nil }
            c.i = afterParen.startIndex
            switch dirPart.trimmed() {
            case "right": arrow = .right
            case "left": arrow = .left
            case "up": arrow = .up
            case "down": arrow = .down
            case "x": arrow = .x
            case "y": arrow = .y
            default: return nil
            }
        } else if let (l, s) = flowchart.shape(&c) {
            label = l
            shapeOf = s
        }
        var span = 1
        if c.peek() == ":", let d2 = c.peek2(), d2.value >= 48 && d2.value <= 57 {
            c.bump()
            let start = c.i
            while let d = c.peek(), d.value >= 48 && d.value <= 57 {
                c.bump()
            }
            guard let parsed = Int(String(c.s[start..<c.i])) else { return nil }
            span = clampInt(parsed, 1, 24)
        }
        return Item(id: id, label: label, shape: shapeOf, arrow: arrow, span: span)
    }

    private static let GAP: Float = 10.0
    private static let PAD: Float = 10.0
    /// The gap between rows when edges run between blocks, so an arrow and its label show.
    private static let EDGE_GAP: Float = 40.0

    /// Each group's rows: the children in it with the column each starts at.
    private static func rows(_ d: BlockDiagram, _ g: Int) -> (Int, [[(Int, Int)]]) {
        guard case .group(let columns, let children) = d.blocks[g].kind else {
            return (1, [])
        }
        let cols: Int
        if let c = columns {
            cols = max(c, 1)
        } else {
            var sum = 0
            for k in children { sum += d.blocks[k].span }
            cols = max(sum, 1)
        }
        var out: [[(Int, Int)]] = [[]]
        var at = 0
        for k in children {
            let span = min(d.blocks[k].span, cols)
            if at > 0 && at + span > cols {
                out.append([])
                at = 0
            }
            out[out.count - 1].append((k, at))
            at += span
        }
        return (cols, out)
    }

    private struct BlockLayout {
        var d: BlockDiagram
        var labels: [Measured]
        var natural: [[Float]]
        var rects: [[Float]]
        var rowGap: Float

        static func pad(_ g: Int) -> Float {
            g == 0 ? 0.0 : PAD
        }

        mutating func measure(_ i: Int) -> [Float] {
            let m = labels[i]
            let size: [Float]
            switch d.blocks[i].kind {
            case .space:
                size = [0.0, 0.0]
            case .node:
                size = nodeSize(d.blocks[i].shape, m.size)
            case .arrow(.up), .arrow(.down), .arrow(.y):
                size = [m.size[0] + 40.0, m.size[1] + 56.0]
            case .arrow:
                size = [m.size[0] + 64.0, m.size[1] + 36.0]
            case .group:
                let (cols, rws) = rows(d, i)
                var cell: Float = 0.0
                var height: Float = 0.0
                for row in rws {
                    var tall: Float = 0.0
                    for (k, _) in row {
                        let s = measure(k)
                        let span = Float(min(d.blocks[k].span, cols))
                        cell = max(cell, (s[0] - (span - 1.0) * GAP) / span)
                        tall = max(tall, s[1])
                    }
                    height += tall
                }
                let p = Self.pad(i)
                size = [
                    Float(cols) * cell + (Float(cols) - 1.0) * GAP + 2.0 * p,
                    height + max(Float(rws.count) - 1.0, 0.0) * rowGap + 2.0 * p,
                ]
            }
            natural[i] = size
            return size
        }

        mutating func place(_ i: Int, _ r: [Float]) {
            rects[i] = r
            guard case .group = d.blocks[i].kind else { return }
            let (cols, rws) = rows(d, i)
            let p = Self.pad(i)
            let cell = (r[2] - 2.0 * p - (Float(cols) - 1.0) * GAP) / Float(cols)
            var y = r[1] + p + max(r[3] - natural[i][1], 0.0) / 2.0
            for row in rws {
                var tall: Float = 0.0
                for (k, _) in row { tall = max(tall, natural[k][1]) }
                for (k, at) in row {
                    let span = Float(min(d.blocks[k].span, cols))
                    let x = r[0] + p + Float(at) * (cell + GAP)
                    place(k, [x, y, span * cell + (span - 1.0) * GAP, tall])
                }
                y += tall + rowGap
            }
        }

        /// Where block `i` is drawn: its centre and size.
        func frame(_ i: Int) -> ([Float], [Float]) {
            let x = rects[i][0]
            let y = rects[i][1]
            let w = rects[i][2]
            let h = rects[i][3]
            let n = natural[i]
            let size: [Float]
            switch d.blocks[i].kind {
            case .group:
                size = [w, h]
            case .arrow:
                size = n
            default:
                if d.blocks[i].shape == .circle || d.blocks[i].shape == .doubleCircle {
                    size = n
                } else {
                    size = [w, n[1]]
                }
            }
            return ([x + w / 2.0, y + h / 2.0], size)
        }
    }

    static func draw(_ d: BlockDiagram, _ paint: DiagramStyle) -> Scene? {
        let n = d.blocks.count
        guard n > 1 else { return nil }
        var l = BlockLayout(
            d: d,
            labels: d.blocks.map { measureWrap($0.label, paint.font, 180.0) },
            natural: Array(repeating: [0.0, 0.0], count: n),
            rects: Array(repeating: [0.0, 0.0, 0.0, 0.0], count: n),
            rowGap: d.edges.isEmpty ? GAP : EDGE_GAP
        )
        let rootSize = l.measure(0)
        l.place(0, [0.0, 0.0, rootSize[0], rootSize[1]])
        var c = Canvas()
        let grpBorder = groupBorder(paint)
        for i in 1..<n {
            if case .group = d.blocks[i].kind {
                let r = l.rects[i]
                let fill = d.blocks[i].style.fill != nil ? d.blocks[i].style.resolve(paint).0 : paint.clusterFill
                c.shape(roundedRect(r[0], r[1], r[0] + r[2], r[1] + r[3], 6.0), fill, grpBorder, 1.0)
            }
        }
        let edgeFont = chart.small(paint)
        for e in d.edges {
            let (ca, sa) = l.frame(e.from)
            let (cb, sb) = l.frame(e.to)
            func outlineShape(_ idx: Int) -> NodeShape {
                if case .node = d.blocks[idx].kind { return d.blocks[idx].shape }
                return .rect
            }
            let pa = boundary(outlineShape(e.from), ca, sa, cb)
            let pb = boundary(outlineShape(e.to), cb, sb, ca)
            let u = unit(pa, pb)
            let a = [pa[0] + u[0] * connector.inset(e.start), pa[1] + u[1] * connector.inset(e.start)]
            let b = [pb[0] - u[0] * connector.inset(e.end), pb[1] - u[1] * connector.inset(e.end)]
            connector.drawConnector(&c, [[a, b]], [(pa, [-u[0], -u[1]]), (pb, u)], e, paint)
            if let text = e.label {
                let m = measureWrap(text, edgeFont, 160.0)
                let mid = [(pa[0] + pb[0]) / 2.0, (pa[1] + pb[1]) / 2.0]
                let s = connector.labelBox(m)
                c.fill(
                    roundedRect(mid[0] - s[0] / 2.0, mid[1] - s[1] / 2.0, mid[0] + s[0] / 2.0, mid[1] + s[1] / 2.0, 4.0),
                    paint.surface
                )
                c.label(m, mid, edgeFont, paint.text, .center)
            }
        }
        for i in 1..<n {
            let b = d.blocks[i]
            let (ctr, size) = l.frame(i)
            let (fill, border, textCol) = b.style.resolve(paint)
            switch b.kind {
            case .node:
                drawShape(&c, b.shape, l.labels[i], ctr, size, [fill, border, textCol], paint)
            case .arrow(let p):
                c.shape(arrowOutline(p, ctr, size), fill, border, 1.0)
                c.label(l.labels[i], ctr, paint.font, textCol, .center)
            case .space, .group:
                break
            }
        }
        return c.finishFit(paint)
    }

    /// A block arrow's outline: a shaft with a head at one end (or both, for `x` and `y`).
    private static func arrowOutline(_ p: Point, _ ctr: [Float], _ size: [Float]) -> [[Float]] {
        let upright = (p == .up || p == .down || p == .y)
        let (len, thick) = upright ? (size[1], size[0]) : (size[0], size[1])
        let hl = len / 2.0
        let ht = thick / 2.0
        let head = min(thick * 0.55, len * 0.4)
        let shaft = ht * 0.62
        let both = (p == .x || p == .y)
        let back = both ? (-hl + head) : -hl
        var pts: [[Float]] = [
            [back, -shaft],
            [hl - head, -shaft],
            [hl - head, -ht],
            [hl, 0.0],
            [hl - head, ht],
            [hl - head, shaft],
            [back, shaft],
        ]
        if both {
            pts.append(contentsOf: [[back, ht], [-hl, 0.0], [back, -ht]])
        }
        let flip = (p == .left || p == .up)
        return pts.map { pt in
            let u = flip ? -pt[0] : pt[0]
            let v = pt[1]
            return upright ? [ctr[0] + v, ctr[1] + u] : [ctr[0] + u, ctr[1] + v]
        }
    }
}
