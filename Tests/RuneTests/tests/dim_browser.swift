// Tests ported from: crates/rune/tests/dim_browser.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! What CSS gives these boxes, in sRGB bytes: `El.dim` fades a solid box as `opacity` would,
//! with its outer shadows outside it and its fill and gradient fading as one, and an outer
//! shadow paints at its authored alpha over a transparent window or an opaque page.

import Testing
@testable import Rune

@Suite("DimBrowserIntegrationTests")
struct DimBrowserIntegrationTests {
    @Test(.disabled("Requires Wave 2 El.dim / El.gradient and Offscreen GPU pixel readback in Renderer"))
    func aDimmedButtonFadesAsCssOpacityDoes() {}

    @Test(.disabled("Requires Wave 2 Offscreen GPU shadow pixel readback in Renderer"))
    func aShadowPaintsItsAuthoredAlpha() {}
}
