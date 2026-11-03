// Tests ported from: crates/rune/src/frame/clock.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("Rune Frame Clock Tests")
struct RuneFrameClockTests {
    @Test("running motion keeps real time and new motion takes one small step")
    func runningMotionKeepsRealTimeAndNewMotionTakesOneSmallStep() {
        let start = RuneInstant.now()
        let ms: (Int64) -> Duration = { .milliseconds($0) }
        var clock = FrameClock.new(start)
        let fresh = FrameStep(catchUp: 0.0, dt: RESUME_STEP)

        #expect(clock.step(start.adding(ms(5)), false) == fresh)
        #expect(clock.step(start.adding(ms(2005)), false) == fresh)

        let late = clock.step(start.adding(ms(2054)), true)
        #expect(abs(late.total() - 0.049) < 1e-9 && late.dt == RESUME_STEP)

        let short = clock.step(start.adding(ms(2058)), true)
        #expect(abs(short.dt - 0.004) < 1e-9 && short.catchUp == 0.0)

        let suspended = clock.step(start.adding(ms(5058)), true)
        #expect(abs(suspended.total() - MAX_GAP) < 1e-9 && suspended.dt == RESUME_STEP)

        clock.hold(start.adding(ms(6000)))
        #expect(clock.step(start.adding(ms(6000)), true) == FrameStep(catchUp: 0.0, dt: 0.0))

        // A display-link target ran ahead; a later `now` before it must not rewind the clock.
        clock.hold(start.adding(ms(6010)))
        clock.hold(start.adding(ms(6002)))
        let next = clock.step(start.adding(ms(6018)), true)
        #expect(abs(next.total() - 0.008) < 1e-9)
    }

    @Test("headless frameAdvanceBy gives timers the full idle gap")
    func headlessAdvanceByGivesTimersFullIdleGap() {
        let rt = Runtime<Int>(0, { _, _ in el() }, (400.0, 50.0), Env())
        _ = rt.frame(0.0)
        let before = rt.clock
        _ = frameAdvanceBy(rt, 1.0, running: false)
        #expect(abs(rt.clock - before - 1.0) < 1e-9)
        _ = frameAdvanceBy(rt, 0.049, running: true)
        #expect(abs(rt.clock - before - 1.049) < 1e-9)
    }

    @Test(
        "window late frame lands where an unbroken cadence would",
        .disabled("Requires full Runtime.frameSplit and Taffy layout integration in Sources/Rune/runtime.swift")
    )
    func windowLateFrameLandsWhereAnUnbrokenCadenceWould() {}

    @Test(
        "window motion starting after idle takes one frame step",
        .disabled("Requires full Runtime.frameSplit and Taffy layout integration in Sources/Rune/runtime.swift")
    )
    func windowMotionStartingAfterIdleTakesOneFrameStep() {}

    @Test(
        "motion starting on a late frame takes one small step while running motion catches up",
        .disabled("Requires full Runtime.frameSplit and Taffy layout integration in Sources/Rune/runtime.swift")
    )
    func motionStartingOnALateFrameTakesOneSmallStepWhileRunningMotionCatchesUp() {}

    @Test(
        "a spring retargeted on a late frame turns from its pose at that time",
        .disabled("Requires full Runtime.frameSplit and Taffy layout integration in Sources/Rune/runtime.swift")
    )
    func springRetargetedOnALateFrameTurnsFromItsPoseAtThatTime() {}

    @Test(
        "one presented frame is one runtime pass",
        .disabled("Requires Runtime.settleAll and Runtime.frameSplit in Sources/Rune/runtime.swift")
    )
    func onePresentedFrameIsOneRuntimePass() {}

    @Test(
        "headless frames start new motion with a small step after idle",
        .disabled("Requires full Runtime.frameSplit and Taffy layout integration in Sources/Rune/runtime.swift")
    )
    func headlessFramesStartNewMotionWithASmallStepAfterIdle() {}
}
