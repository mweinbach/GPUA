// Tests ported from: crates/rune/src/runtime/row_reorder_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import RuneMotion
import Testing
@testable import Rune

private typealias ReorderRows = [(String, Float)]

private func makeChatRows() -> ReorderRows {
    [("m0", 120.0), ("m1", 60.0), ("m2", 90.0), ("p", 36.0), ("w", 77.0)]
}

private func chatView(_ rows: ReorderRows, _ cx: Cx<ReorderRows>, pinned: Bool = true) -> El {
    _ = cx
    let children = rows.map { (k, h) in
        rtAnimateLayout(el().key(k).wFull().h(h).bg(.WHITE))
    }
    let stack = col().key("stack").wFull().pad(12.0).gap(8.0).growth(GrowthSpec()).children(children)
    return col().wFull().hFull().child(
        col().key("scroll").wFull().h(300.0).scroll(ScrollSpec(stickBottom: pinned)).child(stack)
    )
}

private func settledChat(_ rows: ReorderRows) -> Runtime<ReorderRows> {
    let rt = Runtime.new(rows, { r, cx in chatView(r, cx, pinned: true) }, (300.0, 300.0), Env.new(true, 2.0))
    _ = rt.frame(0.0)
    rtStepFrames(rt, 240)
    return rt
}

private func rowTopY(_ rt: Runtime<ReorderRows>, _ key: String) -> Float {
    rt.elements().first { $0.key == key && !$0.exiting }!.rect[1]
}

private func swapLastTwo(_ rows: inout ReorderRows) {
    let n = rows.count
    rows.swapAt(n - 2, n - 1)
}

@Suite("RuntimeRowReorderTests")
struct RuntimeRowReorderTests {
    @Test("Reordered rows slide smoothly into place while stationary rows hold still")
    func reorderedRowsSlideIntoPlace() {
        let rt = settledChat(makeChatRows())
        #expect(!rt.animating)
        let p0 = rowTopY(rt, "p")
        let w0 = rowTopY(rt, "w")
        let m2 = rowTopY(rt, "m2")

        rt.update { rows, _ in swapLastTwo(&rows) }
        var pTrace: [Float] = []
        var wTrace: [Float] = []
        var m2Trace: [Float] = []
        for _ in 0..<120 {
            _ = rt.frame(1.0 / 120.0)
            pTrace.append(rowTopY(rt, "p"))
            wTrace.append(rowTopY(rt, "w"))
            m2Trace.append(rowTopY(rt, "m2"))
        }

        // First frame moves smoothly rather than jumping all 85 pt at once
        #expect(abs(pTrace[0] - p0) > 0.01)
        #expect(abs(pTrace[0] - p0) < 25.0)
        // Lands cleanly at swapped destinations (`p0 + 77 + 8` and `p0`)
        #expect(abs(pTrace.last! - (p0 + 85.0)) < 0.05)
        #expect(abs(wTrace.last! - p0) < 0.05)
        #expect(abs(w0 - (p0 + 44.0)) < 0.05)
        // Unmoved row above holds completely still
        #expect(m2Trace.allSatisfy { abs($0 - m2) < 0.01 })
        #expect(!rt.animating)

        // Swapping back mid-slide reverses smoothly without jumping
        rt.update { rows, _ in swapLastTwo(&rows) }
        rtStepFrames(rt, 12)
        let pMid = rowTopY(rt, "p")
        let wMid = rowTopY(rt, "w")
        rt.update { rows, _ in swapLastTwo(&rows) }
        _ = rt.frame(1.0 / 120.0)
        #expect(abs(rowTopY(rt, "p") - pMid) <= 15.0)
        #expect(abs(rowTopY(rt, "w") - wMid) <= 15.0)
        rtStepFrames(rt, 120)
        #expect(abs(rowTopY(rt, "p") - (p0 + 85.0)) < 0.05)
        #expect(abs(rowTopY(rt, "w") - p0) < 0.05)
    }

    @Test("Instant or reduced-motion reorder lands immediately on the first frame")
    func instantOrReducedMotionReorderLandsAtOnce() {
        for reduced in [false, true] {
            let rt = settledChat(makeChatRows())
            rt.reducedMotion = reduced
            let p0 = rowTopY(rt, "p")
            rt.update { rows, tx in
                if !reduced { tx.instant() }
                swapLastTwo(&rows)
            }
            _ = rt.frame(1.0 / 120.0)
            #expect(abs(rowTopY(rt, "w") - p0) < 0.01)
            #expect(abs(rowTopY(rt, "p") - (p0 + 85.0)) < 0.01)
            #expect(!rt.animating)
        }
    }

    @Test("Row moved past middle siblings slides passed siblings and leaves outer rows untouched")
    func rowMovedPastMiddleSiblingsSlidesPassedSiblingsOnly() {
        let rt = settledChat(makeChatRows())
        let keys = ["m0", "m1", "m2", "p", "w"]
        let before = keys.map { rowTopY(rt, $0) }

        rt.update { rows, _ in
            let r = rows.remove(at: 1)
            rows.insert(r, at: 3)
        }
        var m0Trace: [Float] = []
        var wTrace: [Float] = []
        for _ in 0..<120 {
            _ = rt.frame(1.0 / 120.0)
            m0Trace.append(rowTopY(rt, "m0"))
            wTrace.append(rowTopY(rt, "w"))
        }

        #expect(abs(rowTopY(rt, "m1") - (before[1] + 90.0 + 36.0 + 16.0)) < 0.05)
        #expect(abs(rowTopY(rt, "m2") - (before[2] - 68.0)) < 0.05)
        #expect(abs(rowTopY(rt, "p") - (before[3] - 68.0)) < 0.05)
        #expect(m0Trace.allSatisfy { abs($0 - before[0]) < 0.01 })
        #expect(wTrace.allSatisfy { abs($0 - before[4]) < 0.01 })
    }

    @Test("Row that grows and reorders in one commit settles cleanly above passed sibling")
    func rowThatMovesAndGrowsSettlesWithoutJump() {
        let rt = settledChat([("m0", 120.0), ("m1", 60.0), ("m2", 90.0), ("w", 77.0), ("a", 53.0), ("b", 53.0)])
        let b0 = rowTopY(rt, "b")
        rt.update { rows, _ in
            rows[4].1 = 77.0
            let a = rows.remove(at: 4)
            rows.insert(a, at: 3)
        }
        var prevB = b0
        for _ in 0..<120 {
            _ = rt.frame(1.0 / 120.0)
            let curB = rowTopY(rt, "b")
            #expect(abs(curB - prevB) <= 20.0)
            prevB = curB
        }
        #expect(!rt.animating)
        let endA = rowTopY(rt, "a")
        let endW = rowTopY(rt, "w")
        #expect(abs(endW - endA - 85.0) < 0.05)
    }

    @Test("Variable-height drag reorder target and sibling displacements respect row heights and gap")
    func variableHeightDragReorderDisplacementsRespectGap() {
        let spans: [(Float, Float)] = [(0.0, 36.0), (44.0, 77.0), (129.0, 90.0)]
        let target = resolveRowReorderTarget(spans: spans, sourceIndex: 0, dragOffset: 90.0)
        #expect(target == 1)
        let shifts = computeRowReorderDisplacements(
            spans: spans,
            gap: 8.0,
            sourceIndex: 0,
            targetIndex: target,
            dragOffset: 90.0
        )
        #expect(shifts == [90.0, -44.0, 0.0])
    }
}
