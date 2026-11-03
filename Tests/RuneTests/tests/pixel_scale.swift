// Tests ported from: crates/rune/tests/pixel_scale.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private func pixelScaleView(_: Void, _: Cx<Void>) -> El {
    col().wFull().hFull().child(
        el()
            .key("row")
            .absolute(0.123, 0.137)
            .size(30.123, 20.137)
            .fill(.WHITE)
            .hover(.BLACK)
            .onPress { (_: inout Void, _: inout Tx) in }
    )
}

@Suite("PixelScaleIntegrationTests")
struct PixelScaleIntegrationTests {
    @Test func pixelScaleChangeMatchesInstancesFromAFreshRuntime() {
        let make = { (scale: Float) -> [Instance] in
            let rt = IntegrationSupport.runtime((), pixelScaleView, (240.0, 150.0), Env.new(true, scale))
            return rt.hostFrame(0.0).0
        }
        let rt = IntegrationSupport.runtime((), pixelScaleView, (240.0, 150.0), Env.new(true, 1.0))
        _ = rt.hostFrame(0.0)
        for scale: Float in [2.0, 1.5, 1.0] {
            rt.viewport = (240.0, 150.0)
            rt.env.scale = scale
            rt.scene.setPixelScale(scale)
            rt.hostInvalidate()
            let (instances, _, _) = rt.hostFrame(0.0)
            let fresh = make(scale)
            #expect(instances == fresh)
        }
    }
}
