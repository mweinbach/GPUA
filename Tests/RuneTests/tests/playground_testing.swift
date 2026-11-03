// Tests ported from: crates/rune/tests/playground_testing.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private let pgTestingDt: Double = 1.0 / 60.0

private struct PgTestingPad {
    var count: UInt32 = 0
}

private func pgTestingPadView(_ s: PgTestingPad, _: Cx<PgTestingPad>) -> El {
    col().wFull().hFull()
        .child(text("count \(s.count)").key("count"))
        .child(el().key("inc").size(40.0, 20.0).onPress { (s: inout PgTestingPad, _: inout Tx) in s.count += 1 })
}

private func pgTestingScenes() -> [(String, (inout PgTestingPad) -> Void)] {
    [
        ("Pad/Empty", { _ in }),
        ("Pad/Full", { s in s.count = 10 }),
    ]
}

private struct PgTestingUpload {
    var bytes: UInt32 = 0
    var phase: String = ""
}

private func pgTestingUploadView(_ u: PgTestingUpload, _: Cx<PgTestingUpload>) -> El {
    text("\(u.phase) \(u.bytes)").key("upload")
}

private func pgTestingUploadStory() -> Story<PgTestingUpload> {
    Story.new("Progress/Upload", { PgTestingUpload() }, pgTestingUploadView)
        .trigger("r", "Run") { u, play in
            u.phase = "sending"
            play.after(0.5) { u, play in
                u.phase = "sent"
                play.after(0.25) { u, _ in u.phase = "done" }
            }
        }
        .trigger("f", "Fail") { u, _ in u.phase = "failed" }
        .variant("Small") { u in u.bytes = 10 }
        .variant("Large") { u in u.bytes = 1_000_000 }
}

private func pgTestingPlayground() -> Playground<PgTestingPad> {
    Playground<PgTestingPad>.new()
        .story(pgTestingUploadStory())
        .story(Story<PgTestingUpload>.fromReal("Progress/Mine", { (real: PgTestingPad) in PgTestingUpload(bytes: real.count, phase: "mine") }, pgTestingUploadView))
        .trigger("Full", "d", "Double") { s, _ in s.count *= 2 }
        .variant("Full", "Few") { s in s.count = 3 }
        .variant("Full", "Many") { s in s.count = 99 }
}

private func pgTestingRuntime(_ pg: Playground<PgTestingPad>) -> Runtime<PgTestingPad> {
    var spec = AppSpec.new("pad", (800.0, 500.0), { PgTestingPad() }, pgTestingPadView)
    spec.scenes = pgTestingScenes()
    return App.new(spec).playground(pg).headlessRuntime((800.0, 500.0), Env.new(false, 1.0))
}

private func pgTestingAdvance(_ rt: Runtime<PgTestingPad>, _ secs: Double) {
    let n = Int((secs / pgTestingDt).rounded())
    for _ in 0..<n {
        _ = rt.frame(pgTestingDt)
    }
}

private func pgTestingPhase(_ rt: Runtime<PgTestingPad>) -> String {
    guard let u = rt.playgroundState(PgTestingUpload.self) else {
        preconditionFailure("the upload story's state")
    }
    return u.phase
}

private func pgTestingCompare(_ stage: PgTestingPad, _ real: PgTestingPad, _: Cx<PgTestingPad>) -> El {
    col()
        .child(text("stage \(stage.count) real \(real.count)").key("compare"))
        .child(el().key("keep").size(40.0, 20.0).onPress { (_: inout PgTestingPad, tx: inout Tx) in tx.keepPlayground() })
}

private struct PgTestingPulse {
    var beats: UInt32 = 0
    var settled: Bool = false
}

private func pgTestingPulseView(_ p: PgTestingPulse, _: Cx<PgTestingPulse>) -> El {
    text("beats \(p.beats)").key("pulse")
}

private func pgTestingBeat(_ p: inout PgTestingPulse, _ play: Play<PgTestingPulse>) {
    p.beats += 1
    play.after(0.25, pgTestingBeat)
}

private func pgTestingPulseStory() -> Story<PgTestingPulse> {
    Story.new("Motion/Pulse", { PgTestingPulse() }, pgTestingPulseView)
        .trigger("r", "Pulse", pgTestingBeat)
        .trigger("s", "Settle") { _, play in
            play.clear()
            play.after(0.2) { p, _ in p.settled = true }
        }
}

private struct PgTestingGlow {
    var lit: Bool = false
}

@Suite("PlaygroundTestingIntegrationTests")
struct PlaygroundTestingIntegrationTests {
    @Test func aStoryOpensByPathAndItsRTriggerRunsAtOnce() {
        let rt = pgTestingRuntime(pgTestingPlayground())
        let closedState = rt.playgroundState(PgTestingUpload.self)
        #expect(closedState == nil)
        rt.openPlayground("Progress/Upload", nil)
        #expect(pgTestingPhase(rt) == "sending")
        let shown = rt.playgroundElement("upload")?.text
        #expect(shown == "sending 10")
        let wrongType = rt.playgroundState(PgTestingPad.self)
        #expect(wrongType == nil)
    }

    @Test func playAfterStepsRunOnTheLogicalClock() {
        let rt = pgTestingRuntime(pgTestingPlayground())
        rt.openPlayground("Upload", nil)
        pgTestingAdvance(rt, 0.4)
        #expect(pgTestingPhase(rt) == "sending")
        pgTestingAdvance(rt, 0.2)
        #expect(pgTestingPhase(rt) == "sent")
        pgTestingAdvance(rt, 0.1)
        #expect(pgTestingPhase(rt) == "sent")
        pgTestingAdvance(rt, 0.1)
        #expect(pgTestingPhase(rt) == "done")
    }

    @Test func aTriggerRunsByItsKeyAndRReplays() {
        let rt = pgTestingRuntime(pgTestingPlayground())
        rt.openPlayground("Progress/Upload", nil)
        pgTestingAdvance(rt, 1.0)
        #expect(pgTestingPhase(rt) == "done")
        rt.playgroundTrigger("f")
        #expect(pgTestingPhase(rt) == "failed")
        rt.playgroundTrigger("r")
        #expect(pgTestingPhase(rt) == "sending")
        pgTestingAdvance(rt, 0.6)
        #expect(pgTestingPhase(rt) == "sent")
    }

    @Test func aSceneTriggerActsOnTheStageAndNeverTheRealState() {
        let rt = pgTestingRuntime(pgTestingPlayground())
        rt.state.count = 4
        rt.openPlayground("Pad/Full", nil)
        rt.playgroundTrigger("d")
        let stageCount = rt.playgroundState(PgTestingPad.self)?.count
        #expect(stageCount == 6)
        let elemText = rt.playgroundElement("count")?.text
        #expect(elemText == "count 6")
        let realCount = rt.state.count
        #expect(realCount == 4)
    }

    @Test func aVariantOpensWithItsOwnSetup() {
        let rt = pgTestingRuntime(pgTestingPlayground())
        rt.openPlayground("Progress/Upload", "Large")
        let b1 = rt.playgroundState(PgTestingUpload.self)?.bytes
        #expect(b1 == 1_000_000)
        rt.openPlayground("Progress/Upload", "1")
        let b2 = rt.playgroundState(PgTestingUpload.self)?.bytes
        #expect(b2 == 10)
        rt.openPlayground("Full", "many")
        let c1 = rt.playgroundState(PgTestingPad.self)?.count
        #expect(c1 == 99)
    }

    @Test func aStoryFromRealReadsTheRealStateAndLeavesIt() {
        let rt = pgTestingRuntime(pgTestingPlayground())
        rt.state.count = 7
        rt.openPlayground("Progress/Mine", nil)
        let bytes = rt.playgroundState(PgTestingUpload.self)?.bytes
        #expect(bytes == 7)
        let realCount = rt.state.count
        #expect(realCount == 7)
    }

    @Test func onlyKeepFromASideRealControlWritesTheRealState() {
        let pg = pgTestingPlayground()
            .keep { stage, real in real.count = stage.count }
            .sideReal("Full", pgTestingCompare)
        let rt = pgTestingRuntime(pg)
        rt.openPlayground("Full", nil)
        rt.playgroundTrigger("d")
        _ = rt.frame(pgTestingDt)
        let rc0 = rt.state.count
        #expect(rc0 == 0)
        let stageCompare = rt.playgroundElement("compare")
        #expect(stageCompare == nil)
        guard let (x, y) = rt.testCenter("keep") else {
            Issue.record("missing keep control")
            return
        }
        _ = rt.hostPointerDown(x, y)
        _ = rt.hostPointerUp(x, y)
        _ = rt.frame(pgTestingDt)
        let rc1 = rt.state.count
        #expect(rc1 == 6)
        let compareText = rt.hostElements().first { $0.key == "compare" }?.text
        #expect(compareText == "stage 6 real 6")
    }

    @Test func aTriggerThatClearsStopsTheLoopAndRunsOnlyItsOwnSteps() {
        let rt = pgTestingRuntime(pgTestingPlayground().story(pgTestingPulseStory()))
        rt.openPlayground("Pulse", nil)
        pgTestingAdvance(rt, 1.1)
        func beats() -> (UInt32, Bool)? {
            rt.playgroundState(PgTestingPulse.self).map { ($0.beats, $0.settled) }
        }
        #expect(beats()?.0 == 5 && beats()?.1 == false)
        rt.playgroundTrigger("s")
        #expect(beats()?.0 == 5 && beats()?.1 == false)
        pgTestingAdvance(rt, 0.1)
        #expect(beats()?.0 == 5 && beats()?.1 == false)
        pgTestingAdvance(rt, 0.15)
        #expect(beats()?.0 == 5 && beats()?.1 == true)
        pgTestingAdvance(rt, 1.0)
        #expect(beats()?.0 == 5 && beats()?.1 == true)
        let pulseText = rt.playgroundElement("pulse")?.text
        #expect(pulseText == "beats 5")
    }

    @Test func replaysLandTheirStepsOnTheSameFrameEveryTime() {
        let glow = Story.new("Motion/Glow", { PgTestingGlow() }) { g, _ in
            text(g.lit ? "lit" : "dark").key("glow")
        }
        .trigger("r", "Glow") { g, play in
            g.lit = false
            play.after(0.4) { g, _ in g.lit = true }
        }
        let rt = pgTestingRuntime(pgTestingPlayground().story(glow))
        rt.openPlayground("Motion/Glow", nil)
        let dt = 1.0 / 120.0
        var frames: [Int?] = []
        for _ in 0..<3 {
            rt.playgroundTrigger("r")
            var litOn: Int? = nil
            for step in 1...120 {
                _ = rt.frame(dt)
                if rt.playgroundState(PgTestingGlow.self)?.lit == true {
                    litOn = step
                    break
                }
            }
            frames.append(litOn)
            for _ in 0..<(120 - (litOn ?? 120)) {
                _ = rt.frame(dt)
            }
        }
        #expect(frames == [48, 48, 48])
    }

    @Test func anUnknownStoryPanicsWithTheList() {
        // PORT NOTE: Verifies the exact diagnostic returned by `playgroundOpenCheck` before `openPlayground` calls `preconditionFailure`.
        let rt = pgTestingRuntime(pgTestingPlayground())
        let res = rt.playgroundOpenCheck("Nope", nil)
        if case .failure(let err) = res {
            #expect(err.message.contains("no story \"Nope\" in the playground"))
        } else {
            Issue.record("expected unknown story failure")
        }
    }

    @Test func anUnknownTriggerPanicsWithTheKeys() {
        // PORT NOTE: Verifies the exact diagnostic returned by `playgroundTriggerCheck` before `playgroundTrigger` calls `preconditionFailure`.
        let rt = pgTestingRuntime(pgTestingPlayground())
        rt.openPlayground("Progress/Upload", nil)
        let res = rt.playgroundTriggerCheck("z")
        if case .failure(let err) = res {
            #expect(err.message.contains("has no trigger on 'z'"))
        } else {
            Issue.record("expected unknown trigger failure")
        }
    }
}
