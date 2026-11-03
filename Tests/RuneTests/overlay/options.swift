// Tests ported from: crates/rune/src/overlay/options.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("OverlayOptionsTests")
struct OverlayOptionsTests {
    @Test("a frame takes the scale of the display holding most of it")
    func frameTakesScaleOfDisplayHoldingMostOfIt() {
        // A 2x laptop with a 1x monitor to its right, in one global space.
        let displays: [([Double], Double)] = [
            ([0.0, 0.0, 1512.0, 982.0], 2.0),
            ([1512.0, 0.0, 1920.0, 1080.0], 1.0),
        ]
        #expect(overlayScaleUnder([100.0, 100.0, 400.0, 300.0], displays) == 2.0)
        #expect(overlayScaleUnder([1400.0, 100.0, 400.0, 300.0], displays) == 1.0)
        #expect(overlayScaleUnder([1400.0, 100.0, 200.0, 300.0], displays) == 2.0)
        #expect(overlayScaleUnder([-900.0, 0.0, 400.0, 300.0], displays) == nil)
    }

    @Test("display selection handles negative origins shared edges and disconnects")
    func displaySelectionHandlesNegativeOriginsSharedEdgesAndDisconnects() {
        // Native pixels, so a 2x display can have a larger rectangle than the primary.
        let bounds: [[Double]] = [
            [-3840.0, -200.0, 0.0, 1960.0],
            [0.0, 0.0, 1920.0, 1080.0],
        ]
        #expect(overlayChooseDisplay(bounds, 1, nil, (-100.0, 0.0)) == 0)
        #expect(overlayChooseDisplay(bounds, 1, nil, (0.0, 0.0)) == 1)
        #expect(overlayChooseDisplay(bounds, 1, 0, nil) == 0)
        #expect(overlayChooseDisplay(bounds, 1, 4, nil) == 1)
        #expect(overlayChooseDisplay(bounds, nil, nil, nil) == 0)
        #expect(overlayChooseDisplay([], nil, nil, nil) == nil)
    }

    @Test("edge and rect use display local points")
    func edgeAndRectUseDisplayLocalPoints() {
        let at = OverlayPlacementSpec(
            size: (300.0, 80.0),
            edge: .bottom,
            margin: 24.0,
            align: .end,
            inset: 12.0
        )
        #expect(overlayLocalRect(at, nil, (960.0, 540.0)) == [648.0, 436.0, 300.0, 80.0])
        #expect(overlayLocalRect(at, .fullScreen, (960.0, 540.0)) == [0.0, 0.0, 960.0, 540.0])
        #expect(
            overlayLocalRect(
                at,
                .rect(x: -10.0, y: 20.0, width: 100.0, height: 50.0),
                (960.0, 540.0)
            ) == [-10.0, 20.0, 100.0, 50.0]
        )
        // A 2x display left of primary: scale local offsets, never the desktop origin.
        let r = overlayLocalRect(at, nil, (960.0, 540.0))
        #expect((-1920 + Int32(r[0] * 2.0), -100 + Int32(r[1] * 2.0)) == (-624, 772))
    }
}
