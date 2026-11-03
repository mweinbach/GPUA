// Tests ported from: crates/rune/tests/absolute_in_rows.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Absolute children size and pin against their parent's padding box, wherever the parent sits:
//! plain columns, growth stacks and virtual lists inside a scroll viewport. Root overlays
//! (scrims, anchored popovers) keep sizing against the window.

import Testing
@testable import Rune

private func absInRowsView(_ caseIdx: UInt8, _: Cx<UInt8>) -> El {
    func rowItem(_ i: Int) -> El {
        row().key("row\(i)").wFull().h(40.0).padding(4.0)
            .child(text("hello"))
            .child(el().key("cover\(i)").pin(0.0, 0.0, 0.0, 0.0))
            .child(el().key("full\(i)").absolute(0.0, 0.0).wFull().hFull())
            .child(el().key("half\(i)").absolute(10.0, 2.0).wFrac(0.5).h(4.0))
            .child(el().key("badge\(i)").pin(nil, nil, 6.0, 5.0).size(10.0, 10.0))
            .child(row().key("nest\(i)").absolute(0.0, 0.0).w(100.0).h(20.0)
                .child(el().key("inner\(i)").pin(0.0, nil, 0.0, nil).h(2.0)))
    }
    var stack = col().key("stack").wFull()
    if caseIdx >= 1 {
        stack = stack.growth(GrowthSpec())
    }
    for i in 0..<3 {
        stack = stack.child(rowItem(i))
    }
    return col().wFull().hFull().padding(20.0)
        .child(col().key("scroll").wFull().h(200.0).scroll(ScrollSpec(stickBottom: true)).child(stack))
        .child(el().key("scrim").absolute(0.0, 0.0).wFull().hFull())
        .child(col().key("pop").wFrac(0.25).h(30.0).anchored("row1", .bottom, .end, 4.0))
}

private func absInRowsTarget(_ rt: Runtime<UInt8>, _ key: String) -> [Float] {
    IntegrationSupport.find(rt, key).target
}

@Suite("AbsoluteInRowsIntegrationTests")
struct AbsoluteInRowsIntegrationTests {
    @Test func absoluteChildrenOfRowsSizeAgainstTheRow() {
        for (caseIdx, name) in ["column", "growth stack"].enumerated() {
            let rt = IntegrationSupport.runtime(UInt8(caseIdx), absInRowsView, (400.0, 300.0), Env.new(true, 1.0))
            _ = rt.hostFrame(0.0)
            _ = rt.hostFrame(0.5)
            for i in 0..<3 {
                let y = 20.0 + 40.0 * Float(i)
                func at(_ key: String) -> [Float] {
                    absInRowsTarget(rt, "\(key)\(i)")
                }
                #expect(at("row") == [20.0, y, 360.0, 40.0], "\(name): row\(i)")
                #expect(at("cover") == [20.0, y, 360.0, 40.0], "\(name): pinned to all four edges")
                #expect(at("full") == [20.0, y, 360.0, 40.0], "\(name): wFull / hFull")
                #expect(at("half") == [30.0, y + 2.0, 180.0, 4.0], "\(name): wFrac(0.5)")
                #expect(at("badge") == [380.0 - 6.0 - 10.0, y + 40.0 - 5.0 - 10.0, 10.0, 10.0], "\(name): right/bottom pin")
                #expect(at("inner") == [20.0, y, 100.0, 2.0], "\(name): nested absolute")
            }
            #expect(absInRowsTarget(rt, "scrim") == [0.0, 0.0, 400.0, 300.0], "\(name): a root scrim still fills the window")
            #expect(absInRowsTarget(rt, "pop") == [380.0 - 100.0, 60.0 + 40.0 + 4.0, 100.0, 30.0], "\(name): anchored popover")
        }
    }
}
