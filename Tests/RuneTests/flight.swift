// Tests ported from: crates/rune/src/flight.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import RuneMotion
import Testing
@testable import Rune

private func makeFlight() -> TextFlight {
    TextFlight(
        sourceKey: "source",
        targetKey: "target",
        source: RuneMotion.Rect(40.0, 400.0, 500.0, 40.0),
        sourceClip: [40.0, 400.0, 540.0, 440.0],
        glyphs: [],
        scale: 2.0,
        now: 0.0
    )
}

@Suite("FlightTests")
struct FlightTests {
    @Test("moving destination uses shared progress without restarting it")
    func movingDestinationUsesSharedProgressWithoutRestartingIt() {
        var f = makeFlight()
        _ = f.measure(RuneMotion.Rect(120.0, 260.0, 400.0, 22.0), 0.0, false)
        let p = f.progress.sample(0.08)
        let v = f.progress.velocity(0.08)
        _ = f.measure(RuneMotion.Rect(120.0, 220.0, 400.0, 22.0), 0.08, false)
        #expect(f.progress.sample(0.08) == p)
        #expect(f.progress.velocity(0.08) == v)
        #expect(f.presented.y == 400.0 + (220.0 - 400.0) * p)
        let done = f.measure(RuneMotion.Rect(120.0, 220.0, 400.0, 22.0), 2.0, false)
        #expect(done)
    }

    @Test("flight is time based and reduced motion only fades")
    func flightIsTimeBasedAndReducedMotionOnlyFades() {
        let target = RuneMotion.Rect(120.0, 260.0, 400.0, 22.0)
        var slow = makeFlight()
        var fast = makeFlight()
        _ = slow.measure(target, 0.0, false)
        _ = fast.measure(target, 0.0, false)
        for i in 1...30 {
            _ = slow.measure(target, Double(i) / 30.0, false)
            for j in (i * 4 - 3)...(i * 4) {
                _ = fast.measure(target, Double(j) / 120.0, false)
            }
            #expect(slow.presented == fast.presented)
        }
        var f = makeFlight()
        let midDone = f.measure(target, 0.075, true)
        #expect(!midDone)
        #expect(f.presented == target)
        let alphas = f.alphas(target, 0.075, true)
        #expect(alphas.0 == 0.5 && alphas.1 == 0.5)
        let endDone = f.measure(target, 0.15, true)
        #expect(endDone)
    }

    @Test("selectors match a key or its keyed ancestors")
    func selectorsMatchKeyOrKeyedAncestors() {
        let path = "#0/scroll/#0/msg-42/#1/body"
        #expect(selectsKeyPath("body", path, "body"))
        #expect(selectsKeyPath("msg-42/body", path, "body"))
        #expect(selectsKeyPath("scroll/msg-42/body", path, "body"))
        #expect(!selectsKeyPath("msg-41/body", path, "body"))
        #expect(!selectsKeyPath("scroll/body", path, "body"))
        #expect(!selectsKeyPath("msg-42", path, "body"))
        #expect(!selectsKeyPath("body", "#0/#1", nil))
        #expect(!selectsKeyPath("x/msg-42/body", path, "body"))
    }
}
