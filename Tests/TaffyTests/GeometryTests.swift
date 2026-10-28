// Swift-only: Behavioral tests for ported Taffy geometry types

import Testing
@testable import Taffy

@Suite("Taffy Geometry Tests")
struct TaffyGeometryTests {
    @Test("AbsoluteAxis and AbstractAxis")
    func testAxes() {
        #expect(AbsoluteAxis.horizontal.otherAxis() == .vertical)
        #expect(AbsoluteAxis.vertical.otherAxis() == .horizontal)

        #expect(AbstractAxis.inline.other() == .block)
        #expect(AbstractAxis.block.other() == .inline)
        #expect(AbstractAxis.inline.asAbsNaive() == .horizontal)
        #expect(AbstractAxis.block.asAbsNaive() == .vertical)
    }

    @Test("Point operations")
    func testPoint() {
        let p1 = Point<Float>(x: 10.0, y: 20.0)
        let p2 = Point<Float>(x: 5.0, y: 15.0)
        let pSum = p1 + p2

        #expect(pSum.x == 15.0)
        #expect(pSum.y == 35.0)
        #expect(p1.transpose() == Point<Float>(x: 20.0, y: 10.0))
        #expect(p1.main(direction: .row) == 10.0)
        #expect(p1.cross(direction: .row) == 20.0)
        #expect(p1.main(direction: .column) == 20.0)
        #expect(p1.cross(direction: .column) == 10.0)
    }

    @Test("Size operations and aspect ratio")
    func testSize() {
        let s1 = Size<Float>(width: 100.0, height: 50.0)
        let s2 = Size<Float>(width: 20.0, height: 30.0)

        #expect((s1 + s2) == Size<Float>(width: 120.0, height: 80.0))
        #expect((s1 - s2) == Size<Float>(width: 80.0, height: 20.0))
        #expect(s1.hasNonZeroArea())
        #expect(!Size<Float>.ZERO.hasNonZeroArea())

        let sOpt = Size<Float?>(width: 100.0, height: nil)
        let withRatio = sOpt.maybeApplyAspectRatio(aspectRatio: 2.0)
        #expect(withRatio.width == 100.0)
        #expect(withRatio.height == 50.0)

        let sOptH = Size<Float?>(width: nil, height: 50.0)
        let withRatioH = sOptH.maybeApplyAspectRatio(aspectRatio: 2.0)
        #expect(withRatioH.width == 100.0)
        #expect(withRatioH.height == 50.0)
    }

    @Test("Rect operations")
    func testRect() {
        let r1 = Rect<Float>(left: 1.0, right: 2.0, top: 3.0, bottom: 4.0)
        let r2 = Rect<Float>(left: 10.0, right: 20.0, top: 30.0, bottom: 40.0)
        let rSum = r1 + r2

        #expect(rSum == Rect<Float>(left: 11.0, right: 22.0, top: 33.0, bottom: 44.0))
        #expect(r1.horizontalAxisSum() == 3.0)
        #expect(r1.verticalAxisSum() == 7.0)
        #expect(r1.mainAxisSum(direction: .row) == 3.0)
        #expect(r1.crossAxisSum(direction: .row) == 7.0)
        #expect(r1.mainAxisSum(direction: .column) == 7.0)
        #expect(r1.crossAxisSum(direction: .column) == 3.0)
        #expect(r1.gridAxisSum(axis: .horizontal) == 3.0)
        #expect(r1.gridAxisSum(axis: .vertical) == 7.0)
    }

    @Test("Line operations")
    func testLine() {
        let l = Line<Float>(start: 10.0, end: 20.0)
        #expect(l.sum() == 30.0)
        #expect(l.map { $0 * 2 } == Line<Float>(start: 20.0, end: 40.0))
    }
}
