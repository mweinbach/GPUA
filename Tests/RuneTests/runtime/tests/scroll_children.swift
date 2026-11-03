// Tests ported from: crates/rune/src/runtime/tests/scroll_children.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import RuneMotion
import Taffy
@testable import Rune

@Suite struct RtScrollChildrenTests {
    @Test
    func directRowChildrenScrollToBottomAndIntoView() {
        let rt = Runtime.new(50, { count, _ in
            var sc = col().key("scroll").size(200.0, 200.0).scroll(ScrollSpec(stickBottom: false))
            for i in 0..<count {
                var r = el().key("r\(i)").wFull().h(30.0)
                r.style.flexShrink = 0.0
                sc = sc.child(r)
            }
            return col().size(200.0, 200.0).child(sc)
        }, (200.0, 200.0), Env.new(true, 1.0))

        _ = rt.frame(0.0)
        rt.wheel(100.0, 100.0, -10_000.0)
        _ = rt.frame(1.0 / 60.0)

        let r49 = rtElement(rt, "r49")!
        #expect(abs((r49.rect[1] + r49.rect[3]) - 200.0) < 0.5)
        let stuck = rt.isStuckToBottom("scroll")
        #expect(stuck)

        // Reset to top and scrollIntoView("r39")
        rt.update { _, tx in tx.scrollToInstant("scroll", 0.0) }
        _ = rt.frame(1.0 / 60.0)
        rt.update { _, tx in tx.scrollIntoView("r39") }
        rtStepFrames(rt, 90)
        let r39 = rtElement(rt, "r39")!
        #expect(abs((r39.rect[1] + r39.rect[3]) - 200.0) < 0.5)
    }

    @Test
    func directHorizontalChildrenAndDualAxisScroll() {
        let rt = Runtime.new(50, { count, _ in
            var strip = row().key("strip").size(200.0, 50.0).scroll(ScrollSpec(stickBottom: false))
            for i in 0..<count {
                var c = el().key("c\(i)").size(30.0, 50.0)
                c.style.flexShrink = 0.0
                strip = strip.child(c)
            }
            return col().size(200.0, 200.0).child(strip)
        }, (200.0, 200.0), Env.new(true, 1.0))

        _ = rt.frame(0.0)
        rt.wheel(100.0, 25.0, -10_000.0, 0.0)
        _ = rt.frame(1.0 / 60.0)
        let c49 = rtElement(rt, "c49")!
        #expect(abs((c49.rect[0] + c49.rect[2]) - 200.0) < 0.5)

        // Vertical scroll container with `overflow.x = .scroll` scrolls on both axes
        let dual = Runtime.new(0, { _, _ in
            var canvas = el().key("canvas").size(500.0, 500.0)
            canvas.style.flexShrink = 0.0
            var sc = col().key("both").size(200.0, 200.0).scroll(ScrollSpec(stickBottom: false)).child(canvas)
            sc.style.overflow = Point(x: .scroll, y: .scroll)
            return col().size(200.0, 200.0).child(sc)
        }, (200.0, 200.0), Env.new(true, 1.0))
        _ = dual.frame(0.0)
        dual.wheel(100.0, 100.0, -120.0, -160.0)
        _ = dual.frame(1.0 / 60.0)
        let sx = dual.scrollOffsetX("both")
        let sy = dual.scrollOffset("both")
        #expect(abs(sx - 120.0) < 0.5)
        #expect(abs(sy - 160.0) < 0.5)
    }

    @Test
    func stickBottomStaysPinnedAcrossDirectAndBannerGrowthStacks() {
        // Direct children 6 -> 10 in 150pt viewport
        let directRt = Runtime.new(6, { count, _ in
            var sc = col().key("scroll").size(200.0, 150.0).scroll(ScrollSpec(stickBottom: true))
            for i in 0..<count {
                var r = el().key("r\(i)").wFull().h(40.0)
                r.style.flexShrink = 0.0
                sc = sc.child(r)
            }
            return col().size(200.0, 150.0).child(sc)
        }, (200.0, 150.0), Env.new(true, 1.0))

        _ = directRt.frame(0.0)
        let r5 = rtElement(directRt, "r5")!
        #expect(abs((r5.rect[1] + r5.rect[3]) - 150.0) < 0.5)

        directRt.update { count, _ in count = 10 }
        _ = directRt.frame(1.0 / 60.0)
        let r9 = rtElement(directRt, "r9")!
        #expect(abs((r9.rect[1] + r9.rect[3]) - 150.0) < 0.5)

        // Banner (40 -> 120) above a pinned GrowthSpec stack keeps last row bottom at 200
        struct BannerState: Sendable {
            var count: Int
            var bannerH: Float
        }
        let bannerRt = Runtime.new(BannerState(count: 6, bannerH: 40.0), { s, _ in
            var banner = el().key("banner").wFull().h(s.bannerH)
            banner.style.flexShrink = 0.0
            banner.animateLayoutFlag = true
            var stack = col().key("stack").wFull()
            stack.growthSpec = GrowthSpec()
            for i in 0..<s.count {
                stack = stack.child(el().key("r\(i)").wFull().h(40.0))
            }
            let sc = col().key("scroll").size(200.0, 200.0).scroll(ScrollSpec(stickBottom: true))
                .child(banner)
                .child(stack)
            return col().size(200.0, 200.0).child(sc)
        }, (200.0, 200.0), Env.new(true, 1.0))

        _ = bannerRt.frame(0.0)
        bannerRt.update { s, _ in
            s.count = 8
            s.bannerH = 120.0
        }
        rtStepFrames(bannerRt, 90)
        let lastRow = rtElement(bannerRt, "r7")!
        #expect(abs((lastRow.rect[1] + lastRow.rect[3]) - 200.0) < 0.5)
    }
}
