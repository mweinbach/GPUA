// Tests ported from: crates/rune/tests/absolute_frac.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! `wFrac` on an absolute child resolves against its own parent's padding box: not a padded
//! ancestor's (which made it 12 pt too wide under a 6 pt padded grandparent), not the parent's
//! content box, and with no scrollbar gutter in a scroll viewport.

import Testing
@testable import Rune

private struct AbsFracState {}

private func absFracBar(_ key: String) -> El {
    el().key(key).absolute(0.0, 0.0).wFrac(1.0).h(4.0)
}

private func absFracView(_: AbsFracState, _: Cx<AbsFracState>) -> El {
    col().wFull().hFull().padding(6.0).gap(10.0)
        // Rooms' case: a padded card inside a padded column; the bar spans the card.
        .child(col().key("card").wFull().h(60.0).padding(6.0).border(1.0, .BLACK).child(absFracBar("card-bar")))
        // Half and full widths in a row cell with its own padding.
        .child(row().wFull().h(40.0).child(
            col().key("cell").w(200.0).hFull().px(12.0)
                .child(absFracBar("cell-bar"))
                .child(el().key("cell-half").absolute(0.0, 10.0).wFrac(0.5).h(4.0))
        ))
        // Inside a padded scroll viewport's content: no gutter, no viewport padding added.
        .child(col().key("scroll").w(240.0).h(100.0).padding(6.0).scroll(ScrollSpec(stickBottom: false))
            .child(col().key("content").wFull().h(300.0).child(absFracBar("content-bar"))))
}

private func absFracRect(_ rt: Runtime<AbsFracState>, _ key: String) -> [Float] {
    IntegrationSupport.find(rt, key).rect
}

@Suite("AbsoluteFracIntegrationTests")
struct AbsoluteFracIntegrationTests {
    @Test func absoluteFractionsSpanTheParentsPaddingBox() {
        let rt = IntegrationSupport.runtime(AbsFracState(), absFracView, (400.0, 400.0), Env.new(true, 2.0))
        _ = rt.hostFrame(0.0)
        let card = absFracRect(rt, "card")
        #expect(card[2] == 388.0)
        #expect(absFracRect(rt, "card-bar") == [card[0], card[1], card[2], 4.0])

        let cell = absFracRect(rt, "cell")
        #expect(absFracRect(rt, "cell-bar") == [cell[0], cell[1], 200.0, 4.0])
        #expect(absFracRect(rt, "cell-half") == [cell[0], cell[1] + 10.0, 100.0, 4.0])

        let scroll = absFracRect(rt, "scroll")
        let content = absFracRect(rt, "content")
        #expect(content[2] == 228.0)
        #expect(absFracRect(rt, "content-bar") == [content[0], content[1], 228.0, 4.0])
        #expect(content[0] == scroll[0] + 6.0)
    }
}
