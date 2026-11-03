// Tests ported from: crates/rune/src/playground/groups_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private func pgShown(_ rt: Runtime<PgTestReal>, _ i: Int) -> Bool {
    pgFind(rt, "playground-item-\(i)") != nil
}

@Suite("PlaygroundGroupsTests")
struct PlaygroundGroupsTests {
    @Test func aClickOnAHeaderFoldsItsGroupAndAnotherUnfoldsIt() {
        let rt = pgRuntime(.some("big"))
        #expect(pgShown(rt, 2) && pgShown(rt, 5))
        pgTap(rt, "playground-group-2")
        #expect(!pgShown(rt, 2) && !pgShown(rt, 5))
        #expect(pgShown(rt, 3))
        #expect(pgHeader(rt) == "Motion" && pgSelected(rt) == 0)
        pgTap(rt, "playground-group-2")
        #expect(pgShown(rt, 2) && pgShown(rt, 5))
    }

    @Test func leftRightAndReturnFoldTheSelectedHeader() {
        let rt = pgRuntime(.some("Still"))
        pgPress(rt, .up)
        #expect(pgHeader(rt) == "Motion")
        pgPress(rt, .left)
        #expect(!pgShown(rt, 2))
        pgPress(rt, .down)
        #expect(pgHeader(rt) == "Live")
        pgPress(rt, .up)
        pgPress(rt, .right)
        #expect(pgShown(rt, 2))
        pgPress(rt, .enter)
        #expect(!pgShown(rt, 2))
        pgPress(rt, .enter)
        #expect(pgShown(rt, 2))
        #expect(pgSelected(rt) == 2)
    }

    @Test func foldingTheOpenStorysGroupSelectsItsHeaderAndStaysFoldedAfterClose() {
        let rt = pgRuntime(.some("Fade"))
        pgTap(rt, "playground-group-2")
        #expect(pgHeader(rt) == "Motion" && pgSelected(rt) == 5)
        pgLetter(rt, "r")
        #expect(pgHeader(rt) == "Motion")
        #expect(!pgShown(rt, 5))
        pgEscape(rt)
        rt.update { _, tx in tx.openPlayground() }
        _ = rt.frame(PG_DT)
        #expect(!pgShown(rt, 2) && !pgShown(rt, 5))
        #expect(pgHeader(rt) == "Motion" && pgSelected(rt) == 5)
    }

    @Test func choosingAStoryByNameUnfoldsItsGroup() {
        let rt = pgRuntime(.some("big"))
        pgTap(rt, "playground-group-2")
        rt.update { _, tx in tx.pgPush(.open("Fade")) }
        _ = rt.frame(PG_DT)
        #expect(pgShown(rt, 5))
        #expect(pgHeader(rt) == nil && pgSelected(rt) == 5)
    }
}
