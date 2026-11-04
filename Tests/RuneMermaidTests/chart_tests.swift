// Tests ported from: crates/rune-mermaid/src/chart_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import Rune
@testable import RuneMermaid

@Suite struct ChartTests {
    @Test func inkReadsOnEverySeriesFill() {
        for dark in [false, true] {
            let paint = DiagramStyle.neutral(dark)
            for i in 0..<12 {
                for fill in [chart.solid(paint, chart.hue(i)), chart.soft(paint, chart.hue(i))] {
                    let diff = abs(chart.ink(fill).toOklab()[0] - fill.toOklab()[0])
                    #expect(diff > 0.35, "dark=\(dark) series \(i): \(diff)")
                }
            }
        }
    }

    @Test func axisLabelsStayInsideAndNeverOverlap() {
        let paint = DiagramStyle.neutral(false)
        var c = Canvas()
        let ticks: [(Float, Measured)] = ([0.0, 10.0, 60.0, 200.0] as [Float]).map { x in
            (x, RuneMermaid.measure("2024-01-01", paint.font))
        }
        chart.axisX(&c, ticks, [0.0, 200.0], [0.0, 100.0], paint.font, paint)
        let xs = c.labels.map { $0.at[0] }
        #expect(c.labels.count < 4, "the tick at 10 crowds the first: \(xs)")
        for l in c.labels {
            #expect(l.at[0] >= 0.0 && l.at[0] + l.size[0] <= 200.0 + 0.01, "\(xs)")
        }
        if c.labels.count >= 2 {
            for i in 0..<(c.labels.count - 1) {
                #expect(c.labels[i + 1].at[0] >= c.labels[i].at[0] + c.labels[i].size[0], "\(xs)")
            }
        }
    }
}
