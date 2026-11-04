// Ported from: crates/rune-mermaid/src/sankey.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Sankey diagrams (`sankey-beta`, `sankey`): `source,target,value` rows (CSV, quotes allowed)
//! drawn as columns of nodes joined by bands as thick as their flow.

import Rune

enum sankey {
    struct Sankey {
        var nodes: [String] = []
        /// `(from, to, value)`.
        var links: [(Int, Int, Float)] = []
    }

    static func parse(_ body: [String]) -> Sankey? {
        var s = Sankey()
        var ids: [String: Int] = [:]
        func node(_ name: String) -> Int {
            if let existing = ids[name] {
                return existing
            }
            let next = ids.count
            ids[name] = next
            s.nodes.append(name)
            return next
        }
        for l in body {
            let f = fields(l)
            guard f.count == 3 else { continue }
            guard let v = Float(f[2].trimmed()), v.isFinite, v >= 0.0 else { continue }
            let a = clean(f[0])
            let b = clean(f[1])
            if a.isEmpty || b.isEmpty || a == b {
                continue
            }
            let from = node(a)
            let to = node(b)
            s.links.append((from, to, v))
            if s.nodes.count + s.links.count > MAX_ITEMS {
                return nil
            }
        }
        return s.links.isEmpty ? nil : s
    }

    /// One CSV row: commas split fields outside `"…"`, and `""` inside quotes is a quote.
    private static func fields(_ l: String) -> [String] {
        var out: [String] = []
        var cur = ""
        var quoted = false
        let chars = Array(l)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch == "\"" && quoted && i + 1 < chars.count && chars[i + 1] == "\"" {
                cur.append("\"")
                i += 2
            } else if ch == "\"" {
                quoted.toggle()
                i += 1
            } else if ch == "," && !quoted {
                out.append(cur)
                cur = ""
                i += 1
            } else {
                cur.append(ch)
                i += 1
            }
        }
        out.append(cur)
        return out
    }

    /// Each node's column: its longest path from a source, with sinks pushed to the last column.
    static func columns(_ s: Sankey) -> [Int] {
        let n = s.nodes.count
        var depth = Array(repeating: 0, count: n)
        // Bounded, so a cycle stops growing at the last column.
        for _ in 0..<n {
            var moved = false
            for (a, b, _) in s.links {
                if depth[b] < depth[a] + 1 && depth[a] + 1 < n {
                    depth[b] = depth[a] + 1
                    moved = true
                }
            }
            if !moved {
                break
            }
        }
        let last = depth.max() ?? 0
        for i in 0..<n {
            if !s.links.contains(where: { $0.0 == i }) {
                depth[i] = last
            }
        }
        return depth
    }

    private static let HEIGHT: Float = 300.0
    private static let NODE_W: Float = 10.0
    private static let PAD: Float = 12.0

    static func draw(_ s: Sankey, _ paint: DiagramStyle) -> Scene? {
        let n = s.nodes.count
        let note = chart.small(paint)
        let col = columns(s)
        let cols = (col.max() ?? 0) + 1
        var ins = Array(repeating: Float(0.0), count: n)
        var outs = Array(repeating: Float(0.0), count: n)
        for (a, b, v) in s.links {
            outs[a] += v
            ins[b] += v
        }
        let value = (0..<n).map { max(ins[$0], outs[$0]) }
        let members: [[Int]] = (0..<cols).map { c in (0..<n).filter { col[$0] == c } }
        let ky = max(
            members.map { m -> Float in
                let sumVal = max(m.reduce(Float(0.0)) { $0 + value[$1] }, 1e-6)
                return (HEIGHT - PAD * (Float(m.count) - 1.0)) / sumVal
            }.reduce(Float.greatestFiniteMagnitude, min),
            0.0
        )
        let h = value.map { max($0 * ky, 1.0) }

        // Stack each column, ordered by where its nodes' neighbours sit, centred on the tallest.
        var y = Array(repeating: Float(0.0), count: n)
        func stack(_ m: [Int]) {
            let total = m.reduce(Float(0.0)) { $0 + h[$1] } + PAD * (Float(m.count) - 1.0)
            var at = (HEIGHT - total) / 2.0
            for i in m {
                y[i] = at
                at += h[i] + PAD
            }
        }
        var order = members
        for m in order {
            stack(m)
        }
        for pass in 0..<4 {
            let forward = pass % 2 == 0
            for stepCol in 0..<cols {
                let cIdx = forward ? stepCol : (cols - 1 - stepCol)
                func mid(_ i: Int) -> Float {
                    var sum: Float = 0.0
                    var w: Float = 0.0
                    for (a, b, v) in s.links {
                        let other: Int
                        if b == i && forward {
                            other = a
                        } else if a == i && !forward {
                            other = b
                        } else {
                            continue
                        }
                        sum += (y[other] + h[other] / 2.0) * v
                        w += v
                    }
                    return w > 0.0 ? (sum / w) : (y[i] + h[i] / 2.0)
                }
                var keyed: [(Float, Int)] = order[cIdx].map { (mid($0), $0) }
                keyed.sort { totalLess($0.0, $1.0) }
                order[cIdx] = keyed.map { $0.1 }
                stack(order[cIdx])
            }
        }

        // Columns spread across the room, leaving the labels of the first and last some space.
        let width = room(paint)
        func xOf(_ colIdx: Int) -> Float {
            cols == 1 ? 0.0 : (Float(colIdx) * (width - NODE_W) / Float(cols - 1))
        }
        var c = Canvas()
        var links = Array(0..<s.links.count)
        links.sort { p, q in totalLess(y[s.links[p].1], y[s.links[q].1]) }
        var outAt = y
        var inAt = y
        var ends = Array(repeating: [Float(0.0), Float(0.0)], count: s.links.count)
        for k in links {
            let (a, _, v) = s.links[k]
            ends[k][0] = outAt[a]
            outAt[a] += v * ky
        }
        links.sort { p, q in totalLess(y[s.links[p].0], y[s.links[q].0]) }
        for k in links {
            let (_, b, v) = s.links[k]
            ends[k][1] = inAt[b]
            inAt[b] += v * ky
        }
        for (k, (a, b, v)) in s.links.enumerated() {
            let t = max(v * ky, 0.5)
            let sx = xOf(col[a]) + NODE_W
            let tx = xOf(col[b])
            var band = chart.sCurve([sx, ends[k][0]], [tx, ends[k][1]], false)
            band.append(contentsOf: chart.sCurve([tx, ends[k][1] + t], [sx, ends[k][0] + t], false))
            c.fill(band, chart.solid(paint, chart.hue(a)).alpha(0.42))
        }
        for i in 0..<n {
            let x = xOf(col[i])
            c.fill([[x, y[i]], [x + NODE_W, y[i]], [x + NODE_W, y[i] + h[i]], [x, y[i] + h[i]]], chart.solid(paint, chart.hue(i)))
            let m = measure("\(s.nodes[i]) \(pie.number(Double(value[i])))", note)
            let mid = y[i] + h[i] / 2.0 - m.size[1] / 2.0
            if col[i] + 1 == cols && cols > 1 {
                c.labelAt(m, [x - 6.0 - m.size[0], mid], note, paint.text, .end)
            } else {
                c.labelAt(m, [x + NODE_W + 6.0, mid], note, paint.text, .start)
            }
        }
        return c.finishFit(paint)
    }
}
