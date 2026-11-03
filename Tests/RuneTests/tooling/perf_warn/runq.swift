// Tests ported from: crates/rune/src/tooling/perf_warn/runq.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("PerfWarnRunqTests")
struct PerfWarnRunqTests {
    @Test func aWaitForACoreIsNotBlocking() {
        #expect(perfRunqBlockedMs(wall: 36.0, cpu: 0.5, wait: 35.0, loaded: false) == nil)
        #expect(perfRunqBlockedMs(wall: 36.0, cpu: 0.5, wait: 10.0, loaded: false) == 26.0)
    }

    @Test func realBlockingStillWarns() {
        #expect(perfRunqBlockedMs(wall: 30.0, cpu: 0.0, wait: 0.0, loaded: false) == 30.0)
        #expect(perfRunqBlockedMs(wall: 30.0, cpu: 0.0, wait: nil, loaded: false) == 30.0)
    }

    @Test func computingIsNotBlocking() {
        #expect(perfRunqBlockedMs(wall: 50.0, cpu: 40.0, wait: 0.0, loaded: false) == nil)
    }

    @Test func withoutAWaitALoadedMachineIsForgiven() {
        #expect(perfRunqBlockedMs(wall: 36.0, cpu: 0.5, wait: nil, loaded: true) == nil)
        #expect(perfRunqBlockedMs(wall: 36.0, cpu: 0.5, wait: 0.0, loaded: true) == 36.0)
    }

    @Test func theWaitNeverExceedsTheWall() {
        #expect(perfRunqBlockedMs(wall: 20.0, cpu: 0.0, wait: 99.0, loaded: false) == nil)
    }
}
