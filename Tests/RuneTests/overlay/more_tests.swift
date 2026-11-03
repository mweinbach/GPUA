// Tests ported from: crates/rune/src/overlay/more_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("OverlayMoreTests")
struct OverlayMoreTests {
    @Test("overlay pixels wake only while shown and catch up on show")
    func overlayPixelsWakeOnlyWhileShownAndCatchUpOnShow() {
        let pixels = Pixels.new()
        var opts = OverlayOptions()
        opts.prewarm = true
        opts.keys = .onDemand
        var configured = ConfiguredOverlay(
            spec: OverlaySpec<Pixels>(name: "pixels overlay", size: (4.0, 4.0)) { px, _ in
                el().size(4.0, 4.0).pixels(px)
            }
        )
        configured.options = opts

        let wakeLock = LiveLock()
        nonisolated(unsafe) var wakes = 0
        let overlay = Overlay(configured: configured, initialState: pixels)
        overlay.startOverlay(displays: [Display()]) {
            wakeLock.withLock { wakes += 1 }
        }
        let wakesAfterStart = wakeLock.withLock { wakes }
        pixels.set(1, 1, [255, 255, 255, 255])
        #expect(wakeLock.withLock { wakes } == wakesAfterStart) // hidden overlay isn't woken by live Pixels

        overlay.handle.show()
        overlay.stepOverlayFrame(displays: [Display()])
        let wakesWhenShown = wakeLock.withLock { wakes }
        pixels.set(1, 1, [0, 0, 0, 0])
        pixels.set(1, 1, [1, 1, 1, 1])
        #expect(wakeLock.withLock { wakes } == wakesWhenShown + 1) // coalesced to one wake per frame while shown

        overlay.handle.hide()
        _ = overlay.drainOverlayRequests(displays: [Display()])
        let wakesAfterHide = wakeLock.withLock { wakes }
        pixels.set(1, 1, [2, 2, 2, 2])
        #expect(wakeLock.withLock { wakes } == wakesAfterHide)
    }

    @Test("overlay input switch waits for owned drag release")
    func overlayInputSwitchWaitsForOwnedDragRelease() {
        var opts = OverlayOptions()
        opts.input = .all
        var configured = ConfiguredOverlay(
            spec: OverlaySpec<[Phase]>(name: "input switch", size: (100.0, 100.0), interactive: true) { _, _ in
                el().wFull().hFull().onDrag { (phases: inout [Phase], drag: inout Drag, _: inout Tx) in
                    phases.append(drag.phase)
                }
            }
        )
        configured.options = opts
        let overlay = Overlay(configured: configured, initialState: [])
        overlay.startOverlay(displays: [Display()])
        overlay.handle.show()
        overlay.stepOverlayFrame(displays: [Display()])

        overlay.handleOverlayEvent(.pointerDown(10.0, 10.0, .primary))
        #expect(overlay.rt.hostPointerCaptured())

        overlay.handle.setInput(.regions)
        overlay.handle.setInput(.none)
        _ = overlay.drainOverlayRequests(displays: [Display()])
        #expect(overlay.options.input == .all) // held until drag release!

        overlay.handleOverlayEvent(.pointerMoved(150.0, 150.0))
        overlay.handleOverlayEvent(.pointerUp(150.0, 150.0, .primary))
        _ = overlay.rt.hostFrame(0.0)
        #expect(overlay.options.input == .none)
        #expect(overlay.rt.state.first == .down)
        #expect(overlay.rt.state.last == .up)
        #expect(!overlay.rt.hostPointerCaptured())
    }

    @Test("handle requests apply in order and report availability")
    func handleRequestsApplyInOrderAndReportAvailability() {
        let spec = OverlaySpec<UInt32>(name: "orders", size: (100.0, 40.0)) { _, _ in el() }
        let overlay = Overlay(configured: ConfiguredOverlay(spec: spec), initialState: 0)
        let handle = overlay.handle
        #expect(handle.availability() == .unknown)

        handle.show()
        handle.update { n, _ in n += 1 }
        handle.setPlacement(.edge(edge: .bottom, margin: 24.0, align: .end, inset: 12.0))
        handle.setSize(300.0, 80.0)
        handle.update { n, _ in n *= 3 }
        handle.hide()

        _ = overlay.drainOverlayRequests(displays: [Display()])
        #expect(!overlay.visible)
        #expect(overlay.rt.state == 3)
        #expect(overlay.at.size == (300.0, 80.0))
        #expect(overlay.options.placement == .edge(edge: .bottom, margin: 24.0, align: .end, inset: 12.0))

        overlay.simulatedUnavailableError = "no compositor"
        handle.show()
        _ = overlay.drainOverlayRequests(displays: [Display()])
        #expect(handle.availability() == .unavailable)
        #expect(handle.failure() == "no compositor")
    }

    @Test("a hidden overlay builds nothing until it shows")
    func aHiddenOverlayBuildsNothingUntilItShows() {
        var builds: UInt32 = 0
        let spec = OverlaySpec<UInt32>(name: "hidden counter", size: (200.0, 50.0)) { n, _ in
            builds += 1
            return el().child(text("\(n)").key("n"))
        }
        let overlay = Overlay(configured: ConfiguredOverlay(spec: spec), initialState: 0)
        overlay.startOverlay(displays: [Display()])
        let baseBuilds = builds

        for _ in 1...10 {
            overlay.handle.update { n, _ in n += 1 }
            overlay.stepOverlayFrame(displays: [Display()])
        }
        #expect(overlay.rt.state == 10)
        #expect(builds - baseBuilds == 0)

        overlay.handle.show()
        overlay.stepOverlayFrame(displays: [Display()])
        #expect(builds - baseBuilds == 1)
        #expect(overlay.rt.hostElements().first { $0.key == "n" }?.text == "10")
    }

    @Test("an animated reveal lets the first card enter")
    func anAnimatedRevealLetsTheFirstCardEnter() {
        let view: (Bool, Cx<Bool>) -> El = { card, _ in
            if card {
                return el().child(el().key("card").size(100.0, 40.0).transition(.offset(0.0, -24.0)))
            }
            return el()
        }
        for animate in [true, false] {
            let base = OverlaySpec<Bool>(name: "stack", size: (200.0, 100.0), view: view)
            let configured = animate ? base.animateReveal() : ConfiguredOverlay(spec: base)
            let overlay = Overlay(configured: configured, initialState: false)
            overlay.startOverlay(displays: [Display()])
            _ = overlay.rt.hostFrame(0.0)

            overlay.handle.update { card, _ in card = true }
            overlay.handle.show()
            let t0 = RuneInstant.now()
            overlay.stepOverlayFrame(now: t0, displays: [Display()])
            let y = overlay.rt.hostPresented("card")!.rect.y
            if animate {
                #expect(y < -10.0)
                _ = overlay.drawOverlay(now: t0.adding(.milliseconds(96)))
                let later = overlay.rt.hostPresented("card")!.rect.y
                #expect(later > y)
            } else {
                #expect(y == 0.0)
            }
        }
    }

    @Test("compositor hook observes rendered overlay frames and keeps stepping while animating")
    func compositorHookObservesRenderedOverlayFrames() {
        var observedWidths: [Float] = []
        var configured = ConfiguredOverlay(
            spec: OverlaySpec<Float>(name: "trace", size: (32.0, 16.0)) { width, _ in
                el().size(32.0, 16.0).child(el().key("box").size(width, 8.0).bg(.WHITE))
            }
        )
        configured.compositorRender = { rt, _ in
            if let w = rt.hostElements().first(where: { $0.key == "box" })?.rect[2] {
                observedWidths.append(w)
            }
        }
        configured.compositorAnimating = { observedWidths.count < 3 }

        let overlay = Overlay(configured: configured, initialState: 8.0)
        overlay.startOverlay(displays: [Display()])
        overlay.handle.show()
        let t0 = RuneInstant.now()
        overlay.stepOverlayFrame(now: t0, displays: [Display()])
        overlay.rt.hostUpdate { s, tx in s = 12.0; tx.instant() }
        _ = overlay.drawOverlay(now: t0.adding(.milliseconds(16)))
        overlay.rt.hostUpdate { s, tx in s = 20.0; tx.instant() }
        let keepGoing = overlay.drawOverlay(now: t0.adding(.milliseconds(32)))
        #expect(observedWidths == [8.0, 12.0, 20.0])
        #expect(!keepGoing)
    }
}
