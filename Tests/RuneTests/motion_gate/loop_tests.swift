// Tests ported from: crates/rune/src/motion_gate/loop_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import RuneMotion
import Taffy
import Testing
@testable import Rune

private func loopTestKinds(_ rec: MotionGateRecording) -> [String] {
    motionGateCheck(rec).map(\.kind)
}

private struct BadgeState {
    var shown: Bool = false
    var right: Bool = false
}

private let fadeInBeats: [Beat] = [
    Beat.new(0.0).opacity(0.0),
    Beat.new(0.2).easing(.easeOut),
]

private func badgeView(_ s: BadgeState, _: Cx<BadgeState>) -> El {
    var b = el().key("badge").size(100.0, 40.0).bg(oklch(0.6, 0.1, 250.0))
    b.loopingSpec = LoopSpec.sequence(RuneMotion.Sequence.new(fadeInBeats))
    if s.right {
        b.style.margin.left = .length(200.0)
    }
    return col().wFull().hFull().children(s.shown ? [b] : [])
}

private struct SpinnerState {
    var on: Bool = true
}

private func spinnerView(_ s: SpinnerState, _: Cx<SpinnerState>) -> El {
    var spin = el().key("spin").size(20.0, 20.0).bg(oklch(0.6, 0.1, 250.0))
    spin.loopingSpec = LoopSpec.rotation(1.0)
    return col().wFull().hFull().children(s.on ? [spin] : [])
}

private func runSpin(_ restart: Bool) -> MotionGateRecording {
    let r = MotionGateRun.new(Runtime.new(SpinnerState(on: true), spinnerView, (200.0, 200.0), Env.new(true, 1.0)), 120.0)
    r.idle(0.5)
    r.step()
    r.play(0.6)
    if restart {
        r.act("hide") { rt in rt.update { s, tx in s.on = false; tx.instant() } }
        r.act("show") { rt in rt.update { s, tx in s.on = true; tx.instant() } }
    }
    r.play(0.6)
    return r.rec
}

private struct TimelineState {
    var open: Bool = false
    var rows: Int = 60
    var tick: UInt32 = 0
}

private func timelineView(_ s: TimelineState, _: Cx<TimelineState>) -> El {
    let open = s.open
    let ink = oklch(0.6, 0.1, 250.0)
    var builtRows: [El] = []
    builtRows.reserveCapacity(s.rows)
    for i in 0..<s.rows {
        let item: El
        if i != 55 {
            item = el().wFull().h(40.0).bg(ink)
        } else {
            var group = col().key("group").wFull().child(el().key("hdr").wFull().h(28.0).bg(ink))
            if open {
                let steps = (0..<40).map { k in el().key("step-\(k)").wFull().h(28.0).bg(ink) }
                group = group.child(col().key("steps").wFull().children(steps))
            }
            var foldEl = col().wFull().child(group)
            foldEl.glideSpec = FoldGlide(spring: Spring.new(0.18, 0.0))
            item = foldEl
        }
        builtRows.append(item.key("r\(i)"))
    }
    var rows = col().key("rows").wFull().growth(GrowthSpec()).children(builtRows)
    rows.hasVirtual = true
    return col().key("scroll").size(400.0, 300.0).scroll(ScrollSpec(stickBottom: true)).child(rows)
}

private func runFold(_ toggles: [Double], _ last: ((inout TimelineState, inout Tx) -> Void)?) -> MotionGateRecording {
    let r = MotionGateRun.new(
        Runtime.new(TimelineState(open: false, rows: 60, tick: 0), timelineView, (400.0, 300.0), Env.new(true, 1.0)),
        120.0
    )
    r.idle(1.0)
    r.step()
    func play(_ secs: Double) {
        let count = Int((secs * 120.0).rounded())
        for _ in 0..<count {
            r.rt.update { s, _ in s.tick &+= 1 }
            r.step()
        }
    }
    for secs in toggles {
        r.act("tap") { rt in
            rt.update { s, tx in
                s.open.toggle()
                tx.keepOnScreenKeys.append("hdr")
            }
        }
        play(secs)
    }
    if let last {
        r.act("remove") { rt in rt.update(last) }
        play(0.5)
    }
    return r.rec
}

@Suite("MotionGateLoopTests")
struct MotionGateLoopTests {
    @Test("A one-shot fade that settles is not a loop")
    func aOneShotFadeThatSettlesIsNotALoop() {
        let r = MotionGateRun.new(Runtime.new(BadgeState(), badgeView, (400.0, 200.0), Env.new(true, 1.0)), 120.0)
        r.idle(0.5)
        r.step()
        r.act("show") { rt in rt.update { s, _ in s.shown = true } }
        r.play(1.0)
        #expect(loopTestKinds(r.rec).isEmpty)

        // Nor does it hide what the element does after: a snap is still a jump.
        r.act("move") { rt in rt.update { s, tx in s.right = true; tx.instant() } }
        r.play(0.5)
        #expect(loopTestKinds(r.rec) == ["jump"])
    }

    @Test("A spinner keeps its rhythm unless it restarts")
    func aSpinnerKeepsItsRhythmUnlessItRestarts() {
        #expect(!loopTestKinds(runSpin(false)).contains("loop-jump"))
        #expect(loopTestKinds(runSpin(true)).contains("loop-jump"))
    }

    @Test("Rows under a fold gliding open stay mounted while they show")
    func rowsUnderAFoldGlidingOpenStayMountedWhileTheyShow() {
        let rec = runFold([1.0], nil)
        #expect(!loopTestKinds(rec).contains("pop-out"))
    }

    @Test("A list toggled over and over is not a loop")
    func aListToggledOverAndOverIsNotALoop() {
        let rec = runFold([0.3, 0.3, 0.3, 0.3, 0.3, 0.06, 0.5, 0.8]) { s, tx in
            s.rows = 59
            tx.instant()
        }
        let found = motionGateCheck(rec)
        #expect(found.contains(where: { $0.kind == "pop-out" && $0.element.hasSuffix("r59") }))
    }
}
