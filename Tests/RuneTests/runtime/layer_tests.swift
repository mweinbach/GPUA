// Tests ported from: crates/rune/src/runtime/layer_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import RuneMotion
import Testing
@testable import Rune

@Suite("LayerTests")
struct LayerTests {
    @Test("Live group opacity updates child instances without view or layout commits and hides zero-alpha subtrees")
    func liveGroupOpacityUpdatesWithoutCommits() {
        let alpha = Live<Float>.new(1.0)
        let rt = Runtime.new((), { _, _ in
            el().size(32.0, 16.0).liveOpacity(Binding(live: alpha))
                .child(el().size(24.0, 12.0).bg(.WHITE))
                .child(rtAbsolute(el().size(24.0, 12.0).bg(.WHITE), 4.0, 0.0))
        }, (32.0, 16.0), Env.new(true, 1.0))

        _ = rt.frame(0.0)
        let initialCommits = rt.totalCommits
        #expect(!rt.instances.isEmpty)

        alpha.set(0.5)
        _ = rt.frame(1.0 / 60.0)
        #expect(rt.totalCommits == initialCommits)
        #expect(!rt.instances.isEmpty)

        alpha.set(0.0)
        _ = rt.frame(1.0 / 60.0)
        #expect(rt.totalCommits == initialCommits)
        #expect(rt.instances.allSatisfy { $0.fill[3] <= 1e-4 })

        alpha.set(1.0)
        _ = rt.frame(1.0 / 60.0)
        #expect(rt.totalCommits == initialCommits)
        #expect(rt.instances.contains(where: { $0.fill[3] > 0.99 }))
    }

    @Test("Smoothed live opacity springs continuously across frames without committing")
    func smoothedLiveOpacitySpringsWithoutCommits() {
        let alpha = Live<Float>.new(1.0)
        let rt = Runtime.new((), { _, _ in
            el().size(32.0, 16.0).liveOpacity(alpha.smooth(Spring.new(0.25, 0.0)))
                .child(el().size(16.0, 16.0).bg(.WHITE))
        }, (32.0, 16.0), Env.new(true, 1.0))

        _ = rt.frame(0.0)
        let commits = rt.totalCommits

        alpha.set(0.2)
        _ = rt.frame(1.0 / 60.0)
        let a1 = rt.instances.first?.fill[3] ?? 1.0
        _ = rt.frame(1.0 / 60.0)
        let a2 = rt.instances.first?.fill[3] ?? 1.0
        #expect(a2 < a1 && a2 > 0.2)
        #expect(rt.totalCommits == commits)
    }

    @Test("Layer blur emits isolated KIND_LAYER and KIND_LAYER_END markers around blurred subtrees")
    func layerBlurEmitsLayerMarkers() {
        let rt = Runtime.new((), { _, _ in
            col().size(64.0, 64.0).child(
                col().key("card").size(32.0, 32.0).blur(4.0)
                    .child(el().size(16.0, 16.0).bg(.WHITE))
            )
        }, (64.0, 64.0), Env.new(true, 1.0))

        _ = rt.frame(0.0)
        #expect(rt.instances.contains(where: { $0.params[1] == KIND_LAYER }))
        #expect(rt.instances.contains(where: { $0.params[1] == KIND_LAYER_END }))
    }
}
