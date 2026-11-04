// Ported from: crates/rune-mermaid/src/gantt.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Gantt charts (`gantt`): sections of tasks as bars on a time axis, with `done`, `active`,
//! `crit`, `milestone` and `vert` tags, `after`/`until` links, durations and `excludes`.

import Rune

enum gantt {
    struct Tags: Equatable, Sendable {
        var done: Bool = false
        var active: Bool = false
        var crit: Bool = false
        var milestone: Bool = false
        /// A vertical marker across the chart rather than a bar.
        var vert: Bool = false
    }

    struct Task: Equatable, Sendable {
        var name: String
        var section: Int?
        var start: Double
        var end: Double
        var tags: Tags
    }

    struct Excludes: Equatable, Sendable {
        /// By weekday, 0 Sunday.
        var weekdays: [Bool] = Array(repeating: false, count: 7)
        var days: Set<Int64> = []

        func any() -> Bool {
            weekdays.contains(true) || !days.isEmpty
        }

        func has(_ day: Int64) -> Bool {
            let rem = ((day + 4) % 7 + 7) % 7
            return weekdays[Int(rem)] || days.contains(day)
        }
    }

    struct Gantt {
        var title: String?
        var sections: [String]
        var tasks: [Task]
        var axis: String
        var tick: date.Step?
        /// Days left out of durations, drawn shaded.
        var excludes: Excludes
    }

    private enum From {
        case prev
        case at(Double)
        case after([String])
    }

    private enum To {
        case at(Double)
        case span(date.Span)
        case until([String])
    }

    private struct Raw {
        var name: String
        var section: Int?
        var tags: Tags
        var id: String?
        var from: From
        var to: To
    }

    private static let WEEKDAYS: [String] = [
        "sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday",
    ]

    static func parse(_ header: String, _ body: [String]) -> Gantt? {
        var g = Gantt(
            title: nil,
            sections: [],
            tasks: [],
            axis: "%Y-%m-%d",
            tick: nil,
            excludes: Excludes()
        )
        var format = "YYYY-MM-DD"
        var raws: [Raw] = []
        var inclusive = false
        var weekendFriday = false
        var weekends = false
        // `dateFormat` applies to every task, wherever it is set, so tasks are read after it.
        var lines: [String] = []
        for line in [header] + body {
            for stmt in statements(line) {
                let wordTok: String
                let rest: String
                if let (w, r) = stmt.splitOnceWhere(isUnicodeWS) {
                    wordTok = String(w)
                    rest = String(r.trimmed())
                } else {
                    wordTok = stmt
                    rest = ""
                }
                switch wordTok {
                case "dateFormat" where !rest.isEmpty:
                    format = rest
                case "axisFormat" where !rest.isEmpty:
                    g.axis = rest
                case "tickInterval":
                    g.tick = date.Step.parse(rest) ?? g.tick
                case "inclusiveEndDates":
                    inclusive = true
                case "weekend":
                    weekendFriday = rest.asciiLower() == "friday"
                case "title":
                    let cleaned = cleanQuoted(rest)
                    g.title = cleaned.isEmpty ? nil : cleaned
                case "excludes":
                    var dates = false
                    for rawPart in rest.split(whereSeparator: { $0 == "," || $0 == " " }) {
                        let part = String(rawPart.trimmed())
                        if part.isEmpty { continue }
                        let lower = part.asciiLower()
                        if lower == "weekends" {
                            weekends = true
                        } else if let wd = WEEKDAYS.firstIndex(of: lower) {
                            g.excludes.weekdays[wd] = true
                        } else {
                            dates = true
                        }
                    }
                    // Dates read once `dateFormat` is known.
                    if dates {
                        lines.append(stmt)
                    }
                case "includes", "todayMarker", "topAxis", "weekday", "displayMode", "click", "accTitle", "accDescr":
                    break
                default:
                    lines.append(stmt)
                }
            }
        }
        if weekends {
            let (a, b) = weekendFriday ? (5, 6) : (6, 0)
            g.excludes.weekdays[a] = true
            g.excludes.weekdays[b] = true
        }
        for stmt in lines {
            if let rest = stmt.stripPrefix("excludes") {
                for rawPart in rest.split(whereSeparator: { $0 == "," || $0 == " " }) {
                    let part = String(rawPart.trimmed())
                    if part.isEmpty { continue }
                    if let t = date.parse(part, format) {
                        g.excludes.days.insert(Int64((t / date.DAY).rounded(.down)))
                    }
                }
                continue
            }
            if let rest = stmt.stripPrefix("section") {
                if g.sections.count + raws.count >= MAX_ITEMS {
                    return nil
                }
                g.sections.append(clean(String(rest)))
                continue
            }
            guard let (nameSub, metaSub) = stmt.splitOnce(":") else { continue }
            let section = g.sections.isEmpty ? nil : (g.sections.count - 1)
            if let r = task(clean(String(nameSub)), section, String(metaSub), format, inclusive) {
                if g.sections.count + raws.count >= MAX_ITEMS {
                    return nil
                }
                raws.append(r)
            }
        }
        g.tasks = resolve(raws, g.excludes)
        return g.tasks.isEmpty ? nil : g
    }

    /// `crit, active, id, after a b, 3d` and the shorter forms.
    private static func task(
        _ name: String,
        _ section: Int?,
        _ meta: String,
        _ format: String,
        _ inclusive: Bool
    ) -> Raw? {
        var parts = meta.split(separator: ",", omittingEmptySubsequences: false).map { String($0.trimmed()) }
        var tags = Tags()
        tagLoop: while let first = parts.first {
            switch first {
            case "done": tags.done = true
            case "active": tags.active = true
            case "crit": tags.crit = true
            case "milestone": tags.milestone = true
            case "vert": tags.vert = true
            default:
                break tagLoop
            }
            parts.removeFirst()
        }
        let id: String?
        let from: From
        let toStr: String
        switch parts.count {
        case 1:
            id = nil
            from = .prev
            toStr = parts[0]
        case 2:
            guard let f = fromSpec(parts[0], format) else { return nil }
            id = nil
            from = f
            toStr = parts[1]
        case 3:
            guard let f = fromSpec(parts[1], format) else { return nil }
            id = parts[0].isEmpty ? nil : parts[0]
            from = f
            toStr = parts[2]
        default:
            return nil
        }
        let to: To
        if let ids = toStr.stripPrefix("until ") {
            to = .until(ids.split(whereSeparator: isUnicodeWS).map(String.init))
        } else if let s = date.span(toStr) {
            to = .span(s)
        } else {
            // `inclusiveEndDates` makes an end date the last day of the task, not the day after.
            guard let parsedEnd = date.parse(toStr, format) else { return nil }
            to = .at(parsedEnd + (inclusive ? date.DAY : 0.0))
        }
        return Raw(name: name, section: section, tags: tags, id: id, from: from, to: to)
    }

    private static func fromSpec(_ s: String, _ format: String) -> From? {
        if let ids = s.stripPrefix("after ") {
            return .after(ids.split(whereSeparator: isUnicodeWS).map(String.init))
        }
        return date.parse(s, format).map(From.at)
    }

    /// Starts and ends for every task that has them, following links in any order; a task left
    /// without one (a link to nothing, a loop) is dropped.
    private static func resolve(_ raws: [Raw], _ excludes: Excludes) -> [Task] {
        var ids: [String: Int] = [:]
        for (i, r) in raws.enumerated() {
            if let id = r.id {
                ids[id] = i
            }
        }
        var times: [(Double, Double)?] = Array(repeating: nil, count: raws.count)
        for _ in 0...raws.count {
            var changed = false
            for (i, r) in raws.enumerated() {
                if times[i] != nil {
                    continue
                }
                func linked(
                    _ names: [String],
                    _ pick: ((Double, Double)) -> Double,
                    _ best: (Double, Double) -> Double
                ) -> Double? {
                    let known = names.compactMap { ids[$0] }
                    let got = known.compactMap { times[$0].map(pick) }
                    guard !known.isEmpty && got.count == known.count, let first = got.first else {
                        return nil
                    }
                    return got.dropFirst().reduce(first, best)
                }
                let start: Double?
                switch r.from {
                case .at(let t):
                    start = t
                case .prev:
                    start = i > 0 ? times[i - 1]?.1 : nil
                case .after(let names):
                    start = linked(names, { $0.1 }, max)
                }
                guard let start else { continue }
                let end: Double?
                switch r.to {
                case .at(let t):
                    end = t
                case .span(let s):
                    end = skipExcluded(start, s.after(start), excludes)
                case .until(let names):
                    end = linked(names, { $0.0 }, min)
                }
                if let end {
                    times[i] = (start, max(end, start))
                    changed = true
                }
            }
            if !changed {
                break
            }
        }
        var out: [Task] = []
        for (r, t) in zip(raws, times) {
            if let (start, end) = t {
                out.append(Task(name: r.name, section: r.section, start: start, end: end, tags: r.tags))
            }
        }
        return out
    }

    /// `end` pushed back a day for each excluded day from `start` up to it.
    private static func skipExcluded(_ start: Double, _ endIn: Double, _ excludes: Excludes) -> Double {
        if !excludes.any() {
            return endIn
        }
        var end = endIn
        var day = Int64((start / date.DAY).rounded(.down))
        for _ in 0..<3660 {
            if Double(day) * date.DAY >= end {
                break
            }
            if excludes.has(day) {
                end += date.DAY
            }
            day += 1
        }
        return end
    }

    /// Section hues: the series palette without its reds, which mean `crit`.
    private static let SECTION_HUES: [Float] = [255.0, 150.0, 70.0, 305.0, 195.0, 110.0, 280.0, 225.0]
    private static let CRIT: Float = 25.0

    private static func sectionHue(_ s: Int) -> Float {
        SECTION_HUES[((s % SECTION_HUES.count) + SECTION_HUES.count) % SECTION_HUES.count]
    }

    private static let BAR: Float = 22.0
    private static let PITCH: Float = 28.0

    static func draw(_ g: Gantt, _ paint: DiagramStyle) -> Scene? {
        var small = paint.font
        small.size = paint.font.size - 1.0
        small.lineHeight = paint.font.lineHeight - 2.0
        var bold = small
        bold.weight = 600.0
        let w = room(paint)
        let rows = g.tasks.filter { !$0.tags.vert }
        let marks = g.tasks.filter { $0.tags.vert }
        var used: [Int] = []
        for t in rows {
            if let s = t.section, used.last != s {
                used.append(s)
            }
        }
        let side = (w * 0.28).rounded(.down)
        let titles = g.sections.map { measureWrap($0, bold, side - 16.0) }
        let left = min(used.map { titles[$0].size[0] + 16.0 }.reduce(0.0, max), side)
        let x0 = left + 4.0
        let x1 = w - 4.0
        let lo = g.tasks.map(\.start).reduce(Double.greatestFiniteMagnitude, min)
        var hi = g.tasks.map(\.end).reduce(-Double.greatestFiniteMagnitude, max)
        if hi - lo < 1.0 {
            hi = lo + date.DAY
        }
        func sx(_ t: Double) -> Float {
            x0 + Float((t - lo) / (hi - lo)) * (x1 - x0)
        }

        let markLabels = marks.map { measure($0.name, small) }
        let top = markLabels.map { $0.size[1] + 6.0 }.reduce(0.0, max)
        let bottom = top + Float(rows.count) * PITCH + 4.0
        var c = Canvas()

        // Section bands, then shaded excluded days, then the grid, then bars.
        var r0 = 0
        while r0 < rows.count {
            let sec = rows[r0].section
            var r1 = rows.count
            for idx in r0..<rows.count where rows[idx].section != sec {
                r1 = idx
                break
            }
            let y0 = top + Float(r0) * PITCH
            let y1 = top + Float(r1) * PITCH + (r1 == rows.count ? 4.0 : 0.0)
            if let s = sec {
                c.fill([[0.0, y0], [x1, y0], [x1, y1], [0.0, y1]], chart.strong(paint, sectionHue(s)).alpha(0.07))
                c.label(titles[s], [left / 2.0, (y0 + y1) / 2.0], bold, paint.text, .center)
            }
            r0 = r1
        }
        let d0 = Int64((lo / date.DAY).rounded(.down))
        let d1 = Int64((hi / date.DAY).rounded(.up))
        if g.excludes.any() && d1 - d0 <= 400 {
            for day in d0..<d1 where g.excludes.has(day) {
                let a = max(sx(Double(day) * date.DAY), x0)
                let b = min(sx(Double(day + 1) * date.DAY), x1)
                c.fill([[a, top], [b, top], [b, bottom], [a, bottom]], paint.text.alpha(0.05))
            }
        }
        let probe = measure(date.format(lo, g.axis), small).size[0] + 16.0
        let step = g.tick ?? {
            func px(_ s: date.Step) -> Double {
                s.len() / (hi - lo) * Double(x1 - x0)
            }
            return date.Step.LADDER.first { px($0) >= Double(probe) && (hi - lo) / $0.len() <= 40.0 } ?? .months(60)
        }()
        let ticks: [(Float, Measured)] = step.ticks(lo, hi, 200).map { t in
            (sx(t), measure(date.format(t, g.axis), small))
        }
        chart.axisX(&c, ticks, [x0, x1], [top, bottom], small, paint)

        // Markers under the bars, so a bar's text stays whole.
        for (t, m) in zip(marks, markLabels) {
            let x = sx(t.start)
            let color = t.tags.crit ? chart.strong(paint, CRIT) : paint.muted
            c.dashed([[x, top - 2.0], [x, bottom]], 1.25, color, 4.0, 3.0)
            c.labelAt(m, [clampF(x - m.size[0] / 2.0, 0.0, max(x1 - m.size[0], 0.0)), 0.0], small, color, .start)
        }
        for (r, t) in rows.enumerated() {
            let y = top + Float(r) * PITCH + (PITCH - BAR) / 2.0 + 2.0
            let h = t.tags.crit ? CRIT : sectionHue(t.section ?? 0)
            var fill = chart.soft(paint, h)
            var border = chart.strong(paint, h)
            var width: Float = 1.0
            if t.tags.active {
                fill = oklabMix(fill, paint.surface, 0.55)
                width = 1.5
            }
            if t.tags.done {
                fill = overColor(paint.text.alpha(0.12), paint.surface)
                if !t.tags.crit {
                    border = paint.nodeBorder
                }
            }
            let m = measure(t.name, small)
            let a = sx(t.start)
            let b = max(sx(t.end), sx(t.start) + 2.0)
            let mid = y + BAR / 2.0
            if t.tags.milestone {
                let rad = BAR / 2.0
                c.shape([[a, mid - rad], [a + rad, mid], [a, mid + rad], [a - rad, mid]], fill, border, width)
                let x = (a + rad + 6.0 + m.size[0] <= x1) ? (a + rad + 6.0) : max(a - rad - 6.0 - m.size[0], 0.0)
                c.labelAt(m, [x, mid - m.size[1] / 2.0], small, paint.text, .start)
                continue
            }
            c.shape(roundedRect(a, y, b, y + BAR, 3.0), fill, border, width)
            let at: (Float, Color)
            if m.size[0] + 12.0 <= b - a {
                at = ((a + b - m.size[0]) / 2.0, chart.ink(fill))
            } else if b + 6.0 + m.size[0] <= x1 {
                at = (b + 6.0, paint.text)
            } else {
                at = (max(a - 6.0 - m.size[0], 0.0), paint.text)
            }
            c.labelAt(m, [at.0, mid - m.size[1] / 2.0], small, at.1, .start)
        }
        return c.finishFit(paint)
    }
}
