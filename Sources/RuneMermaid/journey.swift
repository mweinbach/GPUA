// Ported from: crates/rune-mermaid/src/journey.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! User journeys (`journey`): tasks left to right under their sections, each with a face at its
//! score (1 to 5) and dots for the actors in it, and a legend of actors.

import Rune

enum journey {
    struct Task: Equatable, Sendable {
        var name: String
        var score: Float
        var actors: [Int]
        var section: Int?
    }

    struct Journey {
        var title: String?
        var sections: [String]
        var actors: [String]
        var tasks: [Task]
    }

    static func parse(_ body: [String]) -> Journey? {
        var j = Journey(title: nil, sections: [], actors: [], tasks: [])
        for l in body {
            if let rest = word(l, "title") {
                let s = clean(rest)
                j.title = s.isEmpty ? nil : s
                continue
            }
            if let rest = word(l, "section") {
                j.sections.append(clean(rest))
                continue
            }
            if l.hasPrefix("accTitle") || l.hasPrefix("accDescr") {
                continue
            }
            let parts = l.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count >= 2 else { continue }
            let name = String(parts[0])
            guard let score = Float(parts[1].trimmed()), score.isFinite else { continue }
            if j.tasks.count + j.sections.count >= MAX_ITEMS {
                return nil
            }
            var actors: [Int] = []
            let actorsRaw = parts.count >= 3 ? String(parts[2]) : ""
            for rawActor in actorsRaw.split(separator: ",", omittingEmptySubsequences: false) {
                let a = clean(String(rawActor))
                if a.isEmpty { continue }
                let idx: Int
                if let existing = j.actors.firstIndex(of: a) {
                    idx = existing
                } else {
                    j.actors.append(a)
                    idx = j.actors.count - 1
                }
                if !actors.contains(idx) {
                    actors.append(idx)
                }
            }
            let section = j.sections.isEmpty ? nil : (j.sections.count - 1)
            j.tasks.append(Task(name: clean(name), score: clampF(score, 1.0, 5.0), actors: actors, section: section))
        }
        return j.tasks.isEmpty ? nil : j
    }

    private static let COL: Float = 112.0
    private static let GAP: Float = 10.0
    private static let STEP: Float = 20.0
    private static let FACE: Float = 11.0
    private static let DOT: Float = 4.5

    private static func actorHue(_ i: Int) -> Float {
        chart.hue(i + 6)
    }

    /// Green for 5 down to red for 1.
    static func mood(_ score: Float, _ paint: DiagramStyle) -> Color {
        let h = 25.0 + (score - 1.0) / 4.0 * 125.0
        return chart.dark(paint) ? oklch(0.7, 0.14, h) : oklch(0.8, 0.14, h)
    }

    static func draw(_ j: Journey, _ paint: DiagramStyle) -> Scene? {
        let head = chart.bold(paint.font)
        let note = chart.small(paint)
        func xOf(_ i: Int) -> Float {
            Float(i) * (COL + GAP)
        }
        var c = Canvas()

        // The legend: one row of actors.
        var y: Float = 0.0
        if !j.actors.isEmpty {
            var x: Float = 0.0
            let names = j.actors.map { measure($0, note) }
            let h = names.map { $0.size[1] }.reduce(0.0, max)
            for (i, m) in names.enumerated() {
                c.fill(ellipse([x + DOT + 1.0, h / 2.0], DOT + 1.0, DOT + 1.0), chart.solid(paint, actorHue(i)))
                c.labelAt(m, [x + 2.0 * DOT + 8.0, 0.0], note, paint.muted, .start)
                x += 2.0 * DOT + 8.0 + m.size[0] + 16.0
            }
            y = h + 12.0
        }

        if !j.sections.isEmpty {
            let titles = j.sections.map { measureWrap($0, head, 3.0 * COL) }
            let band = titles.map { $0.size[1] }.reduce(0.0, max) + 14.0
            for (s, m) in titles.enumerated() {
                let cols = (0..<j.tasks.count).filter { j.tasks[$0].section == s }
                guard let a = cols.first, let b = cols.last else { continue }
                let fill = chart.solid(paint, chart.hue(s))
                c.fill(roundedRect(xOf(a), y, xOf(b) + COL, y + band, 6.0), fill)
                c.label(m, [(xOf(a) + xOf(b) + COL) / 2.0, y + band / 2.0], head, chart.ink(fill), .center)
            }
            y += band + 8.0
        }

        let names = j.tasks.map { measureWrap($0.name, paint.font, COL - 16.0) }
        let boxH = names.map { $0.size[1] }.reduce(0.0, max) + 20.0
        let facesTop = y + boxH + 22.0 + FACE
        let facesBottom = facesTop + 4.0 * STEP
        for (i, (t, m)) in zip(j.tasks, names).enumerated() {
            let x = xOf(i)
            let h = chart.hue(t.section ?? 0)
            let mid = x + COL / 2.0
            let face = [mid, facesTop + (5.0 - t.score) * STEP]
            c.dashed([[mid, y + boxH], [mid, facesBottom + FACE + 8.0]], 1.0, paint.text.alpha(0.25), 4.0, 3.0)
            c.shape(roundedRect(x, y, x + COL, y + boxH, 6.0), chart.soft(paint, h), chart.strong(paint, h), 1.0)
            c.label(m, [mid, y + boxH / 2.0 + 2.0], paint.font, paint.text, .center)
            for (k, a) in t.actors.enumerated() {
                c.shape(ellipse([x + 12.0 + Float(k) * (2.0 * DOT + 4.0), y], DOT, DOT), chart.solid(paint, actorHue(a)), paint.surface, 1.5)
            }
            drawFace(&c, face, t.score, paint)
        }
        let base = facesBottom + FACE + 8.0
        let right = xOf(j.tasks.count - 1) + COL + 12.0
        c.stroke([[-4.0, base], [right - 8.0, base]], false, 1.5, paint.line)
        c.fill(arrowhead([right, base], [1.0, 0.0], 9.0, 8.0), paint.line)
        return c.finishFit(paint)
    }

    private static func drawFace(_ c: inout Canvas, _ at: [Float], _ score: Float, _ paint: DiagramStyle) {
        let line = oklch(0.25, 0.02, 60.0)
        c.shape(ellipse(at, FACE, FACE), mood(score, paint), line.alpha(0.6), 1.0)
        for dx: Float in [-3.8, 3.8] {
            c.fill(ellipse([at[0] + dx, at[1] - 3.0], 1.4, 1.6), line)
        }
        let mouth: [[Float]]
        if score > 3.0 {
            mouth = arc([at[0], at[1] + 1.0], 5.0, 4.0, 20.0, 160.0, 12)
        } else if score < 3.0 {
            mouth = arc([at[0], at[1] + 8.0], 5.0, 3.5, 200.0, 340.0, 12)
        } else {
            mouth = [[at[0] - 4.5, at[1] + 4.5], [at[0] + 4.5, at[1] + 4.5]]
        }
        c.stroke(mouth, false, 1.3, line)
    }
}
