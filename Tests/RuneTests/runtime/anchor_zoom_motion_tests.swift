// Tests ported from: crates/rune/src/runtime/anchor_zoom_motion_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import RuneMotion
import Testing
@testable import Rune

@Suite("AnchorZoomMotionTests")
struct AnchorZoomMotionTests {
    private struct S: Sendable {
        var zoom: Float
        var open: Bool
    }

    private static func buildView(_ s: S, _ cx: Cx<S>) -> El {
        _ = cx
        let target = rtScale(
            rtAbsolute(el().key("target").size(80.0, 20.0).bg(.WHITE), 100.0, 100.0),
            s.zoom
        )
        let root = col().size(800.0, 600.0).child(target)
        guard s.open else { return root }
        let pop = rtAnchored(
            col().key("pop").w(120.0).pad(10.0).bg(.WHITE)
                .child(text("Rename").key("label").font(TextStyle.new(13.0, 400.0)))
                .transition(Transition.scale(0.95).combined(Transition.opacity())),
            Anchor(key: "target", side: .bottom, align: .start, gap: 5.0)
        )
        return root.child(pop)
    }

    @Test("Anchored popover entering and exiting on a zoomed trigger passes the motion gate")
    func anchoredZoomMotionGate() {
        @Sendable func runCell(_ start: S, _ what: String, _ change: @escaping @Sendable (inout S) -> Void) -> MotionGateRecording {
            let rt = Runtime.new(start, Self.buildView, (800.0, 600.0), Env.new(true, 2.0))
            let r = MotionGateRun.new(rt, 120.0)
            r.idle(1.0)
            r.step()
            r.act(what) { runtime in runtime.update { st, _ in change(&st) } }
            r.play(1.2)
            r.quiet()
            r.play(0.3)
            return r.rec
        }

        let cells: [(String, MotionGateJob)] = [
            ("anchored-zoom/enter-zoomed", { runCell(S(zoom: 1.6, open: false), "open") { $0.open = true } }),
            ("anchored-zoom/exit-zoomed", { runCell(S(zoom: 1.6, open: true), "close") { $0.open = false } }),
        ]
        for (name, job) in cells {
            let rec = job()
            let findings = motionGateCheck(rec)
            #expect(findings.isEmpty, "Unexpected motion findings in \(name): \(findings)")
        }
    }
}
