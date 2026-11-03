// Tests ported from: crates/rune/src/playground/real_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if !os(WASI)
import Foundation
#endif
import Testing
@testable import Rune

private func pgOpen(_ rt: Runtime<PgTestReal>, _ name: String) {
    rt.update { _, tx in tx.pgPush(.open(name)) }
    _ = rt.frame(PG_DT)
}

private func pgCopy(_ real: PgTestReal) -> PgTestReal {
    var out = PgTestReal()
    out.count = real.count
    return out
}

private func pgCompare(_ stage: PgTestReal, _ real: PgTestReal, _: Cx<PgTestReal>) -> El {
    col()
        .child(text("stage \(stage.count) real \(real.count)").key("compare"))
        .child(el().key("keep").size(40.0, 20.0).onPress { (_: inout PgTestReal, tx: inout Tx) in
            tx.keepPlayground()
        })
}

private final class PgAtomicCounter: @unchecked Sendable {
    #if !os(WASI)
    private let lock = NSLock()
    #endif
    private var count: Int = 0

    func increment() {
        #if !os(WASI)
        lock.lock()
        defer { lock.unlock() }
        #endif
        count += 1
    }

    func load() -> Int {
        #if !os(WASI)
        lock.lock()
        defer { lock.unlock() }
        #endif
        return count
    }
}

@Suite("PlaygroundRealTests")
struct PlaygroundRealTests {
    @Test func freshScenesStartFromTheRealStateOnEachChoiceAndReplay() {
        let rt = pgRuntimeWith(pgBase().fresh(pgCopy), nil, windowed: true)
        rt.state.count = 7
        pgOpen(rt, "holding")
        #expect(pgShows(rt, "count") == "count 7")
        pgOpen(rt, "big")
        #expect(pgShows(rt, "count") == "count 100")
        rt.state.count = 9
        pgOpen(rt, "holding")
        #expect(pgShows(rt, "count") == "count 9")
        rt.state.count = 11
        pgLetter(rt, "r")
        #expect(pgShows(rt, "count") == "count 11")
        let realCount = rt.state.count
        #expect(realCount == 11)
    }

    @Test func aStoryFromRealDerivesItsStateWhenItShowsAndOnReplay() {
        let story = Story<PgTestLab>.fromReal(
            "Lab/Derived",
            { (r: PgTestReal) in PgTestLab(ticks: r.count, presses: 0) },
            pgTestLabView
        )
        let rt = pgRuntimeWith(pgBase().story(story), nil, windowed: true)
        rt.state.count = 3
        pgOpen(rt, "Derived")
        #expect(pgShows(rt, "lab") == "ticks 3 presses 0")
        rt.state.count = 4
        pgLetter(rt, "j")
        pgLetter(rt, "k")
        #expect(pgShows(rt, "lab") == "ticks 3 presses 0")
        pgLetter(rt, "r")
        #expect(pgShows(rt, "lab") == "ticks 4 presses 0")
    }

    #if os(macOS) || os(Linux)
    @Test func aStoryFromAnotherAppsStateIsRefused() async {
        await #expect(processExitsWith: .failure) {
            _ = pgBase().story(
                Story<PgTestLab>.fromReal(
                    "Lab/Other",
                    { (l: PgTestLab) in PgTestLab(ticks: l.ticks, presses: 0) },
                    pgTestLabView
                )
            )
        }
    }
    #endif

    @Test func keepCopiesTheStageBackBeforeAReplayASwitchAndBack() {
        let keep = pgBase()
            .fresh(pgCopy)
            .keep { stage, real in real.count = stage.count }
        let rt = pgRuntimeWith(keep, nil, windowed: true)
        rt.state.count = 5
        pgOpen(rt, "Still")
        pgTap(rt, "inc")
        let real1 = rt.state.count
        #expect(pgShows(rt, "count") == "count 6" && real1 == 5)
        pgEscape(rt)
        pgLetter(rt, "r")
        let real2 = rt.state.count
        #expect(pgShows(rt, "count") == "count 6" && real2 == 6)
        pgTap(rt, "inc")
        pgEscape(rt)
        pgLetter(rt, "j")
        let real3 = rt.state.count
        #expect(real3 == 7)
        pgLetter(rt, "k")
        #expect(pgShows(rt, "count") == "count 7")
        pgTap(rt, "inc")
        pgEscape(rt)
        pgEscape(rt)
        let real4 = rt.state.count
        #expect(real4 == 8)
        #expect(pgShows(rt, "count") == "count 8")
    }

    #if !os(WASI)
    @Test func aFreshStageSharesTheRealWakerAndAWakeFromAnotherThreadReachesItsPoll() {
        var spec = AppSpec<PgTestReal>("playground", (800.0, 500.0), { PgTestReal() }, pgTestView)
        spec.scenes = pgTestScenes()
        spec.setup = { s, waker in
            s.waker = waker
            s.inbox = PgTestInbox()
        }
        spec.poll = { s, _, _ in
            let got = s.inbox?.drain() ?? []
            s.count += got.reduce(0, +)
            return !got.isEmpty
        }
        let fresh = pgBase().fresh { real in
            var s = PgTestReal()
            s.waker = real.waker
            s.inbox = PgTestInbox()
            return s
        }
        let wakes = PgAtomicCounter()
        var rt = toolingRuntimeFor(
            spec: spec,
            state: spec.`init`(),
            size: spec.size,
            env: Env.new(false, 1.0),
            waker: { wakes.increment() }
        )
        playgroundAttachHeadless(
            rt: &rt,
            playground: fresh,
            spec: spec,
            cliPlayground: .some("Still"),
            cliVariant: nil,
            windowed: false
        )
        _ = rt.frame(0.0)
        _ = rt.frame(PG_DT)
        let stage = rt.hostPlayground()!.scene!.state
        let waker = stage.waker!
        let inbox = stage.inbox!
        let before = wakes.load()
        let done = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            inbox.push(41)
            waker()
            done.signal()
        }
        done.wait()
        #expect(wakes.load() == before + 1)
        _ = rt.frame(PG_DT)
        #expect(pgShows(rt, "count") == "count 41")
        let realCount = rt.state.count
        #expect(realCount == 0)
    }
    #endif

    @Test func aSideViewReadsTheRealStateAndKeepWritesThePreviewBack() {
        let playground = pgBase()
            .fresh(pgCopy)
            .keep { stage, real in real.count = stage.count }
            .sideReal("Still", pgCompare)
        let rt = pgRuntimeWith(playground, nil, windowed: true)
        rt.state.count = 3
        pgOpen(rt, "Still")
        #expect(pgShows(rt, "compare") == "stage 3 real 3")
        pgTap(rt, "inc")
        #expect(pgShows(rt, "compare") == "stage 4 real 3")
        let generation = rt.hostPlayground()!.generation
        pgTap(rt, "keep")
        #expect(pgShows(rt, "compare") == "stage 4 real 4")
        let realCount = rt.state.count
        let genAfter = rt.hostPlayground()!.generation
        #expect(realCount == 4 && genAfter == generation)
    }
}
