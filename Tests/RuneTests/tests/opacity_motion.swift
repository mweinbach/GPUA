// Tests ported from: crates/rune/tests/opacity_motion.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private struct OpacityMotionState {
    var shown: Bool
    var tick: UInt32
}

private func opacityMotionHiddenView(_ s: OpacityMotionState, _: Cx<OpacityMotionState>) -> El {
    var fade = Anim.new(.spring(Spring.new(0.3, 0.0)))
    fade.velocity = .uniform(-2.0)
    var e = el().key("e").size(50.0, 50.0).fill(.BLACK).opacity(0.0)
    e.opacityMotionAnim = fade
    return col().wFull().hFull().label("tick \(s.tick)").child(e)
}

private func opacityMotionFadeView(_ s: OpacityMotionState, _: Cx<OpacityMotionState>) -> El {
    var fade = Anim.new(.spring(Spring.new(0.3, 0.0)))
    fade.delay = 0.1
    fade.velocity = .uniform(-2.0)
    var e = el().key("e").size(50.0, 50.0).fill(.BLACK).opacity(s.shown ? 1.0 : 0.0)
    e.opacityMotionAnim = fade
    return col().wFull().hFull().child(e).child(el().key("tick\(s.tick)").size(1.0, 1.0))
}

@Suite("OpacityMotionIntegrationTests")
struct OpacityMotionIntegrationTests {
    @Test func anUnrelatedCommitDoesntRestartAFade() {
        let rt = IntegrationSupport.runtime(
            OpacityMotionState(shown: true, tick: 0),
            opacityMotionFadeView,
            (100.0, 100.0),
            Env.new(true, 1.0)
        )
        _ = rt.hostFrame(0.0)
        rt.hostUpdate { s, _ in
            s.shown = false
        }
        var last: Float = 1.0
        for i in UInt32(0)..<40 {
            rt.hostUpdate { s, _ in
                s.tick = i
            }
            _ = rt.hostFrame(1.0 / 60.0)
            let now = IntegrationSupport.find(rt, "e").opacity
            #expect(now <= last + 1e-4)
            last = now
        }
        #expect(last < 0.05)
    }

    @Test func aHiddenElementStaysStillAcrossCommits() {
        let rt = IntegrationSupport.runtime(
            OpacityMotionState(shown: false, tick: 0),
            opacityMotionHiddenView,
            (100.0, 100.0),
            Env.new(true, 1.0)
        )
        _ = rt.hostFrame(0.0)
        for _ in 0..<60 {
            _ = rt.hostFrame(1.0 / 60.0)
        }
        rt.hostUpdate { s, _ in
            s.tick = 1
        }
        _ = rt.hostFrame(1.0 / 60.0)
        for _ in 0..<3 {
            let (_, _, stats) = rt.hostFrame(1.0 / 60.0)
            #expect(!stats.animating)
        }
    }
}
