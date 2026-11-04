// Tests ported from: crates/rune-mermaid/src/timeline_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import Rune
@testable import RuneMermaid

@Suite struct TimelineTests {
    private func parseTimeline(_ src: String) -> timeline.Timeline {
        guard let parsed = RuneMermaid.parse(src), case .timeline(let t) = parsed.diagram else {
            fatalError("not a timeline: \(src)")
        }
        return t
    }

    @Test func periodsEventsAndSections() {
        let t = parseTimeline(
            "timeline\n    title History of Social Media\n    2002 : LinkedIn\n    2004 : Facebook : Google\n         : MySpace\n    section Later\n    2010 : Instagram\n    2012\n    accTitle: skipped"
        )
        #expect(t.title == "History of Social Media")
        #expect(t.sections == ["Later"])
        #expect(t.periods == [
            timeline.Period(time: "2002", events: ["LinkedIn"], section: nil),
            timeline.Period(time: "2004", events: ["Facebook", "Google", "MySpace"], section: nil),
            timeline.Period(time: "2010", events: ["Instagram"], section: 0),
            timeline.Period(time: "2012", events: [], section: 0),
        ])
        #expect(!t.down)
        #expect(parseTimeline("timeline TD\n2020 : a").down)
        #expect(RuneMermaid.parse("timeline\n    title Nothing") == nil)
        let budget = "timeline\n" + (0...MAX_ITEMS).map { "\($0) : e" }.joined(separator: "\n")
        #expect(RuneMermaid.parse(budget) == nil)
    }

    @Test func runsAcrossUntilItWouldNotFit() {
        let paint = DiagramStyle.neutral(false)
        let across = buildScene("timeline\n2001 : a\n2002 : b\n2003 : c", paint, nil)!
        let ys = ["2001", "2002", "2003"].map { t in across.labels.first(where: { $0.text == t })!.at[1] }
        #expect(abs(ys[0] - ys[1]) < 0.5 && abs(ys[1] - ys[2]) < 0.5)
        let many = "timeline\n" + (2000..<2012).map { "\($0) : event" }.joined(separator: "\n")
        let down = buildScene(many, paint, nil)!
        let y: (String) -> Float = { t in down.labels.first(where: { $0.text == t })!.at[1] }
        #expect(y("2001") > y("2000") && y("2011") > y("2010"))
        #expect(down.size[0] <= room(paint) + 2.01)
    }
}
