// Tests ported from: crates/rune/src/window/mac_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("WindowMacDragRegionsTests")
struct WindowMacDragRegionsTests {
    @Test("scopeDragRegions carves out traffic light buttons on titled full-size-content windows")
    func scopeDragRegionsCarvesOutTrafficLightButtons() {
        let chrome = Chrome.DEFAULT // trafficLights at (15, 16)
        let regions = scopeDragRegions(
            chrome: chrome,
            borderless: false,
            fullscreen: false,
            viewport: (600.0, 400.0),
            regions: [[0.0, 0.0, 600.0, 40.0]]
        )
        #expect(!regions.isEmpty)
        // Close button center (14, 13) is excluded from drag regions
        #expect(!pointInDragRegions(14.0, 13.0, regions: regions))
        // Right side of the titlebar (300, 20) remains draggable
        #expect(pointInDragRegions(300.0, 20.0, regions: regions))

        // Borderless windows have no traffic lights, so the full bar remains draggable
        let borderlessRegions = scopeDragRegions(
            chrome: chrome,
            borderless: true,
            fullscreen: false,
            viewport: (600.0, 400.0),
            regions: [[0.0, 0.0, 600.0, 40.0]]
        )
        #expect(pointInDragRegions(14.0, 13.0, regions: borderlessRegions))
    }
}
