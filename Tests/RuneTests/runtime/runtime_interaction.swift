// Tests ported from: crates/rune/src/runtime/interaction.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("RuntimeInteractionUnitTests")
struct RuntimeInteractionUnitTests {
    @Test("Pointer press and wheel events route to target elements and scroll containers")
    func pointerPressAndWheelRouting() {
        let rt = Runtime.new(0, { _, _ in
            col().key("scroll").size(200.0, 100.0).scroll(ScrollSpec(stickBottom: false)).child(
                col().wFull()
                    .child(el().key("btn").size(100.0, 40.0).bg(oklch(0.5, 0.1, 200.0)).onPress { (n: inout Int, _) in n += 1 })
                    .child(el().key("tail").size(100.0, 300.0))
            )
        }, (200.0, 100.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)

        rtClick(rt, "btn")
        _ = rt.frame(0.0)
        #expect(rt.state == 1)

        rt.wheel(50.0, 50.0, -60.0)
        _ = rt.frame(1.0 / 60.0)
        #expect(rt.scrollOffset("scroll") == 60.0)
        #expect(rt.scrolling())
    }
}
