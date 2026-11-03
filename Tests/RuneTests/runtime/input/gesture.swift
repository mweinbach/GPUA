// Tests ported from: crates/rune/src/runtime/input/gesture.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("InputGestureTests")
struct InputGestureTests {
    @Test("Magnify gesture accumulates scale within clamped bounds and resets on cancel")
    func magnifyAccumulatesAndCancels() {
        let rt = Runtime.new((), { _, _ in el().wFull().hFull() }, (200.0, 200.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)
        #expect(!rt.currentGesture().active)

        rt.magnify(MagnifyEvent(x: 50.0, y: 60.0, delta: 0.5, phase: .started))
        #expect(rt.currentGesture().active)
        #expect(abs(rt.currentGesture().scale - 1.5) < 1e-4)

        rt.magnify(MagnifyEvent(x: 50.0, y: 60.0, delta: 0.2, phase: .moved))
        #expect(abs(rt.currentGesture().scale - 1.8) < 1e-4)

        rt.magnify(MagnifyEvent(x: 50.0, y: 60.0, delta: 0.0, phase: .ended))
        #expect(!rt.currentGesture().active)
        #expect(abs(rt.currentGesture().scale - 1.8) < 1e-4)

        rt.magnify(MagnifyEvent(x: 50.0, y: 60.0, delta: 0.0, phase: .cancelled))
        #expect(rt.currentGesture().scale == 1.0)
    }

    @Test("Rotate gesture accumulates radians and clears active flag on end")
    func rotateAccumulatesAndEnds() {
        let rt = Runtime.new((), { _, _ in el().wFull().hFull() }, (200.0, 200.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)

        rt.rotate(RotateEvent(x: 30.0, y: 40.0, delta: 0.25, phase: .started))
        #expect(rt.currentGesture().active)
        #expect(abs(rt.currentGesture().rotation - 0.25) < 1e-4)

        rt.rotate(RotateEvent(x: 30.0, y: 40.0, delta: -0.1, phase: .moved))
        #expect(abs(rt.currentGesture().rotation - 0.15) < 1e-4)

        rt.rotate(RotateEvent(x: 30.0, y: 40.0, delta: 0.0, phase: .cancelled))
        #expect(!rt.currentGesture().active)
        #expect(rt.currentGesture().rotation == 0.0)
    }
}
