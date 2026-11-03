// Tests ported from: crates/rune/tests/pinned_scroll.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private func pinnedScrollRows(_ prefix: String) -> El {
    (0..<30).reduce(col().wFull()) { c, i in
        c.child(el().key("\(prefix)\(i)").wFull().h(40.0))
    }
}

private func pinnedScrollView(_: Void, _: Cx<Void>) -> El {
    col()
        .wFull()
        .hFull()
        .child(
            col()
                .key("panel")
                .w(300.0)
                .h(400.0)
                .padding(10.0)
                .child(
                    col()
                        .key("scroll")
                        .pin(0.0, 40.0, 0.0, 0.0)
                        .scroll(ScrollSpec(stickBottom: false))
                        .child(pinnedScrollRows("a"))
                )
        )
        .child(
            col().wFull().padding(20.0).child(
                col()
                    .key("sidebar")
                    .w(200.0)
                    .h(300.0)
                    .px(8.0)
                    .py(12.0)
                    .border(1.0, .BLACK)
                    .child(
                        col()
                            .key("nested")
                            .pin(0.0, 0.0, 0.0, 30.0)
                            .scroll(ScrollSpec(stickBottom: false))
                            .child(pinnedScrollRows("b"))
                    )
            )
        )
}

private func pinnedScrollGrownView(_: Void, _: Cx<Void>) -> El {
    col()
        .wFull()
        .hFull()
        .child(el().key("header").wFull().h(50.0))
        .child(
            col()
                .key("body")
                .wFull()
                .grow(1.0)
                .shrink()
                .child(
                    col()
                        .key("scroll")
                        .pin(0.0, 0.0, 0.0, 0.0)
                        .scroll(ScrollSpec(stickBottom: true))
                        .child(pinnedScrollRows("c"))
                )
        )
}

@Suite("PinnedScrollIntegrationTests")
struct PinnedScrollIntegrationTests {
    @Test func aPinnedScrollFillsItsInsetsAndScrolls() {
        let rt = IntegrationSupport.runtime((), pinnedScrollView, (600.0, 900.0), Env.new(true, 2.0))
        _ = rt.hostFrame(0.0)
        let panel = IntegrationSupport.find(rt, "panel")
        let scroll = IntegrationSupport.find(rt, "scroll")
        #expect(scroll.rect == [panel.rect[0], panel.rect[1] + 40.0, 300.0, 360.0])

        let sidebar = IntegrationSupport.find(rt, "sidebar")
        let nested = IntegrationSupport.find(rt, "nested")
        #expect(nested.rect == [sidebar.rect[0], sidebar.rect[1], 200.0, 270.0])

        let before = IntegrationSupport.find(rt, "a5").rect[1]
        _ = rt.hostWheel(100.0, 200.0, -120.0)
        for _ in 0..<30 {
            _ = rt.hostFrame(1.0 / 60.0)
        }
        #expect(IntegrationSupport.find(rt, "a5").rect[1] < before - 100.0)
        #expect(IntegrationSupport.find(rt, "scroll").rect == scroll.rect)
    }

    @Test func aPinnedScrollInAFlexGrownParentNeitherGrowsItNorItself() {
        let rt = IntegrationSupport.runtime((), pinnedScrollGrownView, (400.0, 600.0), Env.new(true, 2.0))
        _ = rt.hostFrame(0.0)
        #expect(IntegrationSupport.find(rt, "body").rect == [0.0, 50.0, 400.0, 550.0])
        #expect(IntegrationSupport.find(rt, "scroll").rect == [0.0, 50.0, 400.0, 550.0])
        let last = IntegrationSupport.find(rt, "c29").rect
        #expect(abs(last[1] + last[3] - 600.0) < 0.05)
    }
}
