// Tests ported from: crates/rune/src/platform/display_link.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("DisplayLinkTests")
struct DisplayLinkTests {
    @Test("a frame defers starting the link only when it would draw at once anyway")
    func frameDefersStartingLinkOnlyWhenItWouldDrawAtOnceAnyway() {
        let t = RuneInstant.now()
        let ms: (Int64) -> RuneInstant = { n in t.adding(.milliseconds(n)) }
        let period = Duration.milliseconds(8)
        // A timer 33 ms after the last frame: whenever it starts the link, it draws at once.
        #expect(displayLinkDefersStart(false, ms(100), ms(104), ms(133), period))
        for later: Int64 in [133, 134, 150, 500] {
            #expect(displayLinkOpportunity(nil, ms(100), ms(104), ms(later), period) == .now)
        }
        #expect(displayLinkDefersStart(false, nil, nil, ms(0), period))
        // The last frame may still be queued: start the link now and wait for its tick.
        #expect(!displayLinkDefersStart(false, ms(100), ms(100), ms(105), period))
        #expect(!displayLinkDefersStart(false, ms(100), ms(130), ms(120), period))
        // A running link already paces the surface.
        #expect(!displayLinkDefersStart(true, ms(100), ms(104), ms(133), period))
    }

    @Test("late frames and idle restarts cannot catch up in a burst")
    func lateFramesAndIdleRestartsCannotCatchUpInABurst() {
        let t = RuneInstant.now()
        let ms: (Int64) -> RuneInstant = { n in t.adding(.milliseconds(n)) }
        let period = Duration.milliseconds(16)
        #expect(displayLinkPermits(nil, nil, ms(16), ms(1), period))
        #expect(!displayLinkPermits(ms(15), ms(16), ms(32), ms(17), period))
        #expect(!displayLinkPermits(ms(15), ms(16), ms(32), ms(33), period))
        #expect(!displayLinkPermits(ms(15), ms(32), ms(32), ms(30), period))
        #expect(displayLinkPermits(ms(15), ms(16), ms(32), ms(30), period))
        #expect(!displayLinkPermits(ms(100), ms(112), ms(128), ms(102), period))
        #expect(displayLinkTargetTime(t, hostNow: 100, hostTarget: 116, frequency: 1000.0) == ms(16))
        #expect(displayLinkTargetTime(ms(32), hostNow: 132, hostTarget: 116, frequency: 1000.0) == ms(16))
    }

    @Test("a capped period skips ticks between frames")
    func cappedPeriodSkipsTicksBetweenFrames() {
        let t = RuneInstant.now()
        let ms: (Int64) -> RuneInstant = { n in t.adding(.milliseconds(n)) }
        let capped = Duration.milliseconds(16)
        #expect(!displayLinkPermits(ms(0), ms(8), ms(16), ms(9), capped))
        #expect(displayLinkPermits(ms(2), ms(8), ms(24), ms(17), capped))
        #expect(displayLinkPermits(ms(2), ms(8), ms(16), ms(9), .milliseconds(8)))
    }

    @Test("input at rest draws without waiting for a tick")
    func inputAtRestDrawsWithoutWaitingForATick() {
        let t = RuneInstant.now()
        let ms: (Int64) -> RuneInstant = { n in t.adding(.milliseconds(n)) }
        let period = Duration.milliseconds(8)
        // The link just started after idle: no tick yet, the last frame long gone.
        #expect(displayLinkOpportunity(nil, ms(0), ms(8), ms(500), period) == .now)
        #expect(displayLinkOpportunity(nil, nil, nil, ms(0), period) == .now)
        // A stale tick after a stall doesn't hold a rested surface either.
        #expect(displayLinkOpportunity(ms(400), ms(0), ms(8), ms(500), period) == .now)
        // A fresh tick keeps its target.
        #expect(displayLinkOpportunity(ms(510), ms(0), ms(8), ms(500), period) == .tick(ms(510)))
    }

    @Test("a frame still on its way to the display waits for a tick")
    func frameStillOnItsWayToTheDisplayWaitsForATick() {
        let t = RuneInstant.now()
        let ms: (Int64) -> RuneInstant = { n in t.adding(.milliseconds(n)) }
        let period = Duration.milliseconds(8)
        // Submitted under a refresh and a half ago: it may still be queued.
        #expect(displayLinkOpportunity(nil, ms(100), ms(100), ms(111), period) == .wait)
        #expect(displayLinkOpportunity(nil, ms(100), ms(100), ms(112), period) == .now)
        // Its target hasn't passed.
        #expect(displayLinkOpportunity(nil, ms(100), ms(130), ms(120), period) == .wait)
        // A Low Power cap stretches the period, and with it the rest.
        #expect(displayLinkOpportunity(nil, ms(100), ms(100), ms(118), .milliseconds(16)) == .wait)
        // While moving, a rejected tick right after a frame waits for the next one.
        #expect(displayLinkOpportunity(ms(116), ms(100), ms(108), ms(102), period) == .wait)
    }
}
