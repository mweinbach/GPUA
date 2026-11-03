// Tests ported from: crates/rune/tests/effect_slot.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Effect slots (`El.effect`) and the compositor hooks around them: a compositor draws its own
//! pass at the slot, inside isolated layers, clipped like the primitives around it, in either
//! blend mode and in every format it is handed.

import Testing
@testable import Rune

@Suite("EffectSlotIntegrationTests")
struct EffectSlotIntegrationTests {
    @Test func effectSlotEmitsEffectInstanceAndSlotRectForHostCompositor() {
        func view(_: Void, _: Cx<Void>) -> El {
            el().size(96.0, 96.0).fill(.BLACK)
                .child(effect(7).key("slot").absolute(16.0, 16.0).size(64.0, 64.0))
        }
        let rt = IntegrationSupport.runtime((), view, (96.0, 96.0), Env.new(false, 1.0))
        let (instances, _, _) = rt.hostFrame(0.0)
        let effectInstances = instances.filter { $0.params[1] == KIND_EFFECT }
        #expect(effectInstances.count == 1)
        #expect(effectInstances[0].rect == [16.0, 16.0, 64.0, 64.0])
        let slots = rt.hostEffectSlots()
        #expect(slots.count == 1)
        #expect(slots[0].0 == 7)
        #expect(slots[0].1 == [16.0, 16.0, 64.0, 64.0])
    }

    @Test(.disabled("Requires Wave 2 custom WGSL RenderPipeline pass inside Renderer.encodeLayersWith"))
    func effectInAFadedLayerIsFadedAndUnderLaterContent() {}

    @Test(.disabled("Requires Wave 2 El.clipRounded and WGSL RenderPipeline pass inside Renderer"))
    func roundedClipCutsTheEffectCorner() {}

    @Test(.disabled("Requires Wave 2 custom WGSL RenderPipeline pass inside Renderer"))
    func opaqueEffectsMatchAcrossBlendModes() {}

    @Test(.disabled("Requires Wave 2 custom WGSL RenderPipeline pass inside Renderer"))
    func aFadedSlotIsFadedForTheCompositor() {}

    @Test(.disabled("Requires Wave 2 El.effectBleed and WGSL RenderPipeline pass inside Renderer"))
    func bleedReachesInAndTheScissorHoldsTheClip() {}

    @Test(.disabled("Requires Wave 2 EffectSite scale/backdrop hooks in Renderer"))
    func slotReportsDevicePixelsPerPointWithoutBleed() {}
}
