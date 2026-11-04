// Ported from: crates/rune-mermaid/src/class.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! UML class and Rust struct/trait diagrams (`classDiagram`), laid out on `layered_draw`.

import Rune

enum `class` {
    struct ClassNode {
        var id: String
        var label: String
        var stereo: String?
        var fields: [String]
        var methods: [String]
        var namespace: Int?
        var style: NodeStyle
    }

    struct Namespace {
        var title: String
    }

    struct ClassDiagram {
        var title: String?
        var dir: Dir
        var classes: [ClassNode]
        var edges: [Edge]
        var namespaces: [Namespace]
    }

    /// Relationship tokens, longest first: `(token, start_head, end_head, line)`.
    private static let RELS: [(String, Head, Head, Line)] = [
        ("<|..", .openTriangle, .none, .dotted),
        ("..|>", .none, .openTriangle, .dotted),
        ("<|--", .openTriangle, .none, .solid),
        ("--|>", .none, .openTriangle, .solid),
        ("*--", .diamondFilled, .none, .solid),
        ("--*", .none, .diamondFilled, .solid),
        ("o--", .diamondOpen, .none, .solid),
        ("--o", .none, .diamondOpen, .solid),
        ("<-->", .arrow, .arrow, .solid),
        ("<..>", .arrow, .arrow, .dotted),
        ("-->", .none, .arrow, .solid),
        ("<--", .arrow, .none, .solid),
        ("..>", .none, .arrow, .dotted),
        ("<..", .arrow, .none, .dotted),
        ("--", .none, .none, .solid),
        ("..", .none, .none, .dotted),
    ]

    static func parse(_ header: String, _ body: [String]) -> ClassDiagram? {
        var p = Parser(
            d: ClassDiagram(title: nil, dir: .down, classes: [], edges: [], namespaces: []),
            ids: [:],
            activeClass: nil,
            activeNs: nil,
            styles: StyleSheet(),
            skipping: false,
            members: 0,
            over: false
        )
        // A statement that doesn't read is skipped (with its `{ … }` body); one past the bounds leaves
        // the whole diagram as source.
        for line in [header] + body {
            for stmt in statements(line) {
                if p.skipping {
                    p.skipping = (stmt != "}")
                } else {
                    let classCount = p.d.classes.count
                    let edgeCount = p.d.edges.count
                    if !p.statement(stmt) {
                        if p.over {
                            return nil
                        }
                        // Whatever the statement added before it failed goes too.
                        if p.d.classes.count > classCount {
                            p.d.classes.removeSubrange(classCount...)
                        }
                        if p.d.edges.count > edgeCount {
                            p.d.edges.removeSubrange(edgeCount...)
                        }
                        p.ids = p.ids.filter { $0.value < classCount }
                        p.skipping = stmt.hasSuffix("{")
                    }
                }
            }
        }
        for (id, idx) in p.ids {
            p.d.classes[idx].style = p.styles.get(id)
        }
        return p.d.classes.isEmpty ? nil : p.d
    }

    private struct Parser {
        var d: ClassDiagram
        var ids: [String: Int]
        var activeClass: Int?
        var activeNs: Int?
        var styles: StyleSheet
        /// Inside the body of a block that didn't read, until its `}`.
        var skipping: Bool
        var members: Int
        /// Set once the source goes past `MAX_ITEMS` (or four times that in members).
        var over: Bool

        mutating func budget() -> Bool {
            if d.classes.count + d.edges.count + d.namespaces.count >= MAX_ITEMS {
                over = true
            }
            return !over
        }

        mutating func statement(_ s: String) -> Bool {
            if let idx = activeClass {
                if s == "}" {
                    activeClass = nil
                    return true
                }
                addMember(idx, s)
                return !over
            }
            if s == "}" {
                guard activeNs != nil else { return false }
                activeNs = nil
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
            case "direction":
                guard let dir = Dir.parse(String(s.dropFirst("direction".count).trimmed())) else {
                    return false
                }
                if d.edges.isEmpty {
                    d.dir = dir
                }
            case "namespace":
                if activeNs != nil {
                    return false
                }
                guard let restSub = s.dropFirst("namespace".count).trimmed().stripSuffix("{"),
                      budget()
                else { return false }
                d.namespaces.append(Namespace(title: cleanQuoted(String(restSub.trimmed()))))
                activeNs = d.namespaces.count - 1
            case "class":
                return classDecl(String(s.dropFirst("class".count).trimmed()))
            case "note", "Note", "link", "click", "callback", "accTitle", "accDescr":
                break
            case "classDef":
                styles.classDef(String(s.dropFirst("classDef".count)))
            case "cssClass":
                let rest = String(s.dropFirst("cssClass".count).trimmed())
                if let (targetsRaw, clsRaw) = rsplitOnceWS(rest) {
                    let cls = stripQuotes(String(clsRaw.trimmed()))
                    let targets = stripQuotes(String(targetsRaw.trimmed()))
                    for part in targets.split(separator: ",", omittingEmptySubsequences: false) {
                        styles.addClass(String(part.trimmed()), cls)
                    }
                }
            case "style":
                styles.style(String(s.dropFirst("style".count)))
            default:
                if s.hasPrefix("<<"), let (stereoSub, afterSub) = s.dropFirst(2).splitOnce(">>") {
                    let stereo = clean(String(stereoSub))
                    let id = String(afterSub.trimmed())
                    guard let idx = ensureClass(id) else { return false }
                    d.classes[idx].stereo = stereo
                    return true
                }
                if tryRelation(s) {
                    return true
                }
                if let (lhs, member) = s.splitOnce(":") {
                    guard let id = styles.stripInline(String(lhs)),
                          let idx = ensureClass(id)
                    else { return false }
                    addMember(idx, String(member.trimmed()))
                    return !over
                }
                return false
            }
            return true
        }

        mutating func classDecl(_ rest: String) -> Bool {
            let opens = rest.hasSuffix("{")
            let core0 = opens ? String(rest.dropLast().trimmed()) : rest
            let core1: String
            let inlineStereo: String?
            if let (beforeStereo, afterOpen) = core0.splitOnce("<<") {
                guard let (stRaw, _) = afterOpen.splitOnce(">>") else { return false }
                core1 = String(beforeStereo.trimmed())
                inlineStereo = clean(String(stRaw))
            } else {
                core1 = core0
                inlineStereo = nil
            }
            guard let core = styles.stripInline(core1) else { return false }
            let id: String
            let label: String?
            if let openB = core.firstIndex(of: "["), core.hasSuffix("]") {
                id = String(core[..<openB].trimmed())
                let innerStart = core.index(after: openB)
                let innerEnd = core.index(before: core.endIndex)
                label = cleanQuoted(String(core[innerStart..<innerEnd]))
            } else if let (idSub, aliasSub) = core.splitOnce(" as ") {
                id = String(idSub.trimmed())
                label = cleanQuoted(String(aliasSub))
            } else {
                id = core
                label = nil
            }
            // `class A,B` declares multiple empty classes on one line.
            if !opens && label == nil && id.contains(",") {
                for rawPart in id.split(separator: ",", omittingEmptySubsequences: false) {
                    let part = String(rawPart.trimmed())
                    guard !part.isEmpty else { continue }
                    guard let idx = ensureClass(part) else { return false }
                    if let st = inlineStereo {
                        d.classes[idx].stereo = st
                    }
                }
                return true
            }
            guard let idx = ensureClass(id) else { return false }
            if let l = label {
                d.classes[idx].label = l
            }
            if let st = inlineStereo {
                d.classes[idx].stereo = st
            }
            if opens {
                activeClass = idx
            }
            return true
        }

        mutating func addMember(_ idx: Int, _ raw: String) {
            let t = String(raw.trimmed())
            if t.isEmpty {
                return
            }
            if let a = t.stripPrefix("<<"), let st = a.stripSuffix(">>") {
                d.classes[idx].stereo = clean(String(st))
                return
            }
            members += 1
            if members > MAX_ITEMS * 4 {
                over = true
            }
            let cleaned = clean(tildeGenerics(t))
            if cleaned.contains("(") && cleaned.contains(")") {
                d.classes[idx].methods.append(cleaned)
            } else {
                d.classes[idx].fields.append(cleaned)
            }
        }

        mutating func tryRelation(_ s: String) -> Bool {
            let lhsRel: String
            let labelPart: String?
            if let at = findColonOutsideQuotes(s) {
                lhsRel = String(s[..<at])
                labelPart = cleanQuoted(String(s[s.index(after: at)...]))
            } else {
                lhsRel = s
                labelPart = nil
            }
            guard let (pos, afterRel, (_, startH, endH, line)) = findRel(lhsRel) else {
                return false
            }
            guard let (rawLeftId, leftCard) = parseSide(String(lhsRel[..<pos].trimmed()), true),
                  let (rawRightId, rightCard) = parseSide(String(lhsRel[afterRel...].trimmed()), false),
                  let leftId = styles.stripInline(rawLeftId),
                  let rightId = styles.stripInline(rawRightId),
                  let from0 = ensureClass(leftId),
                  let to0 = ensureClass(rightId),
                  budget()
            else { return false }
            var parts: [String] = []
            if let lc = leftCard, !lc.isEmpty { parts.append(lc) }
            if let lbl = labelPart, !lbl.isEmpty { parts.append(lbl) }
            if let rc = rightCard, !rc.isEmpty { parts.append(rc) }
            let label: String? = parts.isEmpty ? nil : parts.joined(separator: " · ")
            // Inheritance `<|--` puts the base class at the top and the derived class below it.
            let (from, to, start, end): (Int, Int, Head, Head)
            if startH == .openTriangle && endH == .none {
                (from, to, start, end) = (from0, to0, startH, endH)
            } else if endH == .openTriangle && startH == .none {
                (from, to, start, end) = (to0, from0, .openTriangle, .none)
            } else {
                (from, to, start, end) = (from0, to0, startH, endH)
            }
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

        mutating func ensureClass(_ raw: String) -> Int? {
            let idRaw: String
            let generic: String?
            if let at = raw.firstIndex(of: "~"), raw.hasSuffix("~"), at > raw.startIndex {
                idRaw = String(raw[..<at])
                let gStart = raw.index(after: at)
                let gEnd = raw.index(before: raw.endIndex)
                generic = gStart <= gEnd ? String(raw[gStart..<gEnd]) : ""
            } else {
                idRaw = raw
                generic = nil
            }
            var idSub = idRaw.trimmed()
            while idSub.first == "`" { idSub = idSub.dropFirst() }
            while idSub.last == "`" { idSub = idSub.dropLast() }
            let id = String(idSub)
            guard validClassId(id) else { return nil }
            let ns = activeNs
            if let idx = ids[id] {
                if d.classes[idx].namespace == nil {
                    d.classes[idx].namespace = ns
                }
                if let g = generic {
                    d.classes[idx].label = "\(id)<\(g)>"
                }
                return idx
            }
            guard budget() else { return nil }
            let label = generic.map { "\(id)<\($0)>" } ?? id
            d.classes.append(
                ClassNode(
                    id: id,
                    label: label,
                    stereo: nil,
                    fields: [],
                    methods: [],
                    namespace: ns,
                    style: NodeStyle()
                )
            )
            let idx = d.classes.count - 1
            ids[id] = idx
            return idx
        }
    }

    private static func stripQuotes(_ s: String) -> String {
        var sub = s[...]
        while sub.first == "\"" { sub = sub.dropFirst() }
        while sub.last == "\"" { sub = sub.dropLast() }
        return String(sub)
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

    private static func validClassId(_ s: String) -> Bool {
        !s.isEmpty && s.unicodeScalars.allSatisfy { sc in
            isAlphanumericScalar(sc) || sc == "_" || sc == "-" || sc == "."
        }
    }

    private static func tildeGenerics(_ s: String) -> String {
        var out = ""
        out.unicodeScalars.reserveCapacity(s.unicodeScalars.count)
        var open = false
        for sc in s.unicodeScalars {
            if sc == "~" {
                out.unicodeScalars.append(open ? ">" : "<")
                open.toggle()
            } else {
                out.unicodeScalars.append(sc)
            }
        }
        return out
    }

    private static func findColonOutsideQuotes(_ s: String) -> String.Index? {
        var quoted = false
        let scalars = s.unicodeScalars
        var i = scalars.startIndex
        while i < scalars.endIndex {
            let sc = scalars[i]
            let next = scalars.index(after: i)
            if sc == "\"" {
                quoted.toggle()
            } else if sc == ":" && !quoted {
                let nextIsColon = next < scalars.endIndex && scalars[next] == ":"
                let prevIsColon = i > scalars.startIndex && scalars[scalars.index(before: i)] == ":"
                if !nextIsColon && !prevIsColon {
                    return i
                }
            }
            i = next
        }
        return nil
    }

    private static func findRel(_ s: String) -> (String.Index, String.Index, (String, Head, Head, Line))? {
        var quoted = false
        let scalars = s.unicodeScalars
        var i = scalars.startIndex
        while i < scalars.endIndex {
            let sc = scalars[i]
            let next = scalars.index(after: i)
            if sc == "\"" {
                quoted.toggle()
                i = next
                continue
            }
            if quoted {
                i = next
                continue
            }
            let rem = s[i...]
            if let rel = RELS.first(where: { rem.hasPrefix($0.0) }) {
                let afterRel = scalars.index(i, offsetBy: rel.0.unicodeScalars.count)
                if rel.0 == "--" {
                    let prevAlnum = i > scalars.startIndex && isAlphanumericScalar(scalars[scalars.index(before: i)])
                    let nextAlnum = afterRel < scalars.endIndex && isAlphanumericScalar(scalars[afterRel])
                    if prevAlnum && nextAlnum {
                        i = next
                        continue
                    }
                }
                return (i, afterRel, rel)
            }
            i = next
        }
        return nil
    }

    private static func parseSide(_ raw: String, _ left: Bool) -> (String, String?)? {
        let s = String(raw.trimmed())
        if s.isEmpty {
            return nil
        }
        if left && s.hasSuffix("\"") {
            let withoutEnd = s.dropLast()
            guard let q = withoutEnd.lastIndex(of: "\"") else { return nil }
            let card = clean(String(withoutEnd[withoutEnd.index(after: q)...]))
            return (String(withoutEnd[..<q].trimmed()), card)
        }
        if !left, let rest = s.stripPrefix("\"") {
            guard let q = rest.firstIndex(of: "\"") else { return nil }
            let card = clean(String(rest[..<q]))
            let afterQ = rest.index(after: q)
            return (String(rest[afterQ...].trimmed()), card)
        }
        return (s, nil)
    }

    private static let SPACING = Spacing(node: 38.0, rank: 48.0, cluster: 16.0)

    static func draw(_ d: ClassDiagram, _ paint: DiagramStyle, _ hover: (Hover, Color)?) -> Scene? {
        let nodes: [DrawNode] = d.classes.map { c in
            classBox(c.stereo, c.label, c.fields, c.methods, c.namespace, c.style, paint)
        }
        let clusters: [ClusterSpec] = d.namespaces.map { n in
            ClusterSpec(title: n.title, parent: nil)
        }
        return drawLayered(d.dir, nodes, d.edges, clusters, SPACING, paint, hover)
    }
}
