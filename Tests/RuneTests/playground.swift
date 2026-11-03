// Tests ported from: crates/rune/src/playground.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("PlaygroundUnitTests")
struct PlaygroundUnitTests {
    @Test func splitSeparatesGroupAndStoryName() {
        let a = playgroundSplit("Motion/Fade", "Pages")
        #expect(a.0 == "Motion" && a.1 == "Fade")

        let b = playgroundSplit("Controls/Input/Text", "Pages")
        #expect(b.0 == "Controls/Input" && b.1 == "Text")

        let c = playgroundSplit("Lab", "Pages")
        #expect(c.0 == "Pages" && c.1 == "Lab")
    }

    @Test func slugMatchesFoldStorageNormalization() {
        #expect(playgroundSlug("Motion") == "motion")
        #expect(playgroundSlug("Controls / Input") == "controls-input")
        #expect(playgroundSlug("A--B__C") == "a-b-c")
    }

    @Test func widthsClampAndReset() {
        let clamped = playgroundClampPair(50.0, 900.0, 1200.0)
        #expect(clamped.0 == PLAYGROUND_SIDEBAR_MIN)
        #expect(clamped.1 == PLAYGROUND_SIDE_MAX)

        let controls = PlaygroundControls()
        controls.setWidths(50.0, 900.0)
        #expect(controls.sidebarW == PLAYGROUND_SIDEBAR_MIN && controls.sideW == PLAYGROUND_SIDE_MAX)
    }
}
