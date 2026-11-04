// Ported from: crates/rune-mermaid/src/er.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Entity-relationship diagrams (`erDiagram`), laid out on `layered_draw`: entities as
//! attribute tables, relationships in crow's-foot notation.

import Rune

enum er {
    struct Entity {
        var id: String
        var label: String
        var attrs: [Attr]
        var style: NodeStyle
    }

    /// `type name PK, FK "comment"`.
    struct Attr: Equatable {
        var ty: String = ""
        var name: String = ""
        var keys: String = ""
        var comment: String = ""
    }

    struct ErDiagram {
        var title: String?
        var dir: Dir
        var entities: [Entity]
        var edges: [Edge]
    }

    static func parse(_ header: String, _ body: [String]) -> ErDiagram? {
        var p = Parser(
            d: ErDiagram(title: nil, dir: .down, entities: [], edges: []),
            ids: [:],
            open: nil,
            skipping: false,
            styles: StyleSheet(),
            attrs: 0,
            over: false
        )
        for line in [header] + body {
            for stmt in statements(line) {
                if p.skipping {
                    p.skipping = (stmt != "}")
                    continue
                }
                let entCount = p.d.entities.count
                let edgeCount = p.d.edges.count
                if !p.statement(stmt) {
                    if p.over {
                        return nil
                    }
                    if p.d.entities.count > entCount {
                        p.d.entities.removeSubrange(entCount...)
                    }
                    if p.d.edges.count > edgeCount {
                        p.d.edges.removeSubrange(edgeCount...)
                    }
                    p.ids = p.ids.filter { $0.value < entCount }
                    p.skipping = stmt.hasSuffix("{")
                }
            }
        }
        for (id, idx) in p.ids {
            p.d.entities[idx].style = p.styles.get(id)
        }
        return p.d.entities.isEmpty ? nil : p.d
    }

    private struct Parser {
        var d: ErDiagram
        var ids: [String: Int]
        /// The entity whose `{ … }` attribute block is open.
        var open: Int?
        /// Inside the body of a block that didn't read, until its `}`.
        var skipping: Bool
        var styles: StyleSheet
        var attrs: Int
        var over: Bool

        mutating func budget() -> Bool {
            if d.entities.count + d.edges.count >= MAX_ITEMS || attrs > MAX_ITEMS * 4 {
                over = true
            }
            return !over
        }

        mutating func statement(_ s: String) -> Bool {
            if let idx = open {
                if s == "}" {
                    open = nil
                    return true
                }
                guard let attr = parseAttr(s) else { return false }
                attrs += 1
                guard budget() else { return false }
                d.entities[idx].attrs.append(attr)
                return true
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
                return true
            case "direction":
                guard let dir = Dir.parse(String(s.dropFirst("direction".count).trimmed())) else {
                    return false
                }
                d.dir = dir
                return true
            case "accTitle", "accDescr":
                return true
            case "classDef":
                return styles.classDef(String(s.dropFirst("classDef".count)))
            case "class":
                let rest = String(s.dropFirst("class".count).trimmed())
                guard let (idsRaw, clsRaw) = rsplitOnceWS(rest) else { return false }
                let cls = String(clsRaw.trimmed())
                for part in idsRaw.split(separator: ",", omittingEmptySubsequences: false) {
                    styles.addClass(String(part.trimmed()), cls)
                }
                return true
            case "style":
                return styles.style(String(s.dropFirst("style".count)))
            default:
                break
            }
            if relation(s) {
                return true
            }
            // `NAME`, `NAME["Alias"]`, `"Name with spaces"`, optionally opening `{ … }`.
            let head: String
            let block: String?
            if let at = s.firstIndex(of: "{") {
                head = String(s[..<at].trimmed())
                block = String(s[s.index(after: at)...].trimmed())
            } else {
                head = s
                block = nil
            }
            guard let idx = entity(head) else { return false }
            if let blk = block {
                if blk.isEmpty {
                    open = idx
                } else {
                    guard let innerSub = blk.stripSuffix("}") else { return false }
                    let inner = String(innerSub.trimmed())
                    if !inner.isEmpty {
                        guard let attr = parseAttr(inner) else { return false }
                        attrs += 1
                        guard budget() else { return false }
                        d.entities[idx].attrs.append(attr)
                    }
                }
            }
            return true
        }

        mutating func relation(_ s: String) -> Bool {
            let lhs: String
            let labelOpt: String?
            if let at = colonOutsideQuotes(s) {
                lhs = String(s[..<at].trimmed())
                labelOpt = cleanQuoted(String(s[s.index(after: at)...]))
            } else {
                lhs = String(s.trimmed())
                labelOpt = nil
            }
            guard let (a, start, line, end, b) = symbolic(lhs) ?? worded(lhs),
                  let from = entity(a),
                  let to = entity(b),
                  budget()
            else { return false }
            let label: String? = (labelOpt?.isEmpty == false) ? labelOpt : nil
            d.edges.append(
                Edge(
                    from: from,
                    to: to,
                    label: label,
                    line: line,
                    start: start,
                    end: end,
                    minlen: 1,
                    style: EdgeStyle(),
                    onCluster: [nil, nil]
                )
            )
            return true
        }

        mutating func entity(_ rawIn: String) -> Int? {
            let raw: String
            let cls: String?
            if let (idSub, clsSub) = rawIn.splitOnce(":::") {
                raw = String(idSub.trimmed())
                cls = String(clsSub.trimmed())
            } else {
                raw = String(rawIn.trimmed())
                cls = nil
            }
            let idPart: String
            let alias: String?
            if let at = raw.firstIndex(of: "["), raw.hasSuffix("]"), at > raw.startIndex {
                idPart = String(raw[..<at].trimmed())
                let innerStart = raw.index(after: at)
                let innerEnd = raw.index(before: raw.endIndex)
                alias = cleanQuoted(String(raw[innerStart..<innerEnd]))
            } else {
                idPart = raw
                alias = nil
            }
            let id: String
            if let qOpen = idPart.stripPrefix("\""), let q = qOpen.stripSuffix("\"") {
                guard !q.isEmpty && !q.contains("\"") else { return nil }
                id = String(q)
            } else if validId(idPart) {
                id = idPart
            } else {
                return nil
            }
            if let c = cls {
                styles.addClass(id, c)
            }
            let idx: Int
            if let existing = ids[id] {
                idx = existing
            } else {
                guard budget() else { return nil }
                d.entities.append(Entity(id: id, label: clean(id), attrs: [], style: NodeStyle()))
                let newIdx = d.entities.count - 1
                ids[id] = newIdx
                idx = newIdx
            }
            if let a = alias, !a.isEmpty {
                d.entities[idx].label = a
            }
            return idx
        }
    }

    private static func rsplitOnceWS(_ s: String) -> (Substring, Substring)? {
        var idx = s.endIndex
        while idx > s.startIndex {
            let prev = s.index(before: idx)
            if isUnicodeWS(s[prev]) {
                return (s[..<prev], s[idx...])
            }
            idx = prev
        }
        return nil
    }

    private static func validId(_ s: String) -> Bool {
        !s.isEmpty && s.unicodeScalars.allSatisfy { sc in
            isAlphanumericScalar(sc) || sc == "_" || sc == "-" || sc == "." || sc == "*"
        }
    }

    /// `A ||--o{ B`: two marks either side of `--` (identifying) or `..` (not).
    private static func symbolic(_ s: String) -> (String, Head, Line, Head, String)? {
        let scalars = s.unicodeScalars
        let indices = Array(scalars.indices)
        guard indices.count >= 6 else { return nil }
        for k in 2..<(indices.count - 3) {
            let m0 = scalars[indices[k]]
            let m1 = scalars[indices[k + 1]]
            let line: Line
            if m0 == "-" && m1 == "-" {
                line = .solid
            } else if m0 == "." && m1 == "." {
                line = .dotted
            } else {
                continue
            }
            let l0 = scalars[indices[k - 2]]
            let l1 = scalars[indices[k - 1]]
            let left: Head
            if l0 == "|" && l1 == "|" {
                left = .onlyOne
            } else if l0 == "|" && l1 == "o" {
                left = .zeroOrOne
            } else if l0 == "}" && l1 == "|" {
                left = .oneOrMore
            } else if l0 == "}" && l1 == "o" {
                left = .zeroOrMore
            } else {
                continue
            }
            let r0 = scalars[indices[k + 2]]
            let r1 = scalars[indices[k + 3]]
            let right: Head
            if r0 == "|" && r1 == "|" {
                right = .onlyOne
            } else if r0 == "o" && r1 == "|" {
                right = .zeroOrOne
            } else if r0 == "|" && r1 == "{" {
                right = .oneOrMore
            } else if r0 == "o" && r1 == "{" {
                right = .zeroOrMore
            } else {
                continue
            }
            let aEnd = indices[k - 2]
            let zStart = scalars.index(after: indices[k + 3])
            let a = String(s[..<aEnd].trimmed())
            let z = String(s[zStart...].trimmed())
            if a.isEmpty || z.isEmpty {
                return nil
            }
            return (a, left, line, right, z)
        }
        return nil
    }

    /// `CAR only one to zero or more DRIVER`, with `optionally to` for a dotted line.
    private static func worded(_ s: String) -> (String, Head, Line, Head, String)? {
        guard let (a, rest1) = firstToken(s),
              let (rest2, z) = lastToken(rest1)
        else { return nil }
        let words = String(rest2.trimmed())
        let leftStr: String
        let line: Line
        let rightStr: String
        if let (l, r) = words.splitOnce(" optionally to ") {
            leftStr = String(l)
            line = .dotted
            rightStr = String(r)
        } else if let (l, r) = words.splitOnce(" to ") {
            leftStr = String(l)
            line = .solid
            rightStr = String(r)
        } else {
            return nil
        }
        guard let left = card(String(leftStr.trimmed())),
              let right = card(String(rightStr.trimmed()))
        else { return nil }
        return (a, left, line, right, z)
    }

    private static func card(_ s: String) -> Head? {
        switch s.asciiLower() {
        case "only one", "1", "one", "exactly one": return .onlyOne
        case "zero or one", "one or zero": return .zeroOrOne
        case "one or more", "one or many", "many(1)", "1+": return .oneOrMore
        case "zero or more", "zero or many", "many(0)", "0+", "many": return .zeroOrMore
        default: return nil
        }
    }

    private static func firstToken(_ raw: String) -> (String, String)? {
        let s = String(raw.trimmed())
        if let rest = s.stripPrefix("\"") {
            guard let closeIdx = rest.firstIndex(of: "\"") else { return nil }
            let afterClose = s.index(after: closeIdx)
            return (String(s[..<afterClose]), String(s[afterClose...]))
        }
        guard let wsIdx = s.firstIndex(where: { isUnicodeWS($0) }) else { return nil }
        return (String(s[..<wsIdx]), String(s[wsIdx...]))
    }

    private static func lastToken(_ raw: String) -> (String, String)? {
        let s = String(raw.trimmed())
        if let rest = s.stripSuffix("\"") {
            guard let openIdx = rest.lastIndex(of: "\"") else { return nil }
            return (String(s[..<openIdx]), String(s[openIdx...]))
        }
        var idx = s.endIndex
        while idx > s.startIndex {
            let prev = s.index(before: idx)
            if isUnicodeWS(s[prev]) {
                return (String(s[..<idx]), String(s[idx...]))
            }
            idx = prev
        }
        return nil
    }

    private static func colonOutsideQuotes(_ s: String) -> String.Index? {
        var quoted = false
        let scalars = s.unicodeScalars
        var i = scalars.startIndex
        while i < scalars.endIndex {
            let sc = scalars[i]
            let next = scalars.index(after: i)
            if sc == "\"" {
                quoted.toggle()
            } else if sc == ":" && !quoted {
                let isTriple = s[i...].hasPrefix(":::")
                let prevColon = i > scalars.startIndex && scalars[scalars.index(before: i)] == ":"
                if !isTriple && !prevColon {
                    return i
                }
            }
            i = next
        }
        return nil
    }

    /// `type name [PK|FK|UK[, …]] ["comment"]`.
    private static func parseAttr(_ s: String) -> Attr? {
        let body: String
        let comment: String
        if let at = s.firstIndex(of: "\"") {
            body = String(s[..<at].trimmed())
            comment = cleanQuoted(String(s[at...]))
        } else {
            body = String(s.trimmed())
            comment = ""
        }
        let words = body.split(whereSeparator: { isUnicodeWS($0) })
        guard words.count >= 2 else { return nil }
        let ty = String(words[0])
        let name = String(words[1])
        var keys: [String] = []
        for w in words.dropFirst(2) {
            for sub in w.split(separator: ",", omittingEmptySubsequences: false) {
                let k = String(sub.trimmed())
                guard !k.isEmpty else { continue }
                switch k {
                case "PK", "FK", "UK": keys.append(k)
                default: return nil
                }
            }
        }
        return Attr(ty: generics(ty), name: name, keys: keys.joined(separator: ", "), comment: comment)
    }

    /// `list~string~` as `list<string>`.
    private static func generics(_ s: String) -> String {
        var open = false
        var out = ""
        out.unicodeScalars.reserveCapacity(s.unicodeScalars.count)
        for sc in s.unicodeScalars {
            if sc == "~" {
                open.toggle()
                out.unicodeScalars.append(open ? "<" : ">")
            } else {
                out.unicodeScalars.append(sc)
            }
        }
        return out
    }

    private static let SPACING = Spacing(node: 40.0, rank: 52.0, cluster: 16.0)

    static func draw(_ d: ErDiagram, _ paint: DiagramStyle, _ hover: (Hover, Color)?) -> Scene? {
        var headFont = paint.font
        headFont.weight = 600.0
        var rowFont = paint.font
        rowFont.size -= 1.0
        rowFont.lineHeight -= 2.0
        let nodes: [DrawNode] = d.entities.map { e in
            let name = measureWrap(e.label, headFont, 220.0)
            let rows: [[Measured]] = e.attrs.map { a in
                [a.ty, a.name, a.keys, a.comment].map { measureWrap($0, rowFont, 180.0) }
            }
            // A column nobody fills takes no room.
            var cols = [Float](repeating: 0.0, count: 4)
            for row in rows {
                for i in 0..<min(cols.count, row.count) where !row[i].text.isEmpty {
                    cols[i] = max(cols[i], row[i].size[0] + ENTITY_PAD[0] * 2.0)
                }
            }
            let table = cols.reduce(0.0, +)
            let w = max(max(table, name.size[0] + 28.0), 90.0)
            // The last filled column takes up any slack.
            if let lastIdx = cols.lastIndex(where: { $0 > 0.0 }) {
                cols[lastIdx] += w - table
            }
            var rowsHeight: Float = 0.0
            for r in rows { rowsHeight += entityRowH(r) }
            let h = name.size[1] + ENTITY_PAD[1] * 2.0 + rowsHeight
            return .entity(name: name, rows: rows, cols: cols, size: [w, max(h, 36.0)], style: e.style)
        }
        return drawLayered(d.dir, nodes, d.edges, [], SPACING, paint, hover)
    }
}
