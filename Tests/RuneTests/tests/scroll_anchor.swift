// Tests ported from: crates/rune/tests/scroll_anchor.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private struct ScrollAnchorFeed {
    var above: Int = 0
    var firstH: Float = 40.0
    var below: Int = 0
    var stickBottom: Bool = false
}

private func scrollAnchorView(_ s: ScrollAnchorFeed, _: Cx<ScrollAnchorFeed>) -> El {
    var rows: [El] = []
    for k in 0..<s.above {
        rows.append(el().key("new\(k)").wFull().h(30.0))
    }
    rows.append(el().key("r0").wFull().h(s.firstH))
    for k in 1..<(30 + s.below) {
        rows.append(el().key("r\(k)").wFull().h(40.0))
    }
    let list = col().key("list").wFull().children(rows)
    return col().key("scroll").size(300.0, 200.0).scroll(ScrollSpec(stickBottom: s.stickBottom)).child(list)
}

private func scrollAnchorShift(
    _ feed: ScrollAnchorFeed,
    _ at: Float,
    _ change: @escaping (inout ScrollAnchorFeed) -> Void
) -> (Float, Float) {
    let rt = IntegrationSupport.runtime(feed, scrollAnchorView, (300.0, 200.0), Env.new(true, 1.0))
    _ = rt.hostFrame(0.0)
    rt.hostUpdate { _, tx in
        tx.scrollToInstant("scroll", 0.0, at)
    }
    for _ in 0..<4 {
        _ = rt.hostFrame(1.0 / 120.0)
    }
    let before = IntegrationSupport.find(rt, "r5").rect[1]
    rt.hostUpdate { s, _ in
        change(&s)
    }
    for _ in 0..<60 {
        _ = rt.hostFrame(1.0 / 120.0)
    }
    let after = IntegrationSupport.find(rt, "r5").rect[1]
    return (before, after)
}

@Suite("ScrollAnchorIntegrationTests")
struct ScrollAnchorIntegrationTests {
    @Test func withoutTheAnchorTheRowsMoveDown() {
        let (before, after) = scrollAnchorShift(ScrollAnchorFeed(), 150.0) { $0.above = 3 }
        #expect(abs(after - before - 90.0) < 0.5)
    }

    @Test func atTheVeryTopNewRowsShow() {
        let (before, after) = scrollAnchorShift(ScrollAnchorFeed(), 0.0) { $0.above = 3 }
        #expect(abs(after - before - 90.0) < 0.5)
    }

    @Test func aViewportFollowingItsBottomKeepsFollowingIt() {
        let (before, after) = scrollAnchorShift(ScrollAnchorFeed(stickBottom: true), 10_000.0) { $0.below = 3 }
        #expect(abs(after - before + 120.0) < 0.5)
    }

    @Test(.disabled("Requires Wave 2 El.scrollAnchor in Spine El/Runtime"))
    func rowsInsertedOrGrownAboveLeaveTopRowInPlaceWhenAnchored() {}
}
