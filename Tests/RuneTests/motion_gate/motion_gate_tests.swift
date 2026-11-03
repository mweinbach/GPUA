// Tests ported from: crates/rune/src/motion_gate/tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import RuneMotion
import Taffy
import Testing
@testable import Rune

private struct GateBoxState {
    var right: Bool = false
    var shown: Bool = false
}

private func gateBoxView(_ s: GateBoxState, _: Cx<GateBoxState>) -> El {
    let ink = oklch(0.6, 0.15, 25.0)
    var mover = el().key("mover").size(100.0, 40.0).bg(ink).motion(Spring.new(0.3, 0.0))
    if s.right {
        mover.style.margin.left = .length(300.0)
    }
    var page = col().wFull().hFull().child(mover)
    if s.shown {
        page = page.child(el().key("box").size(100.0, 40.0).bg(ink))
    }
    return page
}

private func runGateCell(_ change: (inout GateBoxState, inout Tx) -> Void) -> MotionGateRecording {
    let r = MotionGateRun.new(Runtime.new(GateBoxState(), gateBoxView, (600.0, 400.0), Env.new(true, 1.0)), 120.0)
    r.idle(0.5)
    r.step()
    r.act("change") { rt in rt.update(change) }
    r.play(1.0)
    return r.rec
}

private func gateKinds(_ rec: MotionGateRecording) -> [String] {
    motionGateCheck(rec).map(\.kind)
}

private struct FeedState {
    var pollsChange: Bool
}

private func feedView(_: FeedState, _: Cx<FeedState>) -> El {
    let rows = (0..<40).reduce(col().wFull()) { c, i in
        c.child(el().key("row\(i)").wFull().h(40.0).bg(oklch(0.3, 0.02, 250.0)))
    }
    return col().wFull().hFull().child(col().key("feed").wFull().h(300.0).scroll(ScrollSpec(stickBottom: false)).child(rows))
}

private func runScrollCell(_ pollsChange: Bool) -> MotionGateRecording {
    let rt = Runtime.new(FeedState(pollsChange: pollsChange), feedView, (400.0, 300.0), Env.new(true, 1.0))
    rt.poll = { s, _, _ in s.pollsChange }
    let r = MotionGateRun.new(rt, 120.0)
    r.idle(0.5)
    r.step()
    for _ in 0..<30 {
        r.act("wheel") { rt in rt.wheel(200.0, 150.0, -12.0) }
    }
    r.play(0.5)
    return r.rec
}

private struct ZoomedState {
    var drop: Float
    var spring: Spring
    var down: Bool
}

private func zoomedView(_ s: ZoomedState, _: Cx<ZoomedState>) -> El {
    let ink = oklch(0.6, 0.15, 25.0)
    let rows = (0..<30).reduce(col().key("rows").wFull()) { c, i in
        var row = el().key("row\(i)").wFull().h(40.0).bg(ink).motion(s.spring)
        if i == 0 && s.down {
            row.style.margin.top = .length(s.drop)
        }
        return c.child(row)
    }
    var zoomCol = col().key("zoom").wFull().hFull()
        .child(col().key("feed").wFull().hFull().scroll(ScrollSpec(stickBottom: false)).child(rows))
    zoomCol.scaleValue = 1.6
    return zoomCol
}

private func runZoomedCell(_ drop: Float, _ spring: Spring) -> MotionGateRecording {
    let r = MotionGateRun.new(
        Runtime.new(ZoomedState(drop: drop, spring: spring, down: false), zoomedView, (600.0, 600.0), Env.new(true, 1.0)),
        120.0
    )
    r.rt.update { _, tx in tx.scrollTo("feed", 200.0, animated: false) }
    r.idle(0.5)
    r.step()
    // Data arriving, not a hand: an input would excuse a path that turns.
    r.rt.update { s, tx in
        s.down = true
        tx.scrollTo("feed", 400.0, animated: true)
    }
    r.play(1.0)
    return r.rec
}

private func paddedView(_: Int, _: Cx<Int>) -> El {
    var baseRows = col().key("rows").wFull()
    baseRows.style.padding.top = .length(300.0)
    let rows = (0..<20).reduce(baseRows) { c, i in
        c.child(el().key("row\(i)").wFull().h(40.0).bg(oklch(0.3, 0.02, 250.0)))
    }
    return col().wFull().hFull().child(col().key("list").wFull().h(300.0).scroll(ScrollSpec(stickBottom: false)).child(rows))
}

private func paddedJumps(_ scroll: (MotionGateRun<Int>) -> Void) -> [String] {
    let r = MotionGateRun.new(Runtime.new(0, paddedView, (400.0, 400.0), Env.new(true, 1.0)), 120.0)
    r.idle(0.5)
    r.step()
    scroll(r)
    r.play(1.0)
    let targetKinds: Set<String> = ["jump", "offset-jump", "jerk", "appear-then-jump"]
    return r.finish().filter { targetKinds.contains($0.kind) }.map(\.description)
}

@Suite("MotionGateIntegrationTests")
struct MotionGateIntegrationTests {
    @Test("A run records a spring as clean and a snap as a jump")
    func aRunRecordsASpringAsCleanAndASnapAsAJump() {
        let spring = runGateCell { s, _ in s.right = true }
        #expect(spring.frames == 122)
        #expect(gateKinds(spring).isEmpty)

        let snap = runGateCell { s, tx in
            s.right = true
            tx.instant()
        }
        #expect(gateKinds(snap) == ["jump"])
    }

    @Test("A box that mounts with no transition pops in unless allowed")
    func aBoxThatMountsWithNoTransitionPopsInUnlessAllowed() {
        let rec = runGateCell { s, tx in
            s.shown = true
            tx.instant()
        }
        let findings = motionGateCheck(rec)
        #expect(findings.contains(where: { $0.kind == "pop-in" && $0.element.contains("box") }))

        let cells = [MotionGateCell(name: "show/wide", findings: findings, frames: rec.frames, skipped: false)]
        let open = motionGateReport(cells, [], false, 0.0)
        #expect(open.failing > 0 && open.text.contains("pop-in") && open.text.contains("mounts at or above"))

        let allow: [MotionGateAllow] = [("pop-in", "box", "show/", "the box appears at once, by design")]
        let allowed = motionGateReport(cells, allow, true, 0.0)
        #expect(allowed.failing == 0 && allowed.allowed == 1)
        #expect(allowed.text.contains("allowed") && allowed.text.contains("by design"))
        #expect(motionGateReport(cells, [("pop-in", "box", "narrow", "")], false, 0.0).failing == 1)
    }

    @Test("run keeps filtered cells in order and flags one that recorded nothing")
    func runKeepsFilteredCellsInOrderAndFlagsOneThatRecordedNothing() {
        let jobs: [(String, MotionGateJob)] = [
            ("move/wide", { runGateCell { s, _ in s.right = true } }),
            ("move/narrow", { runGateCell { s, _ in s.right = true } }),
            ("empty/wide", { MotionGateRecording.new((10.0, 10.0), 120.0) }),
            ("show/wide", { Issue.record("filtered out cell should not run"); return MotionGateRecording.new((10.0, 10.0), 120.0) }),
        ]
        let cells = motionGateRun(jobs, "m")
        #expect(cells.map(\.name) == ["move/wide", "move/narrow", "empty/wide"])
        #expect(cells[2].skipped && !cells[0].skipped)
        #expect(motionGateReport(cells, [], false, 0.0).failing == 1)
    }

    @Test("An app that runs its view through a scroll fails the gate")
    func anAppThatRunsItsViewThroughAScrollFailsTheGate() {
        let still = runScrollCell(false)
        #expect(!gateKinds(still).contains("scroll-commit"))

        let busy = runScrollCell(true)
        let f = motionGateCheck(busy).filter { $0.kind == "scroll-commit" }
        #expect(f.count == 1)
        #expect(f.first?.detail.contains("(poll)") == true)
    }

    @Test("Motion inside a zoomed scroll is judged against the scroll")
    func motionInsideAZoomedScrollIsJudgedAgainstTheScroll() {
        func paths(_ rec: MotionGateRecording, _ kinds: Set<String>) -> [String] {
            motionGateCheck(rec).filter { kinds.contains($0.kind) }.map(\.description)
        }
        let turnKinds: Set<String> = ["reversal", "jiggle", "overshoot"]
        let glide = runZoomedCell(60.0, Spring.new(0.2, 0.0))
        let row = glide.tracks.first(where: { $0.path.hasSuffix("row12") })
        #expect(row != nil)
        if let row {
            for idx in 1..<row.frames.count {
                #expect(row.frames[idx].1.rect[1] <= row.frames[idx - 1].1.rect[1] + 0.01)
            }
        }
        #expect(paths(glide, turnKinds).isEmpty)

        let wobble = runZoomedCell(60.0, Spring.new(0.3, 0.5))
        let turns = paths(wobble, turnKinds)
        #expect(turns.contains(where: { $0.contains("row12") }))
    }

    @Test("A scroll that teleports a row into view with no input jumps")
    func aScrollThatTeleportsARowIntoViewWithNoInputJumps() {
        let instant = paddedJumps { r in
            r.rt.update { _, tx in tx.scrollTo("list", 40.0, animated: false) }
            r.step()
        }
        #expect(instant.count == 1)
        #expect(instant.first?.hasPrefix("jump") == true && instant.first?.contains("rows") == true)

        let wheel = paddedJumps { r in
            for _ in 0..<4 {
                r.act("wheel") { rt in rt.wheel(200.0, 150.0, -10.0) }
            }
        }
        #expect(wheel.isEmpty)

        let tapped = paddedJumps { r in
            r.act("tap") { rt in rt.update { _, tx in tx.scrollTo("list", 40.0, animated: false) } }
        }
        #expect(tapped.isEmpty)

        let glide = paddedJumps { r in
            r.rt.update { _, tx in tx.scrollTo("list", 40.0, animated: true) }
            r.step()
        }
        #expect(glide.isEmpty)
    }
}
