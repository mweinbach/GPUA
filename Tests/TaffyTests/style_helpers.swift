// Tests ported from: src/style_helpers.rs (#[cfg(test)] items)
// Upstream commit: 599b1b7d7410d97e13bafc4c01fbe6d7a9cf060a
// Port status: ported

import Testing
@testable import Taffy

@Suite("Taffy Style Helpers Tests")
struct TaffyStyleHelpersTests {
    @Test("Repeat function with integer count")
    func testRepeatU16() {
        let testVec: [TrackSizingFunction] = []
        let component: GridTemplateComponent<String> = repeat_(UInt16(123), testVec)
        #expect(
            component == .repeat_(GridTemplateRepetition(
                count: .count(123),
                tracks: testVec,
                lineNames: []
            ))
        )
    }

    @Test("Repeat function with auto-fit string")
    func testRepeatAutoFitStr() {
        let testVec: [TrackSizingFunction] = []
        let component: GridTemplateComponent<String> = repeat_("auto-fit", testVec)
        #expect(
            component == .repeat_(GridTemplateRepetition(
                count: .autoFit,
                tracks: testVec,
                lineNames: []
            ))
        )
    }

    @Test("Repeat function with auto-fill string")
    func testRepeatAutoFillStr() {
        let testVec: [TrackSizingFunction] = []
        let component: GridTemplateComponent<String> = repeat_("auto-fill", testVec)
        #expect(
            component == .repeat_(GridTemplateRepetition(
                count: .autoFill,
                tracks: testVec,
                lineNames: []
            ))
        )
    }

    @Test("Geometry and helper functions")
    func testHelpers() {
        let p: Point<Float> = .zero()
        #expect(p.x == 0.0 && p.y == 0.0)

        let s: Size<Dimension> = .auto()
        #expect(s.width.isAuto && s.height.isAuto)

        let r: Rect<Float> = .zero()
        #expect(r.left == 0.0 && r.right == 0.0 && r.top == 0.0 && r.bottom == 0.0)

        let l: Dimension = length(42.0)
        #expect(l.intoOption() == 42.0)

        let pct: Dimension = percent(0.5)
        #expect(pct.value == .percent(0.5))

        let f: TrackSizingFunction = flex(2.0)
        #expect(f.maxSizingFunction().isFr)
    }
}
