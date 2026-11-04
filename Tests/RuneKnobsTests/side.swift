// Tests ported from: crates/rune-knobs/src/side.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Rune
import Testing
@testable import RuneKnobs

extension RuneKnobsSerializedSuites {
@Suite("RuneKnobs side unit tests", .serialized)
@MainActor
struct RuneKnobsSideUnitTests {
    private struct Host {
        var knobs = Knobs()
    }

    @Test("section_and_node_keys_match_side_hierarchy")
    func sectionAndNodeKeysMatchSideHierarchy() {
        let k0 = Knob.new("Size", 0.0, 10.0, 5.0)
        let groups = [
            Group.new("Header", "hdr", [k0]).under("Page A"),
            Group.new("Dock", "dock", [k0]),
        ]
        #expect(sectionKey(1) == "knobs-sec-1")
        #expect(nodeKey(.page("Page A"), groups) == "knobs-page-0")
        #expect(nodeKey(.group(1), groups) == "knobs-sec-1/head")
        #expect(nodeKey(.knob(0, 0), groups) == "knobs-sec-0/body/knobs-card/knobs-knob-0")

        var host = Host()
        host.knobs.show()
        let rt = Runtime.new(
            host,
            { s, _ in
                side(el().key("hdr").wFull().hFull(), s.knobs, groups, Style.dark(), \Host.knobs)
            },
            (800.0, 600.0),
            Env.new(true, 1.0)
        )
        _ = rt.frame(0.0)
        #expect(rt.find("knobs-panel") != nil)
    }
}
}
