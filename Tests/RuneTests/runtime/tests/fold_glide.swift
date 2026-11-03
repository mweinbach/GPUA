// Tests ported from: crates/rune/src/runtime/tests/fold_glide.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

@testable import Rune
import RuneMotion
import Testing

private func rtFoldGlideEl(_ base: El, _ spring: Spring = Spring.new(0.18, 0.0)) -> El {
    var copy = base
    copy.glideSpec = FoldGlide(spring: spring)
    return copy
}

private func rtWholeEl(_ base: El) -> El {
    var copy = base
    copy.wholeFlag = true
    return copy
}

private func rtStickyTopEl(_ base: El, _ top: Float = 0.0) -> El {
    var copy = base
    copy.style.gridTemplateRowNames.append(["__rt_sticky_top__", "\(top.isFinite ? top : 0.0)"])
    return copy
}

@Suite
struct RtFoldGlideTests {
    @Test
    func foldGlideShutsOnItsOwnSpringFasterThanTheGrowthStack() {
        func makeStack(_ useFoldGlide: Bool) -> Runtime<Bool> {
            let stackSpring = Spring.new(0.32, 0.0)
            let foldSpring = Spring.new(0.18, 0.0)
            return Runtime.new(true, { open, _ in
                let targetH: Float = open ? 600.0 : 40.0
                var fold = col().key("fold").wFull().h(targetH).bg(.WHITE)
                fold = useFoldGlide ? rtFoldGlideEl(fold, foldSpring) : rtWholeEl(fold)
                return col()
                    .key("stack")
                    .size(300.0, 700.0)
                    .growth(GrowthSpec(spring: stackSpring))
                    .child(fold)
                    .child(el().key("after").wFull().h(40.0).bg(.WHITE))
            }, (300.0, 700.0), Env.new(true, 1.0))
        }

        func shutSecs(_ useFoldGlide: Bool) -> Float {
            let rt = makeStack(useFoldGlide)
            _ = rt.frame(0.0)
            rt.update { open, _ in open = false }
            for k in 1...240 {
                _ = rt.frame(1.0 / 120.0)
                if abs((rtElement(rt, "after")?.rect[1] ?? 600.0) - 40.0) < 0.5 {
                    return Float(k) / 120.0
                }
            }
            return 2.0
        }

        let ownSecs = shutSecs(true)
        let stackSecs = shutSecs(false)
        #expect(ownSecs < 0.35)
        #expect(stackSecs > ownSecs + 0.15)
    }

    @Test
    func zoomedAndViewportClippedFoldGlideOpensSmoothly() {
        let rt = Runtime.new(false, { open, _ in
            let bodyH: Float = open ? 240.0 : 28.0
            let fold = rtFoldGlideEl(col().key("fold").wFull().h(bodyH).bg(.WHITE))
            let stack = col()
                .key("rows")
                .wFull()
                .growth(GrowthSpec())
                .child(fold)
                .child(el().key("tail").wFull().h(36.0).bg(.WHITE))
            return rtScale(
                col().key("scroll").size(240.0, 200.0).scroll(ScrollSpec(stickBottom: false)).child(stack),
                1.5
            )
        }, (300.0, 300.0), Env.new(true, 1.0))

        _ = rt.frame(0.0)
        rt.update { open, _ in open = true }
        var prevTailY = rtElement(rt, "tail")?.rect[1] ?? 0.0
        for _ in 0..<60 {
            _ = rt.frame(1.0 / 120.0)
            let curTailY = rtElement(rt, "tail")?.rect[1] ?? prevTailY
            #expect(curTailY >= prevTailY - 0.5)
            prevTailY = curTailY
        }
        #expect(prevTailY > 200.0)
    }

    @Test
    func reorderingFoldRowsWhileShuttingProducesNoJump() {
        struct ReorderState {
            var openA: Bool = true
            var swapped: Bool = false
        }
        let rt = Runtime.new(ReorderState(), { s, _ in
            let a = rtFoldGlideEl(col().key("a").wFull().h(s.openA ? 180.0 : 40.0).bg(.WHITE))
            let b = el().key("b").wFull().h(40.0).bg(.WHITE)
            let kids = s.swapped ? [b, a] : [a, b]
            return col().key("rows").size(240.0, 300.0).growth(GrowthSpec()).children(kids)
        }, (240.0, 300.0), Env.new(true, 1.0))

        _ = rt.frame(0.0)
        rt.update { s, _ in s.openA = false }
        rtStepFrames(rt, 8)
        let beforeB = rtElement(rt, "b")?.rect[1] ?? 0.0

        rt.update { s, _ in s.swapped = true }
        _ = rt.frame(1.0 / 120.0)
        let firstSwapB = rtElement(rt, "b")?.rect[1] ?? 0.0
        #expect(abs(firstSwapB - beforeB) < 25.0)

        rtStepFrames(rt, 90)
        #expect(abs((rtElement(rt, "b")?.rect[1] ?? 99.0) - 0.0) < 0.5)
        #expect(abs((rtElement(rt, "a")?.rect[1] ?? 0.0) - 40.0) < 0.5)
    }

    @Test
    func stickyHeaderInsideFoldGlideWithKeepOnScreenPassesMotionGate() {
        let ink = oklch(0.6, 0.1, 250.0)
        let run = MotionGateRun.new(
            Runtime.new(false, { open, _ in
                var rows: [El] = (0..<12).map { i in
                    el().key("pre-\(i)").wFull().h(36.0).bg(ink)
                }
                var group = col()
                    .key("group")
                    .wFull()
                    .child(rtStickyTopEl(el().key("hdr").wFull().h(28.0).bg(ink), 0.0))
                if open {
                    group = group.children((0..<12).map { k in
                        el().key("step-\(k)").wFull().h(28.0).bg(ink)
                    })
                }
                rows.append(rtFoldGlideEl(col().key("fold").wFull().child(group)))
                rows.append(contentsOf: (0..<6).map { j in
                    el().key("post-\(j)").wFull().h(36.0).bg(ink)
                })
                var stack = col().key("rows").wFull().growth(GrowthSpec()).children(rows)
                stack.hasVirtual = true
                return col().key("scroll").size(320.0, 240.0).scroll(ScrollSpec(stickBottom: true)).child(stack)
            }, (320.0, 240.0), Env.new(true, 1.0)),
            120.0
        )

        run.idle(0.5)
        run.step()
        run.act("open") { rt in
            rt.update { open, tx in
                open = true
                tx.keepOnScreenKeys.append("hdr")
            }
        }
        run.play(0.6)
        run.act("shut") { rt in
            rt.update { open, tx in
                open = false
                tx.keepOnScreenKeys.append("hdr")
            }
        }
        run.play(0.6)

        let findings = run.finish().filter { $0.kind == "jump" || $0.kind == "jerk" }
        #expect(findings.isEmpty)
    }
}
