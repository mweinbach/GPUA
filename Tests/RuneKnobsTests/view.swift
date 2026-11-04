// Tests ported from: crates/rune-knobs/src/view.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Rune
import Testing
@testable import RuneKnobs

extension RuneKnobsSerializedSuites {
@Suite("RuneKnobs view unit tests", .serialized)
@MainActor
struct RuneKnobsViewUnitTests {
    private struct ViewHost {
        var knobs = Knobs()
        var fired = 0
    }

    @Test("region_at_picks_smallest_enclosing_region")
    func regionAtPicksSmallestEnclosingRegion() {
        let rects: [(String, [Float])] = [
            ("Outer", [0.0, 0.0, 500.0, 500.0]),
            ("Inner", [100.0, 100.0, 120.0, 120.0]),
            ("Right", [500.0, 0.0, 300.0, 500.0]),
        ]
        #expect(regionAt(rects, 150.0, 150.0) == "Inner")
        #expect(regionAt(rects, 50.0, 50.0) == "Outer")
        #expect(regionAt(rects, 600.0, 250.0) == "Right")
        #expect(regionAt(rects, 900.0, 900.0) == nil)
    }

    @Test("keypath_and_knobs_access_overloads_mount_layer_and_inline_actions")
    func keypathAndKnobsAccessOverloadsMountLayerAndInlineActions() {
        let k0 = Knob.new("Pad", 0.0, 20.0, 10.0)
        let groups = [
            Group.new("Main", "main", [k0])
        ]
        var host = ViewHost()
        host.knobs.show()
        let access = knobsAccess(\ViewHost.knobs)
        let rt = Runtime.new(
            host,
            { s, _ in
                col().key("main").wFull().hFull()
                    .child(inline(s.knobs, groups, Style.dark(), \ViewHost.knobs, true))
                    .child(actions(Style.dark(), [Action("P", "Ping") { (s: inout ViewHost, _) in s.fired += 1 }]))
                    .child(layer(s.knobs, groups, Style.dark(), access))
            },
            (800.0, 600.0),
            Env.new(true, 1.0)
        )
        _ = rt.frame(0.0)
        #expect(rt.find("knobs-actions") != nil)
        #expect(rt.click("knobs-action-0"))
        _ = rt.frame(1.0 / 60.0)
        #expect(rt.state.fired == 1)
    }
}
}
