// Tests ported from: crates/rune/tests/effect_data.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! What a compositor's hook learns about each effect slot: its `El.effect` tag
//! (`EffectSite.mark`), its `El.effectData` payload (`EffectSite.data`) frozen with the
//! element through its exit, and where the presented element is, transforms included.

import Testing
@testable import Rune

@Suite("EffectDataIntegrationTests")
struct EffectDataIntegrationTests {
    @Test(.disabled("Requires Wave 2 El.effectData and Renderer.drawWith EffectSite hook in Spine El/Renderer"))
    func siblingSlotsEachHandTheHookTheirOwnMarkAndPayload() {}

    @Test(.disabled("Requires Wave 2 El.effectData and Renderer.drawWith EffectSite hook in Spine El/Renderer"))
    func anExitingSlotKeepsItsMarkAndPayloadWhileItsReplacementEnters() {}

    @Test(.disabled("Requires Wave 2 El.effectData / El.rotate and Renderer.drawWith EffectSite hook"))
    func slotsFollowScaleOffsetAndTransitionsAndTurnInALayer() {}
}
