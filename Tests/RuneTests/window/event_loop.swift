// Tests ported from: crates/rune/src/window/event_loop.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("WindowEventLoopTests")
struct WindowEventLoopTests {
    @Test("computeControlFlow exits when no host is alive and picks earliest deadline otherwise")
    func computeControlFlowExitsWhenEmptyAndPicksEarliestDeadline() {
        #expect(computeControlFlow(hosts: []) == .exit)

        let spec = AppSpec<Int>("w", (200.0, 100.0), { 0 }, { _, _ in el() })
        let host = App.new(spec).buildHost()
        let loop = startAll([host])
        let t0 = RuneInstant.now()
        #expect(computeControlFlow(hosts: [host], now: t0) == .wait)

        host.rt.hostUpdate { _, tx in tx.wakeAfter(0.25) }
        _ = host.rt.hostSchedulePendingWakes()
        let flow = computeControlFlow(hosts: [host], now: t0)
        if case .waitUntil(let at) = flow {
            #expect(at > t0)
        } else {
            Issue.record("expected .waitUntil, got \(flow)")
        }
        loop.shutdown()
    }
}
