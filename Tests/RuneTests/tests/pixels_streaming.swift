// Tests ported from: crates/rune/tests/pixels_streaming.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("PixelsStreamingIntegrationTests")
struct PixelsStreamingIntegrationTests {
    @Test func pixelsStreamUpdatesIncrementRevisionCleanly() {
        let pixels = Pixels.new()
        pixels.set(224, 128, [UInt8](repeating: 0, count: 224 * 128 * 4))
        let rt = IntegrationSupport.runtime(
            pixels,
            { p, _ in el().key("hud").size(112.0, 64.0).pixels(p) },
            (112.0, 64.0),
            Env.new(true, 2.0)
        )
        _ = rt.hostFrame(0.0)
        for n in UInt8(0)..<60 {
            pixels.set(224, 128, [UInt8](repeating: n, count: 224 * 128 * 4))
            _ = rt.hostFrame(1.0 / 60.0)
        }
        #expect(IntegrationSupport.find(rt, "hud").rect == [0.0, 0.0, 112.0, 64.0])
    }

    @Test(.disabled("Requires Wave 2 ImageAtlas streaming slot placement inspection in Spine Runtime"))
    func sixtyHudUpdatesAllocateNothingAndKeepTheSameSlot() {}
}
