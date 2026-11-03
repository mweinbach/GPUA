// Tests ported from: crates/rune/src/runtime/frame.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("RuntimeFrameUnitTests")
struct RuntimeFrameUnitTests {
    @Test("Idle frames skip commits while viewport changes and poll updates trigger commits")
    func idleFramesSkipCommitsUntilInvalidated() {
        let rt = Runtime.new(0, { n, _ in
            col().wFull().hFull().child(el().key("box").size(Float(40 + n), 30.0).bg(oklch(0.6, 0.1, 220.0)))
        }, (200.0, 150.0), Env.new(true, 1.0))

        _ = rt.frame(0.0)
        #expect(rt.stats.commits == 1)
        #expect(!rt.stale())

        _ = rt.frame(1.0 / 60.0)
        #expect(rt.stats.commits == 0)
        #expect(!rt.animating)

        rt.setViewport(240.0, 180.0)
        #expect(rt.stale())
        _ = rt.frame(1.0 / 60.0)
        #expect(rt.stats.commits == 1)

        rt.windowFocus(false)
        #expect(rt.heldModifiers().isEmpty)
    }
}
