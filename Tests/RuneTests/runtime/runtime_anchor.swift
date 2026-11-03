// Tests ported from: crates/rune/src/runtime/anchor.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("RuntimeAnchorUnitTests")
struct RuntimeAnchorUnitTests {
    @Test("resolveAnchoredOverlay flips side when tight, honors unscaled flag, and fits within viewport")
    func resolveAnchoredOverlayFlipsAndScales() {
        let bottomAnchor = Anchor(key: "trig", side: .bottom, align: .start, gap: 6.0)
        // Trigger near bottom of 300x200 viewport -> flips to `.top`
        let flipped = resolveAnchoredOverlay(
            bottomAnchor,
            triggerBounds: [40.0, 150.0, 100.0, 180.0],
            triggerScale: 1.0,
            measuredSize: (80.0, 60.0),
            viewport: (300.0, 200.0)
        )
        #expect(flipped.side == .top)
        #expect(abs(flipped.y - 84.0) < 1e-3)

        // Unscaled overlay keeps `scale == 1.0` even when trigger is zoomed 2x
        var unscaled = bottomAnchor
        unscaled.unscaled = true
        let unscaledRes = resolveAnchoredOverlay(
            unscaled,
            triggerBounds: [20.0, 20.0, 100.0, 60.0],
            triggerScale: 2.0,
            measuredSize: (90.0, 40.0),
            viewport: (300.0, 200.0)
        )
        #expect(unscaledRes.scale == 1.0)
        #expect(unscaledRes.w == 90.0)
    }
}
