// Tests ported from: crates/rune/src/runtime/tests/id_pruning.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

@testable import Rune
import RuneMotion
import Testing

private func rtIdPruningView(_ start: Int, _: Cx<Int>) -> El {
    let items: [El] = (start..<(start + 3)).map { i in
        el().key("r\(i)").wFull().child(el().key("label").h(20.0))
    }
    var stack = col().key("stack").wFull().children(items)
    stack.growthSpec = GrowthSpec()
    return col().key("root").size(200.0, 200.0).child(stack)
}

@Suite
struct RtIdPruningTests {
    @Test
    func rowsThatLeftLeaveNoIdsOrGrowthTracksBehind() {
        let rt = Runtime.new(0, rtIdPruningView, (200.0, 200.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)
        let initialNodes = rt.nodes.count
        for _ in 0..<40 {
            rt.update { n, _ in n += 3 }
            for _ in 0..<90 {
                _ = rt.frame(1.0 / 60.0)
            }
        }
        #expect(rt.growthTracks.count <= 6)
        #expect(rt.exitingNodes.isEmpty)
        #expect(rt.nodes.count == initialNodes)
        #expect(rt.elements().contains(where: { $0.key == "r120" }))
    }

    @Test
    func aPathKeepsItsIdAndScrollStateWhenRemounted() {
        func view(_ on: Bool, _: Cx<Bool>) -> El {
            let items: [El] = (0..<20).map { i in el().key("i\(i)").h(40.0) }
            let list = col().children(items)
            let scroll = col()
                .key("scroll")
                .size(100.0, 100.0)
                .scroll(ScrollSpec(stickBottom: false))
                .child(list)
            var root = col().key("root").size(100.0, 100.0)
            if on {
                root = root.child(scroll)
            }
            return root
        }

        let rt = Runtime.new(true, view, (100.0, 100.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)
        rt.wheel(50.0, 50.0, 0.0, -120.0)
        for _ in 0..<60 {
            _ = rt.frame(1.0 / 60.0)
        }
        let id = rt.nodes.first(where: { $0.key == "scroll" })!.nodeId

        rt.update { on, tx in
            on = false
            tx.instant()
        }
        _ = rt.frame(1.0 / 60.0)
        rt.update { on, tx in
            on = true
            tx.instant()
        }
        _ = rt.frame(1.0 / 60.0)
        let again = rt.nodes.first(where: { $0.key == "scroll" })!.nodeId
        #expect(id == again)
    }

    @Test
    func pruningLeftRowsKeepsRetainedMapsBoundedAcrossRounds() {
        let rt = Runtime.new(0, rtIdPruningView, (200.0, 200.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)
        for _ in 0..<12 {
            rt.update { n, _ in n += 3 }
            for _ in 0..<90 {
                _ = rt.frame(1.0 / 60.0)
            }
            #expect(rt.nodes.count == 8)
            #expect(rt.growthTracks.count <= 6)
            #expect(rt.liveNodeBindings.isEmpty)
        }
    }
}
