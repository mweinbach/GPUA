// Ported from: crates/rune-mermaid/src/pie.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Pie charts (`pie`): slices from twelve o'clock clockwise in source order, percentages on the
//! slices wide enough to hold them, and a legend (with values under `showData`).

import Rune

enum pie {
    struct Pie {
        var title: String?
        var showData: Bool
        var slices: [(String, Double)]
    }

    static func parse(_ header: String, _ body: [String]) -> Pie? {
        var p = Pie(title: nil, showData: false, slices: [])
        for line in [header] + body {
            for stmt in statements(line) {
                var s = stmt
                if let rest = s.stripPrefix("showData") {
                    p.showData = true
                    s = String(rest.trimmed())
                }
                if let rest = s.stripPrefix("title"), rest.isEmpty || rest.first.map(isUnicodeWS) == true {
                    let t = cleanQuoted(String(rest))
                    p.title = t.isEmpty ? nil : t
                    continue
                }
                if s.isEmpty || s.hasPrefix("accTitle") || s.hasPrefix("accDescr") {
                    continue
                }
                guard let (label, value) = s.rsplitOnce(":") else { continue }
                guard let v = Double(value.trimmed()), v.isFinite, v > 0.0 else { continue }
                if p.slices.count >= MAX_ITEMS {
                    return nil
                }
                p.slices.append((cleanQuoted(String(label)), v))
            }
        }
        return p.slices.isEmpty ? nil : p
    }

    /// `386`, `12.5`, `0.33`.
    static func number(_ v: Double) -> String {
        if v.isNaN { return "NaN" }
        if !v.isFinite { return v < 0 ? "-inf" : "inf" }
        if v.truncatingRemainder(dividingBy: 1.0) == 0.0 && abs(v) < 1e15 {
            if v == 0.0 {
                return v.sign == .minus ? "-0" : "0"
            }
            return "\(Int64(v))"
        }
        if abs(v) < 1e15 {
            let scaled = Int64((abs(v) * 100.0).rounded(.toNearestOrEven))
            let sign = (v.sign == .minus) ? "-" : ""
            let whole = scaled / 100
            let frac = scaled % 100
            let fracStr = frac < 10 ? "0\(frac)" : "\(frac)"
            let s = "\(sign)\(whole).\(fracStr)"
            return String(s.trimEndMatches("0").trimEndMatches("."))
        }
        return "\(v)"
    }

    private static let R: Float = 100.0
    private static let SWATCH: Float = 12.0

    static func draw(_ p: Pie, _ paint: DiagramStyle) -> Scene? {
        var small = paint.font
        small.size = paint.font.size - 1.0
        small.lineHeight = paint.font.lineHeight - 2.0
        var pctFont = small
        pctFont.weight = 600.0
        let total = p.slices.reduce(0.0) { $0 + $1.1 }
        let names = p.slices.map { measure($0.0, paint.font) }
        let values: [Measured?] = p.slices.map { s in
            p.showData ? measure(number(s.1), paint.font) : nil
        }
        let rowH = max(paint.font.lineHeight, SWATCH) + 6.0
        let legendW = zip(names, values).map { n, v in
            SWATCH + 8.0 + n.size[0] + (v.map { $0.size[0] + 8.0 } ?? 0.0)
        }.reduce(0.0, max)
        let legendH = Float(p.slices.count) * rowH - 6.0
        let beside = 2.0 * R + 32.0 + legendW <= room(paint)
        let centre: [Float]
        let legend: [Float]
        if beside {
            let h = max(legendH, 2.0 * R)
            centre = [R, h / 2.0]
            legend = [2.0 * R + 32.0, (h - legendH) / 2.0]
        } else {
            centre = [max(R, legendW / 2.0), R]
            legend = [max(R - legendW / 2.0, 0.0), 2.0 * R + 20.0]
        }

        var c = Canvas()
        var a: Float = -90.0
        var edges: [Float] = []
        for (i, s) in p.slices.enumerated() {
            let sweep = Float(s.1 / total) * 360.0
            let steps = max(Int((sweep / 4.0).rounded(.up)), 2)
            var pts = arc(centre, R, R, a, a + sweep, steps)
            if p.slices.count > 1 {
                pts.append(centre)
            }
            c.fill(pts, chart.solid(paint, chart.hue(i)))
            edges.append(a)
            a += sweep
        }
        if p.slices.count > 1 {
            for edgeAngle in edges {
                let r = degToRad(edgeAngle)
                c.stroke([centre, [centre[0] + R * mCos(r), centre[1] + R * mSin(r)]], false, 2.0, paint.surface)
            }
        }
        a = -90.0
        for (i, s) in p.slices.enumerated() {
            let frac = s.1 / total
            let sweep = Float(frac) * 360.0
            let pctVal = Int64((frac * 100.0).rounded(.toNearestOrEven))
            let m = measure("\(pctVal)%", pctFont)
            // Only where the slice is wide enough at that radius to hold it.
            let roomAcross = 2.0 * R * 0.66 * mSin(degToRad(min(sweep / 2.0, 90.0)))
            if p.slices.count == 1 || m.size[0] + 6.0 <= roomAcross {
                let mid = degToRad(a + sweep / 2.0)
                let at = p.slices.count == 1 ? centre : [centre[0] + R * 0.66 * mCos(mid), centre[1] + R * 0.66 * mSin(mid)]
                c.label(m, at, pctFont, chart.ink(chart.solid(paint, chart.hue(i))), .center)
            }
            a += sweep
        }
        for (i, (n, v)) in zip(names, values).enumerated() {
            let y = legend[1] + Float(i) * rowH
            let mid = y + (rowH - 6.0) / 2.0
            let x = legend[0]
            c.fill(roundedRect(x, mid - SWATCH / 2.0, x + SWATCH, mid + SWATCH / 2.0, 3.0), chart.solid(paint, chart.hue(i)))
            c.labelAt(n, [x + SWATCH + 8.0, mid - n.size[1] / 2.0], paint.font, paint.text, .start)
            if let v {
                c.labelAt(v, [x + SWATCH + 16.0 + n.size[0], mid - v.size[1] / 2.0], paint.font, paint.muted, .start)
            }
        }
        return c.finish(1.0, paint)
    }
}
