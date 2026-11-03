// Tests ported from: crates/rune/src/tooling/perf_warn/commits_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("PerfWarnCommitsTests", .serialized)
struct PerfWarnCommitsTests {
    #if !os(WASI)
    @Test func aPollThatCommitsEveryScrollFrameWarnsOnceNamingPoll() {
        _ = perfWarnTakeLogForTests(newScope: true)
        let meter = PerfCommitMeter()
        for _ in 0..<20 {
            meter.poll()
            meter.frameEnds(scrolling: true, committed: true, instant: nil)
        }
        let log = perfWarnTakeLogForTests().filter { $0.contains("of a scroll") }
        #expect(log.count == 1)
        #expect(log[0].hasPrefix("rune: `poll` returned true and committed the view on 6 of "))
    }

    @Test func anOnLayoutTxThatCommitsThroughAScrollNamesItsElementAndWhereItWasSet() {
        _ = perfWarnTakeLogForTests(newScope: true)
        let meter = PerfCommitMeter()
        for _ in 0..<20 {
            meter.handler("on_layout_tx", path: "#0/scroll/rows/r3", at: "commits_tests.rs:43:39")
            meter.frameEnds(scrolling: true, committed: true, instant: nil)
        }
        let log = perfWarnTakeLogForTests().filter { $0.contains("of a scroll") }
        #expect(log.count == 1)
        #expect(log[0].contains("`on_layout_tx` on ") && log[0].contains("r3") && log[0].contains("commits_tests.rs:") && log[0].contains("say `Tx::live_only`"))
    }

    @Test func aLiveOnlyOnLayoutTxStaysQuietThroughAScroll() {
        _ = perfWarnTakeLogForTests(newScope: true)
        let meter = PerfCommitMeter()
        for _ in 0..<20 {
            meter.handler("on_layout_tx", path: "#0/scroll/rows/r4", at: "commits_tests.rs:57:39")
            meter.frameEnds(scrolling: true, committed: false, instant: nil)
        }
        let log = perfWarnTakeLogForTests().filter { $0.contains("of a scroll") }
        #expect(log.isEmpty)
    }

    @Test func aWindowLayoutReadThroughAScrollNamesTheRead() {
        _ = perfWarnTakeLogForTests(newScope: true)
        let meter = PerfCommitMeter()
        for _ in 0..<20 {
            meter.read("window:r5", at: "commits_tests.rs:69:20")
            meter.frameEnds(scrolling: true, committed: true, instant: nil)
        }
        let log = perfWarnTakeLogForTests().filter { $0.contains("of a scroll") }
        #expect(log.count == 1)
        #expect(log[0].contains("`Cx::window_layout` read of \"r5\" at ") && log[0].contains("commits_tests.rs:") && log[0].contains("`Cx::layout_size`"))
    }

    @Test func hoverKeptInStateOnManyRowsWarnsOnceWithWhereItWasSet() {
        _ = perfWarnTakeLogForTests(newScope: true)
        let meter = PerfCommitMeter()
        for y in 0..<10 {
            meter.handler("on_hover_change", path: "#0/scroll/rows/r\(y)", at: "commits_tests.rs:83:27")
            meter.frameEnds(scrolling: false, committed: true, instant: nil)
        }
        let log = perfWarnTakeLogForTests().filter { $0.contains("for 8 elements") }
        #expect(log.count == 1)
        #expect(log[0].contains("`on_hover_change` set at ") && log[0].contains("commits_tests.rs:") && log[0].contains("`El::hover`"))
    }

    @Test func anAppSteppingItsOwnGlideWithInstantScrollsWarns() {
        _ = perfWarnTakeLogForTests(newScope: true)
        let meter = PerfCommitMeter()
        for _ in 0..<12 {
            meter.poll()
            meter.frameEnds(scrolling: false, committed: true, instant: "scroll")
        }
        let log = perfWarnTakeLogForTests().filter { $0.contains("an instant scroll") }
        #expect(log.count == 1)
        #expect(log[0].contains("\"scroll\"") && log[0].contains("scroll_to_with"))
    }

    @Test func instantScrollsWithNoCommitStayQuiet() {
        _ = perfWarnTakeLogForTests(newScope: true)
        let meter = PerfCommitMeter()
        for _ in 0..<12 {
            meter.frameEnds(scrolling: false, committed: false, instant: "scroll")
        }
        let log = perfWarnTakeLogForTests().filter { $0.contains("an instant scroll") }
        #expect(log.isEmpty)
    }
    #endif

    @Test func aBudgetLineNamesThePhaseThatTookMostAndWhyTheFrameCommitted() {
        let times = [9.0, 14.0, 3.0, 1.0, 0.0, 1.5]
        let line = perfBudgetReport(
            total: 14.2,
            budget: 8.0,
            times: times,
            why: ToolingCommitWhy.POLL,
            leftOut: 3
        )
        #expect(
            line == "rune: commit took 14.2 ms, over RUNE_COMMIT_BUDGET_MS=8: view 9.0, layout 3.0 (text 1.0), apply 1.5 ms; most in the view (63%); committed for poll (3 more over budget since the last line)"
        )
    }
}
