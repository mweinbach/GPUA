// Tests ported from: crates/rune/src/runtime/scroll/bottom.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("ScrollBottomTests")
struct ScrollBottomTests {
    @Test("stickBottom viewport starts at bottom, follows content growth, unpins on user scroll up, and re-pins via scrollToBottom")
    func stickBottomFollowsUnpinsAndRepins() {
        let rt = Runtime.new(300.0 as Float, { h, _ in
            col().key("chat").size(200.0, 100.0).scroll(ScrollSpec(stickBottom: true)).child(
                col().key("content").wFull().h(h)
            )
        }, (200.0, 100.0), Env.new(true, 1.0))

        _ = rt.frame(0.0)
        #expect(rt.scrollOffset("chat") == 200.0)
        #expect(rt.isStuckToBottom("chat"))

        // Appending content while stuck glides viewport smoothly to new bottom
        rt.update { h, _ in h = 450.0 }
        rtStepFrames(rt, 90)
        #expect(abs(rt.scrollOffset("chat") - 350.0) < 0.5)
        #expect(rt.isStuckToBottom("chat"))

        // User wheel upward unpins
        rt.wheel(50.0, 50.0, 120.0)
        _ = rt.frame(1.0 / 60.0)
        #expect(abs(rt.scrollOffset("chat") - 230.0) < 0.5)
        #expect(!rt.isStuckToBottom("chat"))

        // Further content growth while unpinned leaves offset at 230
        rt.update { h, _ in h = 500.0 }
        _ = rt.frame(1.0 / 60.0)
        #expect(abs(rt.scrollOffset("chat") - 230.0) < 0.5)

        // Programmatic `scrollToBottom` glides back to bottom and re-pins
        rt.scrollToBottom("chat", animated: true)
        rtStepFrames(rt, 90)
        #expect(abs(rt.scrollOffset("chat") - 400.0) < 0.5)
        #expect(rt.isStuckToBottom("chat"))
    }
}
