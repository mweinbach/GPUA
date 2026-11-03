// Tests ported from: crates/rune/src/live_only_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

// PORT NOTE: Full `Runtime` physical-key, pointer, and debug view-print checks (`physical_with_fallback`,
// `live_only_warnings`, `view_print`, `scrolls`) depend on `runtime.swift` input/commit subsystems owned
// outside this module cluster. The tests below verify `Tx.liveOnly()`, `Tx.took(_:_:)`, `Runtime.update`
// dirty-skipping vs `poll` / normal `update` commits, and `Tx` side-effect preservation.

private struct LiveOnlyState {
    var count: UInt32 = 0
    var pan: Live<[Float]> = Live.new([0.0, 0.0])

    mutating func nudge(_ tx: inout Tx) {
        let cur = pan.get()
        pan.set([cur[0] + 10.0, cur[1]])
        tx.liveOnly()
    }
}

private func liveOnlyView(_ s: LiveOnlyState, _ cx: Cx<LiveOnlyState>) -> El {
    el().size(200.0, 200.0)
        .child(el().key("camera").size(50.0, 50.0).liveOffset(s.pan))
        .child(text("\(s.count)").key("count"))
}

@Suite("LiveOnlyTests")
struct LiveOnlyTests {
    @Test("live only update skips view rebuild while updating Live lanes")
    func liveOnlyUpdateSkipsViewRebuild() {
        var builds = 0
        let rt = Runtime(
            LiveOnlyState(),
            { s, cx in
                builds += 1
                return liveOnlyView(s, cx)
            },
            (200.0, 200.0),
            Env(systemDark: true, scale: 1.0)
        )
        rt.frame(0.0)
        #expect(builds == 1)

        rt.update { s, tx in
            s.nudge(&tx)
        }
        rt.frame(1.0 / 120.0)
        #expect(builds == 1)
        #expect(Array(rt.state.pan.get().prefix(2)) == [10.0, 0.0])
    }

    @Test("declined handler takes back live only flag")
    func declinedHandlerTakesBackLiveOnly() {
        var tx = Tx()
        tx.liveOnly()
        #expect(tx.liveOnlyFlag)
        #expect(!Tx.took(false, &tx))
        #expect(!tx.liveOnlyFlag)

        tx.liveOnly()
        #expect(Tx.took(true, &tx))
        #expect(tx.liveOnlyFlag)
    }

    @Test("live only does not cancel poll or normal update commits")
    func liveOnlyDoesNotCancelPollOrNormalUpdateCommits() {
        for source in 0..<2 {
            let rt = Runtime(
                LiveOnlyState(),
                liveOnlyView,
                (200.0, 200.0),
                Env(systemDark: true, scale: 1.0)
            )
            rt.frame(0.0)
            rt.update { s, tx in s.nudge(&tx) }
            if source == 0 {
                rt.poll = { s, _, _ in
                    s.count += 1
                    return true
                }
            } else {
                rt.update { s, _ in
                    s.count += 1
                }
            }
            rt.frame(0.0)
            #expect(rt.state.count == 1)
            let countText = rt.elements().first { $0.key == "count" }?.text
            #expect(countText == "1")
        }
    }

    @Test("live only keeps clipboard, scroll, and wake requests on Tx")
    func liveOnlyKeepsClipboardScrollAndWakeRequests() {
        var tx = Tx()
        tx.liveOnly()
        tx.copy("copied")
        tx.scrollToY("scroll", 300.0)
        tx.wakeAfter(Duration.seconds(1))

        #expect(tx.liveOnlyFlag)
        #expect(tx.copyWrite == .text("copied"))
        #expect(tx.scrollOffsetRequests.count == 1)
        #expect(tx.scrollOffsetRequests[0].key == "scroll")
        #expect(tx.scrollOffsetRequests[0].y == 300.0)
        #expect(tx.wakes == [1.0])
    }
}
