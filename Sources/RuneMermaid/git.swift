// Ported from: crates/rune-mermaid/src/git.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Git graphs (`gitGraph`, `LR:`, `TB:` or `BT:`): `commit` (`id`, `tag`, `type: NORMAL |
//! REVERSE | HIGHLIGHT`), `branch` (`order`), `checkout`/`switch`, `merge` and `cherry-pick`,
//! one lane per branch in its own colour. Commits without an `id` are drawn unlabelled, since
//! Mermaid would label them with random hashes.

import Rune

enum git {
    enum Kind: Equatable, Sendable {
        case normal
        case reverse
        case highlight
        case merge
        case cherryPick
    }

    struct Commit: Equatable, Sendable {
        var id: String?
        var tag: String?
        var kind: Kind
        var branch: Int
        var parents: [Int]
        /// The commit a cherry-pick copies.
        var picked: Int?
    }

    struct Branch: Equatable, Sendable {
        var name: String
        var order: Float?
    }

    enum Flow: Equatable, Sendable {
        case right
        case down
        case up
    }

    struct GitGraph {
        var flow: Flow
        var branches: [Branch]
        var commits: [Commit]
    }

    static func parse(_ header: String, _ body: [String]) -> GitGraph? {
        let hKey = String(header.trimmed().trimEndMatches(":"))
        let flow: Flow
        switch hKey {
        case "TB", "TD": flow = .down
        case "BT": flow = .up
        default: flow = .right
        }
        var g = GitGraph(flow: flow, branches: [Branch(name: "main", order: nil)], commits: [])
        var heads: [Int?] = [nil]
        var cur = 0
        for line in body {
            for stmt in statements(line) {
                let cmd: String
                let rest: String
                if let (c, r) = stmt.splitOnceWhere(isUnicodeWS) {
                    cmd = String(c)
                    rest = String(r.trimmed())
                } else {
                    cmd = stmt
                    rest = ""
                }
                if g.commits.count + g.branches.count > MAX_ITEMS {
                    return nil
                }
                func find(_ bName: String) -> Int? {
                    g.branches.firstIndex { $0.name == bName }
                }
                switch cmd {
                case "commit":
                    let a = attrs(rest)
                    let k = kind(a) ?? .normal
                    let parents = heads[cur].map { [$0] } ?? []
                    g.commits.append(Commit(id: get(a, "id"), tag: get(a, "tag"), kind: k, branch: cur, parents: parents, picked: nil))
                    heads[cur] = g.commits.count - 1
                case "branch":
                    let (bName, afterName) = name(rest)
                    if bName.isEmpty || find(bName) != nil {
                        continue
                    }
                    let order: Float?
                    if let ordStr = get(attrs(afterName), "order"),
                       let ordVal = Float(ordStr),
                       ordVal.isFinite
                    {
                        order = ordVal
                    } else {
                        order = nil
                    }
                    g.branches.append(Branch(name: bName, order: order))
                    heads.append(heads[cur])
                    cur = g.branches.count - 1
                case "checkout", "switch":
                    if let b = find(name(rest).0) {
                        cur = b
                    }
                case "merge":
                    let (bName, afterName) = name(rest)
                    guard let b = find(bName), b != cur else { continue }
                    guard let theirs = heads[b] else { continue }
                    let ours = heads[cur]
                    // Nothing to merge when ours already has theirs.
                    if let o = ours, reaches(g.commits, o, theirs) {
                        continue
                    }
                    let a = attrs(afterName)
                    var parents: [Int] = []
                    if let o = ours {
                        parents.append(o)
                    }
                    parents.append(theirs)
                    g.commits.append(Commit(id: get(a, "id"), tag: get(a, "tag"), kind: kind(a) ?? .merge, branch: cur, parents: parents, picked: nil))
                    heads[cur] = g.commits.count - 1
                case "cherry-pick":
                    let a = attrs(rest)
                    guard let targetId = get(a, "id"),
                          let src = g.commits.firstIndex(where: { $0.id == targetId })
                    else { continue }
                    if g.commits[src].branch == cur {
                        continue
                    }
                    let parents = heads[cur].map { [$0] } ?? []
                    g.commits.append(Commit(id: nil, tag: get(a, "tag"), kind: .cherryPick, branch: cur, parents: parents, picked: src))
                    heads[cur] = g.commits.count - 1
                default:
                    break
                }
            }
        }
        return g.commits.isEmpty ? nil : g
    }

    /// Whether `to` is `from` or one of its ancestors.
    private static func reaches(_ commits: [Commit], _ from: Int, _ to: Int) -> Bool {
        var seen = Array(repeating: false, count: commits.count)
        var stack = [from]
        while let c = stack.popLast() {
            if c == to {
                return true
            }
            if !seen[c] {
                seen[c] = true
                stack.append(contentsOf: commits[c].parents)
            }
        }
        return false
    }

    /// A branch name, quoted or bare, and what follows it.
    private static func name(_ sIn: String) -> (String, String) {
        let s = sIn.trimmed()
        if let r = s.stripPrefix("\""), let end = r.firstIndex(of: "\"") {
            let afterEnd = r.index(after: end)
            return (clean(String(r[..<end])), String(r[afterEnd...]))
        }
        if let end = s.firstIndex(where: isUnicodeWS) {
            return (clean(String(s[..<end])), String(s[end...]))
        }
        return (clean(String(s)), "")
    }

    /// `key: value` pairs, values quoted or bare.
    private static func attrs(_ s: String) -> [(String, String)] {
        var out: [(String, String)] = []
        var rest: Substring = s.trimmed()
        while let colon = rest.firstIndex(of: ":") {
            let beforeColon = rest[..<colon].trimmed()
            let key: String
            if let lastWS = beforeColon.lastIndex(where: isUnicodeWS) {
                key = String(beforeColon[beforeColon.index(after: lastWS)...])
            } else {
                key = String(beforeColon)
            }
            let after = rest[rest.index(after: colon)...].trimmedStart()
            let value: Substring
            let next: Substring
            if let r = after.stripPrefix("\"") {
                if let end = r.firstIndex(of: "\"") {
                    value = r[..<end]
                    next = r[r.index(after: end)...]
                } else {
                    value = r
                    next = r[r.endIndex...]
                }
            } else if let end = after.firstIndex(where: isUnicodeWS) {
                value = after[..<end]
                next = after[end...]
            } else {
                value = after
                next = after[after.endIndex...]
            }
            out.append((key, clean(String(value))))
            rest = next.trimmedStart()
        }
        return out
    }

    private static func get(_ a: [(String, String)], _ key: String) -> String? {
        guard let v = a.first(where: { $0.0 == key })?.1, !v.isEmpty else {
            return nil
        }
        return v
    }

    private static func kind(_ a: [(String, String)]) -> Kind? {
        guard let t = get(a, "type") else { return nil }
        switch t {
        case "REVERSE": return .reverse
        case "HIGHLIGHT": return .highlight
        case "NORMAL": return .normal
        default: return nil
        }
    }

    private static let R: Float = 9.0
    private static let STEP: Float = 44.0
    private static let PAD: [Float] = [6.0, 2.0]

    static func draw(_ g: GitGraph, _ paint: DiagramStyle) -> Scene? {
        let note = chart.small(paint)
        let head = chart.bold(note)
        // Lanes in `order`, then creation order.
        var lanes = Array(0..<g.branches.count)
        lanes.sort { a, b in
            func key(_ i: Int) -> Float {
                g.branches[i].order ?? (i == 0 ? -.greatestFiniteMagnitude : Float(i))
            }
            let ka = key(a)
            let kb = key(b)
            if ka != kb {
                return totalLess(ka, kb)
            }
            return a < b
        }
        var laneOf = Array(repeating: 0, count: g.branches.count)
        for (pos, b) in lanes.enumerated() {
            laneOf[b] = pos
        }
        let labels = g.commits.map { c in c.id.map { measure($0, note) } ?? Measured() }
        let tags = g.commits.map { c in c.tag.map { measure($0, note) } ?? Measured() }
        let names = g.branches.map { measure($0.name, head) }
        func boxed(_ m: Measured) -> Float {
            m.text.isEmpty ? 0.0 : (m.size[0] + 2.0 * PAD[0])
        }
        let lineH = note.lineHeight + 2.0 * PAD[1]
        let across = g.flow == .right

        // Along the flow: each commit after the last, and clear of the label before it on its lane.
        var along = Array(repeating: Float(0.0), count: g.commits.count)
        var lastOn: [Int?] = Array(repeating: nil, count: g.branches.count)
        for (k, c) in g.commits.enumerated() {
            var u: Float = k == 0 ? 0.0 : (along[k - 1] + STEP)
            if across, let p = lastOn[c.branch] {
                func w(_ i: Int) -> Float {
                    max(boxed(labels[i]), boxed(tags[i]))
                }
                u = max(u, along[p] + (w(p) + w(k)) / 2.0 + 10.0)
            }
            along[k] = u
            lastOn[c.branch] = k
        }
        let hasTags = tags.contains { !$0.text.isEmpty }
        // Across, each lane is as tall as its labels and tags; down, as wide as the widest.
        var laneV = Array(repeating: Float(0.0), count: lanes.count)
        if across {
            var v: Float = 0.0
            for (pos, b) in lanes.enumerated() {
                let tagged = zip(g.commits, tags).contains { $0.0.branch == b && !$0.1.text.isEmpty }
                if tagged {
                    v += lineH + 10.0
                }
                laneV[pos] = v
                v += 2.0 * R + 22.0 + lineH
            }
        } else {
            func wide(_ ms: [Measured]) -> Float {
                ms.map(boxed).reduce(0.0, max)
            }
            let tagW = wide(tags)
            let lane = max(
                2.0 * R + 28.0 + wide(labels) + tagW + (hasTags ? 10.0 : 0.0),
                names.map { $0.size[0] + 24.0 }.reduce(0.0, max)
            )
            for pos in 0..<laneV.count {
                laneV[pos] = tagW + Float(pos) * lane
            }
        }
        func pt(_ u: Float, _ vIdx: Int) -> [Float] {
            let v = laneV[vIdx]
            switch g.flow {
            case .right: return [u, v]
            case .down: return [v, u]
            case .up: return [v, -u]
            }
        }
        let end = (along.last ?? 0.0) + 2.0 * R
        func color(_ b: Int) -> Color {
            chart.solid(paint, chart.hue(b))
        }

        var c = Canvas()
        // Lanes, with their names before them.
        for (b, m) in names.enumerated() {
            let v = laneOf[b]
            let w = m.size[0] + 16.0
            let h = m.size[1] + 8.0
            let start = pt(-2.0 * R, v)
            let p0 = pt(0.0, v)
            let at: [Float]
            switch g.flow {
            case .right:
                at = [p0[0] - 2.0 * R - 10.0 - w, p0[1] - h / 2.0]
            case .down:
                at = [p0[0] - w / 2.0, -2.0 * R - 10.0 - h]
            case .up:
                at = [p0[0] - w / 2.0, 2.0 * R + 10.0]
            }
            c.dashed([start, pt(end, v)], 1.0, color(b).alpha(0.45), 5.0, 4.0)
            c.fill(roundedRect(at[0], at[1], at[0] + w, at[1] + h, h / 2.0), color(b))
            c.labelAt(m, [at[0] + 8.0, at[1] + 4.0], head, chart.ink(color(b)), .start)
        }
        // Links: an elbow toward the lower lane, in that lane's colour.
        for (k, commit) in g.commits.enumerated() {
            for p in commit.parents {
                let parent = g.commits[p]
                let vp = laneOf[parent.branch]
                let vk = laneOf[commit.branch]
                let a = pt(along[p], vp)
                let b = pt(along[k], vk)
                let pts: [[Float]]
                if vp == vk {
                    pts = [a, b]
                } else if vp < vk {
                    pts = elbow(a, pt(along[p], vk), b)
                } else {
                    pts = elbow(a, pt(along[k], vp), b)
                }
                let laneColor = color(vp < vk ? commit.branch : parent.branch)
                c.stroke(pts, false, 2.0, laneColor)
            }
            if let src = commit.picked {
                let a = pt(along[src], laneOf[g.commits[src].branch])
                let b = pt(along[k], laneOf[commit.branch])
                c.dashed(elbow(a, pt(along[k], laneOf[g.commits[src].branch]), b), 1.5, color(commit.branch), 4.0, 3.0)
            }
        }
        for (k, commit) in g.commits.enumerated() {
            let at = pt(along[k], laneOf[commit.branch])
            glyph(&c, commit.kind, at, color(commit.branch), paint)
            let label = labels[k]
            if !label.text.isEmpty {
                let w = boxed(label)
                let o = across ? [at[0] - w / 2.0, at[1] + R + 6.0] : [at[0] + R + 8.0, at[1] - lineH / 2.0]
                c.fill(roundedRect(o[0], o[1], o[0] + w, o[1] + lineH, 4.0), oklabMix(paint.surface, paint.text, 0.08))
                c.labelAt(label, [o[0] + PAD[0], o[1] + PAD[1]], note, paint.muted, .start)
            }
            let tag = tags[k]
            if !tag.text.isEmpty {
                let w = boxed(tag)
                let o = across ? [at[0] - w / 2.0, at[1] - R - 8.0 - lineH] : [at[0] - R - 8.0 - w, at[1] - lineH / 2.0]
                c.shape(roundedRect(o[0], o[1], o[0] + w, o[1] + lineH, 3.0), paint.noteFill, paint.noteBorder, 1.0)
                c.labelAt(tag, [o[0] + PAD[0], o[1] + PAD[1]], note, paint.text, .start)
            }
        }
        return c.finishFit(paint)
    }

    /// `a` to `b` through corner `k`, rounded.
    private static func elbow(_ a: [Float], _ k: [Float], _ b: [Float]) -> [[Float]] {
        let r = min(Float(10.0), min(dist(a, k) / 2.0, dist(k, b) / 2.0))
        if r < 0.5 {
            return [a, b]
        }
        let ua = unit(k, a)
        let ub = unit(k, b)
        let p = [k[0] + ua[0] * r, k[1] + ua[1] * r]
        let q = [k[0] + ub[0] * r, k[1] + ub[1] * r]
        var pts: [[Float]] = [a]
        for i in 0...6 {
            let t = Float(i) / 6.0
            pts.append(lerp(lerp(p, k, t), lerp(k, q, t), t))
        }
        pts.append(b)
        return pts
    }

    private static func glyph(_ c: inout Canvas, _ k: Kind, _ at: [Float], _ fill: Color, _ paint: DiagramStyle) {
        let x = at[0]
        let y = at[1]
        switch k {
        case .highlight:
            c.shape(roundedRect(x - R, y - R, x + R, y + R, 3.0), fill, paint.surface, 2.0)
            c.fill(roundedRect(x - R / 2.0, y - R / 2.0, x + R / 2.0, y + R / 2.0, 1.5), chart.ink(fill).alpha(0.4))
        default:
            c.shape(ellipse(at, R, R), fill, paint.surface, 2.0)
        }
        let mark = chart.ink(fill)
        switch k {
        case .merge:
            c.fill(ellipse(at, R * 0.45, R * 0.45), paint.surface)
        case .reverse:
            let d = R * 0.45
            c.stroke([[x - d, y - d], [x + d, y + d]], false, 1.75, mark)
            c.stroke([[x - d, y + d], [x + d, y - d]], false, 1.75, mark)
        case .cherryPick:
            c.fill(ellipse([x - 2.6, y + 2.0], 2.3, 2.3), mark)
            c.fill(ellipse([x + 2.6, y + 2.0], 2.3, 2.3), mark)
            c.stroke([[x - 2.0, y], [x + 0.5, y - 5.0], [x + 2.4, y]], false, 1.0, mark)
        default:
            break
        }
    }
}
