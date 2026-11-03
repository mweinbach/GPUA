// Tests ported from: crates/rune/src/frame/surface_stats.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("Rune Frame Surface Stats Tests")
struct RuneFrameSurfaceStatsTests {
    private func makeMeter() -> (SurfaceMeter, RuneInstant) {
        let m = SurfaceMeter.new("main", SharedSurfaceStats())
        return (m, m.started)
    }

    @Test("rates are per second over the last window and go stale")
    func ratesArePerSecondOverTheLastWindowAndGoStale() {
        var (meter, start) = makeMeter()
        for _ in 0..<120 {
            meter.redraw(true)
            meter.presented()
        }
        for _ in 0..<3 {
            meter.failed(.timeout)
        }
        meter.skipped()
        meter.turn(false, false)
        meter.turn(true, false)
        meter.setPacing(.displayLink)

        #expect(meter.shared().withLock { $0.perSecond } == SurfaceCounts())
        #expect(meter.tick(start.adding(.milliseconds(1000))) == nil)

        var stats = meter.shared().withLock { $0 }
        #expect(stats.name == "main")
        #expect((stats.perSecond.redraws, stats.perSecond.unpaced, stats.perSecond.presents) == (120, 0, 120))
        #expect((stats.perSecond.timeouts, stats.perSecond.failed(), stats.perSecond.skipped) == (3, 3, 1))
        #expect((stats.perSecond.turns, stats.perSecond.wakes) == (2, 1))
        #expect(stats.pacing == .displayLink)
        #expect(stats.totals.presents == 120)

        // Half the work over the next two seconds: rates are per second, totals keep counting.
        for _ in 0..<60 {
            meter.redraw(false)
            meter.presented()
        }
        _ = meter.tick(start.adding(.milliseconds(3000)))
        stats = meter.shared().withLock { $0 }
        #expect((stats.perSecond.redraws, stats.perSecond.unpaced, stats.perSecond.presents) == (30, 30, 30))
        #expect((stats.totals.redraws, stats.totals.presents) == (180, 180))
        #expect(meter.totals() == stats.totals)

        let fresh = stats.aged(start.adding(.milliseconds(4000)))
        #expect(fresh.perSecond.presents == 30)
        let stale = stats.aged(start.adding(.milliseconds(5500)))
        #expect(stale.perSecond == SurfaceCounts())
        #expect(stale.totals.presents == 180)
    }

    @Test("totals and pacing publish at once")
    func totalsAndPacingPublishAtOnce() {
        var (meter, _) = makeMeter()
        meter.setPacing(.displayLink)
        #expect(readSurfaceStats(meter.shared()).pacing == .displayLink)
        for _ in 0..<3 {
            meter.redraw(true)
            meter.presented()
        }
        meter.setPacing(.idle)
        let stats = readSurfaceStats(meter.shared())
        #expect((stats.totals.redraws, stats.totals.presents) == (3, 3))
        #expect(stats.pacing == .idle)
        #expect(stats.perSecond == SurfaceCounts())
        #expect(stats.summary().contains("totals 3 presents"))
    }

    @Test("only redraws that waited for nothing are unpaced")
    func onlyRedrawsThatWaitedForNothingAreUnpaced() {
        var (meter, _) = makeMeter()
        meter.redraw(true)
        #expect(meter.totals().unpaced == 0)
        meter.waited()
        meter.redraw(false)
        #expect(meter.totals().unpaced == 0)
        meter.turn(true, true)
        meter.redraw(false)
        #expect(meter.totals().unpaced == 0)
        meter.turn(true, false)
        meter.redraw(false)
        #expect(meter.totals().unpaced == 1)
        meter.waited()
        meter.redraw(true)
        meter.redraw(false)
        #expect(meter.totals().unpaced == 2)
    }

    @Test("the guard warns once after two seconds of spinning")
    func guardWarnsOnceAfterTwoSecondsOfSpinning() throws {
        var (meter, start) = makeMeter()
        let at: (Int64) -> RuneInstant = { start.adding(.milliseconds($0)) }
        let spin: (inout SurfaceMeter, Int) -> Void = { m, n in
            for _ in 0..<n {
                m.redraw(true)
                m.failed(.occluded)
            }
        }
        meter.setPacing(.failed(-6661))
        spin(&meter, 5000)
        #expect(meter.tick(at(1000)) == nil)
        spin(&meter, 5000)
        let firstSpinWarning = meter.tick(at(2000))
        let warning = try #require(firstSpinWarning)
        #expect(warning.contains("main") && warning.contains("5000 failed acquires/s") && warning.contains("occluded 5000"))
        #expect(warning.contains("display link failed (-6661)"))
        spin(&meter, 5000)
        #expect(meter.tick(at(3000)) == nil)

        // Unpaced redraws spin too; a calm second in between resets the streak.
        var (meter2, start2) = makeMeter()
        let at2: (Int64) -> RuneInstant = { start2.adding(.milliseconds($0)) }
        let unpaced: (inout SurfaceMeter, Int) -> Void = { m, n in
            for _ in 0..<n {
                m.redraw(false)
                m.presented()
            }
        }
        unpaced(&meter2, 1000)
        #expect(meter2.tick(at2(1000)) == nil)
        unpaced(&meter2, 60)
        #expect(meter2.tick(at2(2000)) == nil)
        unpaced(&meter2, 1000)
        #expect(meter2.tick(at2(3000)) == nil)
        unpaced(&meter2, 1000)
        let secondSpinWarning = meter2.tick(at2(4000))
        let w2 = try #require(secondSpinWarning)
        #expect(w2.contains("1000 redraws/s (1000 unpaced)"))

        // A display's own rate, even 360 Hz, never trips it.
        var (meter3, start3) = makeMeter()
        for second in 1...5 {
            unpaced(&meter3, 360)
            #expect(meter3.tick(start3.adding(.seconds(Int64(second)))) == nil)
        }
    }
}
