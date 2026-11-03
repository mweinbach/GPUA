// Tests ported from: crates/rune/tests/layout_read_highlights.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private struct LayoutReadHighlightState {
    var hitRow: Int
    var rowRect: [Float]? = nil
}

private func layoutReadHighlightView(_ s: LayoutReadHighlightState, _ cx: Cx<LayoutReadHighlightState>) -> El {
    let list = (0..<30).reduce(
        col().key("list").wFull().h(120.0).scroll(ScrollSpec(stickBottom: false))
    ) { c, i in
        c.child(text("row \(i) match here").key("row\(i)").h(20.0))
    }
    _ = cx.windowLayout("row\(s.hitRow)")
    return col().size(240.0, 120.0).child(list)
}

@Suite("LayoutReadHighlightsIntegrationTests")
struct LayoutReadHighlightsIntegrationTests {
    @Test func windowLayoutTracksScrolledRowRects() {
        var latestRowRect: [Float]? = nil
        let rt = IntegrationSupport.runtime(
            LayoutReadHighlightState(hitRow: 6),
            { s, cx in
                latestRowRect = cx.windowLayout("row\(s.hitRow)")
                return layoutReadHighlightView(s, cx)
            },
            (240.0, 120.0),
            Env.new(true, 1.0)
        )
        for _ in 0..<4 {
            _ = rt.hostFrame(1.0 / 60.0)
        }
        guard let initial = latestRowRect else {
            Issue.record("expected windowLayout for row6 after initial frames")
            return
        }
        #expect(abs(initial[1] - 120.0) < 0.01)

        _ = rt.hostWheel(100.0, 60.0, -40.0)
        for _ in 0..<4 {
            _ = rt.hostFrame(1.0 / 60.0)
        }
        rt.hostUpdate { s, _ in
            s.hitRow = 6
        }
        _ = rt.hostFrame(1.0 / 60.0)
        if let scrolled = latestRowRect {
            #expect(scrolled[1] < initial[1])
        } else {
            Issue.record("expected windowLayout for row6 after wheel scroll")
        }
    }

    @Test(.disabled("Requires Wave 2 El.textHighlight sub-element layout rects in Spine El/Runtime"))
    func cxWindowLayoutReadsKeyedTextHighlightsAcrossScrollAndUpdates() {}
}
