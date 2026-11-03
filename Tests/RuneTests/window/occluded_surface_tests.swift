// Tests ported from: crates/rune/src/window/occluded_surface_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("WindowOccludedSurfaceTests")
struct WindowOccludedSurfaceTests {
    @Test("an occluded surface backs off without failed drawables and draws once visible")
    func anOccludedSurfaceBacksOffAndDrawsOnceVisible() {
        let spec = AppSpec<Int>("occluded", (100.0, 100.0), { 0 }, { _, _ in el().size(100.0, 100.0).bg(.WHITE) })
        let host = App.new(spec).buildHost()
        let loop = startAll([host])
        guard let win = host.win else {
            Issue.record("expected host window")
            return
        }

        // Initial visible draw
        let drawsBefore = win.drawCount
        win.occluded = true
        host.rt.hostSetLiveVisible(false)

        var retryState: Duration? = nil
        var checks: UInt64 = 0
        for _ in 0..<20 {
            let status = win.nextAcquireStatus()
            let res = resolveSurfaceAcquire(
                status,
                retryAcquire: { .occluded },
                reconfigure: {},
                meter: &win.surfaceMeter
            )
            #expect(res == Result<Bool, WindowMissed>.failure(.occluded))
            _ = nextOccludedRetry(&retryState)
            checks += 1
        }
        #expect(win.surfaceMeter.snapshot().counts.occluded == checks)
        #expect(win.drawCount == drawsBefore)
        #expect(retryState == OCCLUDED_MAX)

        // Uncovered: draws again
        win.occluded = false
        host.rt.hostSetLiveVisible(true)
        host.rt.hostInvalidate()
        _ = host.drawWindow()
        #expect(win.drawCount == drawsBefore + 1)
        loop.shutdown()
    }

    @Test("suboptimal acquire reconfigures once and retries")
    func suboptimalAcquireReconfiguresOnceAndRetries() {
        var meter = WindowSurfaceMeter()
        var reconfigs = 0
        let ok = resolveSurfaceAcquire(
            .suboptimal,
            retryAcquire: { .good },
            reconfigure: { reconfigs += 1 },
            meter: &meter
        )
        #expect(ok == Result<Bool, WindowMissed>.success(false))
        #expect(reconfigs == 1)
        #expect(meter.snapshot().counts.reconfigured == 1)
    }
}
