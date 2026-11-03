// Tests ported from: crates/rune/src/runtime/paint_tracks_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("PaintTracksTests")
struct PaintTracksTests {
    private struct State {
        var dark: Bool
    }

    private static func buildView(_ s: State, _ cx: Cx<State>) -> El {
        _ = cx
        let (bg, fg): (Color, Color) = s.dark ? (.BLACK, .WHITE) : (.WHITE, .BLACK)
        return col().wFull().hFull().bg(bg).children((0..<8).map { i in
            el().key("row-\(i)").wFull().h(20.0).bg(bg).rounded(4.0).opacity(0.9)
                .border(1.0, fg)
                .boxShadow(Shadow(x: 0.0, y: 2.0, blur: 6.0, spread: 0.0, color: fg))
                .hover(fg.alpha(0.1))
                .press(fg.alpha(0.2))
                .child(text("row \(i)").key("lbl-\(i)").color(fg))
        })
    }

    private func settled(_ dark: Bool) -> Runtime<State> {
        let rt = Runtime.new(State(dark: dark), Self.buildView, (200.0, 300.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)
        for _ in 0..<240 {
            _ = rt.frame(1.0 / 120.0)
            if !rt.animating { break }
        }
        _ = rt.scene.frame()
        return rt
    }

    @Test("A static tree allocates zero paint tracks and unchanged commits leave the scene clean")
    func staticTreeKeepsZeroTracksAndUnchangedCommitLeavesSceneClean() {
        let rt = settled(false)
        #expect(rt.scene.store().trackLen() == 0)
        rt.invalidate()
        _ = rt.frame(1.0 / 120.0)
        #expect(rt.scene.store().trackLen() == 0)
        #expect(rt.scene.frame().changed.isEmpty)
    }

    @Test("A first color change crossfades fill, text, border, and shadow from the drawn color")
    func firstColorChangeCrossfadesFromDrawnColor() {
        let rt = settled(false)
        rt.update { s, _ in s.dark = true }
        _ = rt.frame(1.0 / 120.0)
        _ = rt.frame(1.0 / 120.0)

        let rowIdx = rt.nodes.firstIndex(where: { $0.key == "row-3" })!
        let rowNode = rt.nodes[rowIdx]
        let fill = rt.sampledColor(rowNode.nodeId, P_FILL, rowNode.vis.fill)
        #expect(fill.r > 0.0 && fill.r < 1.0)

        let border = rt.sampledColor(rowNode.nodeId, P_BORDER, rowNode.vis.border)
        #expect(border.r > 0.0 && border.r < 1.0)

        let lblIdx = rt.nodes.firstIndex(where: { $0.key == "lbl-3" })!
        let lblNode = rt.nodes[lblIdx]
        let txtColor = rt.sampledColor(lblNode.nodeId, P_TEXT, lblNode.textSpec!.color)
        #expect(txtColor.r > 0.0 && txtColor.r < 1.0)

        for _ in 0..<240 {
            _ = rt.frame(1.0 / 120.0)
            if !rt.animating { break }
        }
        let settledRow = rt.nodes[rt.nodes.firstIndex(where: { $0.key == "row-3" })!]
        #expect(rt.sampledColor(settledRow.nodeId, P_FILL, settledRow.vis.fill) == .BLACK)
        #expect(rt.sampledColor(settledRow.nodeId, P_BORDER, settledRow.vis.border) == .WHITE)
    }

    @Test("An instant color change lands immediately without allocating a spring track")
    func instantColorChangeLandsImmediately() {
        let rt = settled(false)
        rt.update { s, tx in
            s.dark = true
            tx.instant()
        }
        _ = rt.frame(1.0 / 120.0)
        let rowNode = rt.nodes[rt.nodes.firstIndex(where: { $0.key == "row-3" })!]
        #expect(rt.sampledColor(rowNode.nodeId, P_FILL, rowNode.vis.fill) == .BLACK)
        #expect(rt.scene.store().trackLen() == 0)
    }
}
