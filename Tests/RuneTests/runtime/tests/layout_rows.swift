// Tests ported from: crates/rune/src/runtime/tests/layout_rows.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

@testable import Rune
import RuneMotion
import Testing

@Suite
struct RtLayoutRowsTests {
    @Test
    func duplicateSiblingKeysAreDisambiguatedAndReported() {
        let rt = Runtime.new((), { _, _ in
            col()
                .key("list")
                .size(200.0, 120.0)
                .child(el().key("row:R-94").size(200.0, 20.0))
                .child(el().key("row:R-94").size(200.0, 20.0))
                .child(el().key("row:R-94").size(200.0, 20.0))
        }, (200.0, 120.0), Env.new(true, 1.0))

        _ = rt.frame(0.0)
        let rowPaths = rt.nodes.filter { $0.path.contains("row:R-94") }.map(\.path)
        #expect(rowPaths == ["root/row:R-94", "root/row:R-94#dup1", "root/row:R-94#dup2"])
        let diags = rt.layoutDiagnostics()
        #expect(diags.filter { $0.kind == .duplicateSiblingKey }.count == 2)
    }

    @Test
    func sidePanelResizeWrapsWithoutReshapingMidFlightAndSettleAllClearsAnimations() {
        let rt = Runtime.new(Float(60.0), { sideW, _ in
            row()
                .size(320.0, 200.0)
                .child(el().key("side").size(sideW, 200.0).bg(.WHITE))
                .child(
                    col()
                        .key("main")
                        .grow(1.0)
                        .hFull()
                        .child(text("Wrapping prose paragraph that reflows when the side panel opens wider.").key("prose").wrap().wFull())
                )
        }, (320.0, 200.0), Env.new(true, 1.0))

        _ = rt.frame(0.0)
        rt.update { w, _ in w = 140.0 }
        _ = rt.frame(1.0 / 120.0) // commit frame shapes new target width once
        #expect(rt.animating)

        // Pure animation frames in between do not reshape text
        _ = rt.frame(1.0 / 120.0)
        #expect(rt.stats.shaped == 0)

        rt.settleAll()
        _ = rt.frame(1.0 / 120.0)
        #expect(!rt.animating)
        #expect(rtElement(rt, "side")?.rect[2] == 140.0)
    }

    @Test
    func flyTextRetainsVisibleGlyphsAcrossSubmitAndLandsAtDestination() {
        struct ChatState {
            var submitted: Bool = false
        }
        let rt = Runtime.new(ChatState(), { s, _ in
            var root = col().size(260.0, 200.0)
            if s.submitted {
                root = root.child(text("ship it").key("destination"))
            }
            root = root.child(spacer())
            if !s.submitted {
                root = root.child(text("ship it").key("source"))
            }
            return root
        }, (260.0, 200.0), Env.new(true, 1.0))

        _ = rt.frame(0.0)
        rt.update { s, tx in
            s.submitted = true
            tx.flyText("source", "destination")
        }
        _ = rt.frame(1.0 / 120.0)
        #expect(rt.stats.glyphs > 0)
        #expect(!rt.activeTextFlights.isEmpty)

        rtStepFrames(rt, 90)
        #expect(rt.activeTextFlights.isEmpty)
        #expect(rtElement(rt, "destination")?.text == "ship it")
    }

    @Test
    func reducedMotionGrowthRowsLandHeightImmediatelyWhileFadingPresence() {
        let rt = Runtime.new(1, { count, cx in
            cx.reducedMotion(true)
            let rows = (0..<count).map { i in
                el().key("r\(i)").wFull().h(100.0).bg(.WHITE)
            }
            return col().key("stack").size(200.0, 300.0).growth(GrowthSpec()).children(rows)
        }, (200.0, 300.0), Env.new(true, 1.0))

        _ = rt.frame(0.0)
        rt.update { n, _ in n = 2 }
        _ = rt.frame(1.0 / 120.0)

        let r1 = rtElement(rt, "r1")
        #expect(r1?.rect[3] == 100.0)
        #expect((r1?.opacity ?? 1.0) < 1.0)

        rtStepFrames(rt, 60)
        #expect(abs((rtElement(rt, "r1")?.opacity ?? 0.0) - 1.0) < 1e-3)
    }

    @Test
    func retainedLayoutMatchesFreshRuntimeAcrossEditsAndViewportChanges() {
        struct GridState: Equatable {
            var count: Int
            var pad: Float
            var wide: Bool
        }
        func gridView(_ s: GridState, _: Cx<GridState>) -> El {
            let items = (0..<s.count).map { i in
                row()
                    .key("item-\(i)")
                    .wFull()
                    .padXY(s.pad, 4.0)
                    .child(text("Row \(i) content").key("txt-\(i)").wrap().grow(1.0))
                    .child(el().key("badge-\(i)").size(s.wide ? 32.0 : 16.0, 16.0))
            }
            return col().key("root").wFull().hFull().gap(4.0).children(items)
        }

        let retained = Runtime.new(GridState(count: 4, pad: 6.0, wide: false), gridView, (280.0, 320.0), Env.new(true, 1.0))
        _ = retained.frame(0.0)

        for step in 1...20 {
            let vp: (Float, Float) = (240.0 + Float((step * 17) % 120), 260.0 + Float((step * 23) % 100))
            let scale: Float = (step % 2 == 0) ? 2.0 : 1.0
            let nextState = GridState(
                count: 2 + (step * 3) % 8,
                pad: Float(4 + (step % 5) * 2),
                wide: (step % 3 == 0)
            )
            retained.resize(vp.0, vp.1, Env.new(true, scale))
            retained.update { s, tx in
                tx.instant()
                s = nextState
            }
            _ = retained.frame(1.0 / 60.0)
            retained.settleAll()
            _ = retained.frame(1.0 / 60.0)

            let fresh = Runtime.new(nextState, gridView, vp, Env.new(true, scale))
            _ = fresh.frame(0.0)

            let rRects = retained.elements().map { ($0.path, $0.rect) }
            let fRects = fresh.elements().map { ($0.path, $0.rect) }
            #expect(rRects.count == fRects.count)
            for (a, b) in zip(rRects, fRects) {
                #expect(a.0 == b.0)
                for k in 0..<4 {
                    #expect(abs(a.1[k] - b.1[k]) < 0.5)
                }
            }
        }
    }
}
