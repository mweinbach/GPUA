// Tests ported from: crates/rune/src/playground/stage_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private let PG_STAGE_SIZE: (Float, Float) = (1200.0, 700.0)

private struct PgStageReal {}

private func pgStageRealView(_: PgStageReal, _: Cx<PgStageReal>) -> El {
    text("the app")
}

private struct PgStageCard {}

private func pgStagePlain(_: PgStageCard, _: Cx<PgStageCard>) -> El {
    el().key("plain")
}

private func pgStageTall(_: PgStageCard, _: Cx<PgStageCard>) -> El {
    col().key("tall").wFull().children((0..<40).map { _ in el().h(40.0) })
}

private func pgStageScreen(_: PgStageCard, _: Cx<PgStageCard>) -> El {
    el().key("screen")
}

private func pgStageRuntime() -> Runtime<PgStageReal> {
    let playground = Playground<PgStageReal>.new()
        .story(Story<PgStageCard>.new("Cards/Plain", { PgStageCard() }, pgStagePlain))
        .story(Story<PgStageCard>.new("Cards/Tall", { PgStageCard() }, pgStageTall).stage(.scroll))
        .story(Story<PgStageCard>.new("Screens/Window", { PgStageCard() }, pgStageScreen).stage(.fill))
        .sizes([("Small", (300.0, 200.0))])
    return App.new(AppSpec("stage", PG_STAGE_SIZE, { PgStageReal() }, pgStageRealView))
        .playground(playground)
        .headlessRuntime(PG_STAGE_SIZE, Env.new(false, 1.0))
}

private func pgSizeAtSmall(_ story: String, _ key: String) -> (Float, Float) {
    let rt = pgStageRuntime()
    rt.openPlayground(story, nil)
    rt.update { _, tx in tx.pgPush(.size(1)) }
    _ = rt.frame(1.0 / 60.0)
    guard let e = rt.hostElements().first(where: { $0.key == key }) else {
        preconditionFailure("no \(key)")
    }
    return (e.rect[2], e.rect[3])
}

@Suite("PlaygroundStageTests")
struct PlaygroundStageTests {
    @Test func aCentredStoryTakesThePickedSize() {
        let size = pgSizeAtSmall("Cards/Plain", "plain")
        #expect(size == (300.0, 200.0))
    }

    @Test func aScrollingStoryTakesItsWidthInsideTheMargin() {
        let size = pgSizeAtSmall("Cards/Tall", "tall")
        #expect(size == (300.0 - 2.0 * PLAYGROUND_SCROLL_MARGIN, 1600.0))
    }

    @Test func aScrollingStoryKeepsTheRootHandlers() {
        let rt = pgStageRuntime()
        rt.openPlayground("Cards/Tall", nil)
        let rootIdx = rt.hostPlayground()!.root
        let nodes = windowHostState(for: rt).lastNodes
        let rootKey = rootIdx < nodes.count ? nodes[rootIdx].key : nil
        #expect(rootKey == "tall")
    }

    @Test func aFillStoryKeepsTheWholeStage() {
        let size = pgSizeAtSmall("Screens/Window", "screen")
        #expect(size == (PG_STAGE_SIZE.0 - PLAYGROUND_SIDEBAR - PLAYGROUND_SIDE - 2.0, PG_STAGE_SIZE.1))
    }
}
