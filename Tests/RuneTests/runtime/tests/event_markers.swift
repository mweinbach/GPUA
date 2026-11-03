// Tests ported from: crates/rune/src/runtime/tests/event_markers.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

@testable import Rune
import RuneMotion
import Testing

private func rtEventMarkersView(_: Int, _: Cx<Int>) -> El {
    el().key("tap").size(40.0, 40.0).onPress { (n: inout Int, _) in n += 1 }
}

private func rtTap(_ rt: Runtime<Int>) {
    rt.pointerMove(20.0, 20.0)
    _ = rt.pointerDown(20.0, 20.0)
    rt.pointerUp(20.0, 20.0)
    _ = rt.frame(1.0 / 120.0)
}

private func rtPressMarkers(_ rt: Runtime<Int>) -> Int {
    rt.eventMarkers().filter { $0.kind == "press" && $0.detail == "tap" }.count
}

@Suite
struct RtEventMarkersTests {
    @Test
    func aLiveWindowRecordsNoInputMarkersUnlessTracing() {
        let rt = Runtime.new(0, rtEventMarkersView, (100.0, 100.0), Env.new(true, 1.0))
        rt.setEventMarkersEnabled(false)
        _ = rt.frame(0.0)
        rtTap(rt)
        #expect(rt.state == 1)
        #expect(rt.eventMarkers().isEmpty)

        _ = rt.startTrace()
        rtTap(rt)
        #expect(rt.state == 2)
        #expect(rtPressMarkers(rt) == 1)
    }

    @Test
    func unreadInputMarkersStayBounded() {
        let rt = Runtime.new(0, rtEventMarkersView, (100.0, 100.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)
        let taps = EventLog.capacity + 40
        for _ in 0..<taps {
            rtTap(rt)
        }
        #expect(rt.state == taps)
        let markers = rt.eventMarkers()
        #expect(markers.count <= EventLog.capacity)
        #expect(rtPressMarkers(rt) >= EventLog.capacity / 6)
        #expect(markers.contains(where: { $0.kind == "press" && $0.detail == "tap" }))
    }
}
