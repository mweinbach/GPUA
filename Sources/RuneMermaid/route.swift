// Ported from: crates/rune-mermaid/src/route.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Edge routes for layered diagrams. Each edge leaves and enters its nodes straight along the
//! rank axis, keeps only the layout's bend points it needs to stay clear of other nodes, and
//! joins them with cubics whose tangents also run along the rank axis: no kinks at bends, no
//! wobble from bend points a few points apart, and arrowheads that sit on the line's last
//! tangent. Labels move onto the curve when they fit there.
//!
//! Everything here works in the layout's own axes (ranks run down `y`); callers map points to
//! the screen with `Ctx.screen`.

/// Clearance between an edge and nodes it passes.
private let NODE_GAP: Float = 5.0
/// Clearance between a moved label and anything else.
private let LABEL_GAP: Float = 2.0

/// An edge drawn: its curve and the tips and directions of its heads, in screen points.
struct Route {
    var curve: [[Float]]
    var tipStart: [Float]
    var tipEnd: [Float]
    /// Unit directions the heads point, out of the curve.
    var dirStart: [Float]
    var dirEnd: [Float]
    var label: [Float]?
}

/// The drawing an edge routes through.
struct Ctx {
    var placed: Placed
    /// Screen sizes and shapes per node, then per subgraph an edge stops on (`Ctx.clusterEnds`).
    var sizes: [[Float]]
    var shapes: [NodeShape]
    /// Label box sizes per edge, in layout axes.
    var labels: [[Float]?]
    /// The layout's `x` is the screen's `y`.
    var across: Bool
    /// Edge ends per edge, `(from, to)` as the source wrote them.
    var ends: [(Int, Int)]
    /// Centres in layout axes, in the order of `sizes`.
    private var centers: [[Float]]
    /// How many of `sizes` are nodes; the rest are subgraphs edges stop on.
    private var real: Int
    /// Node outlines in layout axes.
    private var outlines: [[[Float]]]
    /// Subgraph titles, `[x0, y0, x1, y1]` in layout axes.
    private var titleRects: [[Float]]

    init(
        _ placed: Placed,
        _ sizes: [[Float]],
        _ shapes: [NodeShape],
        _ labels: [[Float]?],
        _ across: Bool,
        _ ends: [(Int, Int)]
    ) {
        let swap: ([Float]) -> [Float] = { p in across ? [p[1], p[0]] : p }
        let outlines = (0..<sizes.count).map { v in
            outline(shapes[v], swap(placed.centers[v]), sizes[v]).map(swap)
        }
        self.placed = placed
        self.sizes = sizes
        self.shapes = shapes
        self.labels = labels
        self.across = across
        self.ends = ends
        self.centers = placed.centers
        self.real = sizes.count
        self.outlines = outlines
        self.titleRects = []
    }

    /// Stops edge ends on subgraph borders, `[start, end]` per edge: each subgraph named joins as
    /// a box the edge meets the way it meets a node, and that nodes keep clear of.
    func clusterEnds(_ on: [[Int?]]) -> Ctx {
        var copy = self
        var boxes: [(Int, Int)] = []
        let limit = min(on.count, copy.ends.count)
        for i in 0..<limit {
            let pair = on[i]
            for k in 0..<min(pair.count, 2) {
                guard let cIdx = pair[k],
                      cIdx >= 0, cIdx < copy.placed.clusters.count,
                      copy.placed.clusters[cIdx] != [0.0, 0.0, 0.0, 0.0]
                else { continue }
                let b = copy.placed.clusters[cIdx]
                let v: Int
                if let found = boxes.first(where: { $0.0 == cIdx }) {
                    v = found.1
                } else {
                    let x0 = b[0], y0 = b[1], x1 = b[2], y1 = b[3]
                    let c = [(x0 + x1) / 2.0, (y0 + y1) / 2.0]
                    let size = copy.screen([x1 - x0, y1 - y0])
                    let shape = NodeShape.rect
                    copy.outlines.append(outline(shape, copy.screen(c), size).map { copy.screen($0) })
                    copy.centers.append(c)
                    copy.sizes.append(size)
                    copy.shapes.append(shape)
                    let newV = copy.sizes.count - 1
                    boxes.append((cIdx, newV))
                    v = newV
                }
                if k == 0 {
                    copy.ends[i].0 = v
                } else {
                    copy.ends[i].1 = v
                }
            }
        }
        return copy
    }

    /// Keeps edges and labels off subgraph titles, given as screen rects.
    func titles(_ rects: [[Float]]) -> Ctx {
        var copy = self
        copy.titleRects = rects.map { r in
            let a = copy.screen([r[0], r[1]])
            let b = copy.screen([r[2], r[3]])
            return [a[0], a[1], b[0], b[1]]
        }
        return copy
    }

    /// Whether a label's box (screen, `[x0, y0, x1, y1]`) crosses a subgraph's border.
    func onBorder(_ r: [Float]) -> Bool {
        let a = screen([r[0], r[1]])
        let b = screen([r[2], r[3]])
        let nr = [min(a[0], b[0]), min(a[1], b[1]), max(a[0], b[0]), max(a[1], b[1])]
        return placed.clusters.contains { c in
            c != [0.0, 0.0, 0.0, 0.0] && straddles(nr, c)
        }
    }

    /// A layout point on the screen (and back: the map is its own inverse).
    func screen(_ p: [Float]) -> [Float] {
        across ? [p[1], p[0]] : p
    }

    private func size(_ v: Int) -> [Float] {
        screen(sizes[v])
    }

    /// Where an edge may touch node `v`: within this far of its centre across the rank axis.
    private func portReach(_ v: Int) -> Float {
        let half = size(v)[0] / 2.0
        let isFlat: Bool
        switch shapes[v] {
        case .cylinder, .linedCylinder:
            isFlat = !across
        default:
            isFlat = shapes[v].flat()
        }
        if isFlat {
            return max(half - 10.0, half * 0.5)
        }
        switch shapes[v] {
        case .stadium where !across:
            return max(half - size(v)[1] / 2.0 - 2.0, half * 0.4)
        case .hexagon where !across:
            return max(half - size(v)[1] / 4.0 - 6.0, half * 0.4)
        case .diamond, .hexagon:
            return half * 0.6
        default:
            return half * 0.45
        }
    }

    /// The point on `v`'s outline straight along the rank axis from `x`, on the side `s` points to.
    private func port(_ v: Int, _ xRaw: Float, _ s: Float) -> [Float] {
        let c = centers[v]
        let reach = portReach(v)
        let x = clampF(xRaw, c[0] - reach, c[0] + reach)
        let poly = outlines[v]
        var best: Float? = nil
        for i in 0..<poly.count {
            let a = poly[i]
            let b = poly[(i + 1) % poly.count]
            if (a[0] - x) * (b[0] - x) > 0.0 || abs(a[0] - b[0]) < 1e-4 {
                continue
            }
            let y = a[1] + (b[1] - a[1]) * (x - a[0]) / (b[0] - a[0])
            if best == nil || (y - best!) * s > 0.0 {
                best = y
            }
        }
        if let y = best, (y - c[1]) * s >= 0.0 {
            return [x, y]
        }
        let t = boundary(shapes[v], screen(c), sizes[v], screen([x, c[1] + s * 1e4]))
        return screen(t)
    }

    /// Whether `p` keeps `gap` away from node `v`.
    private func clearOf(_ v: Int, _ p: [Float], _ gap: Float) -> Bool {
        let c = centers[v]
        let s = size(v)
        if abs(p[0] - c[0]) > s[0] / 2.0 + gap || abs(p[1] - c[1]) > s[1] / 2.0 + gap {
            return true
        }
        let poly = outlines[v]
        if routeInside(poly, p) {
            return false
        }
        for i in 0..<poly.count {
            if segDist(p, poly[i], poly[(i + 1) % poly.count]) <= gap {
                return false
            }
        }
        return true
    }

    /// Other edges' label boxes, where the layout put them, and subgraph titles.
    private func labelBoxes(_ skip: Int) -> [[Float]] {
        var out: [[Float]] = []
        for j in 0..<labels.count where j != skip {
            if let at = placed.labels[j], let s = labels[j] {
                out.append([at[0] - s[0] / 2.0, at[1] - s[1] / 2.0, at[0] + s[0] / 2.0, at[1] + s[1] / 2.0])
            }
        }
        out.append(contentsOf: titleRects)
        return out
    }

    /// Whether the curve from `a` to `b` stays clear of every node but `ends` and of other labels.
    private func clear(_ edge: Int, _ a: [Float], _ b: [Float], _ ends: (Int, Int)) -> Bool {
        let cub = routeCubic(a, b)
        var pts: [[Float]] = []
        if cub.count >= 2 {
            for idx in 0..<(cub.count - 1) {
                let p0 = cub[idx]
                let p1 = cub[idx + 1]
                let steps = Int(max((dist(p0, p1) / 3.0).rounded(.up), 1.0))
                for k in 0..<steps {
                    pts.append(lerp(p0, p1, Float(k) / Float(steps)))
                }
            }
        }
        pts.append(b)
        let boxes = labelBoxes(edge)
        for p in pts {
            for v in 0..<real where v != ends.0 && v != ends.1 {
                if !clearOf(v, p, NODE_GAP) {
                    return false
                }
            }
            for r in boxes {
                if !(p[0] < r[0] || p[0] > r[2] || p[1] < r[1] || p[1] > r[3]) {
                    return false
                }
            }
        }
        return true
    }

    /// Edge `i`'s route, with its heads' insets `[start, end]` taken off the line.
    func route(_ i: Int, _ flip: Bool, _ insets: [Float]) -> Route {
        let (from, to) = ends[i]
        var path = placed.paths[i]
        if flip {
            path.reverse()
        }
        let label = placed.labels[i]
        // Edges between the same two nodes keep the layout's separate tracks.
        let twin = ends.enumerated().contains { (j, pair) in
            j != i && ((pair.0 == from && pair.1 == to) || (pair.0 == to && pair.1 == from))
        }
        let labelAt: Int? = label.flatMap { l in path.firstIndex(of: l) }
        var anc = anchors(i, path, twin, nil)
        var at = label
        if let l = label, let lSize = labels[i], !twin {
            // The label sits on the line where it crosses the label's rank, if the line runs
            // straight through it there; a slanted line would jog across the gap.
            let line = routeCurve(anc)
            func upright(_ p: [Float]) -> Bool {
                guard let a = along(line, p[1] - lSize[1] / 2.0),
                      let b = along(line, p[1] + lSize[1] / 2.0)
                else { return false }
                return abs(a - b) < 1.0
            }
            let on = along(line, l[1]).map { [$0, l[1]] }
            if let p = on, upright(p), labelFits(i, p, lSize) {
                at = p
            } else {
                anc = anchors(i, path, false, labelAt)
                // The line meets the label square on: into its near side, out of its far one.
                if let k = anc.firstIndex(of: l), k > 0, k + 1 < anc.count {
                    let h = lSize[1] / 2.0 * signumF(anc[k + 1][1] - anc[k - 1][1])
                    anc.replaceSubrange(k...k, with: [[l[0], l[1] - h], [l[0], l[1] + h]])
                }
            }
        }

        let n = anc.count
        let s0 = signumF(anc[1][1] - anc[0][1])
        let s1 = signumF(anc[n - 1][1] - anc[n - 2][1])
        let tipStart = anc[0]
        let tipEnd = anc[n - 1]
        func hasRoom(_ a: [Float], _ b: [Float], _ ins: Float) -> Bool {
            abs(b[1] - a[1]) > ins + 4.0
        }
        if hasRoom(anc[0], anc[1], insets[0]) {
            anc[0][1] += s0 * insets[0]
        }
        if hasRoom(anc[n - 2], anc[n - 1], insets[1]) {
            anc[n - 1][1] -= s1 * insets[1]
        }
        return Route(
            curve: routeCurve(anc).map { screen($0) },
            tipStart: screen(tipStart),
            tipEnd: screen(tipEnd),
            dirStart: screen([0.0, -s0]),
            dirEnd: screen([0.0, s1]),
            label: at.map { screen($0) }
        )
    }

    /// Ports on both nodes, then the fewest of `path`'s bend points that keep the curve clear;
    /// `all` keeps every one, and `at` one in particular.
    private func anchors(_ i: Int, _ path: [[Float]], _ all: Bool, _ at: Int?) -> [[Float]] {
        func keep(_ k: Int) -> Bool { all || k == at }
        let (from, to) = ends[i]
        let n = path.count
        let endPair = (from, to)
        let s0 = signumF(path[1][1] - path[0][1])
        let s1 = signumF(path[n - 1][1] - path[n - 2][1])
        if !all, at == nil, let pair = direct(i, path, s0, s1) {
            return pair
        }
        var pts = path
        pts[0] = port(from, path[1][0], s0)
        pts[n - 1] = port(to, path[n - 2][0], -s1)

        // Greedy: from each kept point, jump to the farthest point the curve reaches cleanly.
        var kept: [Int] = [0]
        var k = 0
        while k < n - 1 {
            var stop = n - 1
            for j in (k + 1)..<n {
                if j == n - 1 || keep(j) {
                    stop = j
                    break
                }
            }
            var next = k + 1
            for j in stride(from: stop, through: k + 1, by: -1) {
                if j == k + 1 || clear(i, pts[k], pts[j], endPair) {
                    next = j
                    break
                }
            }
            kept.append(next)
            k = next
        }
        var out: [[Float]] = kept.map { pts[$0] }

        // Ports face what they now connect to: straight down when both nodes can meet, else
        // as close to straight as each allows.
        let m = out.count
        let c0 = centers[from][0]
        let c1 = centers[to][0]
        let r0 = portReach(from)
        let r1 = portReach(to)
        let lo = max(c0 - r0, c1 - r1)
        let hi = min(c0 + r0, c1 + r1)
        let wanted: (Float, Float)
        if m == 2 && lo <= hi {
            var sum: Float = 0.0
            if n > 2 {
                for p in path[1..<(n - 1)] { sum += p[0] }
            }
            let mid = sum / Float(max(n - 2, 1))
            let x = n > 2 ? clampF(mid, lo, hi) : clampF((c0 + c1) / 2.0, lo, hi)
            wanted = (x, x)
        } else {
            wanted = (out[1][0], out[m - 2][0])
        }
        if m == 2 {
            let facing = (out[m - 1][0], out[0][0])
            for (x0, x1) in [wanted, facing] {
                let a = port(from, x0, s0)
                let b = port(to, x1, -s1)
                if clear(i, a, b, endPair) {
                    out[0] = a
                    out[m - 1] = b
                    break
                }
            }
        } else {
            func near(_ v: Int, _ toward: [Float], _ s: Float, _ first: Bool) -> [Float]? {
                let c = centers[v][0]
                let r = portReach(v)
                var xs: [Float] = (0...8).map { k in c - r + 2.0 * r * Float(k) / 8.0 }
                xs.append(clampF(toward[0], c - r, c + r))
                xs.sort { totalLess(abs($0 - toward[0]), abs($1 - toward[0])) }
                for x in xs {
                    let p = port(v, x, s)
                    let ok = first ? clear(i, p, toward, endPair) : clear(i, toward, p, endPair)
                    if ok {
                        return p
                    }
                }
                return nil
            }
            if let a = near(from, out[1], s0, true) {
                out[0] = a
            }
            if let b = near(to, out[m - 2], -s1, false) {
                out[m - 1] = b
            }
        }
        return out
    }

    /// One curve straight from node to node, as straight as the nodes allow.
    private func direct(_ i: Int, _ path: [[Float]], _ s0: Float, _ s1: Float) -> [[Float]]? {
        let TRIES = 16
        let (from, to) = ends[i]
        let c0 = centers[from][0]
        let c1 = centers[to][0]
        let r0 = portReach(from)
        let r1 = portReach(to)
        var xs: [Float] = []
        if path.count > 2 {
            for p in path[1..<(path.count - 1)] { xs.append(p[0]) }
        }
        xs.append(contentsOf: [c0, c1, c0 - r0, c0 + r0, c1 - r1, c1 + r1])
        var pairs: [(Float, Float)] = []
        for a in xs {
            for b in xs {
                pairs.append((clampF(a, c0 - r0, c0 + r0), clampF(b, c1 - r1, c1 + r1)))
            }
        }
        func cost(_ p: (Float, Float)) -> Float {
            abs(p.0 - p.1) * 4.0 + abs(p.0 - c0) + abs(p.1 - c1)
        }
        pairs.sort { totalLess(cost($0), cost($1)) }
        var deduped: [(Float, Float)] = []
        for p in pairs {
            if let prev = deduped.last, abs(p.0 - prev.0) < 0.5 && abs(p.1 - prev.1) < 0.5 {
                continue
            }
            deduped.append(p)
        }
        for (x0, x1) in deduped.prefix(TRIES) {
            let a = port(from, x0, s0)
            let b = port(to, x1, -s1)
            if clear(i, a, b, (from, to)) {
                return [a, b]
            }
        }
        return nil
    }

    /// Whether edge `i`'s label, centred at `p`, keeps clear of every node and other label.
    private func labelFits(_ i: Int, _ p: [Float], _ lSize: [Float]) -> Bool {
        let hw = lSize[0] / 2.0 + LABEL_GAP
        let hh = lSize[1] / 2.0 + LABEL_GAP
        let corners: [[Float]] = [
            [p[0] - hw, p[1] - hh],
            [p[0] + hw, p[1] - hh],
            [p[0] + hw, p[1] + hh],
            [p[0] - hw, p[1] + hh],
            p,
        ]
        for v in 0..<real {
            let c = centers[v]
            let s = size(v)
            let apart = abs(p[0] - c[0]) > hw + s[0] / 2.0 || abs(p[1] - c[1]) > hh + s[1] / 2.0
            if !apart {
                let poly = outlines[v]
                let cornersClear = corners.allSatisfy { !routeInside(poly, $0) }
                let polyClear = poly.allSatisfy { abs($0[0] - p[0]) > hw || abs($0[1] - p[1]) > hh }
                if !(cornersClear && polyClear) {
                    return false
                }
            }
        }
        let rect: [Float] = [p[0] - hw, p[1] - hh, p[0] + hw, p[1] + hh]
        let bordersOk = !placed.clusters.contains { c in
            c != [0.0, 0.0, 0.0, 0.0] && straddles(rect, c)
        }
        guard bordersOk else { return false }
        for r in labelBoxes(i) {
            if !(p[0] + hw < r[0] || p[0] - hw > r[2] || p[1] + hh < r[1] || p[1] - hh > r[3]) {
                return false
            }
        }
        return true
    }
}

/// Rust `f32::signum` equivalent: `1.0` for `+0.0` and positives, `-1.0` for `-0.0` and negatives, `NaN` for `NaN`.
@inline(__always)
private func signumF(_ x: Float) -> Float {
    if x.isNaN { return .nan }
    return x.sign == .minus ? -1.0 : 1.0
}

/// A cubic from `a` to `b` leaving and arriving along the rank axis, flattened.
func routeCubic(_ a: [Float], _ b: [Float]) -> [[Float]] {
    let dy = b[1] - a[1]
    if abs(b[0] - a[0]) < 0.25 {
        return [a, b]
    }
    let c1 = [a[0], a[1] + dy * 0.5]
    let c2 = [b[0], b[1] - dy * 0.5]
    let len = dist(a, c1) + dist(c1, c2) + dist(c2, b)
    let steps = Int(clampF((len / 3.0).rounded(.up), 8.0, 96.0))
    return (0...steps).map { s in
        let t = Float(s) / Float(steps)
        let u = 1.0 - t
        let b0 = u * u * u
        let b1 = 3.0 * u * u * t
        let b2 = 3.0 * u * t * t
        let b3 = t * t * t
        return [
            b0 * a[0] + b1 * c1[0] + b2 * c2[0] + b3 * b[0],
            b0 * a[1] + b1 * c1[1] + b2 * c2[1] + b3 * b[1],
        ]
    }
}

/// The curve through `anchors`, one `routeCubic` per pair.
func routeCurve(_ anchors: [[Float]]) -> [[Float]] {
    guard !anchors.isEmpty else { return [] }
    var out: [[Float]] = [anchors[0]]
    if anchors.count >= 2 {
        for idx in 0..<(anchors.count - 1) {
            out.append(contentsOf: routeCubic(anchors[idx], anchors[idx + 1]).dropFirst())
        }
    }
    return out
}

/// Where `pts` crosses the rank coordinate `y`.
private func along(_ pts: [[Float]], _ y: Float) -> Float? {
    guard pts.count >= 2 else { return nil }
    for idx in 0..<(pts.count - 1) {
        let a = pts[idx]
        let b = pts[idx + 1]
        if (a[1] - y) * (b[1] - y) > 0.0 || abs(a[1] - b[1]) < 1e-5 {
            continue
        }
        return a[0] + (b[0] - a[0]) * (y - a[1]) / (b[1] - a[1])
    }
    return nil
}

/// Whether rect `r` lies partly inside and partly outside rect `c` (both `[x0, y0, x1, y1]`).
private func straddles(_ r: [Float], _ c: [Float]) -> Bool {
    let overlaps = r[0] < c[2] && r[2] > c[0] && r[1] < c[3] && r[3] > c[1]
    let within = r[0] >= c[0] && r[2] <= c[2] && r[1] >= c[1] && r[3] <= c[3]
    return overlaps && !within
}

func routeInside(_ poly: [[Float]], _ p: [Float]) -> Bool {
    guard !poly.isEmpty else { return false }
    var odd = false
    for i in 0..<poly.count {
        let a = poly[i]
        let b = poly[(i + 1) % poly.count]
        if (a[1] > p[1]) != (b[1] > p[1]) && p[0] < a[0] + (b[0] - a[0]) * (p[1] - a[1]) / (b[1] - a[1]) {
            odd.toggle()
        }
    }
    return odd
}

func segDist(_ p: [Float], _ a: [Float], _ b: [Float]) -> Float {
    let dx = b[0] - a[0]
    let dy = b[1] - a[1]
    let l = dx * dx + dy * dy
    let t: Float = l < 1e-6 ? 0.0 : clampF(((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / l, 0.0, 1.0)
    return dist(p, [a[0] + dx * t, a[1] + dy * t])
}
