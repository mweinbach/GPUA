// Ported from: crates/rune-mermaid/src/layered_draw.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Shared node geometry, connector arrows and scene rendering on top of `layered` for
//! flowcharts, state diagrams and class diagrams.

import Rune

enum Dir: Sendable, Equatable, Hashable {
    case down
    case up
    case right
    case left

    static func parse(_ s: String) -> Dir? {
        switch s {
        case "", "TD", "TB": return .down
        case "BT": return .up
        case "LR": return .right
        case "RL": return .left
        default: return nil
        }
    }
}

enum Line: Sendable, Equatable, Hashable {
    case solid
    case dotted
    case thick
    case invisible
}

enum Head: Sendable, Equatable, Hashable {
    case none
    case arrow
    case circle
    case cross
    case openTriangle
    case diamondFilled
    case diamondOpen
    /// Entity-relationship cardinalities, drawn in crow's-foot notation.
    case onlyOne
    case zeroOrOne
    case oneOrMore
    case zeroOrMore
    /// A circle with a cross: the container's end of a requirement's `contains`.
    case contains
}

struct Edge: Sendable, Equatable {
    var from: Int
    var to: Int
    var label: String?
    var line: Line
    var start: Head
    var end: Head
    var minlen: Int
    var style: EdgeStyle
    /// `[start, end]`: the subgraph whose border that end stops on, when the source linked the
    /// subgraph itself. Its node (`from` or `to`) is a member that ranks it.
    var onCluster: [Int?]

    init(
        from: Int,
        to: Int,
        label: String? = nil,
        line: Line = .solid,
        start: Head = .none,
        end: Head = .arrow,
        minlen: Int = 1,
        style: EdgeStyle = EdgeStyle(),
        onCluster: [Int?] = [nil, nil]
    ) {
        self.from = from
        self.to = to
        self.label = label
        self.line = line
        self.start = start
        self.end = end
        self.minlen = minlen
        self.style = style
        self.onCluster = onCluster
    }
}

/// How far a horizontal diagram may shrink to fit before it turns top-down instead.
private let TURN_BELOW: Float = 0.78

/// Where a subgraph's title sits inside its top left corner.
private let TITLE_INSET: [Float] = [10.0, 7.0]

struct ClusterSpec: Sendable, Equatable {
    var title: String
    var parent: Int?

    init(title: String, parent: Int? = nil) {
        self.title = title
        self.parent = parent
    }
}

enum DrawNode {
    case shape(
        shape: NodeShape,
        label: Measured,
        size: [Float],
        cluster: Int?,
        style: NodeStyle
    )
    case start(cluster: Int?)
    case end(cluster: Int?)
    case bar(cluster: Int?)
    case classBox(
        stereo: Measured?,
        name: Measured,
        fields: [Measured],
        methods: [Measured],
        size: [Float],
        cluster: Int?,
        style: NodeStyle
    )
    /// An entity: its name over a table of attributes, one row each, in columns `cols` wide.
    case entity(
        name: Measured,
        rows: [[Measured]],
        cols: [Float],
        size: [Float],
        style: NodeStyle
    )
    /// Lines of text, each in its own font, down a filled shape in `[fill, border, text]` (C4
    /// elements), under a person glyph when `person`.
    case card(
        shape: NodeShape,
        lines: [(Measured, TextStyle)],
        size: [Float],
        cluster: Int?,
        colors: [Color],
        person: Bool
    )

    func size() -> [Float] {
        switch self {
        case .shape(_, _, let size, _, _),
             .classBox(_, _, _, _, let size, _, _),
             .entity(_, _, _, let size, _),
             .card(_, _, let size, _, _, _):
            return size
        case .start:
            return [18.0, 18.0]
        case .end:
            return [22.0, 22.0]
        case .bar:
            return [64.0, 8.0]
        }
    }

    func nodeShape() -> NodeShape {
        switch self {
        case .shape(let shape, _, _, _, _),
             .card(let shape, _, _, _, _, _):
            return shape
        case .start, .end:
            return .circle
        case .bar, .classBox, .entity:
            return .rect
        }
    }

    func cluster() -> Int? {
        switch self {
        case .shape(_, _, _, let cluster, _),
             .start(let cluster),
             .end(let cluster),
             .bar(let cluster),
             .classBox(_, _, _, _, _, let cluster, _),
             .card(_, _, _, let cluster, _, _):
            return cluster
        case .entity:
            return nil
        }
    }
}

func drawLayered(
    _ dir: Dir,
    _ nodes: [DrawNode],
    _ edges: [Edge],
    _ clusters: [ClusterSpec],
    _ spacing: Spacing,
    _ paint: DiagramStyle,
    _ hover: (Hover, Color)?
) -> Scene? {
    guard let canvas = layeredCanvas(dir, nodes, [], edges, clusters, spacing, paint, hover) else {
        return nil
    }
    return canvas.finishFit(paint)
}

/// `drawLayered` at full size, before `Canvas.finish`, with each node's name in `ids`
/// (empty: known by index) for a diagram streaming in to hold each node to where it was.
func layeredCanvas(
    _ dir: Dir,
    _ nodes: [DrawNode],
    _ ids: [String],
    _ edges: [Edge],
    _ clusters: [ClusterSpec],
    _ spacing: Spacing,
    _ paint: DiagramStyle,
    _ hover: (Hover, Color)?
) -> Canvas? {
    let edgeFont = chart.small(paint)
    let labels: [Measured?] = edges.map { e in e.label.map { measureBalanced($0, edgeFont) } }
    var titleFont = edgeFont
    titleFont.weight = 500.0
    let titles: [Measured] = clusters.map { c in measure(c.title, titleFont) }
    let fonts = LayeredFonts(edge: edgeFont, title: titleFont)
    let parts = LayeredParts(
        nodes: nodes,
        ids: ids,
        edges: edges,
        clusters: clusters,
        labels: labels,
        titles: titles
    )
    guard var canvas = drawIn(dir, parts, fonts, spacing, paint, hover) else {
        return nil
    }
    // The turn: a horizontal diagram that would shrink below `TURN_BELOW` of its size to fit
    // the card is drawn top-down instead, when that comes out narrower.
    // A diagram streaming in that has turned stays turned.
    let stay = steady.turned()
    if (stay || canvas.width() > room(paint) / TURN_BELOW) && (dir == .right || dir == .left) {
        if let down = drawIn(dir == .right ? .down : .up, parts, fonts, spacing, paint, hover) {
            if stay || down.width() < canvas.width() {
                canvas = down
                canvas.turned = true
            }
        } else {
            return nil
        }
    }
    steady.setTurned(canvas.turned)
    return canvas
}

private struct LayeredFonts {
    var edge: TextStyle
    var title: TextStyle
}

private struct LayeredParts {
    var nodes: [DrawNode]
    var ids: [String]
    var edges: [Edge]
    var clusters: [ClusterSpec]
    var labels: [Measured?]
    var titles: [Measured]
}

private func drawIn(
    _ dir: Dir,
    _ p: LayeredParts,
    _ fonts: LayeredFonts,
    _ spacing: Spacing,
    _ paint: DiagramStyle,
    _ hover: (Hover, Color)?
) -> Canvas? {
    let nodes = p.nodes
    let ids = p.ids
    let edges = p.edges
    let clusters = p.clusters
    let labels = p.labels
    let titles = p.titles
    let across = (dir == .right || dir == .left)
    func ax(_ s: [Float]) -> [Float] { across ? [s[1], s[0]] : s }
    let flip = (dir == .up || dir == .left)
    let graph = Graph(
        sizes: nodes.map { ax($0.size()) },
        edges: zip(edges, labels).map { (e, l) in
            let (from, to) = flip ? (e.to, e.from) : (e.from, e.to)
            return GEdge(
                from: from,
                to: to,
                label: l.map { ax(connector.labelBox($0)) },
                minlen: e.minlen
            )
        },
        nodeCluster: nodes.map { $0.cluster() },
        clusters: zip(clusters, titles).map { (s, t) in
            // The title's height and inset, so the gap under it matches the padding on every other side.
            let lead: Float = t.text.isEmpty ? 0.0 : t.size[1] + TITLE_INSET[1]
            let minW: Float = t.text.isEmpty ? 0.0 : t.size[0] + 24.0
            return GCluster(
                parent: s.parent,
                lead: across ? [lead, 0.0] : [0.0, lead],
                minSpan: across ? [0.0, minW] : [minW, 0.0]
            )
        },
        ids: ids
    )
    guard let placed = layered.layout(graph, spacing) else {
        return nil
    }
    func pt(_ p: [Float]) -> [Float] { across ? [p[1], p[0]] : p }
    var c = Canvas()
    c.hover = hover

    func chainOf(_ start: Int?) -> [Int] {
        var cur = start
        var v: [Int] = []
        while let i = cur {
            if v.count > clusters.count {
                break
            }
            v.append(i)
            cur = clusters[i].parent
        }
        v.reverse()
        return v
    }

    let clusterBorder = groupBorder(paint)
    var titleBoxes: [[Float]] = []
    var order: [Int] = Array(0..<clusters.count)
    order.sort { chainOf($0).count < chainOf($1).count }
    for i in order {
        let b = placed.clusters[i]
        if b == [0.0, 0.0, 0.0, 0.0] {
            continue
        }
        let p0 = pt([b[0], b[1]])
        let p1 = pt([b[2], b[3]])
        c.part(.index(.frame, i))
        c.shape(roundedRect(p0[0], p0[1], p1[0], p1[1], 6.0), paint.clusterFill, clusterBorder, 1.0)
        let at = [p0[0] + TITLE_INSET[0], p0[1] + TITLE_INSET[1]]
        c.labelAt(titles[i], at, fonts.title, paint.muted, .start)
        if !titles[i].text.isEmpty {
            titleBoxes.append(connector.titleBox(titles[i], at))
        }
    }

    let centers: [[Float]] = placed.centers.map { pt($0) }
    let sizes: [[Float]] = nodes.map { $0.size() }
    let ends: [(Int, Int)] = edges.map { ($0.from, $0.to) }
    let boxes: [[Float]?] = labels.map { l in l.map { ax(connector.labelBox($0)) } }
    let onCluster: [[Int?]] = edges.map { $0.onCluster }
    let ctx = Ctx(placed, sizes, nodes.map { $0.nodeShape() }, boxes, across, ends)
        .titles(titleBoxes)
        .clusterEnds(onCluster)
    // A label pill takes the colour of the innermost subgraph holding both its ends.
    let backs: [Color] = edges.map { e in
        let ca = chainOf(nodes[e.from].cluster())
        let cb = chainOf(nodes[e.to].cluster())
        var common = 0
        for (x, y) in zip(ca, cb) {
            if x == y { common += 1 } else { break }
        }
        var bg = paint.surface
        for _ in 0..<common {
            bg = overColor(paint.clusterFill, bg)
        }
        return bg
    }
    connector.edges(&c, ctx, edges, labels, backs, titleBoxes, flip, fonts.edge, paint)

    for (i, n) in nodes.enumerated() {
        c.region(i, outline(n.nodeShape(), centers[i], n.size()))
        c.part(.index(.node, i))
        drawLayeredNode(&c, n, centers[i], paint)
    }
    c.part(nil)
    return c
}

private func drawLayeredNode(_ c: inout Canvas, _ node: DrawNode, _ ctr: [Float], _ paint: DiagramStyle) {
    switch node {
    case .start:
        c.fill(ellipse(ctr, 8.0, 8.0), paint.line)
    case .end:
        c.shape(ellipse(ctr, 10.0, 10.0), paint.nodeFill, paint.line, 1.5)
        c.fill(ellipse(ctr, 5.5, 5.5), paint.line)
    case .bar:
        let s = node.size()
        c.fill(roundedRect(ctr[0] - s[0] / 2.0, ctr[1] - s[1] / 2.0, ctr[0] + s[0] / 2.0, ctr[1] + s[1] / 2.0, 2.0), paint.line)
    case .shape(let shape, let label, let size, _, let style):
        let (fill, border, textColor) = style.resolve(paint)
        drawShape(&c, shape, label, ctr, size, [fill, border, textColor], paint)
    case .classBox(let stereo, let name, let fields, let methods, let size, _, let style):
        let (fill, border, textColor) = style.resolve(paint)
        let x0 = ctr[0] - size[0] / 2.0
        let y0 = ctr[1] - size[1] / 2.0
        let x1 = ctr[0] + size[0] / 2.0
        let y1 = ctr[1] + size[1] / 2.0
        c.shape(roundedRect(x0, y0, x1, y1, 4.0), fill, border, 1.0)
        var headFont = paint.font
        headFont.weight = 600.0
        var memFont = paint.font
        memFont.size -= 1.0
        memFont.lineHeight -= 2.0
        var stereoFont = paint.font
        stereoFont.size -= 2.0
        stereoFont.lineHeight -= 4.0
        stereoFont.italic = true
        var y = y0 + 8.0
        if let st = stereo {
            c.label(st, [ctr[0], y + st.size[1] / 2.0], stereoFont, paint.muted, .center)
            y += st.size[1] + 2.0
        }
        c.label(name, [ctr[0], y + name.size[1] / 2.0], headFont, textColor, .center)
        y += name.size[1] + 8.0
        for section in [fields, methods] {
            if section.isEmpty {
                continue
            }
            c.stroke([[x0, y], [x1, y]], false, 1.0, border)
            y += 6.0
            for item in section {
                c.labelAt(item, [x0 + 12.0, y], memFont, textColor, .start)
                y += item.size[1] + 3.0
            }
            y += 3.0
        }
    case .card(let shape, let lines, let size, _, let colors, let person):
        drawShape(&c, shape, Measured(), ctr, size, colors, paint)
        let cap: Float = shape == .cylinder ? shapeRim(size[0]) : 0.0
        let glyph: Float = person ? PERSON : 0.0
        var linesSum: Float = 0.0
        for l in lines { linesSum += l.0.size[1] + 3.0 }
        let total = glyph + linesSum - 3.0
        var y = ctr[1] - total / 2.0 + cap / 2.0
        if person {
            c.fill(ellipse([ctr[0], y + 6.0], 6.0, 6.0), colors[2])
            c.fill(arc([ctr[0], y + 23.0], 11.0, 8.5, 180.0, 360.0, 16), colors[2])
            y += glyph
        }
        for (m, font) in lines {
            c.label(m, [ctr[0], y + m.size[1] / 2.0], font, colors[2], .center)
            y += m.size[1] + 3.0
        }
    case .entity(let name, let rows, let cols, let size, let style):
        let (fill, border, textColor) = style.resolve(paint)
        let x0 = ctr[0] - size[0] / 2.0
        let y0 = ctr[1] - size[1] / 2.0
        let x1 = ctr[0] + size[0] / 2.0
        let y1 = ctr[1] + size[1] / 2.0
        var headFont = paint.font
        headFont.weight = 600.0
        var rowFont = paint.font
        rowFont.size -= 1.0
        rowFont.lineHeight -= 2.0
        let headH = name.size[1] + ENTITY_PAD[1] * 2.0
        c.shape(roundedRect(x0, y0, x1, y1, 4.0), fill, border, 1.0)
        c.label(name, [ctr[0], y0 + headH / 2.0], headFont, textColor, .center)
        var y = y0 + headH
        let stripe = textColor.alpha(0.035)
        for (r, row) in rows.enumerated() {
            let h = entityRowH(row)
            if r % 2 == 1 {
                c.fill([[x0 + 0.5, y], [x1 - 0.5, y], [x1 - 0.5, y + h], [x0 + 0.5, y + h]], stripe)
            }
            c.stroke([[x0, y], [x1, y]], false, r == 0 ? 1.0 : 0.5, r == 0 ? border : border.alpha(0.5))
            var x = x0
            for (i, (cell, w)) in zip(row, cols).enumerated() {
                // Keys are muted; comments, last, are muted and may run the rest of the width.
                let color = i >= 2 ? paint.muted : textColor
                c.labelAt(cell, [x + ENTITY_PAD[0], y + (h - cell.size[1]) / 2.0], rowFont, color, .start)
                x += w
            }
            y += h
        }
    }
}

/// The room a `DrawNode.card`'s person glyph takes above its text.
let PERSON: Float = 30.0

/// A box of a stereotype, a name and two sections of rows (class members, requirement fields).
func classBox(
    _ stereo: String?,
    _ name: String,
    _ fields: [String],
    _ methods: [String],
    _ cluster: Int?,
    _ style: NodeStyle,
    _ paint: DiagramStyle
) -> DrawNode {
    var headFont = paint.font
    headFont.weight = 600.0
    var memFont = paint.font
    memFont.size -= 1.0
    memFont.lineHeight -= 2.0
    var stereoFont = paint.font
    stereoFont.size -= 2.0
    stereoFont.lineHeight -= 4.0
    stereoFont.italic = true
    let stMeasured = stereo.map { measureWrap("«\($0)»", stereoFont, 240.0) }
    let nameMeasured = measureWrap(name, headFont, 240.0)
    let fieldsMeasured: [Measured] = fields.map { measureWrap($0, memFont, 240.0) }
    let methodsMeasured: [Measured] = methods.map { measureWrap($0, memFont, 240.0) }
    var w = max(nameMeasured.size[0], stMeasured?.size[0] ?? 0.0)
    for m in fieldsMeasured + methodsMeasured {
        w = max(w, m.size[0])
    }
    let finalW = max(w + 26.0, 84.0)
    var h: Float = 16.0 + nameMeasured.size[1] + (stMeasured.map { $0.size[1] + 2.0 } ?? 0.0)
    for sec in [fieldsMeasured, methodsMeasured] where !sec.isEmpty {
        var secSum: Float = 0.0
        for m in sec { secSum += m.size[1] + 3.0 }
        h += 9.0 + secSum
    }
    return .classBox(
        stereo: stMeasured,
        name: nameMeasured,
        fields: fieldsMeasured,
        methods: methodsMeasured,
        size: [finalW, max(h, 38.0)],
        cluster: cluster,
        style: style
    )
}

/// An entity's padding inside each cell: `[across, down]`.
let ENTITY_PAD: [Float] = [10.0, 5.0]

func entityRowH(_ row: [Measured]) -> Float {
    var mx: Float = 0.0
    for m in row { mx = max(mx, m.size[1]) }
    return mx + ENTITY_PAD[1] * 2.0
}
