// Ported from: crates/rune-mermaid/src/state.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! State diagrams (`stateDiagram` and `stateDiagram-v2`), laid out on `layered_draw`.

import Rune

enum state {
    enum StateKind: Sendable, Equatable {
        case normal
        case start
        case end
        case choice
        case bar
        case note
    }

    struct StateNode {
        var id: String
        var label: String
        var desc: [String]
        var kind: StateKind
        var cluster: Int?
        var style: NodeStyle
    }

    struct Composite {
        var title: String
        var parent: Int?
        /// One of a composite's concurrent regions, split by `--`.
        var region: Bool
    }

    struct StateDiagram {
        var title: String?
        var dir: Dir
        var states: [StateNode]
        var edges: [Edge]
        var composites: [Composite]
    }

    private enum Side: Equatable {
        case left
        case right
    }

    static func parse(_ header: String, _ body: [String]) -> StateDiagram? {
        var p = Parser(
            d: StateDiagram(title: nil, dir: .down, states: [], edges: [], composites: []),
            ids: [:],
            compositeIds: [:],
            stack: [],
            noteState: nil,
            pseudoSeq: 0,
            styles: StyleSheet(),
            over: false
        )
        // A statement that doesn't read is skipped; one past the bounds leaves the whole diagram as source.
        for line in [header] + body {
            if p.noteState != nil {
                if !p.noteLine(line) && p.over {
                    return nil
                }
                continue
            }
            for stmt in statements(line) {
                let stateCount = p.d.states.count
                let edgeCount = p.d.edges.count
                if !p.statement(stmt) {
                    if p.over {
                        return nil
                    }
                    // Whatever the statement added before it failed goes too.
                    if p.d.states.count > stateCount {
                        p.d.states.removeSubrange(stateCount...)
                    }
                    if p.d.edges.count > edgeCount {
                        p.d.edges.removeSubrange(edgeCount...)
                    }
                    p.ids = p.ids.filter { $0.value < stateCount }
                }
            }
        }
        // A note left open closes at the end.
        if p.noteState != nil && !p.noteLine("end note") && p.over {
            return nil
        }
        for (id, idx) in p.ids {
            p.d.states[idx].style = p.styles.get(id)
        }
        p.resolveComposites()
        return p.d.states.isEmpty ? nil : p.d
    }

    private struct Parser {
        var d: StateDiagram
        var ids: [String: Int]
        var compositeIds: [String: Int]
        var stack: [Int]
        /// A multi-line note being read: its state, side and lines so far.
        var noteState: (String, Side, [String])?
        var pseudoSeq: Int
        var styles: StyleSheet
        /// Set once the source goes past `MAX_ITEMS` or `MAX_DEPTH`.
        var over: Bool

        mutating func budget() -> Bool {
            if d.states.count + d.edges.count + d.composites.count >= MAX_ITEMS {
                over = true
            }
            return !over
        }

        mutating func noteLine(_ rawLine: String) -> Bool {
            let line = String(rawLine.trimmed())
            if line.asciiLower() != "end note" {
                if var cur = noteState {
                    cur.2.append(line)
                    noteState = cur
                }
                return true
            }
            guard let (target, side, lines) = noteState else { return false }
            noteState = nil
            return addNote(target, side, lines.joined(separator: "\n"))
        }

        mutating func statement(_ s: String) -> Bool {
            if s == "}" {
                guard let top = stack.popLast() else { return false }
                if d.composites[top].region {
                    _ = stack.popLast()
                }
                return true
            }
            if s == "--" {
                return divide()
            }
            let kw: String
            if let idx = s.firstIndex(where: { isUnicodeWS($0) || $0 == ":" }) {
                kw = String(s[..<idx])
            } else {
                kw = s
            }
            switch kw {
            case "title":
                let t = cleanQuoted(String(s.dropFirst("title".count).trimmed()))
                if !t.isEmpty {
                    d.title = t
                }
            case "direction":
                let rest = String(s.dropFirst("direction".count).trimmed())
                guard let dir = Dir.parse(rest) else { return false }
                if stack.isEmpty && d.edges.isEmpty {
                    d.dir = dir
                }
            case "note", "Note":
                return note(String(s.dropFirst(kw.count).trimmed()))
            case "hide", "accTitle", "accDescr":
                break
            case "classDef":
                styles.classDef(String(s.dropFirst("classDef".count)))
            case "class":
                styles.assignClasses(String(s.dropFirst("class".count)))
            case "style":
                styles.style(String(s.dropFirst("style".count)))
            case "state":
                return stateDecl(String(s.dropFirst("state".count).trimmed()))
            default:
                if s.contains("-->") {
                    return transition(s)
                } else if s.contains(":") {
                    return description(s)
                } else {
                    guard validStateId(s) else { return false }
                    return ensureState(s) != nil
                }
            }
            return true
        }

        mutating func stateDecl(_ rest: String) -> Bool {
            let opens = rest.hasSuffix("{")
            let core = opens ? String(rest.dropLast().trimmed()) : rest
            if let (idPart, stereoRaw) = core.splitOnce("<<") {
                guard let stereoSub = stereoRaw.stripSuffix(">>") else { return false }
                let stereo = stereoSub.trimmed().asciiLower()
                let kind: StateKind
                switch stereo {
                case "choice": kind = .choice
                case "fork", "join": kind = .bar
                default: kind = .normal
                }
                let id = String(idPart.trimmed())
                guard validStateId(id), let idx = ensureState(id) else { return false }
                d.states[idx].kind = kind
                return true
            }
            let named = nameAndLabel(core).flatMap { validStateId($0.0) ? $0 : nil }
            if opens {
                guard budget() else { return false }
                if stack.count >= MAX_DEPTH {
                    over = true
                    return false
                }
                // A composite whose name doesn't read still opens, so its `}` closes it and not its parent.
                let title = named?.1 ?? cleanQuoted(core)
                d.composites.append(Composite(title: title, parent: stack.last, region: false))
                let cid = d.composites.count - 1
                if let (id, _) = named {
                    compositeIds[id] = cid
                }
                stack.append(cid)
            } else {
                guard let (id, label) = named, let idx = ensureState(id) else { return false }
                d.states[idx].label = label
            }
            return true
        }

        mutating func transition(_ s: String) -> Bool {
            guard let (leftSub, afterSub) = s.splitOnce("-->") else { return false }
            let leftRaw = String(leftSub.trimmed())
            let after = String(afterSub.trimmed())
            let rightRaw: String
            let label: String?
            if let (r, l) = after.splitOnce(":") {
                let text = cleanQuoted(String(l))
                rightRaw = String(r.trimmed())
                label = text.isEmpty ? nil : text
            } else {
                rightRaw = after
                label = nil
            }
            guard let from = endpoint(leftRaw, true),
                  let to = endpoint(rightRaw, false),
                  budget()
            else { return false }
            d.edges.append(
                Edge(
                    from: from[0],
                    to: to[0],
                    label: label,
                    line: .solid,
                    start: .none,
                    end: .arrow,
                    minlen: 1,
                    style: EdgeStyle(),
                    onCluster: [nil, nil]
                )
            )
            holdRegions(from, to)
            return true
        }

        /// Invisible edges that keep a composite's other regions beside the one an edge is drawn to,
        /// for edges that run forward in the source; a back edge (`retry --> Ready`) holds nothing, so
        /// breaking its cycle can't flip a region below what follows the composite.
        mutating func holdRegions(_ from: [Int], _ to: [Int]) {
            let forward: Bool
            if let fMax = from.max(), let tMin = to.min() {
                forward = fMax < tMin
            } else {
                forward = from.isEmpty && !to.isEmpty
            }
            guard forward else { return }
            var pairs: [(Int, Int)] = []
            if from.count > 1 {
                for f in from.dropFirst() { pairs.append((f, to[0])) }
            }
            if to.count > 1 {
                for t in to.dropFirst() { pairs.append((from[0], t)) }
            }
            for (f, t) in pairs {
                guard budget() else { return }
                d.edges.append(
                    Edge(
                        from: f,
                        to: t,
                        label: nil,
                        line: .invisible,
                        start: .none,
                        end: .none,
                        minlen: 1,
                        style: EdgeStyle(),
                        onCluster: [nil, nil]
                    )
                )
            }
        }

        /// Where an edge meets composite `cid`: it enters at the first state of each region and leaves
        /// from the last, the first region's being the one drawn.
        func compositeEnds(_ cid: Int, _ leaving: Bool) -> [Int] {
            let regions: [Int] = (0..<d.composites.count).filter { r in
                d.composites[r].region && d.composites[r].parent == cid
            }
            let scopes = regions.isEmpty ? [cid] : regions
            return scopes.compactMap { scope -> Int? in
                let members = (0..<d.states.count).filter { i in
                    d.states[i].kind != .note && within(d.states[i].cluster, scope)
                }
                if leaving {
                    return members.filter { d.states[$0].kind != .start }.last
                } else {
                    return members.first
                }
            }
        }

        mutating func description(_ s: String) -> Bool {
            guard let (idRaw, descRaw) = s.splitOnce(":"),
                  let id = styles.stripInline(String(idRaw)),
                  validStateId(id),
                  let idx = ensureState(id)
            else { return false }
            let text = cleanQuoted(String(descRaw))
            if !text.isEmpty {
                d.states[idx].desc.append(text)
            }
            return true
        }

        mutating func endpoint(_ raw: String, _ isStart: Bool) -> [Int]? {
            if raw == "[*]" {
                guard budget() else { return nil }
                pseudoSeq += 1
                let scope = stack.last
                let scopeStr = scope.map { "Some(\($0))" } ?? "None"
                let key = "__pseudo_\(isStart ? "start" : "end")_\(pseudoSeq)_\(scopeStr)"
                let kind: StateKind = isStart ? .start : .end
                d.states.append(
                    StateNode(id: key, label: "", desc: [], kind: kind, cluster: scope, style: NodeStyle())
                )
                return [d.states.count - 1]
            }
            guard let id = styles.stripInline(raw), validStateId(id) else { return nil }
            if let cid = compositeIds[id] {
                let ends = compositeEnds(cid, isStart)
                if !ends.isEmpty {
                    return ends
                }
            }
            guard let idx = ensureState(id) else { return nil }
            return [idx]
        }

        /// A state named before its composite was declared (`[*] --> Busy`, then `state Busy {`) is
        /// that composite: its edges move onto the composite as if named after it, and it goes.
        mutating func resolveComposites() {
            var moves: [Int: ([Int], [Int])] = [:]
            for (id, cid) in compositeIds {
                guard let at = ids[id] else { continue }
                if within(d.states[at].cluster, cid) {
                    continue
                }
                let enter = compositeEnds(cid, false)
                let leave = compositeEnds(cid, true)
                if !enter.isEmpty && !leave.isEmpty {
                    moves[at] = (enter, leave)
                }
            }
            if moves.isEmpty {
                return
            }
            let initialEdgeCount = d.edges.count
            for e in 0..<initialEdgeCount {
                let oldFrom = d.edges[e].from
                let oldTo = d.edges[e].to
                let from = moves[oldFrom]?.1 ?? [oldFrom]
                let to = moves[oldTo]?.0 ?? [oldTo]
                d.edges[e].from = from[0]
                d.edges[e].to = to[0]
                holdRegions(from, to)
            }
            var remap: [Int] = []
            remap.reserveCapacity(d.states.count)
            var kept = 0
            for i in 0..<d.states.count {
                remap.append(kept)
                if moves[i] == nil {
                    kept += 1
                }
            }
            for e in 0..<d.edges.count {
                d.edges[e].from = remap[d.edges[e].from]
                d.edges[e].to = remap[d.edges[e].to]
            }
            d.states = d.states.enumerated().compactMap { (i, st) in
                moves[i] == nil ? st : nil
            }
            ids.removeAll()
        }

        /// Whether `cluster` is composite `cid` or sits inside it.
        func within(_ startCluster: Int?, _ cid: Int) -> Bool {
            var cluster = startCluster
            for _ in 0...MAX_DEPTH {
                guard let c = cluster else { return false }
                if c == cid { return true }
                cluster = d.composites[c].parent
            }
            return false
        }

        /// `--` inside a composite: what came before becomes its first region, and a new one opens.
        mutating func divide() -> Bool {
            guard let top = stack.last else { return false }
            let parent: Int
            if d.composites[top].region {
                _ = stack.popLast()
                guard let p = d.composites[top].parent else { return false }
                parent = p
            } else {
                guard let first = region(top) else { return false }
                for idx in 0..<d.states.count where d.states[idx].cluster == top {
                    d.states[idx].cluster = first
                }
                for idx in 0..<d.composites.count where idx != first && d.composites[idx].parent == top {
                    d.composites[idx].parent = first
                }
                parent = top
            }
            guard let next = region(parent) else { return false }
            stack.append(next)
            return true
        }

        mutating func region(_ parent: Int) -> Int? {
            guard budget() else { return nil }
            if stack.count >= MAX_DEPTH {
                over = true
                return nil
            }
            d.composites.append(Composite(title: "", parent: parent, region: true))
            return d.composites.count - 1
        }

        /// `right of A : text` on one line, or `left of A` opening a note that `end note` closes.
        mutating func note(_ rest: String) -> Bool {
            let place: String
            let text: String?
            if let (p, t) = rest.splitOnce(":") {
                place = String(p.trimmed())
                text = String(t)
            } else {
                place = rest
                text = nil
            }
            let lower = place.asciiLower()
            let side: Side
            let targetRaw: String
            if lower.hasPrefix("right of ") {
                side = .right
                targetRaw = String(place.dropFirst("right of ".count))
            } else if lower.hasPrefix("left of ") {
                side = .left
                targetRaw = String(place.dropFirst("left of ".count))
            } else {
                return false
            }
            let target = String(targetRaw.trimmed())
            guard validStateId(target) else { return false }
            if let t = text {
                return addNote(target, side, cleanQuoted(t))
            } else {
                noteState = (target, side, [])
                return true
            }
        }

        /// A note beside `target`, joined to it by a dotted line.
        mutating func addNote(_ target: String, _ side: Side, _ text: String) -> Bool {
            guard let at = ensureState(target), budget() else { return false }
            let cluster = d.states[at].cluster
            let id = "__note_\(d.states.count)"
            d.states.append(
                StateNode(id: id, label: text, desc: [], kind: .note, cluster: cluster, style: NodeStyle())
            )
            let noteIdx = d.states.count - 1
            let (from, to) = side == .left ? (noteIdx, at) : (at, noteIdx)
            guard budget() else { return false }
            d.edges.append(
                Edge(
                    from: from,
                    to: to,
                    label: nil,
                    line: .dotted,
                    start: .none,
                    end: .none,
                    minlen: 1,
                    style: EdgeStyle(),
                    onCluster: [nil, nil]
                )
            )
            return true
        }

        mutating func ensureState(_ id: String) -> Int? {
            let cluster = stack.last
            if let i = ids[id] {
                if d.states[i].cluster == nil {
                    d.states[i].cluster = cluster
                }
                return i
            }
            guard budget() else { return nil }
            d.states.append(
                StateNode(id: id, label: id, desc: [], kind: .normal, cluster: cluster, style: NodeStyle())
            )
            let idx = d.states.count - 1
            ids[id] = idx
            return idx
        }
    }

    /// `"Label" as id`, `Label as id` or a bare `id`.
    private static func nameAndLabel(_ core: String) -> (String, String)? {
        if let afterQ = core.stripPrefix("\"") {
            guard let endQ = afterQ.firstIndex(of: "\"") else { return nil }
            let afterClosingQuote = core.index(after: endQ)
            let label = cleanQuoted(String(core[..<afterClosingQuote]))
            let tail = String(core[afterClosingQuote...].trimmed())
            guard let idSub = tail.stripPrefix("as ") else { return nil }
            return (String(idSub.trimmed()), label)
        } else if let (lbl, idSub) = core.splitOnce(" as ") {
            return (String(idSub.trimmed()), cleanQuoted(String(lbl)))
        } else {
            return (String(core.trimmed()), cleanQuoted(core))
        }
    }

    private static func validStateId(_ s: String) -> Bool {
        !s.isEmpty && s.unicodeScalars.allSatisfy { sc in
            isAlphanumericScalar(sc) || sc == "_" || sc == "-" || sc == "."
        }
    }

    private static let SPACING = Spacing(node: 34.0, rank: 42.0, cluster: 14.0)

    static func draw(_ d: StateDiagram, _ paint: DiagramStyle, _ hover: (Hover, Color)?) -> Scene? {
        let nodes: [DrawNode] = d.states.map { s in
            switch s.kind {
            case .start:
                return .start(cluster: s.cluster)
            case .end:
                return .end(cluster: s.cluster)
            case .bar:
                return .bar(cluster: s.cluster)
            case .choice:
                return .shape(
                    shape: .diamond,
                    label: Measured(),
                    size: [28.0, 28.0],
                    cluster: s.cluster,
                    style: s.style
                )
            case .note:
                let label = measureBalanced(s.label, paint.font)
                return .shape(
                    shape: .note,
                    label: label,
                    size: nodeSize(.note, label.size),
                    cluster: s.cluster,
                    style: s.style
                )
            case .normal:
                let full = s.desc.isEmpty ? s.label : "\(s.label)\n\(s.desc.joined(separator: "\n"))"
                let label = measureBalanced(full, paint.font)
                return .shape(
                    shape: .round,
                    label: label,
                    size: nodeSize(.round, label.size),
                    cluster: s.cluster,
                    style: s.style
                )
            }
        }
        let clusters: [ClusterSpec] = d.composites.map { c in
            ClusterSpec(title: c.title, parent: c.parent)
        }
        let nm = Names.new(d.states.map { $0.id }, d.edges, [])
        guard var c = layeredCanvas(d.dir, nodes, nm.nodes, d.edges, clusters, SPACING, paint, hover) else {
            return nil
        }
        c.names = nm
        return c.finishFit(paint)
    }
}
