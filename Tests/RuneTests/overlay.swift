// Tests ported from: crates/rune/src/overlay.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("OverlayRootTests")
struct OverlayRootTests {
    @Test("OverlaySpec builders produce ConfiguredOverlay preserving options")
    func overlaySpecBuildersProduceConfiguredOverlayPreservingOptions() {
        let spec = OverlaySpec<Int>(
            name: "capsule",
            size: (240.0, 44.0),
            edge: .top,
            margin: 12.0,
            align: .center,
            inset: 0.0,
            interactive: true,
            view: { _, _ in el() }
        )
        let configured = spec
            .animateReveal()
            .srgbBlend(false)
            .macosLevel(25)
        #expect(configured.animateRevealFlag)
        #expect(!configured.srgbBlend)
        #expect(configured.macosLevel == 25)
        #expect(configured.spec.name == "capsule")
    }
}
