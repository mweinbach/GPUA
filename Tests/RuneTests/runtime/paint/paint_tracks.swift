// Tests ported from: crates/rune/src/runtime/paint/tracks.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import RuneMotion
import Testing
@testable import Rune

@Suite("PaintTracksUnitTests")
struct PaintTracksUnitTests {
    @Test("readyFromRest allocates tracks lazily only when leaving rest value")
    func readyFromRestAllocatesLazily() {
        let scene = Scene()
        let id = RuneMotion.NodeId(42)
        scene.insert(id, NodeSpec(RuneMotion.Rect(0, 0, 10, 10)), .initial)

        #expect(!readyFromRest(scene, id, P_HOVER, 0.0, 0.0))
        #expect(!scene.store().has(id, P_HOVER))

        #expect(readyFromRest(scene, id, P_HOVER, 0.0, 1.0))
        #expect(scene.store().has(id, P_HOVER))
        #expect(scene.get(id, P_HOVER) == 0.0)
    }
}
