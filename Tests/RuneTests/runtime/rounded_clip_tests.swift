// Tests ported from: crates/rune/src/runtime/rounded_clip_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import RuneMotion
import Testing
@testable import Rune

@Suite("RuntimeRoundedClipTests")
struct RuntimeRoundedClipTests {
    @Test("Packed clip radii boundaries and fade lanes do not collide")
    func packedClipRadiiBoundariesAndFadeLanesDoNotCollide() {
        let rect: [Float] = [0.0, 0.0, 2000.0, 2000.0]
        let cases: [([Float], [Float])] = [
            ([0.0, 0.24, 12.26, 63.5], [0.0, 0.0, 12.5, 63.5]),
            ([0.0, 63.6, 127.0, 254.0], [0.0, 64.0, 128.0, 254.0]),
            ([0.0, 256.0, 500.0, 2000.0], [0.0, 254.0, 254.0, 254.0]),
            ([-1.0, -12.5, 0.0, -63.5], [-1.0, -12.5, 0.0, -63.5]),
        ]
        for (radii, want) in cases {
            #expect(unpackClipRadii(packClipRadii(rect, radii)) == want)
        }

        for r: Float in [0.0, 0.125, 63.75, 254.5, 999.0, -999.0] {
            #expect(unpackClipRadii(packClipRadii(rect, [r, r, r, r])) == [r, r, r, r])
        }

        for r: Float in [1e30, -1e30, .infinity] {
            let word = packClipRadii([0.0, 0.0, 1e35, 1e35], [r, r, r, r])
            #expect((word & 0x6000_0000) != 0x6000_0000)
            let unpacked = unpackClipRadii(word)
            #expect(unpacked.allSatisfy { $0.isFinite && abs($0) > 1e18 })
        }

        let fade = packFade([65504.0, 65504.0, 65504.0, 65504.0], rect, rect)
        #expect(fade[3] == 0)
    }

    @Test("Instance roundClip and beginLayer pack clip radius into fade[3]")
    func instanceRoundClipAndBeginLayerPackClipRadius() {
        var inst = Instance(
            rect: [0.0, 0.0, 64.0, 48.0],
            clip: [8.0, 8.0, 56.0, 40.0],
            fade: packFade([1.0, 2.0, 3.0, 4.0], [8.0, 8.0, 56.0, 40.0], [8.0, 8.0, 56.0, 40.0])
        )
        inst.roundClip(16.0)
        #expect(unpackClipRadii(inst.fade[3]) == [16.0, 16.0, 16.0, 16.0])

        inst.roundClipCorners([-12.0, -4.0, 0.0, -8.0])
        #expect(unpackClipRadii(inst.fade[3]) == [-12.0, -4.0, 0.0, -8.0])

        let layer = Instance.beginLayer(
            [8.0, 8.0, 48.0, 32.0],
            [8.0, 8.0, 56.0, 40.0],
            LayerSpec(opacity: 0.8, blend: .sourceOver, blur: 0.0, clipRadius: 16.0)
        )
        #expect(layer.params[1] == KIND_LAYER)
        #expect(unpackClipRadii(layer.fade[3]) == [16.0, 16.0, 16.0, 16.0])
    }

    @Test("Rounded clip container propagates clip bounds and radii to children and group layers")
    func roundedClipPropagatesBoundsAndGroupLayers() {
        let rt = Runtime.new((), { _, _ in
            el().child(
                rtAbsolute(el().key("card").size(48.0, 32.0), 8.0, 8.0)
                    .corners(Corners(12.0, 4.0, 0.0, 8.0))
                    .clip(true)
                    .opacity(0.8)
                    .child(
                        rtAbsolute(el().key("inner").size(64.0, 48.0), -8.0, -8.0)
                            .bg(.WHITE)
                    )
            )
        }, (64.0, 48.0), Env.new(true, 1.0))

        _ = rt.frame(0.0)
        guard let innerIdx = rt.nodes.firstIndex(where: { $0.key == "inner" }) else {
            Issue.record("Missing inner node")
            return
        }
        #expect(rt.nodes[innerIdx].clipBounds == [8.0, 8.0, 56.0, 40.0])
        #expect(rt.nodes[innerIdx].clipRadii == Corners(12.0, 4.0, 0.0, 8.0))
        #expect(rt.layers.count == 1)
        #expect(rt.layers[0].clipRadius > 0.0)
        #expect(rt.instances.contains { $0.params[1] == KIND_LAYER })
    }

    @Test("Blurred chip inside clipped capsule opens blur layer and closes once removed")
    func blurredChipInsideCapsuleOpensAndClosesLayer() {
        let rt = Runtime.new(true, { show, _ in
            var capsule = rtAbsolute(el().key("capsule").size(80.0, 40.0), 8.0, 8.0)
                .rounded(20.0)
                .clip(true)
            if show {
                capsule = capsule.child(
                    el().key("chip").size(40.0, 28.0)
                        .opacity(0.65)
                        .blur(1.5)
                        .rounded(8.0)
                        .bg(.WHITE)
                        .transition(Transition.blurReplace())
                )
            }
            return el().child(capsule)
        }, (96.0, 56.0), Env.new(true, 2.0))

        _ = rt.frame(0.0)
        #expect(rt.instances.contains { $0.params[1] == KIND_LAYER && $0.params[2] > 0.0 })

        rt.state = false
        rt.invalidate()
        _ = rt.frame(0.0)
        _ = rt.frame(0.04)
        #expect(!rt.exitingNodes.isEmpty)

        rtStepFrames(rt, 120)
        #expect(rt.exitingNodes.isEmpty)
        #expect(rt.instances.allSatisfy { $0.params[1] != KIND_LAYER })
    }
}
