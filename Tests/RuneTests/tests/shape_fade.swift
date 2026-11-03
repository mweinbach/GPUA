// Tests ported from: crates/rune/tests/shape_fade.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("ShapeFadeIntegrationTests")
struct ShapeFadeIntegrationTests {
    @Test(.disabled("Requires Wave 2 canvas Shape multi-piece layer emission and Gpu.headless() pixel readback in Spine Runtime/render.swift"))
    func onlyAFadingShapeOfSeveralPiecesPaintsThroughALayer() {}

    @Test(.disabled("Requires Wave 2 canvas Shape multi-piece layer emission and Gpu.headless() pixel readback in Spine Runtime/render.swift"))
    func whereFadedPiecesMeetIsNoDarkerThanOne() {}
}
