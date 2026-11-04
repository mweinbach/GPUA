// Ported from: crates/rune-mermaid/src/hover.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! What hovering a flowchart or state diagram lights up. Each node keeps its outline as a region
//! and each edge a copy of its drawing in the hover colour, its label's index and a backing for
//! it. The finished scene puts a hover group over every node that shows its edges and their
//! labels (and with `Hover.neighbours` the outlines they reach), and a chain of hover groups
//! along every edge and over its label that show that edge and its label. Hover groups light by
//! their rectangles alone, so an edge's rectangles are cut back from every node's box and a node
//! under the pointer always wins.

import Rune

/// What hovering a flowchart or state diagram node lights up.
public enum Hover: Sendable, Equatable, Hashable {
    /// Nothing.
    case off
    /// The edges in and out of it, with their labels.
    case edges
    /// Its edges, its outline and the outlines of the nodes they reach.
    case neighbours

    public static let `default`: Hover = .edges
}

/// How far either side of an edge's line the pointer lights it, in points.
let EDGE_SLOP: Float = 8.0
/// The most rectangles one edge's line is split into, and in a whole diagram.
private let EDGE_HITS: Int = 16
private let ALL_EDGE_HITS: Int = 1200

struct Trace: Sendable {
    var ends: (Int, Int)
    /// The edge it is, as its piece is keyed.
    var part: Part?
    var ops: [Op]
    /// The line as drawn, for its hit rectangles.
    var line: [[Float]]
    /// Its label's index in `Canvas.labels` and its box, `[x0, y0, x1, y1]`.
    var label: (Int, [Float])?
}

/// One hover group: what it is, keyed by the piece it lights (`hover:n:A`, `hover:e:A>B.0`, and
/// `hover:e:A>B.t` over its label) so it stays that node or edge however the layout moves, where (`[x, y, w, h]`, finished), what it
/// draws lit, and which labels it shows in the hover colour.
struct Spot: Sendable {
    var key: String
    var rect: [Float]
    var lit: Shape
    var labels: [Int]
}

extension Canvas {
    /// Node `i` drawn as `outline`: hovering it lights up its traces.
    mutating func region(_ i: Int, _ outline: [[Float]]) {
        guard hover != nil else { return }
        if regions.count <= i {
            regions.append(contentsOf: Array(repeating: [], count: i + 1 - regions.count))
        }
        regions[i] = outline
    }

    /// The ops drawn since `start` are the edge `from` → `to`: keeps a copy with every `line`
    /// colour turned to the hover colour, a little heavier, for hovering either end or the edge.
    /// `label` is the label drawn with it (its index in `Canvas.labels` and box) and the colour
    /// behind it, which its lit backing covers before tinting.
    mutating func trace(_ from: Int, _ to: Int, _ start: Int, _ line: Color, _ label: (Int, [Float], Color)?) {
        guard let (_, lit) = hover else { return }
        var path: [[Float]] = []
        var traceOps: [Op] = []
        if start <= ops.count {
            for op in ops[start...] {
                switch op {
                case .fill(let p, let c) where c == line:
                    traceOps.append(.fill(p, lit))
                case .stroke(let points, let closed, let width, let cap, let color) where color == line:
                    if !closed {
                        path.append(contentsOf: points)
                    }
                    traceOps.append(.stroke(points: points, closed: closed, width: width + 0.5, cap: cap, color: lit))
                default:
                    traceOps.append(op)
                }
            }
        }
        if let (_, g, back) = label {
            let pill = roundedRect(g[0], g[1], g[2], g[3], 4.0)
            traceOps.append(.fill(pill, back))
            traceOps.append(.fill(pill, Color(r: lit.r, g: lit.g, b: lit.b, a: lit.a * 0.14)))
            traceOps.append(.stroke(points: pill, closed: true, width: 1.0, cap: .round, color: lit))
        }
        let cur = currentPart()
        traces.append(Trace(ends: (from, to), part: cur, ops: traceOps, line: path, label: label.map { ($0.0, $0.1) }))
    }

    /// Every hover group, edges first so a node's lit drawing lands over theirs.
    func hovers(_ map: ([Float]) -> [Float], _ paint: (Shape, Op) -> Shape) -> [Spot] {
        guard let (reach, lit) = hover else { return [] }
        func drawn(_ v: Int) -> Bool {
            v >= 0 && v < regions.count && regions[v].count >= 3
        }
        func rect(_ lo: [Float], _ hi: [Float]) -> [Float] {
            let a = map(lo)
            let z = map(hi)
            return [a[0], a[1], z[0] - a[0], z[1] - a[1]]
        }
        var boxes: [[Float]] = []
        for v in 0..<regions.count where drawn(v) {
            let (lo, hi) = polyBounds(regions[v])
            boxes.append(rect(lo, hi))
        }
        func outlineOp(_ v: Int) -> Op {
            .stroke(points: regions[v], closed: true, width: 1.0, cap: .round, color: lit)
        }
        var spots: [Spot] = []
        var seen: [String: Int] = [:]
        func makeKey(_ part: Part) -> String {
            let base = "hover:\(partKey(part).0)"
            let n = (seen[base] ?? 0) + 1
            seen[base] = n
            return n == 1 ? base : "\(base)~\(n - 1)"
        }
        var budget = ALL_EDGE_HITS
        for (k, t) in traces.enumerated() {
            let edge = makeKey(t.part ?? .index(.edge, k))
            var shape = Shape.new()
            for op in t.ops {
                shape = paint(shape, op)
            }
            let lbls: [Int] = t.label.map { [$0.0] } ?? []
            let line = t.line.map(map)
            var hits = cutAway(lineHits(line, EDGE_SLOP), boxes)
            if hits.count > budget {
                hits.removeSubrange(budget..<hits.count)
            }
            budget -= hits.count
            for (j, r) in hits.enumerated() {
                spots.append(Spot(key: "\(edge).\(j)", rect: r, lit: shape, labels: lbls))
            }
            if let (_, g) = t.label {
                spots.append(Spot(key: "\(edge).t", rect: rect([g[0], g[1]], [g[2], g[3]]), lit: shape, labels: lbls))
            }
        }
        for v in 0..<regions.count where drawn(v) {
            let mine = traces.filter { $0.ends.0 == v || $0.ends.1 == v }
            if mine.isEmpty {
                continue
            }
            var shape = Shape.new()
            for t in mine {
                for op in t.ops {
                    shape = paint(shape, op)
                }
            }
            if reach == .neighbours {
                var near: [Int] = []
                for t in mine {
                    if drawn(t.ends.0) { near.append(t.ends.0) }
                    if drawn(t.ends.1) { near.append(t.ends.1) }
                }
                near.sort()
                var deduped: [Int] = []
                for u in near where deduped.last != u {
                    deduped.append(u)
                }
                for u in deduped {
                    shape = paint(shape, outlineOp(u))
                }
            }
            let (lo, hi) = polyBounds(regions[v])
            let lbls = mine.compactMap { $0.label?.0 }
            spots.append(Spot(key: makeKey(.index(.node, v)), rect: rect(lo, hi), lit: shape, labels: lbls))
        }
        return spots
    }
}

private func polyBounds(_ pts: [[Float]]) -> ([Float], [Float]) {
    var lo: [Float] = [.greatestFiniteMagnitude, .greatestFiniteMagnitude]
    var hi: [Float] = [-.greatestFiniteMagnitude, -.greatestFiniteMagnitude]
    for p in pts {
        lo[0] = min(lo[0], p[0])
        lo[1] = min(lo[1], p[1])
        hi[0] = max(hi[0], p[0])
        hi[1] = max(hi[1], p[1])
    }
    return (lo, hi)
}

/// Rectangles (`[x, y, w, h]`) covering `line` to `slop` either side: a run along it grows while
/// its box stays thin, so straight runs take one rectangle and curves a few; at most `EDGE_HITS`.
func lineHits(_ line: [[Float]], _ slop: Float) -> [[Float]] {
    var pts: [[Float]] = []
    if line.count >= 2 {
        for idx in 0..<(line.count - 1) {
            let a = line[idx]
            let b = line[idx + 1]
            let raw = (dist(a, b) / 4.0).rounded(.up)
            let n = Int(clampF(raw.isNaN ? 1.0 : raw, 1.0, 200.0))
            for i in 0..<n {
                pts.append(lerp(a, b, Float(i) / Float(n)))
            }
        }
    }
    if let last = line.last {
        pts.append(last)
    }
    pts.removeAll { !$0[0].isFinite || !$0[1].isFinite }
    if pts.isEmpty {
        return []
    }
    var thin = slop
    while true {
        var out: [[Float]] = []
        var lo = pts[0]
        var hi = pts[0]
        if pts.count >= 2 {
            for idx in 0..<(pts.count - 1) {
                let prev = pts[idx]
                let p = pts[idx + 1]
                let nlo: [Float] = [min(lo[0], p[0]), min(lo[1], p[1])]
                let nhi: [Float] = [max(hi[0], p[0]), max(hi[1], p[1])]
                if min(nhi[0] - nlo[0], nhi[1] - nlo[1]) > thin {
                    out.append([lo[0] - slop, lo[1] - slop, hi[0] - lo[0] + 2.0 * slop, hi[1] - lo[1] + 2.0 * slop])
                    lo = [min(prev[0], p[0]), min(prev[1], p[1])]
                    hi = [max(prev[0], p[0]), max(prev[1], p[1])]
                } else {
                    lo = nlo
                    hi = nhi
                }
            }
        }
        out.append([lo[0] - slop, lo[1] - slop, hi[0] - lo[0] + 2.0 * slop, hi[1] - lo[1] + 2.0 * slop])
        if out.count <= EDGE_HITS || thin > 4096.0 {
            return out
        }
        thin *= 2.0
    }
}

/// `hits` with every part over one of `nodes` cut away, keeping the biggest side left of each cut
/// and dropping what gets too small to aim at.
func cutAway(_ hits: [[Float]], _ nodes: [[Float]]) -> [[Float]] {
    var result: [[Float]] = []
    for var r in hits {
        var kept = true
        for n in nodes {
            let x0 = r[0]
            let y0 = r[1]
            let x1 = r[0] + r[2]
            let y1 = r[1] + r[3]
            let nx0 = n[0]
            let ny0 = n[1]
            let nx1 = n[0] + n[2]
            let ny1 = n[1] + n[3]
            if nx0 >= x1 || nx1 <= x0 || ny0 >= y1 || ny1 <= y0 {
                continue
            }
            let sides: [[Float]] = [
                [x0, y0, nx0 - x0, r[3]],
                [nx1, y0, x1 - nx1, r[3]],
                [x0, y0, r[2], ny0 - y0],
                [x0, ny1, r[2], y1 - ny1],
            ]
            var best: [Float]? = nil
            for s in sides where s[2] >= 4.0 && s[3] >= 4.0 {
                if let b = best {
                    let areaB = b[2] * b[3]
                    let areaS = s[2] * s[3]
                    // Match Rust `Iterator::max_by`: returns the last element if equal
                    if !totalLess(areaS, areaB) {
                        best = s
                    }
                } else {
                    best = s
                }
            }
            if let b = best {
                r = b
            } else {
                kept = false
                break
            }
        }
        if kept {
            result.append(r)
        }
    }
    return result
}
