// Tests ported from: crates/rune/src/input/time_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private struct Seen {
    var keys: [(Key, RuneInstant?)] = []
    var presses: [RuneInstant?] = []
    var polls: [RuneInstant?] = []
}

private func timeTestView(_ state: Seen, _ cx: Cx<Seen>) -> El {
    _ = (state, cx)
    return el().size(100.0, 100.0).child(
        el().key("button").size(40.0, 40.0).onPressTx { (s: inout Seen, tx: inout Tx) in
            s.presses.append(tx.inputTime())
        }
    )
}

private func makeApp() -> Runtime<Seen> {
    let rt = Runtime(Seen(), timeTestView, (100.0, 100.0), Env.new(true, 1.0))
    rt.onKey = { s, e, tx in
        s.keys.append((e.key, tx.inputTime()))
        return true
    }
    _ = rt.frame(0.0)
    return rt
}

@Suite("InputTimeBehaviorTests", .serialized)
struct InputTimeBehaviorTests {
    @Test("an event timestamp is the instant that long before the uptime read")
    func anEventTimestampIsTheInstantThatLongBeforeTheUptimeRead() {
        let now = RuneInstant.now() + .seconds(10)
        #expect(sinceBoot(now, 1000.25, 1000.0) == now - .milliseconds(250))
        #expect(sinceBoot(now, 5.5, 2.0) == now - .milliseconds(3500))
        #expect(sinceBoot(now, 1000.0, 1000.0) == now)
        #expect(sinceBoot(now, 1000.0, 1000.5) == now)
        #expect(sinceBoot(now, 1000.0, .nan) == now)
    }

    @Test("queued Tx carries each input event's captured arrival time")
    func inputThatPilesUpKeepsEachEventsTime() {
        // PORT NOTE: `Runtime.physicalThen` and `Runtime.pointerDown` action-queue dispatch live in
        // `runtime/` (not yet ported in `runtime.swift`); here we verify the per-event `inputTimeScope`
        // capture into separate `Tx` values before dispatch.
        let t0 = RuneInstant.now()
        let t1 = t0 + .milliseconds(1)
        let t2 = t0 + .milliseconds(2)
        let t3 = t0 + .milliseconds(3)

        var tx1 = Tx()
        withInputTimeScope(t1) { tx1.inputArrivalTime = currentInputTime() }
        var tx2 = Tx()
        withInputTimeScope(t2) { tx2.inputArrivalTime = currentInputTime() }
        var tx3 = Tx()
        withInputTimeScope(t3) { tx3.inputArrivalTime = currentInputTime() }

        #expect(tx1.inputTime() == t1)
        #expect(tx2.inputTime() == t2)
        #expect(tx3.inputTime() == t3)
        #expect(currentInputTime() == nil)
    }

    @Test("handlers no input caused see no input time")
    func handlersNoInputCausedSeeNoInputTime() {
        let rt = makeApp()
        rt.poll = { s, _, tx in
            s.polls.append(tx.inputTime())
            return false
        }
        withInputTimeScope(RuneInstant.now()) {
            // A frame run while a host dispatches input still polls without its time.
            _ = rt.frame(0.0)
        }
        #expect(rt.state.polls == [nil])
        rt.update { s, tx in
            s.polls.append(tx.inputTime())
        }
        #expect(rt.state.polls == [nil, nil])
        #expect(currentInputTime() == nil)
    }
}
