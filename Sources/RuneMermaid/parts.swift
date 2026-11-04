// Ported from: crates/rune-mermaid/src/parts.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! A diagram's drawing split into the things it shows (each node, edge and frame), so the
//! finished scene keys each by what it is: a diagram streaming in brings each new node, edge and
//! frame in on its own while the ones already there glide to their new places, and a finished
//! diagram draws the same pieces at once.

import Rune

/// What a run of drawing is.
enum PartKind: Sendable, Equatable, Hashable {
    /// A node, a participant, a note: fades and grows in.
    case node
    /// A connector or message: draws on from its source to its target.
    case edge
    /// A subgraph, a frame, a band, lifelines: fades in.
    case frame

    var prefix: String {
        switch self {
        case .node: return "n:"
        case .edge: return "e:"
        case .frame: return "g:"
        }
    }

    /// How a piece of this kind enters while its diagram streams in.
    func enter() -> Transition {
        switch self {
        case .node: return Transition.scale(0.96)
        case .edge: return Transition.draw()
        case .frame: return Transition.opacity()
        }
    }

    /// How a label of this kind enters: an edge's after its line is under way.
    func labelEnter() -> (Transition, Float) {
        switch self {
        case .node: return (Transition.scale(0.96), 0.0)
        case .edge: return (Transition.opacity(), 0.12)
        case .frame: return (Transition.opacity(), 0.0)
        }
    }
}

/// Which thing a run of drawing belongs to: the `i`th of its kind (named by `Names`, so a
/// flowchart node keeps its key when nodes before it come and go), or one named outright.
enum Part: Sendable, Equatable {
    case index(PartKind, Int)
    case key(PartKind, String)
}

/// What the `i`th node, edge and frame are called (its Mermaid id). Unnamed ones go by index.
struct Names: Sendable, Equatable {
    var nodes: [String] = []
    var edges: [String] = []
    var frames: [String] = []

    init(nodes: [String] = [], edges: [String] = [], frames: [String] = []) {
        self.nodes = nodes
        self.edges = edges
        self.frames = frames
    }

    /// Nodes and frames named as given, edges by their ends' names (`A>B`, then `A>B~1` for a
    /// second edge between the same two).
    static func new(_ nodes: [String], _ edgeList: [Edge], _ frames: [String]) -> Names {
        func id(_ i: Int) -> String {
            (i >= 0 && i < nodes.count) ? nodes[i] : "#\(i)"
        }
        struct Pair: Hashable {
            var a: Int
            var b: Int
        }
        var seen: [Pair: Int] = [:]
        var edgeNames: [String] = []
        edgeNames.reserveCapacity(edgeList.count)
        for e in edgeList {
            let p = Pair(a: e.from, b: e.to)
            let n = (seen[p] ?? 0) + 1
            seen[p] = n
            let name = "\(id(e.from))>\(id(e.to))"
            edgeNames.append(n == 1 ? name : "\(name)~\(n - 1)")
        }
        return Names(nodes: nodes, edges: edgeNames, frames: frames)
    }

    func key(_ part: Part) -> (String, PartKind) {
        switch part {
        case .index(let k, let i):
            let list: [String]
            switch k {
            case .node: list = nodes
            case .edge: list = edges
            case .frame: list = frames
            }
            let name = (i >= 0 && i < list.count) ? list[i] : "#\(i)"
            return ("\(k.prefix)\(name)", k)
        case .key(let k, let s):
            return ("\(k.prefix)\(s)", k)
        }
    }
}

/// Where a part starts: the first op and label drawn for it (`nil`: drawing that is no part).
typealias Mark = (Int, Int, Part?)

extension Canvas {
    /// What is drawn from here on belongs to `part`, until the next call (`nil` ends it).
    mutating func part(_ part: Part?) {
        marks.append((ops.count, labels.count, part))
    }

    /// What `part` is keyed by, in its pieces and its hover groups alike.
    func partKey(_ part: Part) -> (String, PartKind) {
        let (key, kind) = names.key(part)
        // Turned on its side, every edge takes a new route: a diagram streaming in glides its
        // nodes to their new places and draws its edges on afresh, rather than bending the old
        // lines into the new ones.
        return (turned && kind == .edge ? "\(key)|v" : key, kind)
    }

    /// The part drawn now: the one the last `Canvas.part` named.
    func currentPart() -> Part? {
        marks.last?.2
    }

    /// The runs of drawing, in order: each run's part, its ops and its labels.
    func runs() -> [(Part?, Range<Int>, Range<Int>)] {
        var out: [(Part?, Range<Int>, Range<Int>)] = []
        var at: (Int, Int, Part?) = (0, 0, nil)
        for (o, l, p) in marks + [(ops.count, labels.count, nil)] {
            if o > at.0 || l > at.1 {
                out.append((at.2, at.0..<o, at.1..<l))
            }
            at = (o, l, p)
        }
        return out
    }
}

/// One keyed piece of a finished scene: its own shape, placed at `at` and `size` big, in the
/// diagram's finished points.
struct Piece: Sendable {
    var key: String
    var kind: PartKind?
    var at: [Float]
    var size: [Float]
    var shape: Shape

    /// Placed by offset, not layout: a reply's growth row snaps the layout of what it holds,
    /// but an offset still springs, so a piece glides to its new place there too.
    func el(_ streaming: Bool) -> El {
        let enter: Transition
        if streaming {
            enter = kind?.enter() ?? Transition.opacity()
        } else {
            enter = Transition.none()
        }
        // PORT NOTE: `Sources/Rune` does not yet forward `El.offset` (`vis.offset`) into `RuneMotion.Scene`,
        // so `.absolute(at[0], at[1]).animateLayout()` places the piece at `at` and keeps layout springing
        // active even inside `GrowthSpec` rows.
        return canvas(shape)
            .key(key)
            .absolute(at[0], at[1])
            .animateLayout()
            .size(size[0], size[1])
            .transition(enter)
    }
}

/// Each label's key and kind, beside `Scene.labels`.
typealias LabelKey = (String, PartKind?)

/// Splits `c`'s finished ops (already moved and scaled by `map` and `stroke`) into keyed pieces,
/// and keys its labels by the part each belongs to.
func partsPieces(
    _ c: Canvas,
    _ map: ([Float]) -> [Float],
    _ stroke: (Float) -> Float
) -> ([Piece], [LabelKey]) {
    var pieces: [Piece] = []
    var labelKeys: [LabelKey] = Array(repeating: ("", nil), count: c.labels.count)
    var seen: [String: Int] = [:]
    var restLabels = 0
    var restRuns = 0
    for (part, opRange, labelRange) in c.runs() {
        let key: String
        let kind: PartKind?
        if let p = part {
            let (k, kd) = c.partKey(p)
            key = k
            kind = kd
        } else {
            restRuns += 1
            key = restRuns == 1 ? "shape" : "shape\(restRuns)"
            kind = nil
        }
        let n = seen[key] ?? 0
        let runKey = n == 0 ? key : "\(key)~\(n)"
        seen[key] = n + 1
        for (j, i) in labelRange.enumerated() {
            if let k = kind {
                labelKeys[i] = ("\(runKey).t\(j)", k)
            } else {
                restLabels += 1
                labelKeys[i] = ("t\(restLabels - 1)", nil)
            }
        }
        if let built = buildPiece(c.ops[opRange], runKey, kind, map, stroke) {
            pieces.append(built)
        }
    }
    return (pieces, labelKeys)
}

private func buildPiece(
    _ ops: ArraySlice<Op>,
    _ key: String,
    _ kind: PartKind?,
    _ map: ([Float]) -> [Float],
    _ stroke: (Float) -> Float
) -> Piece? {
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
            for p in points { add(map(p), 0.0) }
        case .stroke(let points, _, let width, _, _):
            // A point beyond the stroke's half width for its round caps and antialiasing.
            let r = stroke(width) / 2.0 + 1.0
            for p in points { add(map(p), r) }
        }
    }
    if b[0] > b[2] {
        return nil
    }
    let local: ([Float]) -> [Float] = { p in
        let q = map(p)
        return [q[0] - b[0], q[1] - b[1]]
    }
    var shape = Shape.new()
    for op in ops {
        switch op {
        case .fill(let points, let color):
            shape = shape.fill(points.map(local), color)
        case .stroke(let points, let closed, let width, let cap, let color):
            shape = shape.strokeWith(points.map(local), closed, stroke(width), cap, color)
        }
    }
    let size: [Float] = [max(b[2] - b[0], 1.0), max(b[3] - b[1], 1.0)]
    // Coordinates stretch with the piece, so a frame or lifeline that grows springs to its new
    // size instead of jumping.
    return Piece(key: key, kind: kind, at: [b[0], b[1]], size: size, shape: shape.viewBox(size[0], size[1]))
}
