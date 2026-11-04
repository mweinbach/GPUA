// Ported from: crates/rune-mermaid/src/layered.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! A small layered (Sugiyama) layout for flowcharts and state diagrams, top to bottom: cycles
//! broken by reversing DFS back edges, longest-path ranks on a doubled scale (so edge labels
//! get a rank of their own), long edges split by dummy nodes, barycentre ordering sweeps that
//! keep subgraphs contiguous, and positions from alternating weighted isotonic regressions
//! toward each node's neighbours. Other directions transpose or mirror the result.
//!
//! Sized for the diagrams agents write (tens of nodes): every step is at most quadratic in a
//! layer's edges.

/// The most ranks one edge asks to span (`minlen`); longer links draw this long.
let MAX_MINLEN: Int = 8

/// The most points long edges may add before a graph is left unlaid (see `layered.layout`).
private let MAX_DUMMIES: Int = 3000

/// What to lay out. Sizes are in the layout's own axes: `[along a layer, across layers]`.
struct Graph {
    var sizes: [[Float]]
    var edges: [GEdge]
    /// Each node's innermost cluster.
    var nodeCluster: [Int?]
    var clusters: [GCluster]
    /// Each node's name, which a build of a diagram streaming in knows it by (empty: by index).
    var ids: [String]

    init(
        sizes: [[Float]] = [],
        edges: [GEdge] = [],
        nodeCluster: [Int?] = [],
        clusters: [GCluster] = [],
        ids: [String] = []
    ) {
        self.sizes = sizes
        self.edges = edges
        self.nodeCluster = nodeCluster
        self.clusters = clusters
        self.ids = ids
    }
}

struct GEdge {
    var from: Int
    var to: Int
    /// The label's size (same axes as nodes).
    var label: [Float]?
    /// Ranks the edge spans at least (`-->` 1, `--->` 2, …).
    var minlen: Int

    init(from: Int, to: Int, label: [Float]? = nil, minlen: Int = 1) {
        self.from = from
        self.to = to
        self.label = label
        self.minlen = minlen
    }
}

struct GCluster {
    var parent: Int?
    /// Extra room at the cluster's leading edge along each axis (`[along, across]`), for its title.
    var lead: [Float]
    /// Minimum span along the horizontal screen axis (`[min_along, min_across]`) so titles fit.
    var minSpan: [Float]

    init(parent: Int? = nil, lead: [Float] = [0.0, 0.0], minSpan: [Float] = [0.0, 0.0]) {
        self.parent = parent
        self.lead = lead
        self.minSpan = minSpan
    }
}

struct Spacing {
    var node: Float
    var rank: Float
    var cluster: Float

    init(node: Float, rank: Float, cluster: Float) {
        self.node = node
        self.rank = rank
        self.cluster = cluster
    }
}

/// Where everything went, in layout axes, with the origin at the top-left of the content.
struct Placed: Equatable {
    var centers: [[Float]]
    /// Per edge: the points from its source's centre to its target's centre (in edge
    /// direction), through dummy nodes.
    var paths: [[[Float]]]
    var labels: [[Float]?]
    /// Per cluster: `[x0, y0, x1, y1]`.
    var clusters: [[Float]]

    init(
        centers: [[Float]],
        paths: [[[Float]]],
        labels: [[Float]?],
        clusters: [[Float]]
    ) {
        self.centers = centers
        self.paths = paths
        self.labels = labels
        self.clusters = clusters
    }
}

func layeredLayout(_ g: Graph, _ sp: Spacing) -> Placed? {
    layered.layout(g, sp)
}

enum layered {
    private enum LKind: Equatable {
        case real(Int)
        /// A point on edge `e`; `true` for the one carrying its label.
        case dummy(Int, Bool)
    }

    private struct LNode {
        var kind: LKind
        var rank: Int
        var size: [Float]
        var cluster: Int?
        var preds: [Int]
        var succs: [Int]
    }

    /// How hard a node streaming in holds its place along its rank against its neighbours' pull
    /// (1 for each, 4 for a long edge's point).
    private static let HOLD: Float = 1000.0

    /// The weight that pins a node to its floor: past any pull or room it is solved with.
    private static let PINNED: Float = 1e9

    /// `nil` when long edges would need more than `MAX_DUMMIES` points: such a chart is too
    /// tangled to read at markdown width, and every later step grows with that count.
    static func layout(_ g: Graph, _ sp: Spacing) -> Placed? {
        steady.layout(g.ids) { held in
            place(g, sp, held)
        }
    }

    /// `layout`, holding to `held` while a diagram streams in (see `steady`).
    private static func place(_ g: Graph, _ sp: Spacing, _ held: Memo?) -> (Placed, Memo)? {
        let n = g.sizes.count
        func chain(_ start: Int?) -> [Int] {
            var c = start
            var v: [Int] = []
            while let i = c {
                if v.count > g.clusters.count {
                    break
                }
                v.append(i)
                c = g.clusters[i].parent
            }
            v.reverse()
            return v
        }
        let chains: [[Int]] = (0..<g.clusters.count).map { c in chain(c) }
        func chainOf(_ c: Int?) -> [Int] {
            guard let c = c else { return [] }
            return chains[c]
        }

        // 1. Break cycles: edges back to a node on the DFS stack are reversed.
        var out: [[Int]] = Array(repeating: [], count: n)
        for (i, e) in g.edges.enumerated() {
            if e.from != e.to {
                out[e.from].append(i)
            }
        }
        var reversed = [Bool](repeating: false, count: g.edges.count)
        var state = [UInt8](repeating: 0, count: n)
        for root in 0..<n {
            if state[root] != 0 {
                continue
            }
            var stack: [(Int, Int)] = [(root, 0)]
            state[root] = 1
            while !stack.isEmpty {
                let topIdx = stack.count - 1
                let v = stack[topIdx].0
                let k = stack[topIdx].1
                if k < out[v].count {
                    let e = out[v][k]
                    stack[topIdx].1 = k + 1
                    let w = g.edges[e].to
                    switch state[w] {
                    case 0:
                        state[w] = 1
                        stack.append((w, 0))
                    case 1:
                        reversed[e] = true
                    default:
                        break
                    }
                } else {
                    state[v] = 2
                    stack.removeLast()
                }
            }
        }
        func ends(_ i: Int) -> (Int, Int) {
            let e = g.edges[i]
            return reversed[i] ? (e.to, e.from) : (e.from, e.to)
        }
        let live: [Int] = (0..<g.edges.count).filter { g.edges[$0].from != g.edges[$0].to }

        // 2. Ranks, doubled: every edge spans at least two, so its label has a rank to itself.
        func span(_ i: Int) -> Int {
            2 * clampInt(g.edges[i].minlen, 1, MAX_MINLEN)
        }
        var indeg = [Int](repeating: 0, count: n)
        var succ: [[Int]] = Array(repeating: [], count: n)
        var pred: [[Int]] = Array(repeating: [], count: n)
        for i in live {
            let (a, b) = ends(i)
            indeg[b] += 1
            succ[a].append(i)
            pred[b].append(i)
        }
        var topo: [Int] = []
        topo.reserveCapacity(n)
        var ready: [Int] = (0..<n).filter { indeg[$0] == 0 }.reversed()
        while let v = ready.popLast() {
            topo.append(v)
            for i in succ[v].reversed() {
                let b = ends(i).1
                indeg[b] -= 1
                if indeg[b] == 0 {
                    ready.append(b)
                }
            }
        }
        for v in 0..<n {
            if !topo.contains(v) {
                topo.append(v)
            }
        }
        var rank = [Int](repeating: 0, count: n)
        for v in topo {
            for i in pred[v] {
                rank[v] = max(rank[v], rank[ends(i).0] + span(i))
            }
        }
        // Pull sources down next to their first successor, so a late root doesn't trail a long edge.
        for v in topo.reversed() {
            if pred[v].isEmpty && !succ[v].isEmpty {
                var bestRank = rank[v]
                var first = true
                for i in succ[v] {
                    let cand = rank[ends(i).1] - span(i)
                    if first || cand < bestRank {
                        bestRank = cand
                        first = false
                    }
                }
                rank[v] = bestRank
            }
        }
        if let m = held {
            for v in topo {
                let prevRank = v < m.rank.count ? m.rank[v] : 0
                var rVal = max(rank[v], prevRank)
                for i in pred[v] {
                    rVal = max(rVal, rank[ends(i).0] + span(i))
                }
                rank[v] = rVal
            }
        }

        // 3. The layered graph: real nodes, then one dummy per rank an edge crosses.
        var dummies = 0
        for i in live {
            let (a, b) = ends(i)
            dummies += max(0, rank[b] - (rank[a] + 1))
        }
        if dummies > MAX_DUMMIES {
            return nil
        }
        var nodes: [LNode] = (0..<n).map { v in
            LNode(
                kind: .real(v),
                rank: rank[v],
                size: g.sizes[v],
                cluster: v < g.nodeCluster.count ? g.nodeCluster[v] : nil,
                preds: [],
                succs: []
            )
        }
        var edgeChain: [[Int]] = Array(repeating: [], count: g.edges.count)
        for i in live {
            let (a, b) = ends(i)
            let ca = chainOf(a < g.nodeCluster.count ? g.nodeCluster[a] : nil)
            let cb = chainOf(b < g.nodeCluster.count ? g.nodeCluster[b] : nil)
            var common = 0
            for (x, y) in zip(ca, cb) {
                if x == y { common += 1 } else { break }
            }
            let cluster: Int? = common > 0 ? ca[common - 1] : nil
            let mid = rank[a] + (rank[b] - rank[a]) / 2
            var prev = a
            var ch = [a]
            if rank[a] + 1 < rank[b] {
                for r in (rank[a] + 1)..<rank[b] {
                    let lbl: [Float]? = (r == mid) ? g.edges[i].label : nil
                    let id = nodes.count
                    nodes.append(
                        LNode(
                            kind: .dummy(i, lbl != nil),
                            rank: r,
                            size: lbl ?? [0.0, 0.0],
                            cluster: cluster,
                            preds: [prev],
                            succs: []
                        )
                    )
                    nodes[prev].succs.append(id)
                    ch.append(id)
                    prev = id
                }
            }
            nodes[prev].succs.append(b)
            nodes[b].preds.append(prev)
            ch.append(b)
            edgeChain[i] = ch
        }
        let ranks: Int = nodes.map(\.rank).max().map { $0 + 1 } ?? 0

        // 4. Order within layers: DFS for a start, then barycentre sweeps; keep the fewest crossings.
        var layers: [[Int]] = Array(repeating: [], count: ranks)
        var seen = [Bool](repeating: false, count: nodes.count)
        for root in 0..<n {
            var stack = [root]
            while let v = stack.popLast() {
                if seen[v] {
                    continue
                }
                seen[v] = true
                layers[nodes[v].rank].append(v)
                stack.append(contentsOf: nodes[v].succs.reversed())
            }
        }
        for (v, s) in seen.enumerated() where !s {
            layers[nodes[v].rank].append(v)
        }
        let nodeChains: [[Int]] = nodes.map { chainOf($0.cluster) }
        for r in 0..<layers.count {
            let keys: [Float] = (0..<layers[r].count).map { Float($0) }
            layers[r] = groupedOrder(layers[r], keys, nodeChains)
        }
        var best = layers
        var bestX = crossings(layers, nodes)
        for it in 0..<16 {
            if bestX == 0 {
                break
            }
            let down = it % 2 == 0
            let order: [Int]
            if down {
                order = ranks > 1 ? Array(1..<ranks) : []
            } else {
                order = ranks > 1 ? Array((0..<(ranks - 1)).reversed()) : []
            }
            var pos = positions(layers, nodes.count)
            for r in order {
                let layer = layers[r]
                let keys: [Float] = layer.enumerated().map { (i, v) in
                    let nb = down ? nodes[v].preds : nodes[v].succs
                    if nb.isEmpty {
                        return Float(i)
                    } else {
                        var sum: Float = 0.0
                        for u in nb { sum += Float(pos[u]) }
                        return sum / Float(nb.count)
                    }
                }
                layers[r] = groupedOrder(layer, keys, nodeChains)
                for (i, v) in layers[r].enumerated() {
                    pos[v] = i
                }
            }
            let xCount = crossings(layers, nodes)
            if xCount < bestX {
                bestX = xCount
                best = layers
            }
        }
        layers = best
        if let m = held {
            holdOrder(&layers, m, n, nodeChains)
        }

        // 5. Positions along layers: pack, then pull each node toward its neighbours.
        func isReal(_ v: LNode) -> Bool {
            switch v.kind {
            case .real: return true
            case .dummy(_, let hasLabel): return hasLabel
            }
        }
        let seps: [[Float]] = layers.map { layer in
            guard layer.count >= 2 else { return [] }
            return (0..<(layer.count - 1)).map { idx in
                let w0 = layer[idx]
                let w1 = layer[idx + 1]
                let a = nodes[w0]
                let b = nodes[w1]
                let gap = (isReal(a) && isReal(b)) ? sp.node : sp.node / 2.0
                let ca = nodeChains[w0]
                let cb = nodeChains[w1]
                var common = 0
                for (x, y) in zip(ca, cb) {
                    if x == y { common += 1 } else { break }
                }
                let closing = Float(ca.count - common) * sp.cluster
                var opening: Float = 0.0
                for c in cb[common...] {
                    opening += sp.cluster + g.clusters[c].lead[0]
                }
                return (a.size[0] + b.size[0]) / 2.0 + gap + closing + opening
            }
        }
        var x = [Float](repeating: 0.0, count: nodes.count)
        for (layer, sep) in zip(layers, seps) {
            var at: Float = 0.0
            for (i, v) in layer.enumerated() {
                if i > 0 {
                    at += sep[i - 1]
                }
                x[v] = at
            }
        }
        // Streaming in, a node laid out last time stays there unless new ones need the room, and
        // then only moves on (see `steady`).
        func floorOf(_ v: Int) -> Float? {
            guard v < n, let m = held, v < m.along.count else { return nil }
            return m.along[v]
        }
        func weightOf(_ v: LNode) -> Float {
            switch v.kind {
            case .real: return 1.0
            case .dummy: return 4.0
            }
        }
        for it in 0..<24 {
            let usePreds: Bool
            let useSuccs: Bool
            switch it % 3 {
            case 0: (usePreds, useSuccs) = (true, false)
            case 1: (usePreds, useSuccs) = (false, true)
            default: (usePreds, useSuccs) = (true, true)
            }
            let order: [Int] = (it % 2 == 0) ? Array(0..<ranks) : Array((0..<ranks).reversed())
            for r in order {
                let layer = layers[r]
                var want: [Float] = []
                want.reserveCapacity(layer.count)
                var w: [Float] = []
                w.reserveCapacity(layer.count)
                for v in layer {
                    let node = nodes[v]
                    var nb: [Int] = []
                    if usePreds { nb.append(contentsOf: node.preds) }
                    if useSuccs { nb.append(contentsOf: node.succs) }
                    let aim: Float
                    let pull: Float
                    if let at = floorOf(v) {
                        aim = at
                        pull = HOLD
                    } else if nb.isEmpty {
                        aim = x[v]
                        pull = 0.1
                    } else {
                        var sum: Float = 0.0
                        for u in nb { sum += x[u] }
                        aim = sum / Float(nb.count)
                        pull = weightOf(node) * Float(nb.count)
                    }
                    want.append(aim)
                    w.append(pull)
                }
                let placed = isotonicAbove(want, w, seps[r], layer.map { floorOf($0) })
                for (v, p) in zip(layer, placed) {
                    x[v] = p
                }
            }
        }

        // 6. Layer depths, with room at each cluster's top and bottom.
        var first = [Int](repeating: .max, count: g.clusters.count)
        var last = [Int](repeating: 0, count: g.clusters.count)
        for v in 0..<n {
            let node = nodes[v]
            for c in nodeChains[v] {
                first[c] = min(first[c], node.rank)
                last[c] = max(last[c], node.rank)
            }
        }
        let heights: [Float] = layers.map { l in
            var mx: Float = 0.0
            for v in l { mx = max(mx, nodes[v].size[1]) }
            return mx
        }
        var y = [Float](repeating: 0.0, count: ranks)
        var at: Float = 0.0
        for r in 0..<ranks {
            var opening: Float = 0.0
            for c in 0..<g.clusters.count where first[c] == r {
                opening += sp.cluster + g.clusters[c].lead[1]
            }
            if r > 0 {
                var closingCount = 0
                for c in 0..<g.clusters.count where last[c] == r - 1 && first[c] != .max {
                    closingCount += 1
                }
                let closing = Float(closingCount) * sp.cluster
                at += heights[r - 1] / 2.0 + sp.rank / 2.0 + closing
            }
            at += opening
            if r > 0 || opening > 0.0 {
                at += heights[r] / 2.0
            } else {
                at = heights[0] / 2.0
            }
            y[r] = at
        }
        // Upright bends: a rank gap that an edge crosses far sideways grows (by at most another rank
        // gap) until the edge's S, from the near side of one end to the near side of the other, runs
        // twice as far along the ranks as across them, so it leaves nodes and subgraph borders
        // steeply instead of squeezed.
        func drawn(_ v: Int) -> Bool {
            isReal(nodes[v])
        }
        func slide(_ v: Int) -> Float {
            if case .real = nodes[v].kind {
                return nodes[v].size[0] / 4.0
            }
            return 0.0
        }
        let base = y
        var grown: Float = 0.0
        if ranks > 1 {
            for r in 1..<ranks {
                var need: Float = 0.0
                for v in layers[r] where drawn(v) {
                    for u in nodes[v].preds where drawn(u) {
                        let dx = abs(x[u] - x[v]) - slide(u) - slide(v)
                        let dy = (base[r] - nodes[v].size[1] / 2.0) - (base[r - 1] + nodes[u].size[1] / 2.0)
                        need = max(need, 2.0 * dx - dy)
                    }
                }
                grown += clampF(need, 0.0, sp.rank)
                y[r] += grown
            }
        }
        if let m = held, ranks > 1 {
            let fresh = y
            for r in 1..<ranks {
                let was: Float = (r < m.depth.count && r - 1 < m.depth.count) ? (m.depth[r] - m.depth[r - 1]) : 0.0
                y[r] = y[r - 1] + max(fresh[r] - fresh[r - 1], was)
            }
        }

        // 7. Cluster boxes from their members (nested ones included).
        var depthOrder: [Int] = Array(0..<g.clusters.count)
        depthOrder.sort { chains[$0].count > chains[$1].count }
        func rect(_ xs: [Float], _ v: Int) -> [Float] {
            let node = nodes[v]
            let cx = xs[v]
            let cy = y[node.rank]
            return [cx - node.size[0] / 2.0, cy - node.size[1] / 2.0, cx + node.size[0] / 2.0, cy + node.size[1] / 2.0]
        }
        func boxesOf(_ xs: [Float]) -> [[Float]] {
            var boxes: [[Float]] = Array(
                repeating: [.greatestFiniteMagnitude, .greatestFiniteMagnitude, -.greatestFiniteMagnitude, -.greatestFiniteMagnitude],
                count: g.clusters.count
            )
            for (v, node) in nodes.enumerated() {
                if isReal(node), let c = node.cluster {
                    let r = rect(xs, v)
                    let b = boxes[c]
                    boxes[c] = [min(b[0], r[0]), min(b[1], r[1]), max(b[2], r[2]), max(b[3], r[3])]
                }
            }
            for c in depthOrder {
                let b = boxes[c]
                if b[0] > b[2] {
                    continue
                }
                let lead = g.clusters[c].lead
                let minSpan = g.clusters[c].minSpan
                var padded: [Float] = [
                    b[0] - sp.cluster - lead[0],
                    b[1] - sp.cluster - lead[1],
                    b[2] + sp.cluster,
                    b[3] + sp.cluster,
                ]
                for axis in [0, 1] {
                    let cur = padded[axis + 2] - padded[axis]
                    if cur < minSpan[axis] {
                        let extra = (minSpan[axis] - cur) / 2.0
                        padded[axis] -= extra
                        padded[axis + 2] += extra
                    }
                }
                boxes[c] = padded
                if let p = g.clusters[c].parent {
                    let pb = boxes[p]
                    boxes[p] = [min(pb[0], padded[0]), min(pb[1], padded[1]), max(pb[2], padded[2]), max(pb[3], padded[3])]
                }
            }
            return boxes
        }

        // 8. Push overlapping sibling clusters and loose nodes apart across layers.
        let members: [[Int]] = (0..<g.clusters.count).map { c in
            (0..<nodes.count).filter { nodeChains[$0].contains(c) }
        }
        let pos = positions(layers, nodes.count)
        enum Item {
            case cluster(Int)
            case node(Int)
        }
        func itemNodes(_ it: Item) -> [Int] {
            switch it {
            case .cluster(let c): return members[c]
            case .node(let v): return [layers[nodes[v].rank][pos[v]]]
            }
        }
        let firstOnRank: [[Int: Int]] = members.map { m in
            var dict: [Int: Int] = [:]
            for v in m {
                let r = nodes[v].rank
                if dict[r] == nil {
                    dict[r] = v
                }
            }
            return dict
        }
        func onRank(_ it: Item, _ r: Int) -> Int? {
            switch it {
            case .cluster(let c): return firstOnRank[c][r]
            case .node(let v): return nodes[v].rank == r ? v : nil
            }
        }
        func leftOf(_ a: Item, _ b: Item, _ ba: [Float], _ bb: [Float]) -> Bool {
            for u in itemNodes(a) {
                if let w = onRank(b, nodes[u].rank) {
                    return pos[u] < pos[w]
                }
            }
            return ba[0] + ba[2] <= bb[0] + bb[2]
        }
        for _ in 0..<12 {
            let boxes = boxesOf(x)
            var items: [(Int?, Item, [Float])] = []
            for c in 0..<g.clusters.count where boxes[c][0] <= boxes[c][2] {
                items.append((g.clusters[c].parent, .cluster(c), boxes[c]))
            }
            for v in 0..<n {
                let nc = v < g.nodeCluster.count ? g.nodeCluster[v] : nil
                items.append((nc, .node(v), rect(x, v)))
            }
            var shift = [Float](repeating: 0.0, count: nodes.count)
            var moved = false
            for i in 0..<items.count {
                if i + 1 < items.count {
                    for j in (i + 1)..<items.count {
                        let (pa, a, ba) = items[i]
                        let (pb, b, bb) = items[j]
                        var bothNodes = false
                        if case .node = a, case .node = b { bothNodes = true }
                        if pa != pb || bothNodes || ba[1] >= bb[3] || bb[1] >= ba[3] {
                            continue
                        }
                        let (l, bl, r, br): (Item, [Float], Item, [Float]) = leftOf(a, b, ba, bb) ? (a, ba, b, bb) : (b, bb, a, ba)
                        let d = bl[2] + sp.node / 2.0 - br[0]
                        if d > 0.5 {
                            // Streaming in, nodes only move on along their ranks, so the right one makes the room.
                            let (back, on): (Float, Float) = held != nil ? (0.0, d) : (d / 2.0, d / 2.0)
                            for v in itemNodes(l) { shift[v] -= back }
                            for v in itemNodes(r) { shift[v] += on }
                            moved = true
                        }
                    }
                }
            }
            if !moved {
                break
            }
            for idx in 0..<x.count {
                x[idx] += shift[idx]
            }
            for (layer, sep) in zip(layers, seps) {
                let want: [Float] = layer.map { x[$0] }
                let placed = isotonicAbove(
                    want,
                    [Float](repeating: 1.0, count: layer.count),
                    sep,
                    layer.map { floorOf($0) }
                )
                for (v, p) in zip(layer, placed) {
                    x[v] = p
                }
            }
        }
        let boxes = boxesOf(x)

        // 9. Normalise to the origin.
        var lo: [Float] = [.greatestFiniteMagnitude, .greatestFiniteMagnitude]
        for (v, node) in nodes.enumerated() {
            lo = [min(lo[0], x[v] - node.size[0] / 2.0), min(lo[1], y[node.rank] - node.size[1] / 2.0)]
        }
        for b in boxes where b[0] <= b[2] {
            lo = [min(lo[0], b[0]), min(lo[1], b[1])]
        }
        if lo[0] == .greatestFiniteMagnitude {
            lo = [0.0, 0.0]
        }
        if held != nil {
            // Streaming in, the last layout's axes stay put, and the drawing keeps its corner (see
            // `steady.origin`).
            lo = [0.0, 0.0]
        }
        func atPt(_ v: Int) -> [Float] {
            [x[v] - lo[0], y[nodes[v].rank] - lo[1]]
        }
        let centers: [[Float]] = (0..<n).map { atPt($0) }
        var paths: [[[Float]]] = []
        paths.reserveCapacity(g.edges.count)
        var labels: [[Float]?] = []
        labels.reserveCapacity(g.edges.count)
        for (i, e) in g.edges.enumerated() {
            if e.from == e.to {
                paths.append([atPt(e.from)])
                labels.append(nil)
                continue
            }
            var pts: [[Float]] = edgeChain[i].map { atPt($0) }
            let lblV = edgeChain[i].first { v in
                if case .dummy(_, true) = nodes[v].kind { return true }
                return false
            }
            labels.append(lblV.map { atPt($0) })
            if reversed[i] {
                pts.reverse()
            }
            paths.append(pts)
        }
        let clusters: [[Float]] = boxes.map { b in
            if b[0] <= b[2] {
                return [b[0] - lo[0], b[1] - lo[1], b[2] - lo[0], b[3] - lo[1]]
            } else {
                return [0.0, 0.0, 0.0, 0.0]
            }
        }
        let memo = Memo(
            rank: rank,
            along: (0..<n).map { v in x[v] - lo[0] },
            depth: y.map { $0 - lo[1] },
            ids: []
        )
        return (Placed(centers: centers, paths: paths, labels: labels, clusters: clusters), memo)
    }

    /// While a diagram streams in, the nodes laid out last time keep their order along each rank;
    /// the rest keep the places the sweeps gave them.
    private static func holdOrder(_ layers: inout [[Int]], _ m: Memo, _ n: Int, _ chains: [[Int]]) {
        func along(_ v: Int) -> Float? {
            guard v < n, v < m.along.count else { return nil }
            return m.along[v]
        }
        for r in 0..<layers.count {
            var layer = layers[r]
            let slots: [Int] = (0..<layer.count).filter { along(layer[$0]) != nil }
            var kept: [Int] = slots.map { layer[$0] }
            kept.sort { totalLess(along($0) ?? 0.0, along($1) ?? 0.0) }
            for (i, v) in zip(slots, kept) {
                layer[i] = v
            }
            let keys: [Float] = (0..<layer.count).map { Float($0) }
            layers[r] = groupedOrder(layer, keys, chains)
        }
    }

    /// Each node's index within its layer.
    private static func positions(_ layers: [[Int]], _ len: Int) -> [Int] {
        var pos = [Int](repeating: 0, count: len)
        for layer in layers {
            for (i, v) in layer.enumerated() {
                pos[v] = i
            }
        }
        return pos
    }

    /// Sorts a layer by `keys`, keeping each cluster's members together: clusters sort as one item
    /// at their members' mean key, recursively.
    private static func groupedOrder(_ layer: [Int], _ keys: [Float], _ chains: [[Int]]) -> [Int] {
        func go(_ items: [(Int, Float)], _ depth: Int) -> [(Int, Float)] {
            var groups: [(Int?, [(Int, Float)])] = []
            for it in items {
                let ch = chains[it.0]
                let c: Int? = depth < ch.count ? ch[depth] : nil
                if let cVal = c, let gIdx = groups.firstIndex(where: { $0.0 == cVal }) {
                    groups[gIdx].1.append(it)
                } else {
                    groups.append((c, [it]))
                }
            }
            var keyed: [(Float, [(Int, Float)])] = groups.map { (c, members) in
                var sum: Float = 0.0
                for m in members { sum += m.1 }
                let key = sum / Float(members.count)
                let sortedMembers = c != nil ? go(members, depth + 1) : members
                return (key, sortedMembers)
            }
            keyed.sort { totalLess($0.0, $1.0) }
            return keyed.flatMap { $0.1 }
        }
        let items = Array(zip(layer, keys))
        return go(items, 0).map { $0.0 }
    }

    private static func crossings(_ layers: [[Int]], _ nodes: [LNode]) -> Int {
        let pos = positions(layers, nodes.count)
        var total = 0
        for layer in layers {
            var edges: [(Int, Int)] = []
            for v in layer {
                for w in nodes[v].succs {
                    edges.append((pos[v], pos[w]))
                }
            }
            if edges.count >= 2 {
                for i in 0..<(edges.count - 1) {
                    let a = edges[i]
                    for j in (i + 1)..<edges.count {
                        let b = edges[j]
                        if (a.0 < b.0 && a.1 > b.1) || (a.0 > b.0 && a.1 < b.1) {
                            total += 1
                        }
                    }
                }
            }
        }
        return total
    }

    /// `isotonic`, with places some nodes never go below: those that end up below theirs are
    /// pinned there, the rest solved again around them.
    private static func isotonicAbove(
        _ wantIn: [Float],
        _ wIn: [Float],
        _ sep: [Float],
        _ rawFloors: [Float?]
    ) -> [Float] {
        var want = wantIn
        var w = wIn
        // A floor also lifts the floors after it by the room between them.
        var gap: Float = 0.0
        var lift: Float = -.greatestFiniteMagnitude
        let floors: [Float?] = rawFloors.enumerated().map { (i, f) in
            if i > 0 {
                gap += sep[i - 1]
            }
            lift = max(lift, f.map { $0 - gap } ?? -.greatestFiniteMagnitude)
            return lift > -.greatestFiniteMagnitude ? (lift + gap) : nil
        }
        while true {
            let placed = isotonic(want, w, sep)
            var pinned = false
            for (i, fOpt) in floors.enumerated() {
                if let f = fOpt, placed[i] < f - 0.01, w[i] < PINNED {
                    want[i] = f
                    w[i] = PINNED
                    pinned = true
                }
            }
            if !pinned {
                return placed
            }
        }
    }

    /// The positions closest to `want` (weighted least squares) that keep each neighbour at least
    /// `sep` apart, in order: pool-adjacent-violators on the positions less their cumulative gaps.
    static func isotonic(_ want: [Float], _ w: [Float], _ sep: [Float]) -> [Float] {
        var offset: [Float] = []
        offset.reserveCapacity(want.count)
        var at: Float = 0.0
        for i in 0..<want.count {
            if i > 0 {
                at += sep[i - 1]
            }
            offset.append(at)
        }
        var blocks: [(Float, Float, Int)] = []
        for i in 0..<want.count {
            var b: (Float, Float, Int) = (want[i] - offset[i], max(w[i], 1e-3), 1)
            while let prev = blocks.last {
                if prev.0 <= b.0 {
                    break
                }
                blocks.removeLast()
                let total = prev.1 + b.1
                b = ((prev.0 * prev.1 + b.0 * b.1) / total, total, prev.2 + b.2)
            }
            blocks.append(b)
        }
        var out: [Float] = []
        out.reserveCapacity(want.count)
        for (mean, _, count) in blocks {
            for _ in 0..<count {
                let i = out.count
                out.append(mean + offset[i])
            }
        }
        return out
    }
}
