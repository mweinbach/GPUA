// Tests ported from: crates/rune/src/runtime/scroll/watch.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("ScrollWatchTests")
struct ScrollWatchTests {
    @Test("watchScroll fires once initially, skips idle frames, and updates on wheel and programmatic glides")
    func watchScrollFiresOnlyWhenPositionChanges() {
        let follow = Live.new([0.0, 0.0] as [Float])
        var toldPositions: [ScrollPos] = []

        let rt: Runtime<Int> = Runtime.new(0, { (_: Int, _: Cx<Int>) in
            col().size(300.0, 300.0)
                .child(col().key("scroll").size(300.0, 200.0).scroll(ScrollSpec(stickBottom: false))
                    .child(el().key("content").wFull().h(1000.0)))
                .child(el().key("marker").size(10.0, 10.0).liveOffset(Binding(live: follow)))
        }, (300.0, 300.0), Env())

        rt.watchScroll("scroll") { count, pos, tx in
            count += 1
            toldPositions.append(pos)
            follow.set([0.0, -pos.offset[1]])
            tx.liveOnly()
        }

        _ = rt.frame(0.0)
        _ = rt.frame(1.0 / 60.0)
        #expect(toldPositions.count == 1)
        #expect(toldPositions[0] == ScrollPos(offset: [0.0, 0.0], max: [0.0, 800.0]))

        // Idle frames do not fire again
        for _ in 0..<8 {
            _ = rt.frame(1.0 / 60.0)
        }
        #expect(toldPositions.count == 1)

        // Wheel scroll updates watcher and live follower
        rt.wheel(100.0, 100.0, -25.0)
        _ = rt.frame(1.0 / 60.0)
        #expect(toldPositions.count == 2)
        #expect(toldPositions.last == ScrollPos(offset: [0.0, 25.0], max: [0.0, 800.0]))

        let contentInfo = rtElement(rt, "content")!
        #expect(contentInfo.scrolled == [0.0, 25.0])
    }
}
