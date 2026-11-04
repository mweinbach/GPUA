// Ported from: crates/rune-mermaid/src/quadrant.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Quadrant charts (`quadrantChart`): `x-axis`/`y-axis` ends, four named quadrants, and points
//! at `[x, y]` in 0 to 1, with `radius`, `color`, `stroke-color` and `stroke-width` set inline
//! or through `classDef` and `:::class`.

import Rune

enum quadrant {
    struct Look: Equatable, Sendable {
        var radius: Float? = nil
        var color: Color? = nil
        var stroke: Color? = nil
        var strokeWidth: Float? = nil

        func or(_ base: Look) -> Look {
            Look(
                radius: radius ?? base.radius,
                color: color ?? base.color,
                stroke: stroke ?? base.stroke,
                strokeWidth: strokeWidth ?? base.strokeWidth
            )
        }
    }

    struct Point: Equatable, Sendable {
        var name: String
        var at: [Float]
        var look: Look
    }

    struct Quadrant {
        var title: String? = nil
        /// Low and high ends; an empty high end means one label for the whole axis.
        var x: [String] = ["", ""]
        var y: [String] = ["", ""]
        /// Quadrants 1 (top right) to 4 (bottom right), anticlockwise.
        var names: [String] = ["", "", "", ""]
        var points: [Point] = []
    }

    static func parse(_ body: [String]) -> Quadrant? {
        var q = Quadrant()
        var classes: [String: Look] = [:]
        var pending: [(String, [Float], Look, String?)] = []
        var any = false
        func axis(_ rest: String) -> [String] {
            if let (a, b) = rest.splitOnce("-->") {
                return [clean(String(a)), clean(String(b))]
            }
            return [clean(rest), ""]
        }
        for l in body {
            if let rest = word(l, "title") {
                let t = clean(rest)
                q.title = t.isEmpty ? nil : t
            } else if let rest = word(l, "x-axis") {
                q.x = axis(rest)
                any = true
            } else if let rest = word(l, "y-axis") {
                q.y = axis(rest)
                any = true
            } else if let afterQ = l.stripPrefix("quadrant-"),
                      let (nSub, restSub) = afterQ.splitOnceWhere(isUnicodeWS)
            {
                if let n = Int(nSub), (1...4).contains(n) {
                    q.names[n - 1] = clean(String(restSub))
                    any = true
                }
            } else if let rest = word(l, "classDef") {
                let cName: String
                let props: String
                if let (n, p) = rest.splitOnceWhere(isUnicodeWS) {
                    cName = String(n)
                    props = String(p)
                } else {
                    cName = rest
                    props = ""
                }
                classes[cName] = look(props)
            } else if let p = point(l) {
                if pending.count >= MAX_ITEMS {
                    return nil
                }
                pending.append(p)
            }
        }
        q.points = pending.map { pName, at, pLook, cls in
            let base = cls.flatMap { classes[$0] } ?? Look()
            return Point(name: pName, at: at, look: pLook.or(base))
        }
        return (any || !q.points.isEmpty) ? q : nil
    }

    /// `Name[:::class]: [x, y] props`.
    private static func point(_ l: String) -> (String, [Float], Look, String?)? {
        guard let open = l.firstIndex(of: "["),
              let close = l[open...].firstIndex(of: "]"),
              let headSub = l[..<open].trimmed().stripSuffix(":")
        else { return nil }
        let head = String(headSub)
        let rawName: Substring
        let cls: String?
        if let (n, c) = head.splitOnce(":::") {
            rawName = n
            cls = String(c.trimmed())
        } else {
            rawName = head[...]
            cls = nil
        }
        let coordsStr = l[l.index(after: open)..<close]
        guard let (xSub, ySub) = coordsStr.splitOnce(","),
              let x = Float(xSub.trimmed()),
              let y = Float(ySub.trimmed()),
              x.isFinite && y.isFinite
        else { return nil }
        var unquotedName = rawName.trimmed()
        while unquotedName.first == "\"" { unquotedName = unquotedName.dropFirst() }
        while unquotedName.last == "\"" { unquotedName = unquotedName.dropLast() }
        let propsStr = String(l[l.index(after: close)...])
        return (clean(String(unquotedName)), [clampF(x, 0.0, 1.0), clampF(y, 0.0, 1.0)], look(propsStr), cls)
    }

    private static func look(_ props: String) -> Look {
        var out = Look()
        for part in props.split(separator: ",", omittingEmptySubsequences: false) {
            guard let (k, vSub) = part.splitOnce(":") else { continue }
            let v = String(vSub.trimmed())
            func px() -> Float? {
                let raw = v.trimEndMatches("px").trimmed()
                guard let f = Float(raw), f.isFinite else { return nil }
                return f
            }
            switch k.trimmed() {
            case "radius":
                out.radius = px().map { clampF($0, 1.0, 30.0) }
            case "color":
                out.color = parseColorSpec(v)
            case "stroke-color":
                out.stroke = parseColorSpec(v)
            case "stroke-width":
                out.strokeWidth = px().map { clampF($0, 0.0, 8.0) }
            default:
                break
            }
        }
        return out
    }

    private static let HUE: Float = 255.0

    static func draw(_ q: Quadrant, _ paint: DiagramStyle) -> Scene? {
        let note = chart.small(paint)
        let head = chart.bold(paint.font)
        let ys = q.y.map { measureWrap($0, note, 96.0) }
        let yw = ys.map { $0.size[0] }.reduce(0.0, max)
        let x0: Float = yw > 0.0 ? (yw + 12.0) : 0.0
        let side = clampF(room(paint) - x0, 220.0, 440.0)
        let half = side / 2.0
        let x1 = x0 + side
        let y1 = side

        var c = Canvas()
        // 1 top right, 2 top left, 3 bottom left, 4 bottom right.
        let origins: [[Float]] = [[x0 + half, 0.0], [x0, 0.0], [x0, half], [x0 + half, half]]
        let tints: [Float] = [0.95, 0.7, 0.45, 0.7]
        for (o, a) in zip(origins, tints) {
            let fill = overColor(chart.soft(paint, HUE).alpha(a), paint.surface)
            c.fill([o, [o[0] + half, o[1]], [o[0] + half, o[1] + half], [o[0], o[1] + half]], fill)
        }
        c.stroke([[x0 + half, 0.0], [x0 + half, y1]], false, 2.0, paint.surface)
        c.stroke([[x0, half], [x1, half]], false, 2.0, paint.surface)
        for (o, qName) in zip(origins, q.names) {
            let m = measureWrap(qName, head, half - 16.0)
            let y = q.points.isEmpty ? (o[1] + half / 2.0) : (o[1] + 10.0 + m.size[1] / 2.0)
            c.label(m, [o[0] + half / 2.0, y], head, paint.text, .center)
        }
        let xs = q.x.map { measureWrap($0, note, half - 8.0) }
        let below = y1 + 8.0
        if xs[1].text.isEmpty {
            c.labelAt(xs[0], [x0 + half - xs[0].size[0] / 2.0, below], note, paint.muted, .center)
        } else {
            for (i, m) in xs.enumerated() {
                c.labelAt(m, [x0 + half * (Float(i) + 0.5) - m.size[0] / 2.0, below], note, paint.muted, .center)
            }
        }
        if ys[1].text.isEmpty {
            c.labelAt(ys[0], [x0 - 12.0 - ys[0].size[0], half - ys[0].size[1] / 2.0], note, paint.muted, .end)
        } else {
            // Low at the bottom, high at the top.
            for (i, m) in ys.enumerated() {
                let mid = i == 0 ? (half * 1.5) : (half * 0.5)
                c.labelAt(m, [x0 - 12.0 - m.size[0], mid - m.size[1] / 2.0], note, paint.muted, .end)
            }
        }
        for p in q.points {
            let at = [x0 + p.at[0] * side, y1 - p.at[1] * side]
            let r = p.look.radius ?? 5.0
            let fill = p.look.color ?? chart.strong(paint, HUE)
            let width = p.look.strokeWidth ?? (p.look.stroke != nil ? 2.0 : 0.0)
            c.fill(ellipse(at, r, r), fill)
            if width > 0.0 {
                c.stroke(ellipse(at, r, r), true, width, p.look.stroke ?? fill)
            }
            let m = measure(p.name, note)
            c.labelAt(m, [at[0] - m.size[0] / 2.0, at[1] + r + 3.0], note, paint.text, .center)
        }
        return c.finishFit(paint)
    }
}
