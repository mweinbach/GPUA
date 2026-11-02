// Tests ported from: crates/procwatch/src/gauge.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Procwatch

private let testGaugeA = Gauge.new("test.a")
private let testGaugeB = Gauge.new("test.b")

@Suite("Procwatch Gauge Tests")
struct ProcwatchGaugeTests {
    @Test func leases_add_and_give_back() {
        if !gaugesOn {
            testGaugeA.add(1000)
            #expect(testGaugeA.get() == 0)
            #expect(gauges().isEmpty)
            return
        }
        let lease = testGaugeA.track(1000)
        testGaugeA.add(24)
        testGaugeB.set(5)
        let listed = gauges()
        #expect(listed.first(where: { $0.0 == "test.a" })?.1 == 1024)
        #expect(listed.first(where: { $0.0 == "test.b" })?.1 == 5)
        lease.drop()
        testGaugeA.sub(24)
        #expect(testGaugeA.get() == 0)
        // Registered once, however often it's used.
        testGaugeA.add(1)
        testGaugeA.sub(1)
        #expect(gauges().filter({ $0.0 == "test.a" }).count == 1)
    }
}
