// Ported from: crates/rune-mermaid/src/c4.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! C4 diagrams (`C4Context`, `C4Container`, `C4Component`, `C4Dynamic`, `C4Deployment`), laid
//! out on `layered_draw`: people, systems, containers and components as cards (stores as
//! cylinders, queues on their side, external ones in grey), boundaries and deployment nodes as
//! nested frames, and relationships with their technology.

import Rune

enum c4 {
    enum Base: Sendable, Equatable {
        case person
        case system
        case container
        case component
    }

    enum Store: Sendable, Equatable {
        case plain
        case db
        case queue
    }

    struct Element {
        var base: Base
        var store: Store
        var external: Bool
        var label: String
        var techn: String
        var descr: String
        var boundary: Int?
    }

    struct Boundary {
        var title: String
        var parent: Int?
    }

    struct C4 {
        var title: String? = nil
        var elements: [Element] = []
        var boundaries: [Boundary] = []
        var edges: [Edge] = []
    }

    private struct Rel {
        var from: String
        var to: String
        var label: String
        var techn: String
        var both: Bool
        var way: Way
    }

    /// Which way a relationship's arrow points, and so which end the layout puts above.
    private enum Way: Equatable {
        case down
        /// `Rel_U`: toward `to`, which sits above.
        case up
        /// `Rel_Back`: toward `from`.
        case back
    }

    static func parse(_ header: String, _ body: [String]) -> C4? {
        let dynamic = (header == "C4Dynamic")
        var d = C4()
        var ids: [String: Int] = [:]
        var rels: [Rel] = []
        var stack: [Int] = []
        for l in body {
            if l.hasPrefix("}") {
                _ = stack.popLast()
                continue
            }
            if let rest = word(l, "title") {
                let t = cleanQuoted(rest)
                d.title = t.isEmpty ? nil : t
                continue
            }
            guard let open = l.firstIndex(of: "("),
                  let close = l.lastIndex(of: ")"),
                  open < close
            else { continue }
            let name = String(l[..<open].trimmed())
            let inner = String(l[l.index(after: open)..<close])
            let (posArgs, named) = parseArgs(inner)
            func arg(_ i: Int) -> String {
                i < posArgs.count ? posArgs[i] : ""
            }
            if let defaultKind = boundaryKind(name) {
                if stack.count >= MAX_DEPTH {
                    return nil
                }
                let ty: String? = (posArgs.count > 2 && !posArgs[2].isEmpty) ? posArgs[2] : defaultKind
                let label: String
                if posArgs.count > 1 {
                    label = posArgs[1]
                } else if let first = posArgs.first {
                    label = first
                } else {
                    label = ""
                }
                let title = ty.map { "\(label)\n[\($0)]" } ?? label
                d.boundaries.append(Boundary(title: title, parent: stack.last))
                let afterClose = l[l.index(after: close)...].trimmedStart()
                if afterClose.hasPrefix("{") {
                    stack.append(d.boundaries.count - 1)
                }
            } else if let (base, store, external) = elementKind(name) {
                guard let alias = posArgs.first, !alias.isEmpty else { continue }
                let (defaultTechn, defaultDescr) = (base == .container || base == .component)
                    ? (arg(2), arg(3))
                    : ("", arg(2))
                let techn = named["techn"] ?? defaultTechn
                let descr = named["descr"] ?? defaultDescr
                ids[alias] = d.elements.count
                d.elements.append(
                    Element(
                        base: base,
                        store: store,
                        external: external,
                        label: arg(1),
                        techn: techn,
                        descr: descr,
                        boundary: stack.last
                    )
                )
            } else if let (both, way, indexed) = relationKind(name) {
                let a = indexed ? Array(posArgs.dropFirst()) : posArgs
                func getA(_ i: Int) -> String { i < a.count ? a[i] : "" }
                let techn = named["techn"] ?? getA(3)
                rels.append(
                    Rel(
                        from: getA(0),
                        to: getA(1),
                        label: getA(2),
                        techn: techn,
                        both: both,
                        way: way
                    )
                )
            }
            if d.elements.count + d.boundaries.count + rels.count > MAX_ITEMS {
                return nil
            }
        }
        var n = 0
        for r in rels {
            guard let a = ids[r.from], let b = ids[r.to] else { continue }
            n += 1
            var label = dynamic ? "\(n): \(r.label)" : r.label
            if !r.techn.isEmpty {
                label = "\(label)\n[\(r.techn)]"
            }
            let other: Head = r.both ? .arrow : .none
            let (from, to, start, end): (Int, Int, Head, Head)
            switch r.way {
            case .down: (from, to, start, end) = (a, b, other, .arrow)
            case .up: (from, to, start, end) = (b, a, .arrow, other)
            case .back: (from, to, start, end) = (a, b, .arrow, other)
            }
            let optLabel: String? = label.trimmed().isEmpty ? nil : label
            d.edges.append(
                Edge(
                    from: from,
                    to: to,
                    label: optLabel,
                    line: .solid,
                    start: start,
                    end: end,
                    minlen: 1,
                    style: EdgeStyle(),
                    onCluster: [nil, nil]
                )
            )
        }
        return d.elements.isEmpty ? nil : d
    }

    /// Positional arguments, unquoted, and `$name="value"` ones by name.
    private static func parseArgs(_ s: String) -> ([String], [String: String]) {
        var parts: [String] = []
        var cur = ""
        var quoted = false
        for sc in s.unicodeScalars {
            if sc == "\"" {
                quoted.toggle()
                cur.unicodeScalars.append(sc)
            } else if sc == "," && !quoted {
                parts.append(cur)
                cur = ""
            } else {
                cur.unicodeScalars.append(sc)
            }
        }
        parts.append(cur)
        var pos: [String] = []
        var named: [String: String] = [:]
        for rawP in parts {
            let p = String(rawP.trimmed())
            if let afterDollar = p.stripPrefix("$"), let (k, v) = afterDollar.splitOnce("=") {
                named[String(k.trimmed())] = cleanQuoted(String(v))
            } else if !p.hasPrefix("$") {
                pos.append(cleanQuoted(p))
            }
        }
        return (pos, named)
    }

    /// A boundary function, with the type it shows when none is given.
    private static func boundaryKind(_ name: String) -> String?? {
        switch name {
        case "Boundary", "Deployment_Node", "Node", "Node_L", "Node_R": return .some(nil)
        case "Enterprise_Boundary": return .some("Enterprise")
        case "System_Boundary": return .some("System")
        case "Container_Boundary": return .some("Container")
        default: return nil
        }
    }

    /// `Person`, `SystemDb_Ext`, `ContainerQueue`, …
    private static func elementKind(_ rawName: String) -> (Base, Store, Bool)? {
        let name: String
        let external: Bool
        if let n = rawName.stripSuffix("_Ext") {
            name = String(n)
            external = true
        } else {
            name = rawName
            external = false
        }
        let prefixes: [(String, Base)] = [
            ("Person", .person),
            ("System", .system),
            ("Container", .container),
            ("Component", .component),
        ]
        guard let (w, base) = prefixes.first(where: { name.hasPrefix($0.0) }) else {
            return nil
        }
        let rest = String(name.dropFirst(w.count))
        let store: Store
        switch rest {
        case "": store = .plain
        case "Db" where base != .person: store = .db
        case "Queue" where base != .person: store = .queue
        default: return nil
        }
        return (base, store, external)
    }

    /// `Rel`, `BiRel`, `Rel_Back`, `Rel_U`, `RelIndex`, …: whether it points both ways, which way,
    /// and whether an index comes first.
    private static func relationKind(_ name: String) -> (Bool, Way, Bool)? {
        let both: Bool
        let rest: String
        if let r = name.stripPrefix("BiRel") {
            both = true
            rest = String(r)
        } else if let r = name.stripPrefix("Rel") {
            both = false
            rest = String(r)
        } else {
            return nil
        }
        switch rest {
        case "Index": return (both, .down, true)
        case "_Back": return (both, .back, false)
        case "_U", "_Up": return (both, .up, false)
        case "", "_D", "_Down", "_L", "_Left", "_R", "_Right", "_Neighbor": return (both, .down, false)
        default: return nil
        }
    }

    /// `«external_system_db»` and the like.
    static func stereotype(_ e: Element) -> String {
        let baseStr: String
        switch e.base {
        case .person: baseStr = "person"
        case .system: baseStr = "system"
        case .container: baseStr = "container"
        case .component: baseStr = "component"
        }
        let storeStr: String
        switch e.store {
        case .plain: storeStr = ""
        case .db: storeStr = "_db"
        case .queue: storeStr = "_queue"
        }
        let ext = e.external ? "external_" : ""
        return "«\(ext)\(baseStr)\(storeStr)»"
    }

    /// C4's blues, deepest for people; external elements in grey.
    private static func fill(_ e: Element) -> Color {
        let l: Float
        switch (e.base, e.external) {
        case (.person, true): l = 0.46
        case (_, true): l = 0.64
        case (.person, false): l = 0.36
        case (.system, false): l = 0.48
        case (.container, false): l = 0.6
        case (.component, false): l = 0.76
        }
        return e.external ? oklch(l, 0.0, 0.0) : oklch(l, 0.11 - (l - 0.36) * 0.12, 252.0)
    }

    private static let SPACING = Spacing(node: 44.0, rank: 64.0, cluster: 20.0)

    static func draw(_ d: C4, _ paint: DiagramStyle, _ hover: (Hover, Color)?) -> Scene? {
        let note = chart.small(paint)
        var stereoFont = note
        stereoFont.italic = true
        let boldFont = chart.bold(paint.font)
        var technFont = note
        technFont.italic = true
        let nodes: [DrawNode] = d.elements.map { e in
            let techn = e.techn.isEmpty ? "" : "[\(e.techn)]"
            let rawLines: [(String, TextStyle)] = [
                (stereotype(e), stereoFont),
                (e.label, boldFont),
                (techn, technFont),
                (e.descr, note),
            ]
            let lines: [(Measured, TextStyle)] = rawLines
                .filter { !$0.0.isEmpty }
                .map { (measureWrap($0.0, $0.1, 190.0), $0.1) }
            let shape: NodeShape
            switch e.store {
            case .plain: shape = .round
            case .db: shape = .cylinder
            case .queue: shape = .hCylinder
            }
            var maxLineW: Float = 0.0
            for l in lines { maxLineW = max(maxLineW, l.0.size[0]) }
            let w = maxLineW + (shape == .hCylinder ? 52.0 : 32.0)
            let isPerson = (e.base == .person)
            var sumLineH: Float = 0.0
            for l in lines { sumLineH += l.0.size[1] + 3.0 }
            var h = sumLineH + 22.0 + (isPerson ? PERSON : 0.0)
            if shape == .cylinder {
                h += 3.0 * shapeRim(max(w, 150.0))
            }
            let f = fill(e)
            let border = oklch(max(f.toOklab()[0] - 0.1, 0.2), 0.06, 252.0)
            return .card(
                shape: shape,
                lines: lines,
                size: [max(w, 150.0), max(h, 64.0)],
                cluster: e.boundary,
                colors: [f, border, chart.ink(f)],
                person: isPerson
            )
        }
        let clusters: [ClusterSpec] = d.boundaries.map { b in
            ClusterSpec(title: b.title, parent: b.parent)
        }
        return drawLayered(.down, nodes, d.edges, clusters, SPACING, paint, hover)
    }
}
