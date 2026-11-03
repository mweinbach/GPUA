// Tests ported from: crates/rune/tests/playground_stage.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private let pgStageSize: (Float, Float) = (1200.0, 700.0)
private let pgStageW: Float = 1200.0 - 200.0 - 264.0 - 2.0

private struct PgStagePad {
    var rows: Int = 0
}

private func pgStagePadView(_ s: PgStagePad, _: Cx<PgStagePad>) -> El {
    col().key("pad").wFull().children((0..<s.rows).map { _ in el().h(40.0) })
}

private func pgStageScenes() -> [(String, (inout PgStagePad) -> Void)] {
    [
        ("Pad/Empty", { _ in }),
        ("Pad/Full", { s in s.rows = 3 }),
        ("Long/Scene", { s in s.rows = 40 }),
    ]
}

private struct PgStageCard {
    init() {}
}

private func pgStageCardView(_: PgStageCard, _: Cx<PgStageCard>) -> El {
    text("card").key("card")
}

private func pgStageTallView(_: PgStageCard, _: Cx<PgStageCard>) -> El {
    col().key("tall").wFull().children((0..<40).map { _ in el().h(40.0) })
}

private func pgStageScreenView(_: PgStageCard, _: Cx<PgStageCard>) -> El {
    el().key("screen")
}

private func pgStagePlayground() -> Playground<PgStagePad> {
    Playground<PgStagePad>.new()
        .trigger("Full", "d", "Double") { s, _ in s.rows *= 2 }
        .stage("Long/Scene", .scroll)
        .story(Story.new("Cards/Plain", PgStageCard.init, pgStageCardView))
        .story(Story.new("Cards/Raised", PgStageCard.init, pgStageCardView).trigger("p", "Pop") { _, _ in })
        .story(Story.new("Cards/Tall", PgStageCard.init, pgStageTallView).stage(.scroll))
        .story(Story.new("Screens/Window", PgStageCard.init, pgStageScreenView).stage(.fill))
}

private func pgStageRuntime() -> Runtime<PgStagePad> {
    var spec = AppSpec.new("stage", pgStageSize, { PgStagePad() }, pgStagePadView)
    spec.scenes = pgStageScenes()
    return App.new(spec).playground(pgStagePlayground()).headlessRuntime(pgStageSize, Env.new(false, 1.0))
}

private func pgStageElement(_ rt: Runtime<PgStagePad>, _ key: String) -> ElementInfo? {
    rt.hostElements().first { $0.key == key && !$0.exiting }
}

private func pgStageRect(_ rt: Runtime<PgStagePad>, _ key: String) -> [Float] {
    guard let found = pgStageElement(rt, key) else {
        preconditionFailure("no \(key)")
    }
    return found.rect
}

private func pgStageBoxRect(_ rt: Runtime<PgStagePad>) -> [Float] {
    guard let found = rt.hostElements().first(where: { e in
        guard !e.exiting, let k = e.key, k.hasPrefix("playground-stage-") else { return false }
        return UInt32(k.dropFirst("playground-stage-".count)) != nil
    }) else {
        preconditionFailure("a stage")
    }
    return found.rect
}

private func pgStageClose(_ a: [Float], _ b: [Float]) -> Bool {
    guard a.count == b.count else { return false }
    return zip(a, b).allSatisfy { abs($0 - $1) < 0.5 }
}

@Suite("PlaygroundStageIntegrationTests")
struct PlaygroundStageIntegrationTests {
    @Test func eachHeaderCountsItsStories() {
        let rt = pgStageRuntime()
        rt.openPlayground("Cards/Plain", nil)
        #expect(pgStageElement(rt, "playground-count-0")?.text == "2")
        #expect(pgStageElement(rt, "playground-count-2")?.text == "1")
        #expect(pgStageElement(rt, "playground-count-3")?.text == "3")
        #expect(pgStageElement(rt, "playground-count-6")?.text == "1")
    }

    @Test func aFoldedGroupStillCountsItsStories() {
        let rt = pgStageRuntime()
        rt.openPlayground("Pad/Empty", nil)
        guard let (x, y) = rt.testCenter("playground-group-3") else {
            Issue.record("missing playground-group-3")
            return
        }
        _ = rt.hostPointerMove(x, y)
        _ = rt.hostPointerDown(x, y)
        _ = rt.hostPointerUp(x, y)
        _ = rt.frame(1.0 / 60.0)
        #expect(pgStageElement(rt, "playground-item-3") == nil)
        #expect(pgStageElement(rt, "playground-count-3")?.text == "3")
    }

    @Test func onlyStoriesWithTriggersHaveAMotionMark() {
        let rt = pgStageRuntime()
        rt.openPlayground("Cards/Plain", nil)
        let marked = (0..<7).filter { pgStageElement(rt, "playground-motion-\($0)") != nil }
        #expect(marked == [1, 4])
    }

    @Test func aScrollStageStartsItsContentAtTheTopAndScrolls() {
        let rt = pgStageRuntime()
        rt.openPlayground("Cards/Tall", nil)
        let st = pgStageBoxRect(rt)
        #expect(pgStageClose(st, [201.0, 0.0, pgStageW, pgStageSize.1]))
        let top = pgStageRect(rt, "tall")
        #expect(pgStageClose(top, [st[0] + 24.0, st[1] + 24.0, st[2] - 48.0, 1600.0]))
        _ = rt.frame(1.0 / 60.0)
        _ = rt.hostWheel(st[0] + st[2] / 2.0, st[1] + st[3] / 2.0, -300.0)
        _ = rt.frame(1.0 / 60.0)
        let scrolled = pgStageRect(rt, "tall")
        #expect(abs(scrolled[1] - (top[1] - 300.0)) < 0.5)
    }

    @Test func aSceneTakesItsStageFromThePlayground() {
        let rt = pgStageRuntime()
        rt.openPlayground("Long/Scene", nil)
        let st = pgStageBoxRect(rt)
        let top = pgStageRect(rt, "pad")
        #expect(abs(top[1] - (st[1] + 24.0)) < 0.5 && abs(top[3] - 1600.0) < 0.5)
        rt.openPlayground("Pad/Full", nil)
        #expect(pgStageClose(pgStageRect(rt, "pad"), st))
    }

    @Test func aFillStageGivesTheRootTheWholeStage() {
        let rt = pgStageRuntime()
        rt.openPlayground("Screens/Window", nil)
        let st = pgStageBoxRect(rt)
        #expect(pgStageClose(st, [201.0, 0.0, pgStageW, pgStageSize.1]))
        #expect(pgStageClose(pgStageRect(rt, "screen"), st))
    }
}
