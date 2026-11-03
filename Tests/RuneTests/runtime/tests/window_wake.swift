// Tests ported from: crates/rune/src/runtime/tests/window_wake.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import RuneMotion
import Taffy
import Testing
@testable import Rune

private func rtWindowWakeMatched(_ base: El, _ id: String) -> El {
    var copy = base
    copy.matchedId = id
    return copy
}

private func rtWindowWakeMarginLeft(_ base: El, _ px: Float) -> El {
    var copy = base
    copy.style.margin.left = .length(px)
    return copy
}

@Suite
struct RtWindowWakeTests {
    @Test
    func windowFrameRequestsTakeTheChangeSpring() {
        let rt = Runtime.new((), { _, _ in el() }, (100.0, 100.0), Env.new(true, 1.0))
        func springFor(_ f: (inout Tx) -> Void) -> Spring? {
            rt.update { _, tx in f(&tx) }
            return rt.takeWindowFrame()!.spring
        }

        #expect(springFor { tx in tx.resizeWindow((1.0, 2.0)) } == tok.motion.DEFAULT)
        #expect(springFor { tx in
            tx.motion(tok.motion.SNAP)
            tx.resizeWindow((1.0, 2.0))
        } == tok.motion.SNAP)
        #expect(springFor { tx in
            tx.instant()
            tx.resizeWindow((1.0, 2.0))
        } == nil)
        #expect(springFor { tx in tx.resizeWindowInstant((1.0, 2.0)) } == nil)

        rt.setSystemReducedMotion(true)
        _ = rt.frame(0.0)
        #expect(springFor { tx in tx.resizeWindow((1.0, 2.0)) } == nil)

        rt.update { _, tx in
            tx.resizeWindow((1.0, 2.0))
            tx.centerWindow()
        }
        let req = rt.takeWindowFrame()!
        #expect(req.size?.0 == 1.0)
        #expect(req.size?.1 == 2.0)
        #expect(req.center)
    }

    @Test
    func aWindowResizeStepKeepsSpringsAndFlightsGoing() {
        func view(_ grown: Bool, _: Cx<Bool>) -> El {
            let tile = rtWindowWakeMatched(el().key("tile"), "tile").size(40.0, 40.0).bg(Color.WHITE)
            var left = el().key("left").size(100.0, 60.0)
            var right = rtWindowWakeMarginLeft(el().key("right").size(100.0, 60.0), 150.0)
            if grown {
                right = right.child(tile)
            } else {
                left = left.child(tile)
            }
            return col()
                .key("root")
                .wFull()
                .hFull()
                .child(el().key("box").size(50.0, grown ? 150.0 : 50.0).bg(Color.WHITE))
                .child(left)
                .child(right)
                .child(spacer())
                .child(el().key("bar").wFull().h(20.0).bg(Color.WHITE))
        }
        func runResize(user: Bool) -> Runtime<Bool> {
            let rt = Runtime.new(false, view, (300.0, 400.0), Env.new(true, 1.0))
            _ = rt.frame(0.0)
            rt.update { grown, tx in
                grown = true
                tx.resizeWindow((300.0, 600.0))
            }
            _ = rt.frame(1.0 / 60.0)
            _ = rt.takeWindowFrame()
            if user {
                rt.setViewport((300.0, 450.0), 1.0)
            } else {
                rt.stepViewport((300.0, 450.0), 1.0)
            }
            _ = rt.frame(1.0 / 60.0)
            return rt
        }

        let rt = runResize(user: false)
        let boxH = rt.presented("box")!.0[3]
        let tileMoving = rt.elements().contains(where: { $0.key == "tile" && $0.moving })
        let tileX = rt.presented("tile")!.0[0]
        let barY = rt.presented("bar")!.0[1]
        #expect(boxH > 50.0 && boxH < 150.0)
        #expect(tileMoving)
        #expect(tileX > 0.0 && tileX < 150.0)
        #expect(barY == 430.0)

        let userRt = runResize(user: true)
        let userBoxH = userRt.presented("box")!.0[3]
        #expect(userBoxH == 150.0)
    }

    @Test
    func aWindowThatFitsItsContentRefitsAfterAUserResize() {
        func view(_: Void, _: Cx<Void>) -> El {
            col().key("root").wFull().child(el().size(100.0, 90.0))
        }
        let rt = Runtime.new((), view, (300.0, 400.0), Env.new(true, 1.0))
        rt.fitHeight = true
        let height = rt.contentHeight()
        rt.setViewport((300.0, height), 1.0)
        _ = rt.frame(0.0)
        _ = rt.takeWindowFrame()

        // Mid-move, the window's own frame changes aren't a user's resize.
        rt.setViewport((300.0, height + 40.0), 1.0)
        _ = rt.frame(1.0 / 60.0)
        let midFrame = rt.takeWindowFrame()
        #expect(midFrame == nil)

        rt.windowResting = true
        rt.setViewport((300.0, height + 100.0), 1.0)
        _ = rt.frame(1.0 / 60.0)
        let userFrame = rt.takeWindowFrame()
        #expect(userFrame?.size?.0 == 300.0)
        #expect(userFrame?.size?.1 == height)
    }

    @Test
    func aHiddenWindowThatFitsItsContentLearnsItsHeightBeforeItShows() {
        struct HiddenFitState {
            var count: Int
            var dirtyOnPoll: Bool
        }
        func view(_ s: HiddenFitState, _: Cx<HiddenFitState>) -> El {
            col().key("root").wFull().children((0..<s.count).map { _ in el().size(100.0, 40.0) })
        }
        let rt = Runtime.new(HiddenFitState(count: 1, dirtyOnPoll: false), view, (300.0, 400.0), Env.new(true, 1.0))
        rt.fitHeight = true
        let height = rt.contentHeight()
        rt.setViewport((300.0, height), 1.0)
        _ = rt.frame(0.0)
        _ = rt.takeWindowFrame()
        let unchangedShow = rt.buildForShow()
        #expect(!unchangedShow)

        rt.poll = { s, _, _ in
            guard s.dirtyOnPoll else { return false }
            s.dirtyOnPoll = false
            s.count += 1
            return true
        }
        rt.state.dirtyOnPoll = true
        let commitsBefore = rt.totalCommits
        let polledStale = rt.pollHidden()
        let wfWhileHidden = rt.windowFrame
        let commitsWhileHidden = rt.totalCommits
        #expect(polledStale)
        #expect(wfWhileHidden == nil)
        #expect(commitsWhileHidden == commitsBefore)

        let builtForShow = rt.buildForShow()
        #expect(builtForShow)
        let req = rt.takeWindowFrame()!
        #expect(req.size?.0 == 300.0)
        #expect(req.size?.1 == 80.0)
        #expect(!req.animate)

        rt.setViewport((300.0, 80.0), 1.0)
        _ = rt.frame(0.0)
        let commitsAfterShow = rt.totalCommits
        let wfAfterShow = rt.windowFrame
        #expect(commitsAfterShow == commitsBefore + 1)
        #expect(wfAfterShow == nil)
    }

    @Test
    func timedWakesAreExactCoalescedAndDoNotCommitOrAnimate() {
        func view(_: [Double], _ cx: Cx<[Double]>) -> El {
            cx.timeScale(0.1)
            return el()
        }
        let rt = Runtime.new([Double](), view, (100.0, 100.0), Env.new(true, 1.0))
        rt.poll = { seen, clock, tx in
            seen.append(clock)
            if clock == 0.0 {
                tx.wakeAfter(0.25)
                tx.wakeAfter(0.25)
                tx.wakeAfter(0.375)
            }
            return false
        }
        _ = rt.frame(0.0)
        let anim0 = rt.animating
        let deadlines0 = rt.timerWakes.deadlines
        #expect(!anim0)
        #expect(deadlines0 == [0.25, 0.375])

        _ = rt.frame(0.5)
        let anim5 = rt.animating
        let seen = rt.state
        let commits = rt.totalCommits
        let wakeEnd = rt.wakeDeadline()
        let tNow = rt.t
        #expect(!anim5)
        #expect(seen == [0.0, 0.25, 0.375, 0.5])
        #expect(commits == 1)
        #expect(wakeEnd == nil)
        #expect(abs(tNow - 0.05) < 1e-8)
    }

    @Test
    func wakesAPollKeepsAskingForCollapseToOnePollAFrame() {
        struct PollArmState {
            var pollsThisFrame: Int
            var delay: Double
        }
        for delay in [0.0, 1.0 / 60.0, 1.0 / 120.0, 0.505, 0.5] {
            let rt = Runtime.new(
                PollArmState(pollsThisFrame: 0, delay: delay),
                { _, _ in el() },
                (100.0, 100.0),
                Env.new(true, 1.0)
            )
            rt.poll = { s, _, tx in
                s.pollsThisFrame += 1
                tx.wakeAfter(s.delay)
                return false
            }
            for _ in 0..<1000 {
                rt.state.pollsThisFrame = 0
                _ = rt.frame(1.0 / 60.0)
                let polls = rt.state.pollsThisFrame
                #expect(polls == 1)
            }
            let pendingCount = rt.timerWakes.deadlines.count
            #expect(pendingCount <= 32)
        }
    }

    @Test
    func aZeroWakeDoesNotHideALaterWakeInACoarseFrame() {
        let rt = Runtime.new([Double](), { _, _ in el() }, (100.0, 100.0), Env.new(true, 1.0))
        rt.poll = { s, now, tx in
            s.append((now * 1000.0).rounded() / 1000.0)
            if s.count == 1 {
                tx.wakeAfter(0.0)
                tx.wakeAfter(0.05)
            }
            return false
        }
        _ = rt.frame(0.0)
        _ = rt.frame(0.1)
        let seen = rt.state
        #expect(seen == [0.0, 0.017, 0.05, 0.1])
    }

    @Test
    func timedWakesFromHandlersSurviveTransactionMerging() {
        func view(_: Void, _: Cx<Void>) -> El {
            el().key("button").size(100.0, 100.0).onPress { (_: inout Void, tx: inout Tx) in
                tx.wakeAfter(0.25)
            }
        }
        let rt = Runtime.new((), view, (100.0, 100.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)
        _ = rt.pointerDown(10.0, 10.0)
        rt.pointerUp(10.0, 10.0)
        _ = rt.frame(0.1)
        let wake1 = rt.wakeDeadline()
        #expect(wake1 != nil)
        if let w1 = wake1 {
            #expect(abs(w1 - 0.35) < 1e-9)
        }
        _ = rt.frame(0.25)
        let wake2 = rt.wakeDeadline()
        #expect(wake2 == nil)
    }

    @Test
    func aTitlebarInsetChangeRebuildsTheView() {
        func view(_: Void, _ cx: Cx<Void>) -> El {
            row().size(300.0, 40.0)
                .child(el().key("leading").w(cx.titlebarInset()))
                .child(el().key("title").size(50.0, 20.0))
        }
        let rt = Runtime.new((), view, (300.0, 40.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)
        let x0 = rt.presented("title")!.0[0]
        #expect(x0 == 0.0)

        rt.setTitlebarInset(Chrome.DEFAULT.titlebarInset())
        _ = rt.frame(0.1)
        _ = rt.frame(5.0)
        let xLights = rt.presented("title")!.0[0]
        #expect(xLights == 67.0)

        rt.setTitlebarInset(0.0)
        _ = rt.frame(5.1)
        _ = rt.frame(10.0)
        let xFull = rt.presented("title")!.0[0]
        #expect(xFull == 0.0)

        let titled = Chrome(fullSizeContent: false)
        #expect(titled.titlebarInset() == 0.0)
    }

    @Test
    func aNewSystemAccentRebuildsTheViewAndItsMemos() {
        func view(_: Void, _ cx: Cx<Void>) -> El {
            let accent = cx.accent()
            let focus = cx.focusColor()
            return row().size(300.0, 40.0)
                .child(el().key("accent").size(accent.g * 100.0, 10.0))
                .child(memo("ring", 0) { el().key("ring").size(focus.a * 100.0, 10.0) })
        }
        func widthOf(_ rt: Runtime<Void>, _ key: String) -> Float {
            (rt.presented(key)!.0[2] * 10.0).rounded() / 10.0
        }
        let rt = Runtime.new((), view, (300.0, 40.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)
        let wAccent0 = widthOf(rt, "accent")
        let wRing0 = widthOf(rt, "ring")
        #expect(wAccent0 == 23.1)
        #expect(wRing0 == 50.0)

        let pink = Color(1.0, 0.2, 0.6, 1.0)
        rt.setSystemAccent(SystemAccent.new(pink, pink).withFocus(pink, pink.alpha(0.7)))
        _ = rt.frame(0.1)
        _ = rt.frame(5.0)
        let wAccent1 = widthOf(rt, "accent")
        let wRing1 = widthOf(rt, "ring")
        #expect(wAccent1 == 20.0)
        #expect(wRing1 == 70.0)
    }
}
