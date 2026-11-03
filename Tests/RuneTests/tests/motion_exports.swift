// Tests ported from: crates/rune/tests/motion_exports.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import Rune

@Suite("MotionExportsIntegrationTests")
struct MotionExportsIntegrationTests {
    @Test func transitionAndAnimArgumentsAreNameableFromRune() {
        let anchored = Transition.scaleAnchor(0.96, Vec2(0.5, 0.0))
        #expect(anchored.insertion.anchor == Vec2(0.5, 0.0))
        let dir: Vec2 = Edge.top.direction()
        #expect(dir == Vec2(0.0, -1.0))
        let combined: Effect = Effect.scale(0.9).combined(Effect.opacity(0.0))
        #expect(combined.opacity == 0.0)
        let reveal = Reveal(edge: .bottom, feather: 4.0)
        #expect(reveal.edge == .bottom && reveal.feather == 4.0)
        let bezier = Easing.cubicBezier(CubicBezier.new(0.2, 0.0, 0.0, 1.0))
        let steps = Easing.steps(4, StepPosition.end)
        #expect(bezier != steps)
        let decay = Decay.iosNormal
        #expect(decay.rate > 0.0)
        let anim = Spring.fromResponse(0.3, 1.0).blend(MotionBlend.additive).velocity(Velocity.zero)
        #expect(anim.blend == .additive && anim.velocity == .zero)
    }
}
