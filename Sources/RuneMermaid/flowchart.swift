// Ported from: crates/rune-mermaid/src/flowchart.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Flowcharts: the parser for `graph`/`flowchart` sources and their drawing on `layered_draw`.

import Rune

@inline(__always)
func isAlphanumericScalar(_ sc: Unicode.Scalar) -> Bool {
    if sc.properties.isAlphabetic { return true }
    switch sc.properties.generalCategory {
    case .decimalNumber, .letterNumber, .otherNumber: return true
    default: return false
    }
}

enum flowchart {
    struct Node {
        var id: String
        var label: String
        var shape: NodeShape
        var cluster: Int?
        var style: NodeStyle
        var explicitShape: Bool
    }

    struct Subgraph {
        var id: String?
        var title: String
        var parent: Int?
    }

    struct Flowchart {
        var title: String?
        var dir: Dir
        var nodes: [Node]
        var edges: [Edge]
        var subgraphs: [Subgraph]
    }

    struct Link {
        var id: String?
        var line: Line
        var start: Head
        var end: Head
        var minlen: Int
        var label: String?
    }

    /// `header` is what follows `graph`/`flowchart` on its line; `body` the remaining lines.
    static func parse(_ header: String, _ body: [String]) -> Flowchart? {
        let dirStr: String
        let rest: String
        let trimmedStartHeader = header.trimmedStart()
        if let (d, r) = trimmedStartHeader.splitOnceWhere({ isUnicodeWS($0) || $0 == ";" }) {
            dirStr = String(d)
            rest = String(r)
        } else {
            dirStr = String(header.trimmed())
            rest = ""
        }
        // A direction it doesn't know reads top-down.
        let dir = Dir.parse(dirStr) ?? .down
        var p = Parser(
            f: Flowchart(title: nil, dir: dir, nodes: [], edges: [], subgraphs: []),
            ids: [:],
            stack: [],
            styles: StyleSheet(),
            defaultEdgeStyle: EdgeStyle(),
            edgeStyles: [:],
            edgeIds: [],
            over: false
        )
        // A statement that doesn't read is skipped; one past the bounds leaves the whole diagram as source.
        for line in [rest] + body {
            for stmt in statements(line) {
                if !p.statement(stmt) && p.over {
                    return nil
                }
            }
        }
        for (id, idx) in p.ids {
            p.f.nodes[idx].style = p.styles.get(id)
        }
        for i in 0..<p.f.edges.count {
            var st = p.defaultEdgeStyle
            if let es = p.edgeStyles[i] {
                st = st.merge(es)
            }
            p.f.edges[i].style = st
        }
        resolveSubgraphEndpoints(&p.f)
        return p.f.nodes.isEmpty ? nil : p.f
    }

    /// Redirects edges targeting a `subgraph id` placeholder onto that subgraph's first/last member,
    /// which ranks the edge, and marks that end to stop on the subgraph's border. An edge from inside
    /// the subgraph to itself keeps the member.
    private static func resolveSubgraphEndpoints(_ f: inout Flowchart) {
        var redirects: [Int: (Int, Int, Int)] = [:]
        for (sgIdx, sg) in f.subgraphs.enumerated() {
            guard let id = sg.id else { continue }
            guard let nodeIdx = f.nodes.firstIndex(where: { $0.id == id && !$0.explicitShape }) else { continue }
            let members: [Int] = (0..<f.nodes.count).filter { i in
                i != nodeIdx && inCluster(i, sgIdx, f.nodes, f.subgraphs)
            }
            if let first = members.first, let last = members.last {
                redirects[nodeIdx] = (first, last, sgIdx)
            }
        }
        if redirects.isEmpty {
            return
        }
        let subgraphsSnapshot = f.subgraphs
        let nodesSnapshot = f.nodes
        func inside(_ v: Int, _ sg: Int) -> Bool {
            if let r = redirects[v] {
                var cur: Int? = r.2
                var steps = 0
                while let s = cur, steps <= subgraphsSnapshot.count {
                    if s == sg { return true }
                    cur = subgraphsSnapshot[s].parent
                    steps += 1
                }
                return false
            } else {
                return inCluster(v, sg, nodesSnapshot, subgraphsSnapshot)
            }
        }
        for idx in 0..<f.edges.count {
            let from = f.edges[idx].from
            let to = f.edges[idx].to
            if let (_, last, sg) = redirects[from] {
                f.edges[idx].from = last
                f.edges[idx].onCluster[0] = !inside(to, sg) ? sg : nil
            }
            if let (first, _, sg) = redirects[to] {
                f.edges[idx].to = first
                f.edges[idx].onCluster[1] = !inside(from, sg) ? sg : nil
            }
        }
        var keep: [Int] = []
        keep.reserveCapacity(f.nodes.count)
        var remap = [Int](repeating: 0, count: f.nodes.count)
        for i in 0..<f.nodes.count {
            if redirects[i] == nil {
                remap[i] = keep.count
                keep.append(i)
            }
        }
        let oldNodes = f.nodes
        f.nodes = keep.map { oldNodes[$0] }
        for idx in 0..<f.edges.count {
            f.edges[idx].from = remap[f.edges[idx].from]
            f.edges[idx].to = remap[f.edges[idx].to]
        }
    }

    private static func inCluster(
        _ nodeIdx: Int,
        _ target: Int,
        _ nodes: [Node],
        _ subgraphs: [Subgraph]
    ) -> Bool {
        var cur = nodes[nodeIdx].cluster
        var steps = 0
        while let c = cur {
            if c == target {
                return true
            }
            cur = subgraphs[c].parent
            steps += 1
            if steps > subgraphs.count {
                break
            }
        }
        return false
    }

    private struct Parser {
        var f: Flowchart
        var ids: [String: Int]
        var stack: [Int]
        var styles: StyleSheet
        var defaultEdgeStyle: EdgeStyle
        var edgeStyles: [Int: EdgeStyle]
        var edgeIds: Set<String>
        /// Set once the source goes past `MAX_ITEMS` or `MAX_DEPTH`.
        var over: Bool

        mutating func budget() -> Bool {
            if f.nodes.count + f.edges.count + f.subgraphs.count >= MAX_ITEMS {
                over = true
            }
            return !over
        }

        mutating func statement(_ s: String) -> Bool {
            let kw: String
            if let idx = s.firstIndex(where: { isUnicodeWS($0) || $0 == ":" }) {
                kw = String(s[..<idx])
            } else {
                kw = s
            }
            switch kw {
            case "subgraph":
                let rest = String(s.dropFirst("subgraph".count).trimmed())
                let sgId: String?
                let title: String
                if let openBracket = rest.firstIndex(of: "["), rest.hasSuffix("]") {
                    let rawId = String(rest[..<openBracket].trimmed())
                    sgId = rawId.isEmpty ? nil : rawId
                    let innerStart = rest.index(after: openBracket)
                    let innerEnd = rest.index(before: rest.endIndex)
                    title = cleanQuoted(String(rest[innerStart..<innerEnd]))
                } else {
                    let hasWS = rest.contains(where: { isUnicodeWS($0) })
                    sgId = (!rest.hasPrefix("\"") && !hasWS && !rest.isEmpty) ? rest : nil
                    title = cleanQuoted(rest)
                }
                guard budget() else { return false }
                if stack.count >= MAX_DEPTH {
                    over = true
                    return false
                }
                f.subgraphs.append(Subgraph(id: sgId, title: title, parent: stack.last))
                stack.append(f.subgraphs.count - 1)
            case "end" where s == "end":
                guard stack.popLast() != nil else { return false }
            case "title":
                let t = cleanQuoted(String(s.dropFirst("title".count).trimmed()))
                if !t.isEmpty {
                    f.title = t
                }
            case "direction":
                let rest = String(s.dropFirst("direction".count).trimmed())
                if stack.isEmpty && f.edges.isEmpty, let d = Dir.parse(rest) {
                    f.dir = d
                }
            case "classDef":
                styles.classDef(String(s.dropFirst("classDef".count)))
            case "class":
                styles.assignClasses(String(s.dropFirst("class".count)))
            case "style":
                styles.style(String(s.dropFirst("style".count)))
            case "linkStyle":
                let rest = String(s.dropFirst("linkStyle".count).trimmed())
                if let (targets, props) = rest.splitOnceWhere({ isUnicodeWS($0) }) {
                    let st = parseEdgeStyleProps(String(props))
                    for rawTok in targets.split(separator: ",", omittingEmptySubsequences: false) {
                        let tok = String(rawTok.trimmed())
                        if tok == "default" {
                            defaultEdgeStyle = defaultEdgeStyle.merge(st)
                        } else if let idx = Int(tok), idx >= 0 {
                            let cur = edgeStyles[idx] ?? EdgeStyle()
                            edgeStyles[idx] = cur.merge(st)
                        }
                    }
                }
            case "click", "accTitle", "accDescr":
                break
            default:
                return chain(s)
            }
            return true
        }

        /// `A --> B & C -.-> D`, read whole before anything is added, so a chain that doesn't read
        /// leaves no stray nodes behind.
        mutating func chain(_ s: String) -> Bool {
            var c = Cur(s)
            // `e1@{ animate: true }` sets how a named edge moves, which a still drawing leaves out.
            if let (idSub, _) = s.splitOnce("@{"), edgeIds.contains(String(idSub.trimmed())) {
                return true
            }
            guard let firstGroup = group(&c) else { return false }
            var groups: [[NodeRef]] = [firstGroup]
            var links: [Link] = []
            while true {
                c.skipWs()
                if c.done() {
                    break
                }
                guard let lnk = flowchart.link(&c) else { return false }
                links.append(lnk)
                c.skipWs()
                guard let grp = group(&c) else { return false }
                groups.append(grp)
            }
            var resolvedGroups: [[Int]] = []
            resolvedGroups.reserveCapacity(groups.count)
            for g in groups {
                var rg: [Int] = []
                rg.reserveCapacity(g.count)
                for nRef in g {
                    guard let nIdx = node(nRef) else { return false }
                    rg.append(nIdx)
                }
                resolvedGroups.append(rg)
            }
            for lnk in links {
                if let eid = lnk.id {
                    edgeIds.insert(eid)
                }
            }
            for i in 0..<links.count {
                let lnk = links[i]
                let leftGroup = resolvedGroups[i]
                let rightGroup = resolvedGroups[i + 1]
                for from in leftGroup {
                    for to in rightGroup {
                        guard budget() else { return false }
                        f.edges.append(
                            Edge(
                                from: from,
                                to: to,
                                label: lnk.label,
                                line: lnk.line,
                                start: lnk.start,
                                end: lnk.end,
                                minlen: lnk.minlen,
                                style: EdgeStyle(),
                                onCluster: [nil, nil]
                            )
                        )
                    }
                }
            }
            return true
        }

        mutating func node(_ r: NodeRef) -> Int? {
            if let cls = r.className {
                styles.addClass(r.id, cls)
            }
            let cluster = stack.last
            let i: Int
            if let existing = ids[r.id] {
                i = existing
            } else {
                guard budget() else { return nil }
                f.nodes.append(
                    Node(
                        id: r.id,
                        label: r.id,
                        shape: .rect,
                        cluster: cluster,
                        style: NodeStyle(),
                        explicitShape: false
                    )
                )
                let newIdx = f.nodes.count - 1
                ids[r.id] = newIdx
                i = newIdx
            }
            if f.nodes[i].cluster == nil {
                f.nodes[i].cluster = cluster
            }
            if let (lbl, shp) = r.shape {
                if let l = lbl {
                    f.nodes[i].label = l
                }
                f.nodes[i].shape = shp
                f.nodes[i].explicitShape = true
            }
            return i
        }
    }

    /// A node as written in a chain: its id, its shape and label if given, and a `:::class`.
    private struct NodeRef {
        var id: String
        var shape: (String?, NodeShape)?
        var className: String?
    }

    private static func group(_ c: inout Cur) -> [NodeRef]? {
        guard let first = nodeRef(&c) else { return nil }
        var v = [first]
        while true {
            c.skipWs()
            if !c.eat("&") {
                return v
            }
            c.skipWs()
            guard let next = nodeRef(&c) else { return nil }
            v.append(next)
        }
    }

    private static func nodeRef(_ c: inout Cur) -> NodeRef? {
        guard let id = ident(&c) else { return nil }
        let shp = shape(&c)
        let cls: String?
        if c.eat(":::") {
            guard let cname = ident(&c) else { return nil }
            cls = cname
        } else {
            cls = nil
        }
        return NodeRef(id: id, shape: shp, className: cls)
    }

    static func ident(_ c: inout Cur) -> String? {
        let start = c.i
        while let ch = c.peek() {
            func isWord(_ sc: Unicode.Scalar) -> Bool {
                isAlphanumericScalar(sc) || sc == "_"
            }
            if isWord(ch) || (ch == "-" && c.i > start && (c.peek2().map(isWord) ?? false)) {
                c.bump()
            } else {
                break
            }
        }
        return c.i > start ? String(c.s[start..<c.i]) : nil
    }

    private static let SHAPES: [(String, String, NodeShape)] = [
        ("(((", ")))", .doubleCircle),
        ("([", "])", .stadium),
        ("[[", "]]", .subroutine),
        ("[(", ")]", .cylinder),
        ("((", "))", .circle),
        ("{{", "}}", .hexagon),
        (">", "]", .asymmetric),
        ("[", "]", .rect),
        ("(", ")", .round),
        ("{", "}", .diamond),
    ]

    private static func startsWithScalars(
        _ scalars: String.UnicodeScalarView,
        at idx: String.UnicodeScalarIndex,
        _ target: String
    ) -> String.UnicodeScalarIndex? {
        var cur = idx
        for sc in target.unicodeScalars {
            guard cur < scalars.endIndex, scalars[cur] == sc else { return nil }
            cur = scalars.index(after: cur)
        }
        return cur
    }

    private static func findClose(
        _ s: String,
        from startIdx: String.UnicodeScalarIndex,
        _ open: String,
        _ close: String
    ) -> String.UnicodeScalarIndex? {
        let scalars = s.unicodeScalars
        let nested = open.unicodeScalars.count == 1 && close.unicodeScalars.count == 1 && open != ">"
        var depth = 1
        var quoted = false
        var escaped = false
        var i = startIdx
        while i < scalars.endIndex {
            let ch = scalars[i]
            if escaped {
                escaped = false
                i = scalars.index(after: i)
                continue
            }
            if quoted {
                if ch == "\\" {
                    escaped = true
                } else if ch == "\"" {
                    quoted = false
                }
                i = scalars.index(after: i)
                continue
            }
            if ch == "\"" {
                quoted = true
                i = scalars.index(after: i)
                continue
            }
            if let afterClose = startsWithScalars(scalars, at: i, close) {
                depth -= 1
                if depth == 0 {
                    return i
                }
                i = afterClose
                continue
            }
            if nested, let afterOpen = startsWithScalars(scalars, at: i, open) {
                depth += 1
                i = afterOpen
                continue
            }
            i = scalars.index(after: i)
        }
        return nil
    }

    private static func findQuoteEnd(
        _ s: String,
        from startIdx: String.UnicodeScalarIndex
    ) -> (String, String.UnicodeScalarIndex)? {
        let scalars = s.unicodeScalars
        var out = ""
        var escaped = false
        var i = startIdx
        while i < scalars.endIndex {
            let ch = scalars[i]
            let next = scalars.index(after: i)
            if escaped {
                out.unicodeScalars.append(ch)
                escaped = false
                i = next
                continue
            }
            if ch == "\\" {
                escaped = true
            } else if ch == "\"" {
                return (out, next)
            } else {
                out.unicodeScalars.append(ch)
            }
            i = next
        }
        return nil
    }

    private static func findUnquoted(
        _ s: String,
        from startIdx: String.UnicodeScalarIndex,
        _ needle: String
    ) -> String.UnicodeScalarIndex? {
        let scalars = s.unicodeScalars
        var quoted = false
        var escaped = false
        var i = startIdx
        while i < scalars.endIndex {
            let ch = scalars[i]
            let next = scalars.index(after: i)
            if escaped {
                escaped = false
                i = next
                continue
            }
            if quoted {
                if ch == "\\" {
                    escaped = true
                } else if ch == "\"" {
                    quoted = false
                }
                i = next
                continue
            }
            if ch == "\"" {
                quoted = true
                i = next
                continue
            }
            if startsWithScalars(scalars, at: i, needle) != nil {
                return i
            }
            i = next
        }
        return nil
    }

    /// Mermaid v11 `@{ shape: cyl, label: "Postgres" }` node metadata. Shapes it doesn't know, and
    /// parts it can't read, leave a plain rectangle.
    private static func parseAtShape(_ c: inout Cur) -> (String?, NodeShape)? {
        _ = c.eat("@{")
        guard let end = findClose(c.s, from: c.i, "{", "}") else { return nil }
        let inner = String(c.s[c.i..<end])
        var kind: NodeShape = .rect
        var label: String? = nil
        for part in splitTopCommas(inner) {
            guard let (k, vRaw) = part.splitOnce(":") else { continue }
            let v = String(vRaw.trimmed())
            switch k.trimmed() {
            case "shape":
                let name = stripBothQuotes(v).asciiLower()
                kind = NodeShape.named(name) ?? .rect
            case "label":
                label = cleanQuoted(v)
            case "form" where kind == .rect:
                // Icons and images can't be fetched, so they draw as their frame with the label.
                switch stripBothQuotes(v) {
                case "circle": kind = .circle
                case "rounded": kind = .round
                default: kind = .rect
                }
            default:
                break
            }
        }
        c.i = c.s.unicodeScalars.index(after: end)
        return (label, kind)
    }

    private static func stripBothQuotes(_ s: String) -> String {
        var scalars = Substring.UnicodeScalarView(s.unicodeScalars)
        while scalars.first == "\"" { scalars = scalars.dropFirst() }
        while scalars.last == "\"" { scalars = scalars.dropLast() }
        return String(scalars)
    }

    private static func splitTopCommas(_ s: String) -> [String] {
        var out: [String] = []
        let scalars = s.unicodeScalars
        var start = scalars.startIndex
        var quoted = false
        var escaped = false
        var i = scalars.startIndex
        while i < scalars.endIndex {
            let ch = scalars[i]
            let next = scalars.index(after: i)
            if escaped {
                escaped = false
                i = next
                continue
            }
            if ch == "\\" && quoted {
                escaped = true
            } else if ch == "\"" {
                quoted.toggle()
            } else if ch == "," && !quoted {
                let seg = String(s[start..<i].trimmed())
                if !seg.isEmpty {
                    out.append(seg)
                }
                start = next
            }
            i = next
        }
        let tail = String(s[start...].trimmed())
        if !tail.isEmpty {
            out.append(tail)
        }
        return out
    }

    /// A node's bracketed label and shape, `nil` when it has none. An opener without its closer
    /// reads as a plain rectangle holding the text as written, so `[/route]` is the label `/route`.
    static func shape(_ c: inout Cur) -> (String?, NodeShape)? {
        let start = c.i
        let isAt = startsWithScalars(c.s.unicodeScalars, at: c.i, "@{") != nil
        if !isAt {
            guard let p = c.peek(), (p == "[" || p == "(" || p == "{" || p == ">") else {
                return nil
            }
        }
        if let exact = exactShape(&c) {
            return exact
        }
        c.i = start
        return looseShape(&c)
    }

    private static func exactShape(_ c: inout Cur) -> (String?, NodeShape)? {
        if startsWithScalars(c.s.unicodeScalars, at: c.i, "@{") != nil {
            return parseAtShape(&c)
        }
        for open in ["[/", "[\\"] {
            if c.eat(open) {
                guard let end = findClose(c.s, from: c.i, "[", "]") else { return nil }
                let inner = c.s[c.i..<end]
                guard let closeSc = inner.unicodeScalars.last, (closeSc == "/" || closeSc == "\\") else {
                    return nil
                }
                let beforeClose = inner.unicodeScalars.index(before: inner.unicodeScalars.endIndex)
                let label = cleanQuoted(String(c.s[c.i..<beforeClose]))
                c.i = c.s.unicodeScalars.index(after: end)
                let kind: NodeShape
                if open == "[/" && closeSc == "/" {
                    kind = .leanRight
                } else if open == "[/" {
                    kind = .trapBottom
                } else if closeSc == "/" {
                    kind = .trapTop
                } else {
                    kind = .leanLeft
                }
                return (label, kind)
            }
        }
        guard let (open, close, kind) = SHAPES.first(where: {
            startsWithScalars(c.s.unicodeScalars, at: c.i, $0.0) != nil
        }) else {
            return nil
        }
        _ = c.eat(open)
        c.skipWs()
        let rawLabel: String
        if c.peek() == "\"" {
            c.bump()
            guard let (lbl, afterQuote) = findQuoteEnd(c.s, from: c.i) else { return nil }
            c.i = afterQuote
            c.skipWs()
            guard c.eat(close) else { return nil }
            rawLabel = lbl
        } else {
            guard let end = findClose(c.s, from: c.i, open, close) else { return nil }
            rawLabel = String(c.s[c.i..<end])
            c.i = c.s.unicodeScalars.index(end, offsetBy: close.unicodeScalars.count)
        }
        return (clean(rawLabel), kind)
    }

    /// A rectangle from the opener's first bracket to its match, or to the end of the statement.
    private static func looseShape(_ c: inout Cur) -> (String?, NodeShape) {
        let scalars = c.s.unicodeScalars
        let at = startsWithScalars(scalars, at: c.i, "@{") != nil
        let first = c.peek()
        let open: String
        let close: String
        if first == "(" {
            (open, close) = ("(", ")")
        } else if first == "{" {
            (open, close) = ("{", "}")
        } else if first == ">" {
            (open, close) = (">", "]")
        } else if at {
            (open, close) = ("{", "}")
        } else {
            (open, close) = ("[", "]")
        }
        let skip = at ? 2 : 1
        let bodyStart = scalars.index(c.i, offsetBy: skip)
        let text: String
        if let end = findClose(c.s, from: bodyStart, open, close) {
            text = String(c.s[bodyStart..<end])
            c.i = scalars.index(after: end)
        } else {
            text = String(c.s[bodyStart...])
            c.i = scalars.endIndex
        }
        let label = cleanQuoted(text)
        let optLabel: String? = (!at && !label.isEmpty) ? label : nil
        return (optLabel, .rect)
    }

    private static func run(_ c: inout Cur) -> String {
        let start = c.i
        while let ch = c.peek(), (ch == "-" || ch == "=" || ch == "." || ch == "~") {
            c.bump()
        }
        return String(c.s[start..<c.i])
    }

    private static func endHead(_ c: inout Cur) -> Head {
        guard let ch = c.peek() else { return .none }
        if ch == ">" {
            c.bump()
            return .arrow
        }
        if ch == "o" || ch == "x" {
            let p2 = c.peek2()
            if p2 == nil || p2!.properties.isWhitespace || p2 == "|" {
                c.bump()
                return ch == "o" ? .circle : .cross
            }
        }
        return .none
    }

    static func link(_ c: inout Cur) -> Link? {
        // A v11 edge id, `A e1@--> B`, names the edge for a later `e1@{ … }`.
        let save = c.i
        var edgeId: String? = nil
        if let cand = ident(&c), c.eat("@"), let pk = c.peek(),
           (pk == "-" || pk == "=" || pk == "." || pk == "~" || pk == "<" || pk == "o" || pk == "x")
        {
            edgeId = cand
        } else {
            c.i = save
        }

        let start: Head
        if c.eat("<") {
            start = .arrow
        } else if let ch = c.peek(), (ch == "o" || ch == "x"),
                  let ch2 = c.peek2(), (ch2 == "-" || ch2 == "=")
        {
            c.bump()
            start = ch == "o" ? .circle : .cross
        } else {
            start = .none
        }

        let first = run(&c)
        if first.unicodeScalars.count < 2 {
            return nil
        }
        var end = endHead(&c)
        var body = first
        var label: String? = nil
        if end == .none && (first == "--" || first == "==" || first == "-.") {
            let close = first == "-." ? ".-" : first
            guard let at = findUnquoted(c.s, from: c.i, close) else { return nil }
            let text = cleanQuoted(String(c.s[c.i..<at]))
            if text.isEmpty {
                return nil
            }
            label = text
            c.i = at
            body = run(&c)
            end = endHead(&c)
        }
        let line: Line
        if body.contains("~") {
            line = .invisible
        } else if body.contains("=") {
            line = .thick
        } else if body.contains(".") {
            line = .dotted
        } else {
            line = .solid
        }
        let rawMinlen: Int
        if line == .dotted {
            rawMinlen = body.unicodeScalars.filter { $0 == "." }.count
        } else {
            let n = body.unicodeScalars.filter { $0 == "-" || $0 == "=" || $0 == "~" }.count
            rawMinlen = end == .none ? max(0, n - 2) : max(0, n - 1)
        }
        let minlen = clampInt(rawMinlen, 1, MAX_MINLEN)

        let saveAfter = c.i
        c.skipWs()
        if c.eat("|") {
            guard let at = findUnquoted(c.s, from: c.i, "|") else { return nil }
            let text = cleanQuoted(String(c.s[c.i..<at]))
            c.i = c.s.unicodeScalars.index(after: at)
            if !text.isEmpty {
                label = text
            }
        } else {
            c.i = saveAfter
        }
        return Link(id: edgeId, line: line, start: start, end: end, minlen: minlen, label: label)
    }

    private static let SPACING = Spacing(node: 36.0, rank: 44.0, cluster: 14.0)

    static func draw(_ f: Flowchart, _ paint: DiagramStyle, _ hover: (Hover, Color)?) -> Scene? {
        drawCanvas(f, paint, hover)?.finishFit(paint)
    }

    /// `f` drawn at full size, before `Canvas.finish`.
    static func drawCanvas(_ f: Flowchart, _ paint: DiagramStyle, _ hover: (Hover, Color)?) -> Canvas? {
        let nodes: [DrawNode] = f.nodes.map { n in
            let label = measureBalanced(n.label, paint.font)
            return .shape(
                shape: n.shape,
                label: label,
                size: nodeSize(n.shape, label.size),
                cluster: n.cluster,
                style: n.style
            )
        }
        let clusters: [ClusterSpec] = f.subgraphs.map { s in
            ClusterSpec(title: s.title, parent: s.parent)
        }
        let nm = names(f)
        guard var c = layeredCanvas(f.dir, nodes, nm.nodes, f.edges, clusters, SPACING, paint, hover) else {
            return nil
        }
        c.names = nm
        return c
    }

    /// Nodes and subgraphs by id, edges by their ends.
    private static func names(_ f: Flowchart) -> Names {
        let frames: [String] = f.subgraphs.enumerated().map { (i, s) in
            s.id ?? "#\(i)"
        }
        return Names.new(f.nodes.map { $0.id }, f.edges, frames)
    }
}
