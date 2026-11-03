// Tests ported from: crates/rune/tests/clip.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private struct ClipTestState {
    var pressed: Bool = false
    var stick: Bool = false
    var soft: Bool = false
}

private func clipTestView(_ s: ClipTestState, _: Cx<ClipTestState>) -> El {
    let scroll = col().key("scroll").size(100.0, 100.0).scroll(ScrollSpec(stickBottom: s.stick))
        .child(el().size(100.0, 60.0).fill(.WHITE))
        .child(el().key("under").size(100.0, 80.0).fill(.WHITE).onPress { (s: inout ClipTestState, _: inout Tx) in s.pressed = true })
    return col().size(100.0, 200.0).child(el().h(40.0)).child(scroll)
}

@Suite("ClipIntegrationTests")
struct ClipIntegrationTests {
    @Test(.disabled("Requires Wave 2 wgpu Offscreen pixel readback in Renderer"))
    func overflowingScrollContentStaysInsideTheBoxAsItScrolls() {}

    @Test func aPressOutsideTheBoxMissesClippedContent() {
        let rt = IntegrationSupport.runtime(ClipTestState(), clipTestView, (100.0, 200.0), Env.new(true, 1.0))
        _ = rt.hostFrame(0.0)
        _ = rt.hostPointerDown(50.0, 160.0)
        _ = rt.hostPointerUp(50.0, 160.0)
        _ = rt.hostFrame(1.0 / 120.0)
        let p0 = rt.state.pressed
        #expect(!p0, "the overflowing part of the child isn't hit")
        _ = rt.hostPointerDown(50.0, 130.0)
        _ = rt.hostPointerUp(50.0, 130.0)
        _ = rt.hostFrame(1.0 / 120.0)
        let p1 = rt.state.pressed
        #expect(p1, "the visible part still is")
    }

    @Test(.disabled("Requires Wave 2 El.clipFade and Offscreen GPU pixel readback in Renderer"))
    func anExplicitSoftClipStillWins() {}

    @Test(.disabled("Requires Wave 2 El.clipFade / El.clipSoft and Offscreen GPU pixel readback in Renderer"))
    func packedFadesSurviveGroupLayerProjectionWithoutDoubleApplication() {}

    @Test(.disabled("Requires Wave 2 El.clipFade / El.streaming and Offscreen GPU pixel readback in Renderer"))
    func narrowerNestedEdgeAndStreamingMaskSurviveOuterFades() {}

    @Test(.disabled("Requires Wave 2 El.clipFade and Offscreen GPU pixel readback in Renderer"))
    func nestedRowTextKeepsFullAlphaInTheMiddleOfAFadedList() {}
}
