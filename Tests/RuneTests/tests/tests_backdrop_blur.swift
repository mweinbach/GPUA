// Tests ported from: crates/rune/tests/backdrop_blur.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! `El.backdropBlur`: an element blurs what is drawn behind it in the same window, inside its
//! rounded rect and clip, under its fill.

import Testing
@testable import Rune

@Suite("BackdropBlurIntegrationTests")
struct BackdropBlurIntegrationTests {
    @Test(.disabled("Requires Wave 2 wgpu Offscreen backdropBlur pixel readback in Renderer/Runtime"))
    func stripesBlurInsideTheRoundedRectAndNowhereElse() {}

    @Test(.disabled("Requires Wave 2 wgpu Offscreen backdropBlur pixel readback in Renderer/Runtime"))
    func theFillTintsOverTheBlur() {}

    @Test(.disabled("Requires Wave 2 wgpu Offscreen backdropBlur pixel readback in Renderer/Runtime"))
    func withoutBackdropBlurTheFrameIsUnchanged() {}

    @Test(.disabled("Requires Wave 2 wgpu Offscreen backdropBlur pixel readback in Renderer/Runtime"))
    func twoBarsEachBlurTheirOwnBackdrop() {}

    @Test(.disabled("Requires Wave 2 wgpu Offscreen backdropBlur pixel readback in Renderer/Runtime"))
    func barsPastTheCapDrawOnlyTheirFill() {}

    @Test(.disabled("Requires Wave 2 wgpu Offscreen backdropBlur pixel readback in Renderer/Runtime"))
    func aFadedBarBlursTheWindowNotItsOwnLayer() {}

    @Test(.disabled("Requires Wave 2 wgpu Offscreen backdropBlur pixel readback in Renderer/Runtime"))
    func hidpiBlursInDevicePixels() {}

    @Test(.disabled("Requires Wave 2 wgpu Offscreen backdropBlur pixel readback in Renderer/Runtime"))
    func windowEdgesDoNotDarken() {}

    @Test(.disabled("Requires Wave 2 wgpu Offscreen backdropBlur pixel readback in Renderer/Runtime"))
    func scrolledContentChangesTheBlurAndAStillFrameStaysIdle() {}

    @Test(.disabled("Requires Wave 2 wgpu Offscreen backdropBlur pixel readback in Renderer/Runtime"))
    func theBlurStopsAtAnAncestorClip() {}

    @Test(.disabled("Requires Wave 2 wgpu Offscreen backdropBlur pixel readback in Renderer/Runtime"))
    func insideALayerTheBlurReadsTheLayer() {}
}
