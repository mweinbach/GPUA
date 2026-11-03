// Tests ported from: crates/rune/src/window/win.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("WindowWinTests")
struct WindowWinTests {
    @Test("deferred first frame holds reveal until ready or expired")
    func deferredFirstFrameHoldsRevealUntilReadyOrExpired() {
        let t0 = RuneInstant.now()
        var frame = FirstFrame(deferred: true, now: t0)
        #expect(frame.isWaiting)
        #expect(frame.deadline() == t0.adding(FIRST_FRAME_HOLD))
        let expEarly = frame.expireIfPast(t0.adding(.milliseconds(100)))
        #expect(!expEarly)
        let ready1 = frame.markReady()
        #expect(ready1)
        #expect(!frame.isWaiting)
        let ready2 = frame.markReady()
        #expect(!ready2)

        var timedOut = FirstFrame(deferred: true, now: t0)
        let expLate = timedOut.expireIfPast(t0.adding(FIRST_FRAME_HOLD))
        #expect(expLate)
        #expect(!timedOut.isWaiting)
    }

    @Test("Win resize and sRGB toggle reconfigure surface and invalidate presented")
    func winResizeAndSrgbToggleReconfigureSurfaceAndInvalidatePresented() {
        let nw = NativeWindow(title: "test", innerSize: (400, 300))
        let win = Win(window: nw, options: WindowOptions(), mac: MacWindowOptions(), srgb: true)
        #expect(win.config.width == 400 && win.config.height == 300 && win.config.srgb)
        win.resize((640, 480))
        #expect(win.config.width == 640 && win.config.height == 480)
        #expect(win.surfaceMeter.snapshot().counts.reconfigured == 1)
        win.setSrgbBlend(false)
        #expect(!win.config.srgb)
        #expect(win.surfaceMeter.snapshot().counts.reconfigured == 2)
    }

    @Test("onReady fires for a window launched occluded or hidden")
    func onReadyFiresForAWindowLaunchedOccludedOrHidden() {
        var readyId: String? = nil
        var hiddenOpts = WindowOptions()
        hiddenOpts.visible = false
        let spec = AppSpec<Int>("hidden", (200.0, 120.0), { 0 }, { _, _ in el() })
        let app = App.new(spec).windowOptions(hiddenOpts).onReady { h in
            readyId = h.key()
        }
        let host = app.buildHost()
        let loop = startAll([host])
        #expect(readyId == "main")
        loop.shutdown()
    }
}
