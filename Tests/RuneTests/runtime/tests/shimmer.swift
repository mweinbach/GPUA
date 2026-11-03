// Tests ported from: crates/rune/src/runtime/tests/shimmer.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import RuneMotion
import Taffy
import Testing
@testable import Rune

private struct RtShimmerState: Sendable {
    var running: Bool
    var zoom: Float
}

private func rtShimmerLoopEl(_ base: El, _ spec: LoopSpec?) -> El {
    var copy = base
    copy.loopingSpec = spec
    return copy
}

private func rtShimmerAbsolute(_ base: El, _ left: Float, _ top: Float) -> El {
    var copy = base
    copy.style.position = .absolute
    copy.style.inset = Taffy.Rect(left: .length(left), right: .auto(), top: .length(top), bottom: .auto())
    return copy
}

private func rtShimmerView(_ s: RtShimmerState, _: Cx<RtShimmerState>) -> El {
    let w: Float = 160.0
    let sheenW: Float = 40.0
    let period: Double = 1.2
    let x0: Float = -sheenW
    let x1: Float = w
    let style = TextStyle.new(16.0, 500.0)

    let baseText = text("Shimmering row").font(style).key("dim")
    var box = el().key("host").size(w, 32.0).child(baseText)
    box.vis.clip = true
    box.scaleValue = s.zoom

    if s.running {
        let sheenLoop = LoopSpec.slide(period, [x0 / sheenW, 0.0], [x1 / sheenW, 0.0]).easing(.linear)
        let counterLoop = LoopSpec.slide(period, [-x0 / w, 0.0], [-x1 / w, 0.0]).easing(.linear)

        var lit = rtShimmerAbsolute(text("Shimmering row").font(style).key("lit"), 0.0, 0.0)
        lit = rtShimmerLoopEl(lit.size(w, 32.0), counterLoop)

        var sheen = rtShimmerAbsolute(el().key("sheen").size(sheenW, 32.0), 0.0, 0.0).child(lit)
        sheen.vis.clip = true
        sheen = rtShimmerLoopEl(sheen, sheenLoop)
        box = box.child(sheen)
    }

    return col().size(240.0, 120.0).child(box)
}

@Suite struct RtShimmerTests {
    @Test
    func counterSlidingSheenAndLitKeepZeroNetOffsetAcrossZoomsAndRestarts() {
        for zoom: Float in [1.0, 1.1, 0.9, 1.25] {
            let rt = Runtime.new(
                RtShimmerState(running: true, zoom: zoom),
                rtShimmerView,
                (240.0, 120.0),
                Env.new(true, 2.0)
            )
            _ = rt.frame(0.0)

            let sheenId = rt.nodes.first { $0.key == "sheen" }!.nodeId
            let litId = rt.nodes.first { $0.key == "lit" }!.nodeId

            for step in 1...24 {
                _ = rt.frame(Double(step) * 0.003 + 1.0 / 120.0)
                let a = rt.scene.get(sheenId, RuneMotion.prop.offset)?.x ?? 0.0
                let b = rt.scene.get(litId, RuneMotion.prop.offset)?.x ?? 0.0
                #expect(abs(a + b) <= 0.01)

                let dimRect = rtElement(rt, "dim")!.rect
                let litRect = rtElement(rt, "lit")!.rect
                #expect(abs(dimRect[0] - litRect[0]) <= 1.0)
            }

            // Stop and restart shimmer cleanly, settle entrance, then check window visibility toggle & settleAll
            rt.update { s, _ in s.running = false }
            _ = rt.frame(1.0 / 120.0)
            rt.update { s, _ in s.running = true }
            rt.settleAll()
            _ = rt.frame(1.0 / 120.0)

            rt.setWindowVisible(false)
            _ = rt.frame(0.25)
            let animHidden = rt.animating
            #expect(!animHidden)

            rt.setWindowVisible(true)
            _ = rt.frame(1.0 / 120.0)
            let newSheenId = rt.nodes.first { $0.key == "sheen" }!.nodeId
            let newLitId = rt.nodes.first { $0.key == "lit" }!.nodeId
            let a2 = rt.scene.get(newSheenId, RuneMotion.prop.offset)?.x ?? 0.0
            let b2 = rt.scene.get(newLitId, RuneMotion.prop.offset)?.x ?? 0.0
            #expect(abs(a2 + b2) <= 0.01)

            rt.settleAll()
            _ = rt.frame(1.0 / 120.0)
            let a3 = rt.scene.get(newSheenId, RuneMotion.prop.offset)?.x ?? 0.0
            let b3 = rt.scene.get(newLitId, RuneMotion.prop.offset)?.x ?? 0.0
            #expect(abs(a3 + b3) <= 0.01)
        }
    }
}
