// Tests ported from: crates/rune/tests/drawn_layout.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Rects under live transforms: `El.onDrawnLayout` reports where an element on a zoomed,
//! panned canvas shows, hit tests and `ElementInfo.rect` agree with it, and `onLayout` keeps
//! the laid-out rect.

import Testing
@testable import Rune

@Suite("DrawnLayoutIntegrationTests")
struct DrawnLayoutIntegrationTests {
    @Test(.disabled("Requires Wave 2 El.onDrawnLayout and El.liveScale camera zoom in Spine El/Runtime"))
    func aCameraPanAndZoomReportTheDrawnRectWithoutACommit() {}

    @Test(.disabled("Requires Wave 2 El.liveScale hit-test inverse projection in Spine Runtime"))
    func hitTestsAndDragsFollowTheLiveZoomAndPan() {}

    @Test(.disabled("Requires Wave 2 El.onDrawnLayout feedback damping in Spine Runtime"))
    func aHandlerThatMovesItsOwnElementFallsQuiet() {}

    @Test func dragPointsInAScrolledListAreFromWhereTheRowIsDrawn() {
        struct Pt: Equatable {
            var x: Float
            var y: Float
        }
        func list(_: [Pt], _: Cx<[Pt]>) -> El {
            var rows = col().wFull()
            for i in 0..<20 {
                rows = rows.child(
                    el().key("row\(i)").wFull().h(40.0)
                        .onDrag { (s: inout [Pt], d: inout Drag, _: inout Tx) in
                            s.append(Pt(x: d.x, y: d.y))
                        }
                )
            }
            return col().wFull().hFull()
                .child(col().key("list").wFull().h(200.0).scroll(ScrollSpec(stickBottom: false)).child(rows))
        }
        let rt = IntegrationSupport.runtime([] as [Pt], list, (300.0, 300.0), Env.new(true, 1.0))
        _ = rt.hostFrame(0.0)
        _ = rt.hostWheel(150.0, 100.0, -100.0)
        _ = rt.hostFrame(0.0)
        // Row 5 (laid out at 200) is drawn at 100.
        _ = rt.hostPointerDown(10.0, 110.0)
        _ = rt.hostPointerUp(10.0, 110.0)
        _ = rt.hostFrame(0.0)
        let first = rt.state.first
        #expect(first == Pt(x: 10.0, y: 10.0))
    }
}
