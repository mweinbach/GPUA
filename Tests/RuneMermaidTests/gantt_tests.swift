// Tests ported from: crates/rune-mermaid/src/gantt_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import Rune
@testable import RuneMermaid

@Suite struct GanttTests {
    private func parseGantt(_ src: String) -> gantt.Gantt {
        guard let parsed = RuneMermaid.parse(src), case .gantt(let g) = parsed.diagram else {
            fatalError("not a gantt chart: \(src)")
        }
        return g
    }

    private func day(_ y: Int64, _ m: UInt32, _ d: UInt32) -> Double {
        Double(date.daysFromCivil(y, m, d)) * date.DAY
    }

    private func spanOf(_ g: gantt.Gantt, _ name: String) -> (Double, Double, gantt.Task) {
        let t = g.tasks.first(where: { $0.name == name })!
        return (t.start, t.end, t)
    }

    @Test func tasksLinksTagsAndSections() {
        let g = parseGantt(
            "gantt\ntitle Release\ndateFormat YYYY-MM-DD\naxisFormat %b %d\nsection Build\nDesign :done, des, 2024-01-01, 2024-01-05\nCode :active, code, after des, 5d\nTest :crit, 3d\nsection Ship\nReview :rev, after code test2, 2d\nLaunch :milestone, after des, until rev\nFreeze :vert, 2024-01-08, 0d"
        )
        #expect(g.title == "Release")
        #expect(g.sections == ["Build", "Ship"])
        #expect(g.axis == "%b %d")
        let (s0, e0, t0) = spanOf(g, "Design")
        #expect(s0 == day(2024, 1, 1) && e0 == day(2024, 1, 5) && t0.tags.done && t0.section == 0)
        let (s1, e1, t1) = spanOf(g, "Code")
        #expect(s1 == day(2024, 1, 5) && e1 == day(2024, 1, 10) && t1.tags.active)
        let (s2, e2, t2) = spanOf(g, "Test")
        #expect(s2 == day(2024, 1, 10) && e2 == day(2024, 1, 13) && t2.tags.crit)
        #expect(spanOf(g, "Review").0 == day(2024, 1, 10))
        #expect(spanOf(g, "Review").2.section == 1)
        let (s4, e4, t4) = spanOf(g, "Launch")
        #expect(s4 == day(2024, 1, 5) && e4 == day(2024, 1, 10) && t4.tags.milestone)
        #expect(spanOf(g, "Freeze").2.tags.vert)
    }

    @Test func forwardLinksResolveAndLoopsDrop() {
        let g = parseGantt("gantt\nB :b, after a, 1d\nA :a, 2024-03-01, 2d\nC :c, after d, 1d\nD :d, after c, 1d")
        #expect(spanOf(g, "B").0 == day(2024, 3, 3))
        #expect(g.tasks.count == 2)
    }

    @Test func excludesPushDurationsPastWeekendsAndDates() {
        let g1 = parseGantt("gantt\nexcludes weekends, 2024-01-09\nA :2024-01-05, 3d\nB :2024-01-05, 2024-01-08")
        #expect(spanOf(g1, "A").1 == day(2024, 1, 11))
        #expect(spanOf(g1, "B").1 == day(2024, 1, 8))
        #expect(g1.excludes.weekdays[0] && g1.excludes.weekdays[6])
        let g2 = parseGantt("gantt\nweekend friday\nexcludes weekends\nA :2024-01-04, 2d")
        #expect(spanOf(g2, "A").1 == day(2024, 1, 8))
    }

    @Test func formatsInclusiveEndsAndBadLines() {
        let g = parseGantt("gantt\ndateFormat DD/MM/YYYY\ninclusiveEndDates\nnot a task\nA :01/02/2024, 03/02/2024\nB :what, ever\nC :after nobody, 1d")
        #expect(g.tasks.count == 1)
        #expect(spanOf(g, "A").1 == day(2024, 2, 4))
        #expect(RuneMermaid.parse("gantt\ntitle Nothing\nsection Empty") == nil)
    }

    @Test func drawsBarsLabelsAndAnAxis() {
        let paint = DiagramStyle.neutral(true)
        let s = buildScene("gantt\ntitle Plan\nsection Work\nShort :2024-01-01, 1d\nA much longer task name :2024-01-02, 20d", paint, nil)!
        #expect(s.title == "Plan")
        let texts = s.labels.map { $0.text }
        #expect(texts.contains("Work") && texts.contains("Short") && texts.contains("A much longer task name"))
        #expect(texts.contains { $0.hasPrefix("2024-01-") })
        let late = buildScene("gantt\nA :a, 2024-01-01, 20d\nA long milestone name at the very end :milestone, after a, 0d", paint, nil)!
        #expect(late.size[0] <= room(paint) + 2.01)
        let budget = "gantt\n" + (0...MAX_ITEMS).map { "T\($0) :2024-01-01, 1d" }.joined(separator: "\n")
        #expect(RuneMermaid.parse(budget) == nil)
    }
}
