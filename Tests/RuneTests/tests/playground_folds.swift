// Tests ported from: crates/rune/tests/playground_folds.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private struct PgFoldsReal {
    init() {}
}

private func pgFoldsRealView(_: PgFoldsReal, _: Cx<PgFoldsReal>) -> El {
    text("the app")
}

private struct PgFoldsCard {
    init() {}
}

private func pgFoldsCardView(_: PgFoldsCard, _: Cx<PgFoldsCard>) -> El {
    text("card").key("card")
}

private func pgFoldsPlayground() -> Playground<PgFoldsReal> {
    Playground<PgFoldsReal>.new()
        .story(Story.new("Cards/Plain", PgFoldsCard.init, pgFoldsCardView))
        .story(Story.new("Cards/Raised", PgFoldsCard.init, pgFoldsCardView))
        .story(Story.new("Lists/Short", PgFoldsCard.init, pgFoldsCardView))
}

private func pgFoldsRuntime(_ pg: Playground<PgFoldsReal>) -> Runtime<PgFoldsReal> {
    App.new(AppSpec.new("folds", (800.0, 500.0), PgFoldsReal.init, pgFoldsRealView))
        .playground(pg)
        .headlessRuntime((800.0, 500.0), Env.new(false, 1.0))
}

private func pgFoldsShown(_ rt: Runtime<PgFoldsReal>, _ key: String) -> Bool {
    rt.hostElements().contains { $0.key == key && !$0.exiting }
}

private func pgFoldsTap(_ rt: Runtime<PgFoldsReal>, _ key: String) {
    guard let (x, y) = rt.testCenter(key) else {
        preconditionFailure("no \(key)")
    }
    _ = rt.hostPointerMove(x, y)
    _ = rt.hostPointerDown(x, y)
    _ = rt.hostPointerUp(x, y)
    _ = rt.frame(1.0 / 60.0)
}

private func pgFoldsReopen(_ rt: Runtime<PgFoldsReal>) {
    rt.update { _, tx in tx.closePlayground() }
    _ = rt.frame(1.0 / 60.0)
    rt.update { _, tx in tx.openPlayground() }
    _ = rt.frame(1.0 / 60.0)
}

@Suite("PlaygroundFoldsIntegrationTests")
struct PlaygroundFoldsIntegrationTests {
    @Test func aFoldedGroupStaysFoldedAfterThePlaygroundCloses() {
        let rt = pgFoldsRuntime(pgFoldsPlayground())
        rt.openPlayground("Lists/Short", nil)
        #expect(pgFoldsShown(rt, "playground-item-1"))
        pgFoldsTap(rt, "playground-group-0")
        #expect(!pgFoldsShown(rt, "playground-item-1"))
        pgFoldsReopen(rt)
        #expect(!pgFoldsShown(rt, "playground-item-1"))
        #expect(pgFoldsShown(rt, "playground-item-2"))
    }

    @Test func foldsLoadsOnceAndSavesEachChange() {
        final class StateBox {
            var saved: [[String]] = []
            var loads: Int = 0
        }
        let box = StateBox()
        let pg = pgFoldsPlayground().folds(
            {
                box.loads += 1
                return ["Cards", "Gone"]
            },
            { groups in
                box.saved.append(groups)
            }
        )
        let rt = pgFoldsRuntime(pg)
        #expect(box.loads == 0)
        rt.openPlayground("Lists/Short", nil)
        #expect(!pgFoldsShown(rt, "playground-item-0") && pgFoldsShown(rt, "playground-item-2"))
        pgFoldsTap(rt, "playground-group-2")
        pgFoldsTap(rt, "playground-group-0")
        #expect(box.saved == [["Cards", "Lists"], ["Lists"]])
        pgFoldsReopen(rt)
        #expect(box.loads == 1)
        rt.openPlayground("Lists/Short", nil)
        #expect(box.saved.last?.count == 0)
    }
}
