// Tests ported from: crates/rune-mermaid/src/xychart_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import Rune
@testable import RuneMermaid

@Suite struct XyChartTests {
    private func parseXy(_ src: String) -> xychart.XyChart {
        guard let parsed = RuneMermaid.parse(src), case .xyChart(let x) = parsed.diagram else {
            fatalError("not an xy chart: \(src)")
        }
        return x
    }

    @Test func axesAndSeries() {
        let x = parseXy(
            "xychart-beta\n    title \"Sales Revenue\"\n    x-axis [jan, feb, \"mar, apr\", may]\n    y-axis \"Revenue (in $)\" 4000 --> 11000\n    bar [5000, 6000, 7500, 8200]\n    line \"Trend\" [5000, 6000.5, -7500, 8200]\n    line [1, two, 3]\n    bar oops"
        )
        #expect(x.title == "Sales Revenue")
        #expect(!x.horizontal)
        #expect(x.bands == ["jan", "feb", "mar, apr", "may"])
        #expect(x.yTitle == "Revenue (in $)")
        #expect(x.yRange == [4000.0, 11000.0])
        #expect(x.series.count == 2)
        #expect(x.series[1].kind == .line && x.series[1].name == "Trend")
        #expect(x.series[1].values[2] == -7500.0)

        let h = parseXy("xychart-beta horizontal\n    x-axis \"Score\" 10 --> 0\n    y-axis Votes\n    bar [3, 5]")
        #expect(h.horizontal)
        #expect(h.xTitle == "Score" && h.xRange == [0.0, 10.0])
        #expect(h.yTitle == "Votes" && h.yRange == nil)
        #expect(RuneMermaid.parse("xychart-beta\n    title Nothing\n    x-axis [a, b]") == nil)
        let budget = "xychart-beta\n    bar [\(Array(repeating: "1", count: MAX_ITEMS + 1).joined(separator: ", "))]"
        #expect(RuneMermaid.parse(budget) == nil)
    }

    @Test func theValueAxisRoundsOutAndTakesInZero() {
        let makeSeries: ([Float]) -> [xychart.Series] = { v in
            [xychart.Series(kind: .bar, name: "", values: v)]
        }
        let s1 = xychart.scale(nil, makeSeries([3.0, 47.0]))
        #expect(s1.0 == [0.0, 50.0] && s1.1 == [0.0, 10.0, 20.0, 30.0, 40.0, 50.0])
        let (bounds, ticks) = xychart.scale(nil, makeSeries([-12.0, 30.0]))
        #expect(bounds[0] <= -12.0 && bounds[1] >= 30.0 && ticks.contains(0.0))
        #expect(xychart.scale([4000.0, 11000.0], makeSeries([5000.0])).1.first == 4000.0)
    }

    @Test func barsRiseWithTheirValuesUprightAndOnTheirSide() {
        let paint = DiagramStyle.neutral(false)
        for (src, horizontal) in [
            ("xychart-beta\nx-axis [low, high]\nbar [1, 9]", false),
            ("xychart-beta horizontal\nx-axis [low, high]\nbar [1, 9]", true),
        ] {
            let s = buildScene(src, paint, nil)!
            let at: (String) -> [Float] = { t in s.labels.first(where: { $0.text == t })!.at }
            if horizontal {
                #expect(at("low")[1] < at("high")[1])
            } else {
                #expect(at("low")[0] < at("high")[0])
            }
        }
    }
}
