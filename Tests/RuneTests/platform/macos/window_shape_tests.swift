// Tests ported from: crates/rune/src/platform/macos/window_shape_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("WindowShapeTests")
struct WindowShapeTests {
    private struct Sim {
        var state: MacShadowResample = .idle
        var acquired: UInt64 = 0
        var onScreen: UInt64 = 0
        var resamples: Int = 0

        @discardableResult
        mutating func present() -> UInt64 {
            acquired += 1
            state.presented(acquired)
            return acquired
        }

        mutating func land(_ n: UInt64) {
            onScreen = max(onScreen, n)
        }

        mutating func turn() {
            if state.turn(onScreen) {
                resamples += 1
            }
        }

        mutating func frame() {
            let n = present()
            turn()
            land(n)
            turn()
        }
    }

    @Test("first show resamples once its first frame is on screen")
    func firstShowResamplesOnceItsFirstFrameIsOnScreen() {
        var sim = Sim()
        sim.state.shown(0)
        sim.turn()
        #expect(sim.resamples == 0)
        let n = sim.present()
        sim.turn()
        #expect(sim.resamples == 0)
        sim.land(n)
        sim.turn()
        #expect(sim.resamples == 1)
        sim.turn()
        #expect(sim.resamples == 1)
    }

    @Test("ordinary frames never resample")
    func ordinaryFramesNeverResample() {
        var sim = Sim()
        for _ in 0..<20 {
            sim.frame()
        }
        #expect(sim.resamples == 0)
        sim.state.shown(sim.acquired)
        sim.turn()
        #expect(sim.resamples == 1)
        for _ in 0..<20 {
            sim.frame()
        }
        #expect(sim.resamples == 1)
    }

    @Test("resize and scale wait for a frame drawn after them")
    func resizeAndScaleWaitForAFrameDrawnAfterThem() {
        for _ in ["resize", "scale"] {
            var sim = Sim()
            sim.state.shown(0)
            sim.frame()
            #expect(sim.resamples == 1)
            let stale = sim.present()
            sim.state.redraw()
            sim.land(stale)
            sim.turn()
            #expect(sim.resamples == 1)
            sim.frame()
            #expect(sim.resamples == 2)
            sim.frame()
            #expect(sim.resamples == 2)
        }
    }

    @Test("a live resize resamples after it settles")
    func liveResizeResamplesAfterItSettles() {
        var sim = Sim()
        for _ in 0..<10 {
            sim.state.redraw()
            let n = sim.present()
            sim.turn()
            sim.state.redraw()
            sim.land(n)
            sim.turn()
        }
        #expect(sim.resamples == 0)
        sim.frame()
        #expect(sim.resamples == 1)
    }

    @Test("prewarm resamples after its hidden frame and reveal after the cached one")
    func prewarmResamplesAfterItsHiddenFrameAndRevealAfterTheCachedOne() {
        var sim = Sim()
        sim.state.redraw()
        sim.frame()
        #expect(sim.resamples == 1)
        sim.frame()
        sim.frame()
        #expect(sim.resamples == 1)
        sim.state.shown(sim.acquired)
        sim.turn()
        #expect(sim.resamples == 2)
        sim.state.hidden()
        let n = sim.present()
        sim.state.shown(n)
        sim.turn()
        #expect(sim.resamples == 2)
        sim.land(n)
        sim.turn()
        #expect(sim.resamples == 3)
    }

    @Test("hiding cancels a pending resample")
    func hidingCancelsAPendingResample() {
        var sim = Sim()
        sim.state.shown(0)
        let n = sim.present()
        sim.state.hidden()
        sim.land(n)
        sim.turn()
        #expect(sim.resamples == 0)
    }

    @Test("a show keeps waiting for the frame a resize asked for")
    func showKeepsWaitingForTheFrameAResizeAskedFor() {
        var sim = Sim()
        sim.frame()
        sim.state.redraw()
        sim.state.shown(sim.acquired)
        sim.turn()
        #expect(sim.resamples == 0)
        sim.frame()
        #expect(sim.resamples == 1)
    }
}
