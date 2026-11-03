// Tests ported from: crates/rune/tests/canvas_input.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Canvas input: `onWheel` ahead of scroll views, pinch, rotation and smart magnify in the
//! handler's own points, the middle button pressing and dragging elements that opt in, and key
//! releases.

import Testing
@testable import Rune

@Suite("CanvasInputIntegrationTests")
struct CanvasInputIntegrationTests {
    @Test(.disabled("Requires Wave 2 El.onWheel gesture routing in Spine El/Runtime"))
    func aWheelHandlerHearsDeltasBeforeTheScrollViewAroundIt() {}

    @Test(.disabled("Requires Wave 2 El.onWheel gesture routing in Spine El/Runtime"))
    func aDeclinedDeltaScrollsAndTheGestureStaysAScroll() {}

    @Test(.disabled("Requires Wave 2 El.onWheel momentum routing in Spine El/Runtime"))
    func momentumFollowsTheHandlerThatTookTheGesture() {}

    @Test(.disabled("Requires Wave 2 El.onMagnify / El.onRotate / El.onSmartMagnify in Spine El/Runtime"))
    func pinchRotationAndSmartMagnifyArriveInTheHandlersPoints() {}

    @Test(.disabled("Requires Wave 2 El.pointerButtons middle/back/forward opt-in in Spine El/Runtime"))
    func theMiddleButtonDragsOnlyElementsThatTakeIt() {}

    @Test(.disabled("Requires Wave 2 El.onKeyUp in Spine El/Runtime"))
    func aKeyReleaseGoesToTheFocusedElementThenUpToTheRoot() {}

    @Test func withoutKeyUpHandlersAReleaseNeedsNoFrame() {
        let rt = IntegrationSupport.runtime((), { _, _ in el().w(10.0).h(10.0) }, (100.0, 100.0), Env.new(true, 1.0))
        _ = rt.hostFrame(0.0)
        let handled = rt.hostKeyUp(KeyEvent(key: .escape, mods: Mods()))
        #expect(!handled)
        let (_, _, stats) = rt.hostFrame(1.0 / 60.0)
        #expect(!stats.animating)
    }
}
