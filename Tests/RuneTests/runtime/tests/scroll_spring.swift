// Tests ported from: crates/rune/src/runtime/tests/scroll_spring.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Foundation
import Testing
import RuneMotion
@testable import Rune

private let rtSpringDt: Double = 1.0 / 120.0
private let rtSpringRowH: Int = 60
private let rtSpringViewH: Int = 300

private func rtScrollSpringView(_: Int, _: Cx<Int>) -> El {
    var rows = col().key("rows").wFull()
    for k in 0..<400 {
        rows = rows.child(el().key("r\(k)").wFull().h(Float(rtSpringRowH)))
    }
    return col().size(200.0, Float(rtSpringViewH)).child(
        col().key("scroll").size(200.0, Float(rtSpringViewH)).scroll(ScrollSpec(stickBottom: false)).child(rows)
    )
}

private func rtHoldScroll(_ ask: (inout Tx, Float, Float) -> Void) -> [Double] {
    let rt = Runtime.new(0, rtScrollSpringView, (200.0, Float(rtSpringViewH)), Env.new(true, 1.0))
    _ = rt.frame(0.0)
    var moves: [Double] = []
    var last = Double(rt.scrollOffset("scroll"))
    for f in 0..<120 {
        if f % 4 == 0 {
            let selected = 5 + f / 4
            let y = Float((selected + 1) * rtSpringRowH - rtSpringViewH)
            let at = rt.scrollOffset("scroll")
            rt.update { _, tx in ask(&tx, y, at) }
        }
        _ = rt.frame(rtSpringDt)
        let cur = Double(rt.scrollOffset("scroll"))
        moves.append(cur - last)
        last = cur
    }
    return moves
}

private func rtSteadyStats(_ moves: [Double]) -> (cv: Double, slowestRatio: Double) {
    let steady = Array(moves[(moves.count / 2)...])
    let mean = steady.reduce(0.0, +) / Double(steady.count)
    let variance = steady.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) } / Double(steady.count)
    let cv = variance.squareRoot() / max(mean, 1e-9)
    let slowest = (steady.min() ?? 0.0) / max(mean, 1e-9)
    return (cv, slowest)
}

@Suite struct RtScrollSpringTests {
    @Test
    func keyRepeatRetargetsGlideAsOneMotion() {
        let quick = Spring.new(0.18, 0.0)
        let glide = rtHoldScroll { tx, y, _ in tx.scrollTo("scroll", y) }
        let withQuick = rtHoldScroll { tx, y, _ in tx.scrollToWith("scroll", y, quick) }
        let stairs = rtHoldScroll { tx, y, at in
            tx.scrollToInstant("scroll", at)
            tx.scrollTo("scroll", y)
        }

        let (glideCv, glideSlow) = rtSteadyStats(glide)
        let (quickCv, quickSlow) = rtSteadyStats(withQuick)
        let (stairsCv, stairsSlow) = rtSteadyStats(stairs)

        #expect(glideCv < 0.05 && glideSlow > 0.9)
        #expect(quickCv < 0.05 && quickSlow > 0.9)
        #expect(stairsCv > 0.25 && stairsSlow < 0.5)
    }

    @Test
    func quickerSpringCoversMoreOfFirstFrameAndDefaultMatchesGlide() {
        func firstStep(_ ask: (inout Tx) -> Void) -> Float {
            let rt = Runtime.new(0, rtScrollSpringView, (200.0, Float(rtSpringViewH)), Env.new(true, 1.0))
            _ = rt.frame(0.0)
            rt.update { _, tx in ask(&tx) }
            _ = rt.frame(rtSpringDt)
            return rt.scrollOffset("scroll")
        }

        let defaultStep = firstStep { tx in tx.scrollTo("scroll", 500.0) }
        let explicitGlide = firstStep { tx in tx.scrollToWith("scroll", 500.0, tok.motion.GLIDE) }
        let quickStep = firstStep { tx in tx.scrollToWith("scroll", 500.0, Spring.new(0.18, 0.0)) }

        #expect(quickStep > defaultStep * 2.5)
        #expect(abs(defaultStep - explicitGlide) < 1e-4)

        // `scrollToBottom` resets custom spring back to `tok.motion.GLIDE`
        let rt = Runtime.new(0, rtScrollSpringView, (200.0, Float(rtSpringViewH)), Env.new(true, 1.0))
        _ = rt.frame(0.0)
        rt.update { _, tx in tx.scrollToWith("scroll", 100.0, Spring.new(0.18, 0.0)) }
        rtStepFrames(rt, 60)
        rt.update { _, tx in tx.scrollToBottom("scroll") }
        _ = rt.frame(rtSpringDt)
        let bottomStep = rt.scrollOffset("scroll") - 100.0

        let rtRef = Runtime.new(0, rtScrollSpringView, (200.0, Float(rtSpringViewH)), Env.new(true, 1.0))
        _ = rtRef.frame(0.0)
        rtRef.update { _, tx in tx.scrollToInstant("scroll", 100.0) }
        _ = rtRef.frame(rtSpringDt)
        rtRef.update { _, tx in tx.scrollToBottom("scroll") }
        _ = rtRef.frame(rtSpringDt)
        let refStep = rtRef.scrollOffset("scroll") - 100.0
        #expect(abs(bottomStep - refStep) < 1e-3)
    }
}
