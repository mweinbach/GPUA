// Tests ported from: crates/rune/src/runtime/tests/draw_on.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

@testable import Rune
import RuneMotion
import Testing

private struct RtDrawOnState {
    var mounted: Bool
    var transition: Transition
}

private func rtLineView(_ s: RtDrawOnState, _: Cx<RtDrawOnState>) -> El {
    let pts: [[Float]] = (0...10).map { i in [Float(i) * 10.0, 20.0] }
    var root = col().size(200.0, 100.0)
    if s.mounted {
        var line = canvas(Shape.new().stroke(pts, 2.0, .WHITE)).key("line").size(120.0, 40.0)
        line.transitionSpec = s.transition
        root = root.child(line)
    }
    return root
}

private func rtDrawSegments(_ rt: Runtime<RtDrawOnState>) -> Int {
    rt.instances.filter { $0.params[1] == KIND_SEGMENT }.count
}

@Suite
struct RtDrawOnTests {
    @Test
    func aDrawTransitionTracesAShapeOnAndReduceMotionDrawsItWhole() {
        let rt = Runtime.new(
            RtDrawOnState(mounted: false, transition: Transition.draw()),
            rtLineView,
            (200.0, 100.0),
            Env.new(true, 1.0)
        )
        _ = rt.frame(0.0)
        rt.update { s, _ in s.mounted = true }
        _ = rt.frame(0.0)

        var seen: [Int] = [rtDrawSegments(rt)]
        for _ in 0..<90 {
            _ = rt.frame(1.0 / 120.0)
            seen.append(rtDrawSegments(rt))
        }
        #expect(seen[0] < 3)
        for i in 1..<seen.count {
            #expect(seen[i - 1] <= seen[i])
        }
        #expect(seen.contains(where: { $0 > 3 && $0 < 10 }))
        #expect(seen.last == 10)

        let rtReduced = Runtime.new(
            RtDrawOnState(mounted: false, transition: Transition.draw()),
            rtLineView,
            (200.0, 100.0),
            Env.new(true, 1.0)
        )
        rtReduced.setSystemReducedMotion(true)
        _ = rtReduced.frame(0.0)
        rtReduced.update { s, _ in s.mounted = true }
        _ = rtReduced.frame(0.0)
        #expect(rtDrawSegments(rtReduced) == 10)
    }
}
