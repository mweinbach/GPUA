// Ported from: crates/rune-mermaid/src/xychart.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! XY charts (`xychart-beta`, `xychart`): bars and lines over a category or numeric x-axis and a
//! value y-axis, upright or (`horizontal`) on their side.

import Rune

enum xychart {
    enum Kind: Equatable, Sendable {
        case bar
        case line
    }

    struct Series: Equatable, Sendable {
        var kind: Kind
        var name: String
        var values: [Float]
    }

    struct XyChart {
        var title: String? = nil
        var horizontal: Bool = false
        var xTitle: String = ""
        /// Category names; empty when the x-axis is a range or not given.
        var bands: [String] = []
        var xRange: [Float]? = nil
        var yTitle: String = ""
        var yRange: [Float]? = nil
        var series: [Series] = []
    }

    static func parse(_ header: String, _ body: [String]) -> XyChart? {
        var x = XyChart(horizontal: header.trimmed() == "horizontal")
        var items = 0
        for l in body {
            if let rest = word(l, "title") {
                let t = cleanQuoted(rest)
                x.title = t.isEmpty ? nil : t
            } else if let rest = word(l, "x-axis") {
                let (title, bands, range) = axis(rest)
                items += bands.count
                x.xTitle = title
                x.bands = bands
                x.xRange = range
            } else if let rest = word(l, "y-axis") {
                let (title, _, range) = axis(rest)
                x.yTitle = title
                x.yRange = range
            } else if let (k, rest) = word(l, "bar").map({ (Kind.bar, $0) }) ?? word(l, "line").map({ (Kind.line, $0) }) {
                guard let open = rest.firstIndex(of: "[") else { continue }
                let itemsRaw = list(String(rest[open...]))
                var values: [Float] = []
                var valid = true
                for vStr in itemsRaw {
                    if let f = Float(vStr), f.isFinite {
                        values.append(f)
                    } else {
                        valid = false
                        break
                    }
                }
                guard valid && !values.isEmpty else { continue }
                items += values.count
                x.series.append(Series(kind: k, name: cleanQuoted(String(rest[..<open])), values: values))
            }
            if items > MAX_ITEMS {
                return nil
            }
        }
        return x.series.isEmpty ? nil : x
    }

    /// `"Title" [a, b]`, `Title 0 --> 10`, or a title alone.
    private static func axis(_ rest: String) -> (String, [String], [Float]?) {
        if let open = rest.firstIndex(of: "[") {
            let bands = list(String(rest[open...])).map { cleanQuoted($0) }
            return (cleanQuoted(String(rest[..<open])), bands, nil)
        }
        if let (aSub, bSub) = rest.splitOnce("-->") {
            let a = String(aSub.trimmed())
            let title: String
            let loStr: String
            if let lastWS = a.lastIndex(where: isUnicodeWS) {
                title = String(a[..<lastWS])
                loStr = String(a[a.index(after: lastWS)...])
            } else {
                title = ""
                loStr = a
            }
            if let lo = Float(loStr),
               let hi = Float(bSub.trimmed()),
               lo.isFinite && hi.isFinite && lo != hi
            {
                return (cleanQuoted(title), [], [min(lo, hi), max(lo, hi)])
            }
        }
        return (cleanQuoted(rest), [], nil)
    }

    /// The items of `[a, "b, c", d]`, trimmed.
    private static func list(_ s: String) -> [String] {
        guard let afterOpen = s.trimmed().stripPrefix("["),
              let end = afterOpen.lastIndex(of: "]")
        else { return [] }
        let inner = afterOpen[..<end]
        if inner.trimmed().isEmpty {
            return []
        }
        var out: [String] = []
        var cur = ""
        var quoted = false
        for ch in inner {
            if ch == "\"" {
                quoted.toggle()
                cur.append(ch)
            } else if ch == "," && !quoted {
                out.append(cur)
                cur = ""
            } else {
                cur.append(ch)
            }
        }
        out.append(cur)
        return out.map { String($0.trimmed()) }
    }

    /// A round step near `raw`: 1, 2 or 5 times a power of ten.
    private static func nice(_ raw: Float) -> Float {
        let p = mPow(10.0, Float(mLog10D(Double(max(raw, 1e-9))).rounded(.down)))
        let m = raw / p
        let mult: Float
        if m <= 1.0 {
            mult = 1.0
        } else if m <= 2.0 {
            mult = 2.0
        } else if m <= 5.0 {
            mult = 5.0
        } else {
            mult = 10.0
        }
        return p * mult
    }

    /// The value axis's ends and ticks: `range` as given, or the data's (taking in zero) rounded out.
    static func scale(_ range: [Float]?, _ series: [Series]) -> ([Float], [Float]) {
        let bounds: [Float]
        if let range {
            bounds = range
        } else {
            var lo: Float = 0.0
            var hi: Float = 0.0
            for s in series {
                for v in s.values {
                    lo = min(lo, v)
                    hi = max(hi, v)
                }
            }
            if hi - lo < 1e-9 {
                hi = lo + 1.0
            }
            let step = nice((hi - lo) / 5.0)
            bounds = [(lo / step).rounded(.down) * step, (hi / step).rounded(.up) * step]
        }
        let lo = bounds[0]
        let hi = bounds[1]
        let step = nice((hi - lo) / 5.0)
        let first = (lo / step).rounded(.up)
        var ticks: [Float] = []
        for k in 0..<12 {
            let t = (first + Float(k)) * step
            if t > hi + step * 1e-3 {
                break
            }
            ticks.append(abs(t) < step * 1e-3 ? 0.0 : t)
        }
        return ([lo, hi], ticks)
    }

    private static let PLOT_H: Float = 240.0

    static func draw(_ x: XyChart, _ paint: DiagramStyle) -> Scene? {
        guard let n = x.series.map({ $0.values.count }).max(), n > 0 else { return nil }
        let note = chart.small(paint)
        let (bounds, ticks) = scale(x.yRange, x.series)
        let lo = bounds[0]
        let hi = bounds[1]
        let names: [String]
        if !x.bands.isEmpty {
            names = (0..<n).map { i in i < x.bands.count ? x.bands[i] : "" }
        } else if let r = x.xRange {
            let a = r[0]
            let b = r[1]
            let denom = Float(max(n, 2) - 1)
            names = (0..<n).map { i in pie.number(Double(a + (b - a) * Float(i) / denom)) }
        } else {
            names = Array(repeating: "", count: n)
        }
        var c = Canvas()

        var top: Float = 0.0
        if x.series.contains(where: { !$0.name.isEmpty }) {
            var at: Float = 0.0
            var h: Float = 0.0
            for (i, s) in x.series.enumerated() {
                let m = measure(s.name, note)
                c.fill(ellipse([at + 5.0, m.size[1] / 2.0], 5.0, 5.0), chart.solid(paint, chart.hue(i)))
                c.labelAt(m, [at + 14.0, 0.0], note, paint.muted, .start)
                at += 14.0 + m.size[0] + 16.0
                h = max(h, m.size[1])
            }
            top = h + 12.0
        }
        let valueTitle = measure(x.yTitle, note)
        let bandTitle = measure(x.xTitle, note)
        let values: [(Float, Measured)] = ticks.map { t in (t, measure(pie.number(Double(t)), note)) }
        func v01(_ v: Float) -> Float {
            clampF((v - lo) / (hi - lo), 0.0, 1.0)
        }
        let base = v01(0.0)

        // Plot bounds and where a value lands along a band, as `point(u px along the bands, v 0..1)`.
        let x0: Float
        let y0: Float
        let x1: Float
        let y1: Float
        let labels: [Measured]
        if x.horizontal {
            labels = names.map { measureWrap($0, note, 120.0) }
            let lw = labels.map { $0.size[0] }.reduce(0.0, max)
            let bandH = max(labels.map { $0.size[1] }.reduce(0.0, max) + 10.0, 26.0)
            if !bandTitle.text.isEmpty {
                c.labelAt(bandTitle, [0.0, top], note, paint.muted, .start)
                top += bandTitle.size[1] + 6.0
            }
            x0 = lw > 0.0 ? (lw + 10.0) : 0.0
            y0 = top
            x1 = max(room(paint), x0 + 200.0)
            y1 = y0 + bandH * Float(n)
        } else {
            let vw = values.map { $0.1.size[0] }.reduce(0.0, max)
            if !valueTitle.text.isEmpty {
                c.labelAt(valueTitle, [0.0, top], note, paint.muted, .start)
                top += valueTitle.size[1] + 8.0
            }
            x0 = vw + 10.0
            y0 = top
            x1 = max(room(paint), x0 + 200.0)
            y1 = top + PLOT_H
            let bandW = (x1 - x0) / Float(n)
            labels = names.map { measureWrap($0, note, max(bandW - 4.0, 24.0)) }
        }
        let length = x.horizontal ? (y1 - y0) : (x1 - x0)
        let band = length / Float(n)
        func point(_ u: Float, _ v: Float) -> [Float] {
            if x.horizontal {
                return [x0 + v * (x1 - x0), y0 + u]
            }
            return [x0 + u, y1 - v * (y1 - y0)]
        }

        // The value axis: grid lines and tick labels.
        if x.horizontal {
            let tickPoints: [(Float, Measured)] = values.map { t, m in (point(0.0, v01(t))[0], m) }
            chart.axisX(&c, tickPoints, [x0, x1], [y0, y1], note, paint)
            if !valueTitle.text.isEmpty {
                let h = values.map { $0.1.size[1] }.reduce(0.0, max)
                c.label(valueTitle, [(x0 + x1) / 2.0, y1 + h + 14.0 + valueTitle.size[1] / 2.0], note, paint.muted, .center)
            }
        } else {
            for (t, m) in values {
                let y = point(0.0, v01(t))[1]
                c.stroke([[x0, y], [x1, y]], false, 1.0, paint.text.alpha(0.08))
                c.labelAt(m, [x0 - 8.0 - m.size[0], y - m.size[1] / 2.0], note, paint.muted, .end)
            }
        }
        c.stroke([point(0.0, base), point(length, base)], false, 1.0, paint.surfaceBorder)

        // Band labels.
        for (i, m) in labels.enumerated() {
            let mid = (Float(i) + 0.5) * band
            if x.horizontal {
                c.labelAt(m, [x0 - 10.0 - m.size[0], y0 + mid - m.size[1] / 2.0], note, paint.muted, .end)
            } else {
                c.labelAt(m, [x0 + mid - m.size[0] / 2.0, y1 + 6.0], note, paint.muted, .center)
            }
        }
        if !x.horizontal && !bandTitle.text.isEmpty {
            let h = labels.map { $0.size[1] }.reduce(0.0, max)
            c.label(bandTitle, [(x0 + x1) / 2.0, y1 + h + 14.0 + bandTitle.size[1] / 2.0], note, paint.muted, .center)
        }

        // Bars side by side within a band, then lines over them.
        let bars = (0..<x.series.count).filter { x.series[$0].kind == .bar }
        let group = band * 0.72
        let each = group / Float(max(bars.count, 1))
        for (k, i) in bars.enumerated() {
            let fill = chart.solid(paint, chart.hue(i))
            for (b, v) in x.series[i].values.enumerated() {
                let u0 = Float(b) * band + (band - group) / 2.0 + Float(k) * each + each * 0.06
                let u1 = u0 + each * 0.88
                let p = point(u0, base)
                let q = point(u1, v01(v))
                let ax = min(p[0], q[0])
                let ay = min(p[1], q[1])
                let bx = max(p[0], q[0])
                let by = max(p[1], q[1])
                c.fill([[ax, ay], [bx, ay], [bx, by], [ax, by]], fill)
            }
        }
        for (i, s) in x.series.enumerated() where s.kind == .line {
            let color = chart.solid(paint, chart.hue(i))
            let pts: [[Float]] = s.values.enumerated().map { b, v in point((Float(b) + 0.5) * band, v01(v)) }
            c.stroke(pts, false, 2.0, color)
            for p in pts {
                c.shape(ellipse(p, 3.0, 3.0), color, paint.surface, 1.0)
            }
        }
        return c.finishFit(paint)
    }
}
