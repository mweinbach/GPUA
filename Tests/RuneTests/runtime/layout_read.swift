// Tests ported from: crates/rune/src/runtime/layout_read.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("LayoutReadUnitTests")
struct LayoutReadUnitTests {
    @Test("LayoutReadSnapshot compares layout, window, and caret rects with sub-pixel tolerance")
    func layoutReadSnapshotDiffersOnlyForWatchedKeys() {
        var snapA = LayoutReadSnapshot()
        snapA.layoutRects["card"] = [10.0, 20.0, 100.0, 40.0]
        snapA.layoutRects["other"] = [0.0, 0.0, 50.0, 50.0]
        snapA.windowRects["card"] = [10.0, 20.0, 100.0, 40.0]

        var snapB = snapA
        snapB.layoutRects["other"] = [0.0, 120.0, 50.0, 50.0]

        // Watching only `"card"` sees no change when `"other"` moves
        #expect(!snapB.differs(for: ["card"], caretRead: false, from: snapA))
        #expect(snapB.differs(for: ["other"], caretRead: false, from: snapA))

        // Caret movement triggers `caretRead`
        snapB.caret = ("root/field", [12.0, 24.0, 1.5, 18.0])
        #expect(snapB.differs(for: [], caretRead: true, from: snapA))
        #expect(!snapB.differs(for: [], caretRead: false, from: snapA))
    }

    @Test("Runtime layoutRect and windowLayoutRect report committed element bounds")
    func runtimeLayoutRectAndWindowLayoutRect() {
        let rt = Runtime.new((), { _, _ in
            col().wFull().hFull().pad(10.0).child(
                el().key("card").size(100.0, 40.0)
            )
        }, (300.0, 200.0), Env.new(true, 2.0))
        _ = rt.frame(0.0)

        #expect(rt.layoutRect("card") == [10.0, 10.0, 100.0, 40.0])
        #expect(rt.windowLayoutRect("card") == [10.0, 10.0, 100.0, 40.0])
    }
}
