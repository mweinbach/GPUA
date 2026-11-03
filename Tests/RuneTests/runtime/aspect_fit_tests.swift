// Tests ported from: crates/rune/src/runtime/aspect_fit_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("AspectFitTests")
struct AspectFitTests {
    private func cell(_ ratio: Float) -> El {
        col().size(300.0, 200.0).itemsCenter()
            .child(rtAspectFit(el().key("pic"), ratio))
            .child(text("caption").key("cap").h(20.0))
    }

    private func targetRects(_ rt: Runtime<Float>, _ keys: [String]) -> [[Float]] {
        let all = rt.elements()
        return keys.map { k in all.first(where: { $0.key == k })!.target }
    }

    @Test("A picture fits its cell and reacts to ratio and viewport changes")
    func pictureFitsCellAndReactsToRatioAndViewport() {
        let rt = Runtime.new(Float(2.0), { r, _ in
            col().wFull().hFull().itemsCenter().child(rtAspectFit(el().key("pic"), r))
        }, (800.0, 600.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)
        let r0 = targetRects(rt, ["pic"])[0]
        #expect([r0[2], r0[3]] == [800.0, 400.0])

        rt.update { r, _ in r = 0.5 }
        _ = rt.frame(1.0)
        let r1 = targetRects(rt, ["pic"])[0]
        #expect([r1[2], r1[3]] == [300.0, 600.0])

        rt.setViewport((400.0, 400.0), 1.0)
        _ = rt.frame(1.0)
        let r2 = targetRects(rt, ["pic"])[0]
        #expect([r2[2], r2[3]] == [200.0, 400.0])
    }

    @Test("Cells in a row each fit their own aspect ratio")
    func cellsInARowEachFitTheirOwn() {
        let rt = Runtime.new(Float(3.0), { r, _ in
            func makeCell(_ k: String, _ ratio: Float) -> El {
                col().grow(1.0).hFull().itemsCenter().child(rtAspectFit(el().key(k), ratio))
            }
            return col().child(
                row().size(610.0, 200.0).gap(10.0)
                    .child(makeCell("a", r))
                    .child(makeCell("b", 0.5))
            )
        }, (800.0, 600.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)
        #expect(targetRects(rt, ["a", "b"]) == [[0.0, 0.0, 300.0, 100.0], [410.0, 0.0, 100.0, 200.0]])
    }

    @Test("Max sizes and explicit cell dimensions bound aspect-fit elements")
    func maxSizesAndCellDimensionsBoundFittedBox() {
        let rt = Runtime.new(Float(2.0), { r, _ in
            col().child(cell(r))
        }, (800.0, 600.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)
        let rs = targetRects(rt, ["pic", "cap"])
        #expect(rs[0][2] == 300.0 && rs[0][3] == 150.0)
        #expect(rs[1][1] == 150.0)
    }
}
