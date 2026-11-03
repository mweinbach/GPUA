// Tests ported from: crates/rune/src/runtime/tests/scroll_growth.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import RuneMotion
@testable import Rune

@Suite struct RtScrollGrowthTests {
    @Test
    func growthRowsGrowAndStickyScrollLandsAtBottom() {
        let rt = Runtime.new(10, { n, _ in
            var stack = col().key("stack").wFull()
            stack.growthSpec = GrowthSpec()
            for i in 0..<n {
                stack = stack.child(el().key("r\(i)").wFull().h(100.0))
            }
            let sc = col().key("scroll").size(200.0, 300.0).scroll(ScrollSpec(stickBottom: true)).child(stack)
            return col().size(200.0, 300.0).child(sc)
        }, (200.0, 300.0), Env.new(true, 1.0))

        _ = rt.frame(0.0)
        #expect(abs(rt.scrollOffset("scroll") - 700.0) < 0.5)

        rt.update { n, _ in n = 11 }
        _ = rt.frame(1.0 / 60.0)
        // Growing smoothly from 700 -> 800
        let firstOff = rt.scrollOffset("scroll")
        #expect(firstOff > 700.0 && firstOff < 800.0)

        rtStepFrames(rt, 90)
        let finalOff = rt.scrollOffset("scroll")
        #expect(abs(finalOff - 800.0) < 0.5)
        let r10 = rtElement(rt, "r10")!
        #expect(abs((r10.rect[1] + r10.rect[3]) - 300.0) < 0.5)
    }

    @Test
    func animateLayoutSpringsHorizontallyInsideGrowthRowAndSkipsOffscreen() {
        struct RowState: Sendable {
            var wide: Bool
        }
        let rt = Runtime.new(RowState(wide: false), { s, _ in
            var stack = col().key("stack").wFull()
            stack.growthSpec = GrowthSpec()
            for i in 0..<35 {
                let chipW: Float = s.wide ? 88.0 : 53.0
                var chip = el().key("chip\(i)").size(chipW, 24.0)
                chip.animateLayoutFlag = true
                stack = stack.child(row().key("r\(i)").wFull().h(40.0).child(chip))
            }
            let sc = col().key("scroll").size(200.0, 200.0).scroll(ScrollSpec(stickBottom: false)).child(stack)
            return col().size(200.0, 200.0).child(sc)
        }, (200.0, 200.0), Env.new(true, 1.0))

        _ = rt.frame(0.0)
        rt.update { s, _ in s.wide = true }
        _ = rt.frame(1.0 / 60.0)

        let visibleChip = rtElement(rt, "chip0")!
        let offscreenChip = rtElement(rt, "chip30")!
        // Visible chip springs width toward 88 while offscreen chip lands at 88 immediately
        #expect(visibleChip.rect[2] > 53.0 && visibleChip.rect[2] < 88.0)
        #expect(abs(offscreenChip.rect[2] - 88.0) < 0.5)

        rtStepFrames(rt, 90)
        #expect(abs(rtElement(rt, "chip0")!.rect[2] - 88.0) < 0.5)
    }

    @Test
    func readerScrolledUpClampsCleanlyWhenRowsShrinkAndHonorsKeepOnScreen() {
        let rt = Runtime.new(20, { n, _ in
            var stack = col().key("stack").wFull()
            stack.growthSpec = GrowthSpec()
            for i in 0..<n {
                stack = stack.child(el().key("r\(i)").wFull().h(100.0))
            }
            let sc = col().key("scroll").size(200.0, 300.0).scroll(ScrollSpec(stickBottom: true)).child(stack)
            return col().size(200.0, 300.0).child(sc)
        }, (200.0, 300.0), Env.new(true, 1.0))

        _ = rt.frame(0.0)
        // Reader scrolls slightly up from bottom (to 1500 out of max 1700)
        rt.wheel(100.0, 150.0, 200.0)
        _ = rt.frame(1.0 / 60.0)
        #expect(abs(rt.scrollOffset("scroll") - 1500.0) < 0.5)

        // Shrinking from 20 -> 15 rows lowers maxScroll to 1200; offset clamps cleanly to 1200
        rt.update { n, _ in n = 15 }
        rtStepFrames(rt, 90)
        #expect(abs(rt.scrollOffset("scroll") - 1200.0) < 0.5)

        // Requesting `keepOnScreen("r14")` keeps `r14` visible in viewport
        rt.update { _, tx in tx.keepOnScreen("r14") }
        rtStepFrames(rt, 60)
        let r14 = rtElement(rt, "r14")!
        #expect(r14.rect[1] >= -0.5 && (r14.rect[1] + r14.rect[3]) <= 300.5)
    }
}
