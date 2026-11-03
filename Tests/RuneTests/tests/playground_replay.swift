// Tests ported from: crates/rune/tests/playground_replay.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private struct PgReplayReal {
    init() {}
}

private struct PgReplayCount {
    var n: UInt32 = 0
}

private func pgReplayCountView(_ c: PgReplayCount, _: Cx<PgReplayCount>) -> El {
    text("\(c.n)").key("count")
}

private func pgReplayRuntime() -> Runtime<PgReplayReal> {
    let story = Story.new("Motion/Count", { PgReplayCount() }, pgReplayCountView)
        .trigger("r", "Replay") { c, _ in c.n += 1 }
        .trigger("s", "Step") { c, _ in c.n += 100 }
    return App.new(AppSpec.new("replay", (400.0, 300.0), PgReplayReal.init) { _, _ in text("app") })
        .playground(Playground<PgReplayReal>.new().story(story))
        .headlessRuntime((400.0, 300.0), Env.new(false, 1.0))
}

private func pgReplayN(_ rt: Runtime<PgReplayReal>) -> UInt32? {
    rt.playgroundState(PgReplayCount.self)?.n
}

private func pgReplayHandler(_ rt: Runtime<PgReplayReal>, _ f: (inout Tx) -> Void) {
    rt.update { _, tx in f(&tx) }
    _ = rt.frame(0.0)
    _ = rt.frame(0.0)
}

@Suite("PlaygroundReplayIntegrationTests")
struct PlaygroundReplayIntegrationTests {
    @Test func aHandlerTriggersAndReplaysTheOpenStory() {
        let rt = pgReplayRuntime()
        rt.openPlayground("motion-count", nil)
        #expect(pgReplayN(rt) == 1)
        pgReplayHandler(rt) { tx in tx.playgroundTrigger("s") }
        #expect(pgReplayN(rt) == 101)
        pgReplayHandler(rt) { tx in tx.replayPlayground() }
        #expect(pgReplayN(rt) == 1)
        pgReplayHandler(rt) { tx in tx.playgroundTrigger("S") }
        pgReplayHandler(rt) { tx in tx.playgroundTrigger("R") }
        #expect(pgReplayN(rt) == 1)
        pgReplayHandler(rt) { tx in tx.playgroundTrigger("x") }
        #expect(pgReplayN(rt) == 1)
    }

    @Test func aLinkOpensThenReplaysInOneHandler() {
        let rt = pgReplayRuntime()
        pgReplayHandler(rt) { tx in
            tx.openPlaygroundAt("motion-count", nil)
            tx.playgroundTrigger("s")
            tx.replayPlayground()
        }
        #expect(pgReplayN(rt) == 1)
    }

    @Test func closedItDoesNothing() {
        let rt = pgReplayRuntime()
        pgReplayHandler(rt) { tx in
            tx.replayPlayground()
            tx.playgroundTrigger("s")
        }
        #expect(pgReplayN(rt) == nil)
    }
}
