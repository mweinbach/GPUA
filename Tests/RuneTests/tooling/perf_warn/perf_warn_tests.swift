// Tests ported from: crates/rune/src/tooling/perf_warn/tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if !os(WASI)
import Foundation
#endif
import Testing
@testable import Rune

@Suite("PerfWarnTests", .serialized)
struct PerfWarnTests {
    private func stillView(_ n: UInt32, _ cx: Cx<UInt32>) -> El {
        _ = n
        _ = cx
        return col().size(200.0, 200.0).child(row().size(20.0, 20.0).bg(Color.WHITE))
    }

    private func titled<S>(
        _ state: S,
        _ view: @escaping (S, Cx<S>) -> El,
        title: String,
        poll: @escaping (inout S, Double, inout Tx) -> Bool
    ) -> Runtime<S> {
        let rt = Runtime(state, view, (200.0, 200.0), Env.new(true, 1.0))
        hostAttachment(for: rt).startWindowTitle(title)
        rt.poll = poll
        return rt
    }

    #if !os(WASI)
    @Test func aVirtualizeListThatBuildsFarMoreRowsThanItMountsWarnsOnce() {
        _ = perfWarnTakeLogForTests(newScope: true)
        perfWarnOverbuilt(path: "#0/overbuilt-rows", site: "tests.rs:10:50", built: 1000, mounted: 12)
        perfWarnOverbuilt(path: "#0/overbuilt-rows", site: "tests.rs:10:50", built: 1000, mounted: 12)
        let log = perfWarnTakeLogForTests()
        #expect(log.count == 1)
        #expect(log[0].contains("overbuilt-rows") && log[0].contains("virtual_rows") && log[0].contains("built 1000 rows"))
    }

    @Test func aShortVirtualizeListStaysQuiet() {
        _ = perfWarnTakeLogForTests(newScope: true)
        perfWarnOverbuilt(path: "#0/short-rows", site: "tests.rs:10:50", built: 150, mounted: 12)
        #expect(perfWarnTakeLogForTests().isEmpty)
    }

    @Test func aCallbackBlockedPastItsCpuTimeWarnsOncePerSite() {
        if perfRunqWaitMs() == nil && perfRunqOverloaded() {
            return
        }
        _ = perfWarnTakeLogForTests(newScope: true)
        for _ in 0..<2 {
            let stall = PerfStall.start()
            Thread.sleep(forTimeInterval: 0.07)
            stall.end { ("test-blocked", "`poll`") }
        }
        let log = perfWarnTakeLogForTests()
        #expect(log.count == 1)
        guard let first = log.first else { return }
        #expect(first.hasPrefix("rune: `poll` blocked ") && first.contains("on the main thread: move IO off it with `rune::Latest` or a thread"))
    }

    @Test func aCallbackThatComputesIsNotAStall() {
        _ = perfWarnTakeLogForTests(newScope: true)
        guard let cpu0 = toolingThreadCpuMs() else { return }
        let wall0 = RuneInstant.now()
        let stall = PerfStall.start()
        var acc: UInt64 = 1
        while (toolingThreadCpuMs() ?? 0.0) - cpu0 < 30.0 {
            acc = acc &* 6_364_136_223_846_793_005 &+ 1
        }
        withExtendedLifetime(acc) {}
        if wall0.elapsedSeconds() * 1000.0 > 30.0 * PERF_STALL_CPU_RATIO / 2.0 {
            return
        }
        stall.end { ("test-computing", "`poll`") }
        let quick = PerfStall.start()
        quick.end { ("test-quick", "`poll`") }
        #expect(perfWarnTakeLogForTests().isEmpty)
    }

    @Test func aBlockingPollNamesPoll() {
        if perfRunqWaitMs() == nil && perfRunqOverloaded() {
            return
        }
        _ = perfWarnTakeLogForTests(newScope: true)
        let rt = Runtime(UInt32(0), { _, _ in col() }, (100.0, 100.0), Env.new(true, 1.0))
        rt.poll = { _, _, _ in
            Thread.sleep(forTimeInterval: 0.07)
            return false
        }
        _ = rt.hostFrame(0.0)
        _ = rt.hostFrame(1.0 / 60.0)
        let log = perfWarnTakeLogForTests()
        #expect(log.count == 1 && log[0].hasPrefix("rune: `poll` blocked "))
    }

    @Test func rowsOfOneListShareAHandlerSite() {
        #expect(perfHandlerSite("on_press", "#0/list/r12") == perfHandlerSite("on_press", "#0/list/r7"))
        #expect(perfHandlerSite("on_press", "#0/list/r12") != perfHandlerSite("on_hover", "#0/list/r12"))
    }

    @Test func aPollThatAlwaysSaysChangedButChangesNothingWarnsAfter30Frames() {
        _ = perfWarnTakeLogForTests(newScope: true)
        let rt = titled(UInt32(0), stillView, title: "poll-noop") { n, _, _ in
            n += 1
            return true
        }
        for _ in 0..<29 {
            _ = rt.hostFrame(1.0 / 60.0)
        }
        #expect(perfWarnTakeLogForTests().isEmpty)
        for _ in 0..<40 {
            _ = rt.hostFrame(1.0 / 60.0)
        }
        let log = perfWarnTakeLogForTests()
        #expect(log.count == 1)
        #expect(
            log[0].hasPrefix("rune: `poll` of window \"poll-noop\" returned true but nothing changed")
            && log[0].contains("return true only when visible state changed")
        )
    }

    @Test func aPollThatChangesWhatShowsStaysQuiet() {
        _ = perfWarnTakeLogForTests(newScope: true)
        let rt = titled(
            UInt32(0),
            { n, _ in col().size(200.0, 200.0).child(text("tick \(n)")) },
            title: "poll-real"
        ) { n, _, tx in
            n += 1
            tx.wakeAfter(0.016)
            return true
        }
        for _ in 0..<300 {
            _ = rt.hostFrame(1.0 / 60.0)
        }
        #expect(perfWarnTakeLogForTests().isEmpty)
    }

    @Test func anEndless16MsWakeAfterLoopOnAnIdleWindowWarns() {
        _ = perfWarnTakeLogForTests(newScope: true)
        let rt = titled(UInt32(0), stillView, title: "idle-loop") { _, _, tx in
            tx.wakeAfter(0.016)
            return false
        }
        for _ in 0..<100 {
            _ = rt.hostFrame(1.0 / 60.0)
        }
        #expect(perfWarnTakeLogForTests().isEmpty)
        for _ in 0..<100 {
            _ = rt.hostFrame(1.0 / 60.0)
        }
        let log = perfWarnTakeLogForTests()
        #expect(log.count == 1)
        #expect(
            log[0].hasPrefix("rune: idle window \"idle-loop\" still drawing: check `wake_after` loops (120 frames in ")
            && log[0].contains("woken by a `wake_after` loop)")
        )
    }

    @Test func aWakeAfterLoopThatAlwaysSaysChangedNamesPollToo() {
        _ = perfWarnTakeLogForTests(newScope: true)
        let rt = titled(UInt32(0), stillView, title: "idle-poll-loop") { _, _, tx in
            tx.wakeAfter(0.016)
            return true
        }
        for _ in 0..<200 {
            _ = rt.hostFrame(1.0 / 60.0)
        }
        let log = perfWarnTakeLogForTests()
        #expect(log.count == 2)
        #expect(log[0].contains("`poll` of window \"idle-poll-loop\" returned true"))
        #expect(log[1].contains("woken by a `wake_after` loop whose `poll` returns true"))
    }

    @Test func aWakeAfterLoopThatStopsStaysQuiet() {
        _ = perfWarnTakeLogForTests(newScope: true)
        let rt = titled(UInt32(0), stillView, title: "loop-stops") { n, _, tx in
            n += 1
            if n < 100 {
                tx.wakeAfter(0.016)
            }
            return false
        }
        for _ in 0..<400 {
            _ = rt.hostFrame(1.0 / 60.0)
        }
        #expect(perfWarnTakeLogForTests().isEmpty)
    }

    @Test func aWakeAfterLoopUnderRunningMotionStaysQuiet() {
        _ = perfWarnTakeLogForTests(newScope: true)
        func springView(_ x: Float, _ cx: Cx<Float>) -> El {
            _ = cx
            return col().size(200.0, 200.0).child(
                row().key("box").size(20.0, 20.0).pgAbsolute(x, 0.0).bg(Color.WHITE)
                    .motion(Spring.new(3.0, 0.0))
            )
        }
        let rt = titled(Float(0.0), springView, title: "spring-moving") { _, clock, tx in
            if clock < 2.5 {
                tx.wakeAfter(0.016)
            }
            return false
        }
        _ = rt.hostFrame(0.0)
        rt.update { x, _ in x = 150.0 }
        rt.hostInvalidate()
        var moving = 0
        for _ in 0..<150 {
            if rt.hostFrame(1.0 / 60.0).2.animating {
                moving += 1
            }
        }
        #expect(moving >= 140)
        for _ in 0..<100 {
            _ = rt.hostFrame(1.0 / 60.0)
        }
        #expect(perfWarnTakeLogForTests().isEmpty)
    }

    @Test func aMemoOverADifferentlyKeyedRootWarnsOncePerSite() {
        _ = perfWarnTakeLogForTests(newScope: true)
        perfWarnMemoKeyReplaced(id: "same", existing: "same", site: "tests.rs:203:1")
        perfWarnMemoKeyReplaced(id: "outer", existing: "inner", site: "tests.rs:204:1")
        perfWarnMemoKeyReplaced(id: "outer", existing: "inner", site: "tests.rs:204:1")
        let log = perfWarnTakeLogForTests()
        #expect(log.count == 1)
        #expect(log[0].contains("\"outer\"") && log[0].contains("\"inner\""))
    }
    #endif

    @Test func aSlowLaunchNamesItsSlowestPartAndRunesOwnTimeStaysQuiet() {
        #expect(perfLaunchReport(setup: 5.0, initMs: 40.0, view: 20.0, total: 400.0) == nil)
        let message = perfLaunchReport(setup: 10.0, initMs: 180.0, view: 12.0, total: 260.0)
        #expect(
            message == "first frame took 260 ms (setup 10 ms, init 180 ms, first view 12 ms, window and GPU 58 ms); the slowest is `init`: start slow work from `on_ready`"
        )
        #expect(perfLaunchReport(setup: 150.0, initMs: 0.0, view: 0.0, total: 200.0)?.contains("the slowest is setup in `main` before `run`") == true)
    }
}
