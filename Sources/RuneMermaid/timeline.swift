// Ported from: crates/rune-mermaid/src/timeline.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Timelines (`timeline`): time periods left to right with their events stacked under them,
//! grouped and coloured by `section`. Too many periods to fit across run top to bottom instead.

import Rune

enum timeline {
    struct Period: Equatable, Sendable {
        var time: String
        var events: [String]
        var section: Int?
    }

    struct Timeline {
        var title: String?
        var sections: [String]
        var periods: [Period]
        /// `timeline TD`: top to bottom however many periods there are.
        var down: Bool
    }

    static func parse(_ header: String, _ body: [String]) -> Timeline? {
        let hTrim = header.trimmed()
        var t = Timeline(
            title: nil,
            sections: [],
            periods: [],
            down: hTrim == "TD" || hTrim == "TB"
        )
        var items = 0
        for l in body {
            if let rest = word(l, "title") {
                let s = clean(rest)
                t.title = s.isEmpty ? nil : s
                continue
            }
            if let rest = word(l, "section") {
                t.sections.append(clean(rest))
                items += 1
                continue
            }
            if l.hasPrefix("accTitle") || l.hasPrefix("accDescr") {
                continue
            }
            let parts = l.split(separator: ":", omittingEmptySubsequences: false).map { clean(String($0)) }
            let time = parts.first ?? ""
            let events = parts.dropFirst().filter { !$0.isEmpty }
            items += events.count + (time.isEmpty ? 0 : 1)
            if items > MAX_ITEMS {
                return nil
            }
            // `: event` on its own line adds to the period above.
            if time.isEmpty {
                if !t.periods.isEmpty {
                    t.periods[t.periods.count - 1].events.append(contentsOf: events)
                }
                continue
            }
            let section = t.sections.isEmpty ? nil : (t.sections.count - 1)
            t.periods.append(Period(time: time, events: events, section: section))
        }
        return t.periods.isEmpty ? nil : t
    }

    private static let COL: Float = 136.0
    private static let GAP: Float = 12.0
    private static let PAD: [Float] = [10.0, 7.0]

    /// The hue of period `i`: its section's, or its own when there are none.
    private static func periodHue(_ t: Timeline, _ i: Int) -> Float {
        chart.hue(t.periods[i].section ?? i)
    }

    static func draw(_ t: Timeline, _ paint: DiagramStyle) -> Scene? {
        let n = Float(t.periods.count)
        if t.down || n * COL + (n - 1.0) * GAP > room(paint) / 0.75 {
            return drawDown(t, paint)
        }
        let head = chart.bold(paint.font)
        let note = chart.small(paint)
        let inner = COL - 2.0 * PAD[0]
        let times = t.periods.map { measureWrap($0.time, head, inner) }
        let events = t.periods.map { p in p.events.map { measureWrap($0, note, inner) } }
        let titles = t.sections.map { measureWrap($0, head, 4.0 * COL) }
        func xOf(_ i: Int) -> Float {
            Float(i) * (COL + GAP)
        }

        var c = Canvas()
        var y: Float = 0.0
        if !t.sections.isEmpty {
            let band = titles.map { $0.size[1] }.reduce(0.0, max) + 2.0 * PAD[1]
            for (s, m) in titles.enumerated() {
                let cols = (0..<t.periods.count).filter { t.periods[$0].section == s }
                guard let a = cols.first, let b = cols.last else { continue }
                let fill = chart.solid(paint, chart.hue(s))
                c.fill(roundedRect(xOf(a), 0.0, xOf(b) + COL, band, 6.0), fill)
                c.label(m, [(xOf(a) + xOf(b) + COL) / 2.0, band / 2.0], head, chart.ink(fill), .center)
            }
            y = band + 10.0
        }
        let boxH = times.map { $0.size[1] }.reduce(0.0, max) + 2.0 * PAD[1]
        let lineY = y + boxH + 18.0
        var bottom = lineY
        for (i, m) in times.enumerated() {
            let h = periodHue(t, i)
            let x = xOf(i)
            var ey = lineY + 18.0
            let boxes: [(Float, Float)] = events[i].map { e in
                let top = ey
                ey += e.size[1] + 2.0 * PAD[1] + 8.0
                return (top, e.size[1] + 2.0 * PAD[1])
            }
            let end = boxes.last.map { $0.0 + $0.1 / 2.0 } ?? lineY
            c.dashed([[x + COL / 2.0, y + boxH], [x + COL / 2.0, end]], 1.0, chart.strong(paint, h).alpha(0.6), 4.0, 3.0)
            c.shape(roundedRect(x, y, x + COL, y + boxH, 6.0), chart.soft(paint, h), chart.strong(paint, h), 1.0)
            c.label(m, [x + COL / 2.0, y + boxH / 2.0], head, paint.text, .center)
            for (e, (top, eh)) in zip(events[i], boxes) {
                c.shape(roundedRect(x + 6.0, top, x + COL - 6.0, top + eh, 5.0), paint.nodeFill, chart.strong(paint, h).alpha(0.55), 1.0)
                c.label(e, [x + COL / 2.0, top + eh / 2.0], note, paint.text, .center)
                bottom = max(bottom, top + eh)
            }
        }
        let right = xOf(t.periods.count - 1) + COL + 14.0
        c.stroke([[-6.0, lineY], [right - 8.0, lineY]], false, 2.0, paint.line)
        c.fill(arrowhead([right, lineY], [1.0, 0.0], 10.0, 9.0), paint.line)
        return c.finishFit(paint)
    }

    /// Periods down a line on the left, each with its events as chips flowing to its right.
    private static func drawDown(_ t: Timeline, _ paint: DiagramStyle) -> Scene? {
        let head = chart.bold(paint.font)
        let note = chart.small(paint)
        let times = t.periods.map { measureWrap($0.time, head, 140.0) }
        let tw = times.map { $0.size[0] }.reduce(0.0, max)
        let spine = tw + 18.0
        let x0 = spine + 18.0
        let x1 = max(room(paint), x0 + 160.0)
        var c = Canvas()
        var y: Float = 0.0
        var section: Int? = nil
        for (i, (p, m)) in zip(t.periods, times).enumerated() {
            if p.section != section, let s = p.section {
                section = s
                let title = measureWrap(t.sections[s], head, x1 - 2.0 * PAD[0])
                let band = title.size[1] + 2.0 * PAD[1]
                let fill = chart.solid(paint, chart.hue(s))
                c.fill(roundedRect(0.0, y, x1, y + band, 6.0), fill)
                c.labelAt(title, [PAD[0], y + PAD[1]], head, chart.ink(fill), .start)
                y += band + 10.0
            }
            let h = periodHue(t, i)
            let chips = p.events.map { measureWrap($0, note, x1 - x0 - 2.0 * PAD[0]) }
            var at: [[Float]] = []
            var cx = x0
            var cy = y
            var rowH: Float = 0.0
            for chip in chips {
                let w = chip.size[0] + 2.0 * PAD[0]
                if cx > x0 && cx + w > x1 {
                    cx = x0
                    cy += rowH + 6.0
                    rowH = 0.0
                }
                at.append([cx, cy])
                cx += w + 6.0
                rowH = max(rowH, chip.size[1] + 2.0 * PAD[1])
            }
            let rowBottom = max(cy + rowH, y + m.size[1] + 2.0 * PAD[1])
            let mid = y + (m.size[1] + 2.0 * PAD[1]) / 2.0
            c.labelAt(m, [spine - 14.0 - m.size[0], mid - m.size[1] / 2.0], head, paint.text, .end)
            c.stroke([[spine, y - 5.0], [spine, rowBottom + 5.0]], false, 2.0, paint.line)
            c.shape(ellipse([spine, mid], 5.0, 5.0), chart.solid(paint, h), paint.surface, 2.0)
            for (chip, a) in zip(chips, at) {
                let w = chip.size[0] + 2.0 * PAD[0]
                let ch = chip.size[1] + 2.0 * PAD[1]
                c.shape(roundedRect(a[0], a[1], a[0] + w, a[1] + ch, 5.0), chart.soft(paint, h), chart.strong(paint, h).alpha(0.6), 1.0)
                c.labelAt(chip, [a[0] + PAD[0], a[1] + PAD[1]], note, paint.text, .start)
            }
            y = rowBottom + 10.0
        }
        return c.finish(1.0, paint)
    }
}
