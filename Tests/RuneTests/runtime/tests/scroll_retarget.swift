// Tests ported from: crates/rune/src/runtime/tests/scroll_retarget.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Foundation
import Testing
@testable import Rune

private let rtRetargetDt: Double = 1.0 / 60.0

private func rtScrollRetargetView(_: Int, _: Cx<Int>) -> El {
    var rows = col().key("rows").wFull()
    for k in 0..<40 {
        rows = rows.child(el().key("r\(k)").wFull().h(50.0))
    }
    return col().size(200.0, 200.0).child(
        col().key("scroll").size(200.0, 200.0).scroll(ScrollSpec(stickBottom: false)).child(rows)
    )
}

private func rtRetargetAt(_ to: Float) -> Runtime<Int> {
    let rt = Runtime.new(0, rtScrollRetargetView, (200.0, 200.0), Env.new(true, 1.0))
    _ = rt.frame(0.0)
    rt.update { _, tx in tx.scrollToInstant("scroll", to) }
    _ = rt.frame(rtRetargetDt)
    return rt
}

private func rtGlidePath(_ rt: Runtime<Int>) -> [Float] {
    var path: [Float] = [rt.scrollOffset("scroll")]
    for _ in 0..<240 {
        _ = rt.frame(rtRetargetDt)
        path.append(rt.scrollOffset("scroll"))
        if !rt.scrolling() { break }
    }
    return path
}

@Suite struct RtScrollRetargetTests {
    @Test
    func glideSentNearerMidFlightStopsWithoutOvershooting() {
        let rt = rtRetargetAt(1000.0)
        rt.update { _, tx in tx.scrollTo("scroll", 0.0) }
        for _ in 0..<5 { _ = rt.frame(rtRetargetDt) }
        let mid = rt.scrollOffset("scroll")
        #expect(mid < 900.0)

        let to = mid - 40.0
        rt.update { _, tx in tx.scrollTo("scroll", to) }
        let path = rtGlidePath(rt)
        let past = path.map { to - $0 }.max() ?? 0.0
        #expect(past < 0.05)
        for i in 1..<path.count {
            #expect(path[i] <= path[i - 1] + 1e-4)
        }
        #expect(abs((path.last ?? -1.0) - to) < 1e-3)
    }

    @Test
    func glideSentFurtherMidFlightKeepsSpeedAndLandsWithoutStepJump() {
        let rt = rtRetargetAt(1000.0)
        rt.update { _, tx in tx.scrollTo("scroll", 500.0) }
        for _ in 0..<5 { _ = rt.frame(rtRetargetDt) }
        let a = rt.scrollOffset("scroll")
        _ = rt.frame(rtRetargetDt)
        let b = rt.scrollOffset("scroll")
        rt.update { _, tx in tx.scrollTo("scroll", 0.0) }
        _ = rt.frame(rtRetargetDt)
        let c = rt.scrollOffset("scroll")
        #expect((b - c) >= (a - b) - 0.5)

        // Full glide lands without a step jump on the final frame
        let rt2 = rtRetargetAt(1000.0)
        rt2.update { _, tx in tx.scrollTo("scroll", 0.0) }
        let path = rtGlidePath(rt2)
        var steps: [Float] = []
        for i in 1..<path.count {
            steps.append(path[i - 1] - path[i])
        }
        #expect(steps.count > 10)
        #expect(steps[steps.count - 1] <= steps[steps.count - 2] + 0.1)
    }

    @Test
    func centeringGlideRetargetedNearerOrFurtherBehavesMonotonically() {
        let rt = rtRetargetAt(0.0)
        rt.update { _, tx in tx.scrollCenter("r30") }
        for _ in 0..<5 { _ = rt.frame(rtRetargetDt) }
        let mid = rt.scrollOffset("scroll")
        let k = Int(((mid + 40.0 + 75.0) / 50.0).rounded(.up))
        let to = Float(k) * 50.0 - 75.0
        #expect(to < 1425.0)

        rt.update { _, tx in tx.scrollCenter("r\(k)") }
        let path = rtGlidePath(rt)
        let past = path.map { $0 - to }.max() ?? 0.0
        #expect(past < 0.05)
        for i in 1..<path.count {
            #expect(path[i] >= path[i - 1] - 1e-4)
        }
        #expect(abs((path.last ?? -1.0) - to) < 1e-3)

        // Retargeting further (`r20` -> `r35`) keeps speed
        let rtFar = rtRetargetAt(0.0)
        rtFar.update { _, tx in tx.scrollCenter("r20") }
        for _ in 0..<5 { _ = rtFar.frame(rtRetargetDt) }
        let a = rtFar.scrollOffset("scroll")
        _ = rtFar.frame(rtRetargetDt)
        let b = rtFar.scrollOffset("scroll")
        rtFar.update { _, tx in tx.scrollCenter("r35") }
        _ = rtFar.frame(rtRetargetDt)
        let c = rtFar.scrollOffset("scroll")
        #expect((c - b) >= (b - a) - 0.5)
    }
}
