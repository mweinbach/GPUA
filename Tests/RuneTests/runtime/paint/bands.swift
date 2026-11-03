// Tests ported from: crates/rune/src/runtime/paint/bands.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("PaintBandsUnitTests")
struct PaintBandsUnitTests {
    @Test("pushBandSplit keeps small boxes whole and splits large interiors into 4 edge bands")
    func pushBandSplitSplitsOnlyLargeHoles() {
        var inst = Instance()
        inst.rect = [0.0, 0.0, 60.0, 60.0]

        var smallOut: [Instance] = []
        pushBandSplit(&smallOut, inst, [4.0, 4.0, 56.0, 56.0], 2.0)
        #expect(smallOut.count == 1)
        #expect(smallOut[0].uv == [0.0, 0.0, 0.0, 0.0])

        var largeInst = Instance()
        largeInst.rect = [0.0, 0.0, 300.0, 300.0]
        var largeOut: [Instance] = []
        pushBandSplit(&largeOut, largeInst, [10.0, 10.0, 290.0, 290.0], 4.0)
        #expect(largeOut.count == 4)
        #expect(largeOut.allSatisfy { $0.uv[2] < 0.0 })
    }
}
