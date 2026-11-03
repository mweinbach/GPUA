// Tests ported from: crates/rune/src/playground/scenes_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private func pgCountUp() -> Playground<PgTestReal> {
    pgBase().trigger("Still", "r", "Count up") { s, play in
        s.count = 1
        play.after(0.5) { s, _ in
            s.count = 2
        }
    }
}

private func pgRunFor(_ rt: Runtime<PgTestReal>, _ secs: Double) {
    let steps = Int((secs * 60.0).rounded())
    for _ in 0..<steps {
        _ = rt.frame(1.0 / 60.0)
    }
}

@Suite("PlaygroundScenesTests")
struct PlaygroundScenesTests {
    @Test func theSceneFilterListsOnlyTheScenesItKeeps() {
        let rt = pgRuntimeWith(pgBase().scenes { name in name.contains("/") }, .some(nil), windowed: true)
        #expect(pgFind(rt, "playground-item-0") == nil && pgFind(rt, "playground-item-1") == nil)
        #expect(pgFind(rt, "playground-item-2") != nil)
        #expect(pgSelected(rt) == 2)
        let live = rt.hostPlayground()!
        #expect(live.find("big") == nil)
        #expect(live.find("Still") == 2)
        pgLetter(rt, "k")
        #expect(pgSelected(rt) == 4)
    }

    @Test func choosingASceneRunsItsRTrigger() {
        let rt = pgRuntimeWith(pgCountUp(), .some("Still"), windowed: false)
        _ = rt.frame(PG_DT)
        #expect(pgShows(rt, "count") == "count 1")
        pgRunFor(rt, 0.6)
        #expect(pgShows(rt, "count") == "count 2")
        pgLetter(rt, "j")
        pgLetter(rt, "k")
        _ = rt.frame(PG_DT)
        #expect(pgShows(rt, "count") == "count 1")
    }

    @Test func aStoryRunsItsRTriggerWhenItsStateIsMadeNotWhenItComesBack() {
        let rt = pgRuntime(.some("Fade"))
        _ = rt.frame(PG_DT)
        #expect(pgShows(rt, "fade") == "[\"start\"]")
        pgRunFor(rt, 1.0)
        #expect(pgShows(rt, "fade") == "[\"start\", \"half\", \"end\"]")
        pgLetter(rt, "j")
        pgLetter(rt, "k")
        pgRunFor(rt, 1.0)
        #expect(pgShows(rt, "fade") == "[\"start\", \"half\", \"end\"]")
        pgLetter(rt, "r")
        _ = rt.frame(PG_DT)
        #expect(pgShows(rt, "fade") == "[\"start\"]")
    }
}
