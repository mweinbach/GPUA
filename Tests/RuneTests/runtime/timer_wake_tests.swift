// Tests ported from: crates/rune/src/runtime/timer_wake_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private let timerPeriod: Double = 5.0

private struct TimerAppState {
    var polls: UInt32 = 0
    var changeAt: UInt32 = 0
    var step: Bool = false
    var width: Float = 0.0
}

private func timerView(_ s: TimerAppState, _ cx: Cx<TimerAppState>) -> El {
    _ = cx
    return col().children([
        rtAnimateLayout(el().key("box").size(10.0 + s.width, 8.0))
    ])
}

private func makeTimerRuntime(_ app: TimerAppState = TimerAppState()) -> Runtime<TimerAppState> {
    let rt = Runtime.new(app, timerView, (200.0, 50.0), Env())
    rt.poll = { s, _, tx in
        s.polls += 1
        tx.wakeAfter(s.step ? 0.0 : timerPeriod)
        return s.step || s.polls == s.changeAt
    }
    _ = rt.frame(0.0)
    #expect(!rt.animating)
    return rt
}

@Suite("RuntimeTimerWakeTests")
struct RuntimeTimerWakeTests {
    @Test("A resting window's timer commits view only when poll reports a change")
    func restingTimerCommitsOnlyWhenPollChangedSomething() {
        let rt = makeTimerRuntime()
        let initialPolls = rt.state.polls
        rt.state.changeAt = initialPolls + 9

        for _ in 0..<8 {
            let delay = rt.nextWakeAfter() ?? timerPeriod
            _ = rt.frame(delay + 1e-4)
            #expect(rt.stats.commits == 0)
        }
        #expect(rt.state.polls == initialPolls + 8)
        guard let deadline = rt.wakeDeadline() else {
            Issue.record("Expected armed wake deadline")
            return
        }
        #expect(deadline > rt.clock)

        // The 9th wake returns `true` from `poll` and commits the view exactly once
        var committedFrames = 0
        for _ in 0..<6 {
            let delay = rt.nextWakeAfter() ?? timerPeriod
            _ = rt.frame(delay + 1e-4)
            if rt.stats.commits > 0 {
                committedFrames += 1
                #expect(rt.stats.commits == 1)
            }
        }
        #expect(committedFrames == 1)
        #expect(rt.state.polls == initialPolls + 14)
    }

    @Test("A poll stepping every frame with wakeAfter(0) schedules an immediate wake every frame")
    func pollSteppingEveryFrameDrawsEveryFrame() {
        let rt = makeTimerRuntime(TimerAppState(step: true))
        let startPolls = rt.state.polls
        for _ in 0..<10 {
            #expect(rt.nextWakeAfter() == 0.0)
            _ = rt.frame(1.0 / 60.0)
            #expect(rt.stats.commits == 1)
        }
        #expect(rt.state.polls - startPolls == 10)

        // Even when `poll` returns `false`, `tx.wakeAfter(0.0)` still arms an immediate wake
        rt.poll = { s, _, tx in
            s.polls += 1
            tx.wakeAfter(0.0)
            return false
        }
        for _ in 0..<5 {
            _ = rt.frame(1.0 / 60.0)
            #expect(rt.nextWakeAfter() == 0.0)
            #expect(rt.stats.commits == 0)
        }
    }

    @Test("Motion in flight keeps animating while preserving armed poll deadline")
    func motionInFlightTakesTimerFrame() {
        let rt = makeTimerRuntime()
        rt.update { s, _ in s.width = 120.0 }
        _ = rt.frame(1.0 / 60.0)
        #expect(rt.animating)
        #expect(rt.wakeDeadline() != nil)
    }

    @Test("TimerWakeQueue fires due deadlines in order and coalesces sub-0.1ms duplicates")
    func timerWakeQueueOrderingAndCoalescing() {
        var queue = TimerWakeQueue()
        queue.schedule(now: 10.0, after: 0.5)
        queue.schedule(now: 10.0, after: 0.50002) // coalesced within 0.1 ms
        queue.schedule(now: 10.0, after: 0.1)
        #expect(queue.deadlines.count == 2)
        #expect(abs(queue.deadlines[0] - 10.1) < 1e-9)
        #expect(abs(queue.deadlines[1] - 10.5) < 1e-9)

        let firedEarly = queue.fireDue(now: 10.05)
        #expect(!firedEarly)
        let firedOnTime = queue.fireDue(now: 10.1)
        #expect(firedOnTime)
        #expect(queue.deadlines.count == 1)
        #expect(abs((queue.nextWakeDelay(now: 10.2) ?? 0.0) - 0.3) < 1e-9)
    }
}
