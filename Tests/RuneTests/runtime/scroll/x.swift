// Tests ported from: crates/rune/src/runtime/scroll/x.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("ScrollXTests")
struct ScrollXTests {
    @Test("Horizontal row scroll viewport clamps offsets and glides smoothly when animated")
    func horizontalScrollClampsAndGlides() {
        let rt = Runtime.new((), { _, _ in
            row().key("strip").size(200.0, 60.0).scroll(ScrollSpec(stickBottom: false)).children(
                (0..<6).map { i in el().key("tile-\(i)").size(100.0, 60.0).bg(oklch(0.6, 0.1, 200.0)) }
            )
        }, (200.0, 60.0), Env.new(true, 1.0))

        _ = rt.frame(0.0)
        #expect(rt.scrollOffsetX("strip") == 0.0)

        // Instant clamped set
        rt.setScrollOffsetX("strip", 999.0, animated: false)
        #expect(rt.scrollOffsetX("strip") == 400.0)

        // Animated glide back toward 100
        rt.setScrollOffsetX("strip", 100.0, animated: true)
        _ = rt.frame(1.0 / 60.0)
        let mid = rt.scrollOffsetX("strip")
        #expect(mid > 100.0 && mid < 400.0)

        rtStepFrames(rt, 90)
        #expect(abs(rt.scrollOffsetX("strip") - 100.0) < 0.5)
    }
}
