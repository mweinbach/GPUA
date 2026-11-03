// Tests ported from: crates/rune/src/runtime/tests/text_glide.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import RuneMotion
import Testing
@testable import Rune

private func rtCardRectAt(_ instances: [Instance]) -> (Float, Float)? {
    for inst in instances where abs(inst.params[1] - KIND_RECT) < 0.5 && inst.fill[3] > 0.0 {
        return (inst.rect[0], inst.rect[1])
    }
    return nil
}

private func rtFirstGlyphCenter(_ instances: [Instance]) -> (Float, Float)? {
    for inst in instances where abs(inst.params[1] - KIND_GLYPH) < 0.5 {
        return (inst.rect[0] + inst.rect[2] * 0.5, inst.rect[1] + inst.rect[3] * 0.5)
    }
    return nil
}

@Suite struct RtTextGlideTests {
    @Test
    func cardWithTextGlidesSubpixelSmoothlyAndSettlesToExactRestingInstances() {
        let cases: [(step: Float, hz: Double)] = [
            (0.08, 120.0),
            (0.08, 60.0),
            (0.3, 60.0),
            (1.0, 120.0),
        ]

        for (amp, hz) in cases {
            let liveOff = Live([Float(0.0), Float(0.0)])
            let rt = Runtime.new(0, { _, _ in
                let card = col()
                    .key("card")
                    .size(180.0, 48.0)
                    .bg(.WHITE)
                    .liveOffset(Binding(live: liveOff, spring: Spring.new(0.28, 0.0)))
                    .child(text("Quiet harbor glides").font(TextStyle.new(16.0, 500.0)).key("label"))
                return col().size(300.0, 140.0).pad(20.0).child(card)
            }, (300.0, 140.0), Env.new(true, 2.0))

            _ = rt.frame(0.0)
            let startCard = rtCardRectAt(rt.instances)!
            let startGlyph = rtFirstGlyphCenter(rt.instances)!
            let baseRelX = startGlyph.0 - startCard.0
            let baseRelY = startGlyph.1 - startCard.1

            liveOff.set([amp * 8.0, amp * 6.0])
            var maxRelDrift: Float = 0.0
            for _ in 0..<45 {
                _ = rt.frame(1.0 / hz)
                let curCard = rtCardRectAt(rt.instances)!
                let curGlyph = rtFirstGlyphCenter(rt.instances)!
                let relX = curGlyph.0 - curCard.0
                let relY = curGlyph.1 - curCard.1
                maxRelDrift = max(maxRelDrift, max(abs(relX - baseRelX), abs(relY - baseRelY)))
            }
            #expect(maxRelDrift <= 0.35)
        }

        // Settled runtime at `[0.7, -1.3]` matches a fresh still runtime at `[0.7, -1.3]`
        let targetOff: [Float] = [0.7, -1.3]
        let liveMoved = Live([Float(0.0), Float(0.0)])
        let movingRt = Runtime.new(0, { _, _ in
            let card = col()
                .key("card")
                .size(180.0, 48.0)
                .bg(.WHITE)
                .liveOffset(Binding(live: liveMoved, spring: Spring.new(0.2, 0.0)))
                .child(text("Quiet harbor glides").font(TextStyle.new(16.0, 500.0)))
            return col().size(300.0, 140.0).pad(20.0).child(card)
        }, (300.0, 140.0), Env.new(true, 2.0))
        _ = movingRt.frame(0.0)
        liveMoved.set(targetOff)
        rtStepFrames(movingRt, 120)

        let liveStill = Live(targetOff)
        let stillRt = Runtime.new(0, { _, _ in
            let card = col()
                .key("card")
                .size(180.0, 48.0)
                .bg(.WHITE)
                .liveOffset(Binding(live: liveStill, spring: nil))
                .child(text("Quiet harbor glides").font(TextStyle.new(16.0, 500.0)))
            return col().size(300.0, 140.0).pad(20.0).child(card)
        }, (300.0, 140.0), Env.new(true, 2.0))
        _ = stillRt.frame(0.0)

        let movedInst = movingRt.instances
        let stillInst = stillRt.instances
        #expect(movedInst.count == stillInst.count)
        for idx in movedInst.indices {
            for rIdx in 0..<4 {
                #expect(abs(movedInst[idx].rect[rIdx] - stillInst[idx].rect[rIdx]) < 1e-3)
            }
        }
    }
}
