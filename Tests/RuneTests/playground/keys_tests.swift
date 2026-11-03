// Tests ported from: crates/rune/src/playground/keys_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private func pgTyping() -> Playground<PgTestReal> {
    pgBase()
        .typing { s in s.typing }
        .trigger("big", "t", "Type") { s, _ in s.typing = true }
}

private func pgTyped(_ rt: Runtime<PgTestReal>) -> String {
    rt.hostPlayground()?.scene?.state.typed ?? ""
}

@Suite("PlaygroundKeysTests")
struct PlaygroundKeysTests {
    @Test func whileTheStageIsTypingItsOnKeyGetsKeysBeforeThePlayground() {
        let rt = pgRuntimeWith(pgTyping(), .some("big"), windowed: true)
        pgLetter(rt, "t")
        _ = rt.frame(PG_DT)
        for c in ["j", "r", "t", "2"] {
            pgLetter(rt, c)
        }
        #expect(pgTyped(rt) == "jrt2" && pgSelected(rt) == 0)
        pgPress(rt, .down)
        #expect(pgSelected(rt) == 1)
    }

    @Test func withoutTypingThePlaygroundKeepsItsKeys() {
        let rt = pgRuntimeWith(
            pgBase().trigger("big", "t", "Type") { s, _ in s.typing = true },
            .some("big"),
            windowed: true
        )
        pgLetter(rt, "t")
        _ = rt.frame(PG_DT)
        pgLetter(rt, "j")
        #expect(pgSelected(rt) == 1)
    }
}
