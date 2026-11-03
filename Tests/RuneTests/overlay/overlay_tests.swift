// Tests ported from: crates/rune/src/overlay/tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("OverlayTests")
struct OverlayTests {
    private static let FRAME: Duration = .microseconds(16_667)

    private static func widthOverlay(_ name: String, options: OverlayOptions = OverlayOptions()) -> Overlay<Float> {
        let spec = OverlaySpec<Float>(name: name, size: (400.0, 50.0)) { width, _ in
            el().child(el().key("box").size(width, 8.0))
        }
        var configured = ConfiguredOverlay(spec: spec)
        configured.options = options
        return Overlay(configured: configured, initialState: 12.0)
    }

    private static func boxWidth<T>(_ overlay: Overlay<T>) -> Float {
        overlay.rt.hostPresented("box")!.rect.w
    }

    @Test("hiding stops drawing and clears live visibility")
    func hidingStopsDrawingAndClearsLiveVisibility() {
        let overlay = Self.widthOverlay("hide")
        overlay.startOverlay(displays: [Display()])
        overlay.handle.show()
        _ = overlay.drainOverlayRequests(displays: [Display()])
        #expect(overlay.visible && overlay.rt.hostLiveVisible())

        overlay.handle.hide()
        _ = overlay.drainOverlayRequests(displays: [Display()])
        #expect(!overlay.visible && !overlay.rt.hostLiveVisible())
        #expect(!overlay.drawOverlay())
    }

    @Test("a poll asking for the next frame keeps a shown overlay stepping")
    func aPollAskingForTheNextFrameKeepsAShownOverlayStepping() {
        let spec = OverlaySpec<UInt32>(name: "frame poll", size: (100.0, 50.0)) { _, _ in
            el().key("box").size(10.0, 10.0)
        }.poll { steps, _, tx in
            steps += 1
            if steps < 4 { tx.wakeAfter(0.0) }
            return true
        }
        let overlay = Overlay(configured: spec, initialState: 0)
        overlay.startOverlay(displays: [Display()])
        overlay.handle.show()
        _ = overlay.drainOverlayRequests(displays: [Display()])
        let t0 = RuneInstant.now()
        var keepGoing: [Bool] = []
        for k in 1...5 {
            keepGoing.append(overlay.drawOverlay(now: t0.adding(.microseconds(Int64(k) * 16_667))))
        }
        #expect(overlay.rt.state == 5)
        #expect(keepGoing == [true, true, true, false, false])
    }

    @Test("overlay motion starting after idle takes one frame step")
    func overlayMotionStartingAfterIdleTakesOneFrameStep() {
        func firstPose(_ idleWait: Duration) -> Float {
            let overlay = Self.widthOverlay("after idle")
            overlay.startOverlay(displays: [Display()])
            overlay.handle.show()
            let t0 = RuneInstant.now()
            overlay.stepOverlayFrame(now: t0, displays: [Display()])
            overlay.clock.pause()

            overlay.rt.hostUpdate { width, _ in width = 212.0 }
            _ = overlay.drawOverlay(now: t0.adding(idleWait))
            return Self.boxWidth(overlay)
        }
        let short = firstPose(Self.FRAME)
        let long = firstPose(.seconds(2))
        #expect(short > 12.0 && short < 40.0)
        #expect(abs(long - short) < 0.001)
    }

    @Test("window panel overlay focus callback runs on requestKeys and releaseKeys")
    func windowPanelOverlayFocusCallbackRunsOnKeys() {
        var opts = OverlayOptions()
        opts.keys = .onDemand
        var configured = OverlaySpec<[Bool]>(name: "focus", size: (100.0, 100.0)) { _, _ in el() }
            .onFocus { s, focused, tx in
                s.append(focused)
                if !focused { tx.closeWindow() }
            }
        configured.options = opts
        let overlay = Overlay(configured: configured, initialState: [])
        overlay.startOverlay(displays: [Display()])
        overlay.handle.show()
        overlay.handle.requestKeys()
        _ = overlay.drainOverlayRequests(displays: [Display()])
        #expect(overlay.rt.state == [true])
        #expect(overlay.visible)

        overlay.handle.releaseKeys()
        _ = overlay.drainOverlayRequests(displays: [Display()])
        #expect(overlay.rt.state == [true, false])
        #expect(!overlay.visible) // `tx.closeWindow()` hid the overlay!
    }

    @Test("a timer frame that changes nothing on screen draws nothing")
    func aTimerFrameThatChangesNothingOnScreenDrawsNothing() {
        struct S {
            var polls: UInt32 = 0
            var width: Float = 0.0
            var grow: Bool = false
        }
        let configured = OverlaySpec<S>(name: "quiet timer", size: (100.0, 40.0)) { s, _ in
            el().child(el().key("box").size(10.0 + s.width, 8.0).bg(.WHITE))
        }.poll { s, _, tx in
            s.polls += 1
            if s.grow { s.width += 1.0 }
            tx.wakeAfter(0.033)
            return true
        }
        let overlay = Overlay(configured: configured, initialState: S())
        overlay.startOverlay(displays: [Display()])
        overlay.handle.show()
        let t0 = RuneInstant.now()
        overlay.stepOverlayFrame(now: t0, displays: [Display()])
        let drawsAfterShow = overlay.drawCount
        let pollsAfterShow = overlay.rt.state.polls

        // Advance past timer without visual change -> poll runs, draw skipped!
        _ = overlay.drawOverlay(now: t0.adding(.milliseconds(40)))
        #expect(overlay.rt.state.polls == pollsAfterShow + 1)
        #expect(overlay.drawCount == drawsAfterShow)

        // Now grow -> visual change -> draws!
        overlay.rt.state.grow = true
        _ = overlay.drawOverlay(now: t0.adding(.milliseconds(80)))
        #expect(overlay.drawCount == drawsAfterShow + 1)
    }
}
