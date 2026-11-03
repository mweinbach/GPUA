// Tests ported from: crates/rune/src/runtime/web/runtime.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("WebRuntimeTests")
struct WebRuntimeTests {
    @Test("syncWebViewport and webFrame clamp frame dt and update DPR and dark-mode environment")
    func syncWebViewportAndWebFrameStepCleanly() {
        let rt = Runtime.new((), { _, _ in
            el().key("panel").wFull().hFull().bg(oklch(0.3, 0.05, 250.0))
        }, (300.0, 200.0), Env.new(false, 1.0))

        rt.syncWebViewport(cssWidth: 640.0, cssHeight: 400.0, devicePixelRatio: 2.0, dark: true)
        let (inst0, _) = rt.webFrame(1000.0)
        #expect(!inst0.isEmpty)
        #expect(rt.viewport == (640.0, 400.0))
        #expect(rt.env.scale == 2.0)
        #expect(rt.env.systemDark == true)

        let tBefore = rt.t
        // Large browser background tab jump (5000 ms) clamps `dt` to `0.1` s
        _ = rt.webFrame(6000.0)
        #expect(abs((rt.t - tBefore) - 0.1) < 1e-6)
    }
}
