// Tests ported from: crates/rune/tests/instant_keeps_flight.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private struct FlightState {
    var wide: Bool = false
    var dim: Bool = false
    var label: String = "a"
}

private func flightView(_ s: FlightState, _: Cx<FlightState>) -> El {
    let grow = el().key("grow").h(40.0).w(s.wide ? 200.0 : 100.0).motion(Spring.new(0.3, 0.0))
        .opacity(s.dim ? 0.2 : 1.0)
    return row().wFull().hFull().child(grow).child(text(s.label).key("label"))
}

private func flightApp() -> Runtime<FlightState> {
    let rt = IntegrationSupport.runtime(FlightState(), flightView, (400.0, 200.0), Env.new(true, 1.0))
    _ = rt.hostFrame(0.0)
    return rt
}

private func flightWidth(_ rt: Runtime<FlightState>) -> Float {
    IntegrationSupport.find(rt, "grow").rect[2]
}

private func flightMidFlight() -> Runtime<FlightState> {
    let rt = flightApp()
    rt.hostUpdate { s, tx in
        tx.animated()
        s.wide = true
        s.dim = true
    }
    for _ in 0..<4 {
        _ = rt.hostFrame(1.0 / 60.0)
    }
    return rt
}

@Suite("InstantKeepsFlightIntegrationTests")
struct InstantKeepsFlightIntegrationTests {
    @Test func anInstantCommitLeavesAWidthAlreadySpringing() {
        let rt = flightMidFlight()
        let before = flightWidth(rt)
        #expect(before > 100.0 && before < 190.0, "mid-spring: \(before)")
        rt.hostUpdate { s, tx in
            tx.instant()
            s.label = "b"
        }
        _ = rt.hostFrame(1.0 / 60.0)
        let after = flightWidth(rt)
        #expect(after > before && after < 195.0, "still springing, not landed: \(before) -> \(after)")
        for _ in 0..<90 {
            _ = rt.hostFrame(1.0 / 60.0)
        }
        #expect(abs(flightWidth(rt) - 200.0) < 0.5)
    }

    @Test func anInstantCommitStillLandsWhatItChanges() {
        let rt = flightMidFlight()
        rt.hostUpdate { s, tx in
            tx.instant()
            s.wide = false
        }
        _ = rt.hostFrame(1.0 / 60.0)
        #expect(flightWidth(rt) == 100.0)
    }

    @Test func settleLandsMotionAlreadyRunning() {
        let rt = flightMidFlight()
        rt.hostUpdate { s, tx in
            tx.settle()
            s.label = "b"
        }
        _ = rt.hostFrame(1.0 / 60.0)
        #expect(flightWidth(rt) == 200.0)
    }
}
