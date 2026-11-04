// Ported from: crates/rune-mermaid/src/requirement.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Requirement diagrams (`requirementDiagram`), laid out on `layered_draw`: requirements
//! and elements as boxes of their fields, joined by `contains`, `satisfies` and the other
//! relationships.

import Rune

enum requirement {
    struct Req {
        var name: String
        /// "Requirement", "Functional Requirement", "Element", …; empty for a name only ever related.
        var kind: String
        /// `Key: value` rows.
        var fields: [String]
        var style: NodeStyle
    }

    struct Requirements {
        var dir: Dir
        var nodes: [Req]
        var edges: [Edge]
    }

    private static let KINDS: [(String, String)] = [
        ("requirement", "Requirement"),
        ("functionalRequirement", "Functional Requirement"),
        ("interfaceRequirement", "Interface Requirement"),
        ("performanceRequirement", "Performance Requirement"),
        ("physicalRequirement", "Physical Requirement"),
        ("designConstraint", "Design Constraint"),
        ("element", "Element"),
    ]

    private static let RELATIONS: [String] = [
        "contains", "copies", "derives", "satisfies", "verifies", "refines", "traces",
    ]

    static func parse(_ body: [String]) -> Requirements? {
        var d = Requirements(dir: .down, nodes: [], edges: [])
        var ids: [String: Int] = [:]
        var styles = StyleSheet()
        var open: Int? = nil
        for rawL in body {
            if let i = open {
                let l: String
                let closes: Bool
                if let sub = rawL.stripSuffix("}") {
                    l = String(sub.trimmed())
                    closes = true
                } else {
                    l = rawL
                    closes = false
                }
                if let (k, vRaw) = l.splitOnce(":") {
                    let v = cleanQuoted(String(vRaw))
                    let row: String?
                    switch k.trimmed().asciiLower() {
                    case "id": row = "ID: \(v)"
                    case "text": row = "Text: \(v)"
                    case "risk": row = "Risk: \(titleCase(v))"
                    case "verifymethod": row = "Verification: \(titleCase(v))"
                    case "type": row = "Type: \(v)"
                    case "docref": row = "Doc Ref: \(v)"
                    default: row = nil
                    }
                    if let r = row {
                        d.nodes[i].fields.append(r)
                    }
                }
                if closes {
                    open = nil
                }
                continue
            }
            if let rest = word(rawL, "direction") {
                d.dir = Dir.parse(rest) ?? d.dir
            } else if let rest = word(rawL, "classDef") {
                styles.classDef(rest)
            } else if let rest = word(rawL, "class") {
                if let (names, cls) = rest.splitOnceWhere({ isUnicodeWS($0) }) {
                    let cTrim = String(cls.trimmed())
                    for n in names.split(separator: ",", omittingEmptySubsequences: false) {
                        styles.addClass(cleanQuoted(String(n)), cTrim)
                    }
                }
            } else if let rest = word(rawL, "style") {
                if let (names, props) = rest.splitOnceWhere({ isUnicodeWS($0) }) {
                    let st = parseStyleProps(String(props))
                    for n in names.split(separator: ",", omittingEmptySubsequences: false) {
                        styles.addStyle(cleanQuoted(String(n)), st)
                    }
                }
            } else if let (kindName, rest) = matchKind(rawL) {
                guard let nameSub = rest.stripSuffix("{") else { continue }
                let name = String(nameSub.trimmed())
                guard !name.isEmpty else { continue }
                let i = ensureNode(&d, &ids, &styles, name)
                d.nodes[i].kind = kindName
                open = i
            } else if let (from, rel, to) = relation(rawL) {
                let a = ensureNode(&d, &ids, &styles, from)
                let b = ensureNode(&d, &ids, &styles, to)
                let isContains = (rel == "contains")
                d.edges.append(
                    Edge(
                        from: a,
                        to: b,
                        label: "«\(rel)»",
                        line: isContains ? .solid : .dotted,
                        start: isContains ? .contains : .none,
                        end: isContains ? .none : .arrow,
                        minlen: 1,
                        style: EdgeStyle(),
                        onCluster: [nil, nil]
                    )
                )
            }
            if d.nodes.count + d.edges.count > MAX_ITEMS {
                return nil
            }
        }
        for (name, i) in ids {
            d.nodes[i].style = styles.get(name)
        }
        return d.nodes.isEmpty ? nil : d
    }

    private static func matchKind(_ l: String) -> (String, String)? {
        for (w, k) in KINDS {
            if let r = word(l, w) {
                return (k, r)
            }
        }
        return nil
    }

    /// The node `name` (`"quoted"`, maybe with a `:::class`) names, added if it's new.
    private static func ensureNode(
        _ d: inout Requirements,
        _ ids: inout [String: Int],
        _ styles: inout StyleSheet,
        _ rawName: String
    ) -> Int {
        let namePart: String
        let clsPart: String?
        if let (n, c) = rawName.splitOnce(":::") {
            namePart = String(n)
            clsPart = String(c.trimmed())
        } else {
            namePart = rawName
            clsPart = nil
        }
        let name = cleanQuoted(namePart)
        let i: Int
        if let existing = ids[name] {
            i = existing
        } else {
            d.nodes.append(Req(name: name, kind: "", fields: [], style: NodeStyle()))
            let newIdx = d.nodes.count - 1
            ids[name] = newIdx
            i = newIdx
        }
        if let c = clsPart {
            styles.addClass(d.nodes[i].name, c)
        }
        return i
    }

    /// `a - satisfies -> b`, or `b <- satisfies - a`: the source, the relationship and the target.
    private static func relation(_ l: String) -> (String, String, String)? {
        let fromSub: Substring
        let midSub: Substring
        let toSub: Substring
        if let (left, to) = l.splitOnce("->") {
            guard let (from, mid) = left.rsplitOnce("-") else { return nil }
            fromSub = from
            midSub = mid
            toSub = to
        } else if let (to, right) = l.splitOnce("<-") {
            guard let (mid, from) = right.splitOnce("-") else { return nil }
            fromSub = from
            midSub = mid
            toSub = to
        } else {
            return nil
        }
        let midLower = midSub.trimmed().asciiLower()
        guard let rel = RELATIONS.first(where: { $0 == midLower }) else { return nil }
        let from = String(fromSub.trimmed())
        let to = String(toSub.trimmed())
        guard !from.isEmpty && !to.isEmpty else { return nil }
        return (from, rel, to)
    }

    private static func titleCase(_ s: String) -> String {
        guard let first = s.first else { return "" }
        return first.uppercased() + s.dropFirst().lowercased()
    }

    private static let SPACING = Spacing(node: 40.0, rank: 56.0, cluster: 16.0)

    static func draw(_ d: Requirements, _ paint: DiagramStyle, _ hover: (Hover, Color)?) -> Scene? {
        let nodes: [DrawNode] = d.nodes.map { r in
            classBox(r.kind.isEmpty ? nil : r.kind, r.name, r.fields, [], nil, r.style, paint)
        }
        return drawLayered(d.dir, nodes, d.edges, [], SPACING, paint, hover)
    }
}
