// Tests ported from: crates/rune/src/runtime/tests/picture_scale.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

@testable import Rune
import RuneMotion
import Testing

@Suite
struct RtPictureScaleTests {
    @Test
    func textInsideAScaleDrawsAtThatSizeAndHitTestsDrawnBounds() {
        struct ScaleHitState {
            var hits: Int = 0
        }
        let liveHalf = Live.new(Float(0.5))

        for useLive in [false, true] {
            let rt: Runtime<ScaleHitState> = Runtime.new(ScaleHitState(), { _, _ in
                var card = col()
                    .key("card")
                    .size(200.0, 80.0)
                    .bg(.WHITE)
                    .onPress { (s: inout ScaleHitState, _) in
                        s.hits += 1
                    }
                    .child(text("Scaled").key("lbl").font(TextStyle(size: 20.0, weight: 400.0)))
                card = useLive ? card.liveScale(Binding(live: liveHalf)) : rtScale(card, 0.5)
                return col().size(240.0, 120.0).child(card)
            }, (240.0, 120.0), Env.new(true, 1.0))

            _ = rt.frame(0.0)
            let info = rtElement(rt, "card")!
            // Layout target stays [0, 0, 200, 80], while drawn rect about centre (100, 40) is [50, 20, 100, 40]
            #expect(info.target == [0.0, 0.0, 200.0, 80.0])
            #expect(info.rect == [50.0, 20.0, 100.0, 40.0])

            let glyphHeights = rt.instances.filter { $0.params[1] == KIND_GLYPH }.map { $0.rect[3] }
            #expect(!glyphHeights.isEmpty)
            for gh in glyphHeights {
                #expect(gh <= 14.0)
            }

            // Outside drawn bounds (10, 10) misses; inside drawn bounds (100, 40) hits
            rt.pointerMove(10.0, 10.0)
            _ = rt.pointerDown(10.0, 10.0)
            rt.pointerUp(10.0, 10.0)
            #expect(rt.state.hits == 0)

            rt.pointerMove(100.0, 40.0)
            _ = rt.pointerDown(100.0, 40.0)
            rt.pointerUp(100.0, 40.0)
            #expect(rt.state.hits == 1)
        }
    }

    @Test
    func nestedScalesComposeAboutEachMappedCentre() {
        for factors: [Float] in [[0.5, 0.8], [0.5, 2.0], [0.5, 0.8, 0.9]] {
            let rt = Runtime.new((), { _, _ in
                var cur = el().key("leaf").size(100.0, 100.0).bg(.WHITE)
                for (idx, k) in factors.enumerated().reversed() {
                    cur = rtScale(col().key("lvl-\(idx)").size(100.0, 100.0).child(cur), k)
                }
                return col().size(200.0, 200.0).child(cur)
            }, (200.0, 200.0), Env.new(true, 1.0))

            _ = rt.frame(0.0)
            let expectedProduct = factors.reduce(Float(1.0), *)
            let leaf = rtElement(rt, "leaf")!
            #expect(abs(leaf.rect[2] - 100.0 * expectedProduct) < 0.05)
            #expect(abs(leaf.rect[3] - 100.0 * expectedProduct) < 0.05)
            // Concentric 100x100 boxes keep their centre at (50, 50)
            #expect(abs((leaf.rect[0] + leaf.rect[2] * 0.5) - 50.0) < 0.05)
            #expect(abs((leaf.rect[1] + leaf.rect[3] * 0.5) - 50.0) < 0.05)
        }
    }

    @Test
    func pictureWithOneSideSizesTheOtherFromItsImageWithoutReRunningView() {
        final class ViewCounter: @unchecked Sendable {
            var runs: Int = 0
        }
        let counter = ViewCounter()
        let px = Pixels.new()

        let rt = Runtime.new(false, { explicitAspect, _ in
            counter.runs += 1
            var pic = el().key("pic").w(120.0).pixels(px)
            if explicitAspect {
                pic.style.aspectRatio = 1.0
            }
            return col().size(240.0, 320.0).child(pic)
        }, (240.0, 320.0), Env.new(true, 1.0))

        _ = rt.frame(0.0)
        #expect(counter.runs == 1)
        #expect(rtElement(rt, "pic")?.rect == [0.0, 0.0, 120.0, 0.0])

        // Setting a 4x2 image updates height to 60 instantly without animating
        px.set(4, 2, [UInt8](repeating: 255, count: 4 * 2 * 4))
        _ = rt.frame(1.0 / 120.0)
        #expect(rtElement(rt, "pic")?.rect == [0.0, 0.0, 120.0, 60.0])
        let animAfterSet = rt.animating
        #expect(!animAfterSet)

        // Setting a new 4x2 frame with the SAME dimensions costs 0 commits
        let commitsBeforeSameSize = rt.totalCommits
        px.set(4, 2, [UInt8](repeating: 128, count: 4 * 2 * 4))
        _ = rt.frame(1.0 / 120.0)
        let commitsAfterSameSize = rt.totalCommits
        #expect(commitsAfterSameSize == commitsBeforeSameSize)

        // Changing dimensions to 2x4 updates height to 240
        px.set(2, 4, [UInt8](repeating: 200, count: 2 * 4 * 4))
        _ = rt.frame(1.0 / 120.0)
        #expect(rtElement(rt, "pic")?.rect == [0.0, 0.0, 120.0, 240.0])

        // Explicit `aspectRatio` wins over the image's natural aspect
        rt.update { explicitAspect, tx in
            tx.instant()
            explicitAspect = true
        }
        _ = rt.frame(1.0 / 120.0)
        #expect(rtElement(rt, "pic")?.rect == [0.0, 0.0, 120.0, 120.0])
    }

    @Test
    func removedPictureStopsWakingAndExitingPictureWakesUntilExitEnds() {
        final class WakeCount: @unchecked Sendable {
            var count: Int = 0
        }
        let wakes = WakeCount()
        let px = Pixels.new()
        px.set(2, 2, [UInt8](repeating: 255, count: 16))

        let rt = Runtime.new(true, { shown, _ in
            var root = col().size(160.0, 160.0)
            if shown {
                var pic = el().key("pic").size(60.0, 60.0).pixels(px)
                pic.transitionSpec = .opacity()
                root = root.child(pic)
            }
            return root
        }, (160.0, 160.0), Env.new(true, 1.0))
        rt.setLiveWaker { wakes.count += 1 }

        _ = rt.frame(0.0)
        wakes.count = 0

        // Animated removal: while `pic` is still fading out, `px.set` continues waking the window
        rt.update { shown, _ in shown = false }
        _ = rt.frame(1.0 / 120.0)
        let hasExiting = !rt.exitingNodes.isEmpty
        #expect(hasExiting)
        wakes.count = 0
        px.set(2, 2, [UInt8](repeating: 200, count: 16))
        #expect(wakes.count == 1)
        let pendingWhileExiting = rt.livePending()
        #expect(pendingWhileExiting)
        _ = rt.frame(1.0 / 120.0)

        // Once the exit finishes, `px.set` stops waking
        rtStepFrames(rt, 90)
        let exitedDone = rt.exitingNodes.isEmpty
        #expect(exitedDone)
        wakes.count = 0
        px.set(2, 2, [UInt8](repeating: 100, count: 16))
        #expect(wakes.count == 0)
        let pendingAfterExit = rt.livePending()
        #expect(!pendingAfterExit)

        // Instant removal (`tx.instant()`) stops waking immediately
        rt.update { shown, tx in
            tx.instant()
            shown = true
        }
        _ = rt.frame(1.0 / 120.0)
        rt.update { shown, tx in
            tx.instant()
            shown = false
        }
        _ = rt.frame(1.0 / 120.0)
        wakes.count = 0
        px.set(2, 2, [UInt8](repeating: 50, count: 16))
        #expect(wakes.count == 0)
        let pendingAfterInstant = rt.livePending()
        #expect(!pendingAfterInstant)
    }
}
