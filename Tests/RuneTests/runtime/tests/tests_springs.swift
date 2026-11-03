// Tests ported from: crates/rune/src/runtime/tests/springs.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import RuneMotion
import Testing
@testable import Rune

private func rtSpringsSequence(_ base: El, _ seq: RuneMotion.Sequence) -> El {
    var copy = base
    copy.loopingSpec = .sequence(seq)
    return copy
}

private func rtSpringsMatched(_ base: El, _ id: String) -> El {
    var copy = base
    copy.matchedId = id
    return copy
}

private func rtSpringsTimeScale(_ base: El, _ factor: Float) -> El {
    var copy = base
    copy.timeScaleValue = factor
    return copy
}

private func rtSpringsOpacityMotion(_ base: El, _ anim: Anim) -> El {
    var copy = base
    copy.opacityMotionAnim = anim
    return copy
}

private struct RtSpringsLab {
    var outside: Float
    var inside: Float
    var badge: Bool
    var outer: Float
    var inner: Float

    static func at(_ outer: Float, _ inner: Float) -> RtSpringsLab {
        RtSpringsLab(outside: 1.0, inside: 1.0, badge: true, outer: outer, inner: inner)
    }

    func runtime() -> Runtime<RtSpringsLab> {
        func view(_ s: RtSpringsLab, _: Cx<RtSpringsLab>) -> El {
            func dot(_ key: String, _ o: Float) -> El {
                el().key(key).size(20.0, 20.0).bg(Color.WHITE).opacity(o)
            }
            var inner = rtSpringsTimeScale(col().key("inner"), s.inner).child(dot("inside", s.inside))
            if s.badge {
                inner = inner.child(
                    el().key("badge").size(20.0, 20.0).bg(Color.WHITE).transition(.opacity())
                )
            }
            return col()
                .key("root")
                .size(200.0, 200.0)
                .child(dot("outside", s.outside))
                .child(rtSpringsTimeScale(col().key("outer"), s.outer).child(inner))
        }
        let rt = Runtime.new(self, view, (200.0, 200.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)
        let anim0 = rt.animating
        #expect(!anim0)
        return rt
    }
}

private let rtLabDt: Double = 1.0 / 60.0

private func rtLabSet(_ rt: Runtime<RtSpringsLab>, _ f: (inout RtSpringsLab) -> Void) {
    f(&rt.state)
    rt.dirty = true
}

private func rtLabSteps(_ rt: Runtime<RtSpringsLab>, _ n: Int) {
    for _ in 0..<n {
        _ = rt.frame(rtLabDt)
    }
}

private func rtLabOpacity(_ rt: Runtime<RtSpringsLab>, _ key: String) -> Float? {
    rt.elements().first(where: { $0.key == key })?.opacity
}

@Suite
struct RtSpringsTests {
    @Test
    func sequencesRunWithoutCommitsThenSleepAndSettle() {
        let beats: [Beat] = [
            Beat.new(0.0).opacity(0.0).scale(0.8),
            Beat.new(0.3).easing(.linear),
            Beat.new(0.6).opacity(0.5).scale(1.1).easing(.linear),
            Beat.new(0.9).easing(.linear),
        ]
        func view(_: Void, _: Cx<Void>) -> El {
            el().key("root").size(200.0, 100.0).child(
                rtSpringsSequence(
                    el().key("beat").size(80.0, 40.0),
                    RuneMotion.Sequence.new(beats).delay(0.2)
                )
            )
        }
        func make() -> Runtime<Void> {
            Runtime.new((), view, (200.0, 100.0), Env(systemDark: true, scale: 1.0))
        }
        func pose(_ rt: Runtime<Void>) -> ElementInfo {
            rt.elements().first(where: { $0.key == "beat" })!
        }

        let rt = make()
        _ = rt.frame(0.0)
        let anim0 = rt.animating
        let wake0 = rt.wakeDeadline()
        #expect(!anim0)
        #expect(wake0 == 0.2)

        let commitsBefore = rt.totalCommits
        _ = rt.frame(0.35)
        let anim35 = rt.animating
        let p35 = pose(rt)
        let commitsAfter = rt.totalCommits
        #expect(anim35)
        #expect(abs(p35.opacity - 0.5) < 1e-5)
        #expect(abs(p35.scale - 0.9) < 1e-5)
        #expect(commitsAfter == commitsBefore)

        rt.invalidate()
        _ = rt.frame(0.0)
        let pInvalidated = pose(rt)
        #expect(abs(pInvalidated.opacity - 0.5) < 1e-5)

        _ = rt.frame(1.0)
        let animEnd = rt.animating
        let wakeEnd = rt.wakeDeadline()
        let pEnd = pose(rt)
        #expect(!animEnd)
        #expect(wakeEnd == nil)
        #expect(pEnd.opacity == 1.0)
        #expect(pEnd.scale == 1.0)

        let settled = make()
        _ = settled.frame(0.0)
        settled.settleAll()
        _ = settled.frame(0.0)
        let settledAnim = settled.animating
        let settledWake = settled.wakeDeadline()
        let pSettled = pose(settled)
        #expect(!settledAnim)
        #expect(pSettled.opacity == 1.0)
        #expect(settledWake == nil)

        let reduced = make()
        reduced.setSystemReducedMotion(true)
        _ = reduced.frame(0.0)
        let reducedAnim = reduced.animating
        let reducedWake = reduced.wakeDeadline()
        let pReduced = pose(reduced)
        #expect(!reducedAnim)
        #expect(pReduced.scale == 1.0)
        #expect(pReduced.opacity == 1.0)
        #expect(pReduced.loopPhase == 1.0)
        #expect(reducedWake == nil)
    }

    @Test
    func motionCurveMovesLayoutOnATween() {
        func view(_ h: Float, _: Cx<Float>) -> El {
            col().size(200.0, 300.0).child(el().key("card").w(100.0).h(h))
        }
        func cardH(_ rt: Runtime<Float>) -> Float {
            rt.elements().first(where: { $0.key == "card" })!.rect[3]
        }
        func run(_ set: (inout Tx) -> Void) -> [Float] {
            let rt = Runtime.new(Float(100.0), view, (200.0, 300.0), Env(systemDark: true, scale: 1.0))
            _ = rt.frame(0.0)
            rt.update { x, tx in
                x = 200.0
                set(&tx)
            }
            _ = rt.frame(0.0)
            var hs: [Float] = []
            for _ in 0..<60 {
                _ = rt.frame(1.0 / 120.0)
                hs.append(cardH(rt))
            }
            return hs
        }

        let linear = run { tx in tx.motionCurve(Anim(Curve.linear(0.4))) }
        #expect(abs(linear[23] - 150.0) < 3.0)
        #expect(abs(linear[47] - 200.0) < 0.01)

        let spring = run { tx in tx.motion(Spring.new(0.4, 0.0)) }
        #expect(abs(spring[23] - linear[23]) > 3.0)
        #expect(run { tx in tx.motionCurve(Anim(Spring.new(0.4, 0.0))) } == spring)
        #expect(run { tx in
            tx.motionCurve(Anim(Curve.linear(0.4)))
            tx.motion(Spring.new(0.4, 0.0))
        } == spring)
    }

    @Test
    func layoutMotionDoesNotReplaceExplicitTransitionExit() {
        struct PillState {
            var show: Bool
            var duration: Float
        }
        func view(_ s: PillState, _: Cx<PillState>) -> El {
            var root = col().size(200.0, 100.0)
            if s.show {
                root = root.child(
                    el()
                        .key("pill")
                        .size(100.0, 40.0)
                        .motion(Spring.new(s.duration, 0.0))
                        .transition(
                            Transition.scale(0.96).springs(
                                SpringPair(enter: Spring.new(0.3, 0.0), exit: Spring.new(0.8, 0.0))
                            )
                        )
                )
            }
            return root
        }
        func make(_ duration: Float) -> Runtime<PillState> {
            Runtime.new(PillState(show: true, duration: duration), view, (200.0, 100.0), Env(systemDark: true, scale: 1.0))
        }
        let fast = make(0.05)
        let slow = make(0.6)
        for rt in [fast, slow] {
            _ = rt.frame(0.0)
            rt.state.show = false
            rt.invalidate()
            _ = rt.frame(0.0)
            _ = rt.frame(0.1)
        }
        let fastOp = fast.elements().first(where: { $0.key == "pill" })!.opacity
        let slowOp = slow.elements().first(where: { $0.key == "pill" })!.opacity
        #expect(fastOp > 0.5)
        #expect(abs(fastOp - slowOp) < 1e-6)
    }

    @Test
    func aNodeLeavesWithTheTransitionOfItsLastRender() {
        struct PageState {
            var shown: Bool
            var way: Float
        }
        func view(_ s: PageState, _: Cx<PageState>) -> El {
            var root = col().size(200.0, 100.0)
            if s.shown {
                root = root.child(
                    el().key("page").size(100.0, 40.0).transition(Transition.offset(40.0 * s.way, 0.0))
                )
            }
            return root
        }
        func pageX(_ rt: Runtime<PageState>) -> Float {
            rt.elements().first(where: { $0.key == "page" })!.rect[0]
        }
        func make(_ shown: Bool) -> Runtime<PageState> {
            Runtime.new(PageState(shown: shown, way: -1.0), view, (200.0, 100.0), Env(systemDark: true, scale: 1.0))
        }

        let kept = make(false)
        let turned = make(false)
        for rt in [kept, turned] {
            _ = rt.frame(0.0)
            rt.state.shown = true
            rt.invalidate()
            _ = rt.frame(0.0)
            _ = rt.frame(0.05)
        }
        turned.state.way = 1.0
        turned.invalidate()
        _ = kept.frame(0.05)
        _ = turned.frame(0.05)
        let tx = pageX(turned)
        let kx = pageX(kept)
        #expect(tx < 0.0)
        #expect(abs(kx - tx) < 1e-4)

        let rt = make(true)
        _ = rt.frame(0.0)
        _ = rt.frame(2.0)
        #expect(pageX(rt) == 0.0)
        rt.state.way = 1.0
        rt.invalidate()
        _ = rt.frame(0.0)
        rt.state.shown = false
        rt.invalidate()
        _ = rt.frame(0.0)
        _ = rt.frame(0.1)
        #expect(pageX(rt) > 1.0)
    }

    @Test
    func elementEffectsIncludeAncestorOpacityScaleAndExitBlur() {
        func view(_ show: Bool, _: Cx<Bool>) -> El {
            var root = col().size(200.0, 100.0)
            if show {
                let parent = el()
                    .key("parent")
                    .size(100.0, 60.0)
                    .opacity(0.5)
                    .liveScale(Binding(live: Live.new(0.8)))
                    .transition(Transition.blur(4.0))
                    .child(
                        el()
                            .key("child")
                            .size(20.0, 20.0)
                            .opacity(0.5)
                            .liveScale(Binding(live: Live.new(0.5)))
                    )
                root = root.child(parent)
            }
            return root
        }
        let rt = Runtime.new(true, view, (200.0, 100.0), Env(systemDark: true, scale: 2.0))
        _ = rt.frame(0.0)
        let child0 = rt.elements().first(where: { $0.key == "child" })!
        #expect(abs(child0.opacity - 0.25) < 1e-6)
        #expect(abs(child0.scale - 0.4) < 1e-6)
        #expect(child0.blur == 0.0)

        rt.state = false
        rt.invalidate()
        _ = rt.frame(0.0)
        _ = rt.frame(0.05)
        let elements = rt.elements()
        let parent = elements.first(where: { $0.key == "parent" })!
        let child = elements.first(where: { $0.key == "child" })!
        #expect(parent.blur > 0.0)
        #expect(child.blur == parent.blur)
        #expect(abs(child.opacity - parent.opacity * 0.5) < 1e-6)
    }

    @Test
    func exitingElementsAreFlaggedAndGoneFromKeyLookups() {
        func view(_ show: Bool, _: Cx<Bool>) -> El {
            var root = col().size(200.0, 100.0)
            if show {
                root = root.child(
                    el()
                        .key("card")
                        .size(100.0, 60.0)
                        .transition(Transition.blur(4.0))
                        .child(el().key("label").size(20.0, 20.0))
                )
            }
            return root
        }
        let rt = Runtime.new(true, view, (200.0, 100.0), Env(systemDark: true, scale: 1.0))
        _ = rt.frame(0.0)
        let cardFound = rt.find("card")
        let labelFound = rt.find("label")
        let anyExiting0 = rt.elements().contains(where: { $0.exiting })
        #expect(cardFound != nil && labelFound != nil)
        #expect(!anyExiting0)

        rt.state = false
        rt.invalidate()
        _ = rt.frame(0.0)
        _ = rt.frame(0.05)
        let elements = rt.elements()
        for key in ["card", "label"] {
            let e = elements.first(where: { $0.key == key })
            let found = rt.find(key)
            let pres = rt.presented(key)
            #expect(e != nil)
            if let elInfo = e {
                #expect(elInfo.exiting && elInfo.inert)
            }
            #expect(found == nil)
            #expect(pres != nil)
        }
    }

    @Test
    func aDuplicateMatchedIdMatchesTheLastOneAndWarns() {
        func view(_: Void, _: Cx<Void>) -> El {
            col()
                .child(rtSpringsMatched(el().key("a"), "tile").size(10.0, 10.0))
                .child(rtSpringsMatched(el().key("b"), "tile").size(10.0, 10.0))
        }
        let rt = Runtime.new((), view, (100.0, 100.0), Env.new(true, 1.0))
        rt.keyWarnings = []
        _ = rt.frame(0.0)
        let warnings = rt.keyWarnings ?? []
        #expect(warnings.count == 1)
        if let first = warnings.first {
            #expect(first.contains("duplicate matched id \"tile\""))
        }
        let bId = rt.nodes.first(where: { $0.key == "b" })!.nodeId
        let matchedIds = rt.matched.map { $0.1 }
        #expect(matchedIds == [bId])
    }

    @Test
    func presenceExitsStayDrawnAndReviveMidFlight() {
        func view(_ show: Bool, _: Cx<Bool>) -> El {
            var root = col().key("root").size(200.0, 100.0)
            if show {
                root = root.child(
                    el()
                        .key("badge")
                        .size(80.0, 30.0)
                        .bg(Color.WHITE)
                        .transition(Transition.blurReplace())
                )
            }
            return root
        }

        let rt = Runtime.new(true, view, (200.0, 100.0), Env.new(true, 2.0))
        _ = rt.frame(0.0)
        let anim0 = rt.animating
        let count0 = rt.elements().count
        #expect(!anim0)
        #expect(count0 == 2)

        rt.state = false
        rt.dirty = true
        _ = rt.frame(1.0 / 60.0)
        let anim1 = rt.animating
        let badge = rt.elements().first(where: { $0.key == "badge" })!
        #expect(anim1)
        #expect(badge.opacity > 0.0 && badge.opacity < 1.0)

        let before = badge.opacity
        rt.state = true
        rt.dirty = true
        _ = rt.frame(1.0 / 60.0)
        let after = rt.elements().first(where: { $0.key == "badge" })!.opacity
        #expect(abs(after - before) < 0.15)

        rt.state = false
        rt.dirty = true
        for _ in 0..<120 {
            _ = rt.frame(1.0 / 60.0)
        }
        let animSettled = rt.animating
        let hasBadge = rt.elements().contains(where: { $0.key == "badge" })
        #expect(!animSettled)
        #expect(!hasBadge)
    }

    @Test
    func timeScaleZeroFreezesItsSubtreeWhileTheRestMoves() {
        let rt = RtSpringsLab.at(1.0, 0.0).runtime()
        rtLabSet(rt) { s in
            s.outside = 0.0
            s.inside = 0.0
        }
        rtLabSteps(rt, 12)
        let outside = rtLabOpacity(rt, "outside")!
        let inside = rtLabOpacity(rt, "inside")
        #expect(outside < 0.9)
        #expect(inside == 1.0)
    }

    @Test
    func halfTimeScaleReachesTheSamePointAtTwiceTheTime() {
        let rt = RtSpringsLab.at(1.0, 0.5).runtime()
        rtLabSet(rt) { s in
            s.outside = 0.0
            s.inside = 0.0
        }
        rtLabSteps(rt, 10)
        let reference = rtLabOpacity(rt, "outside")!
        #expect(reference > 0.05 && reference < 0.95)
        rtLabSteps(rt, 10)
        let inside = rtLabOpacity(rt, "inside")!
        #expect(abs(inside - reference) < 1e-4)
    }

    @Test
    func nestedTimeScalesMultiply() {
        let rt = RtSpringsLab.at(0.5, 0.5).runtime()
        rtLabSet(rt) { s in
            s.outside = 0.0
            s.inside = 0.0
        }
        rtLabSteps(rt, 5)
        let reference = rtLabOpacity(rt, "outside")!
        #expect(reference > 0.05 && reference < 0.95)
        rtLabSteps(rt, 15)
        let inside = rtLabOpacity(rt, "inside")!
        #expect(abs(inside - reference) < 1e-4)
    }

    @Test
    func aFrozenSubtreeWithPendingMotionRequestsNoFrames() {
        let rt = RtSpringsLab.at(1.0, 0.0).runtime()
        rtLabSet(rt) { s in s.inside = 0.0 }
        for _ in 0..<5 {
            _ = rt.frame(rtLabDt)
            let anim = rt.animating
            #expect(!anim)
        }
        let activeLen = rt.scene.store().activeLen()
        let wake = rt.wakeDeadline()
        let insideBefore = rtLabOpacity(rt, "inside")
        #expect(activeLen > 0)
        #expect(wake == nil)
        #expect(insideBefore == 1.0)

        rtLabSet(rt) { s in s.inner = 1.0 }
        _ = rt.frame(rtLabDt)
        let resumedAnim = rt.animating
        let insideAfter = rtLabOpacity(rt, "inside")!
        #expect(resumedAnim)
        #expect(insideAfter < 1.0)
    }

    @Test
    func resumingAFrozenSubtreeContinuesFromTheSameValue() {
        let rt = RtSpringsLab.at(1.0, 1.0).runtime()
        rtLabSet(rt) { s in
            s.outside = 0.0
            s.inside = 0.0
        }
        rtLabSteps(rt, 5)
        let held = rtLabOpacity(rt, "inside")!
        #expect(held < 1.0)

        rtLabSet(rt) { s in s.inner = 0.0 }
        rtLabSteps(rt, 5)
        let reference = rtLabOpacity(rt, "outside")!
        rtLabSteps(rt, 5)
        #expect(rtLabOpacity(rt, "inside") == held)

        rtLabSet(rt) { s in s.inner = 1.0 }
        _ = rt.frame(0.0)
        #expect(rtLabOpacity(rt, "inside") == held)
        rtLabSteps(rt, 5)
        let inside = rtLabOpacity(rt, "inside")!
        #expect(abs(inside - reference) < 1e-4)
    }

    @Test
    func anExitInAFrozenSubtreeFinishesAfterResuming() {
        let rt = RtSpringsLab.at(1.0, 0.0).runtime()
        rtLabSet(rt) { s in s.badge = false }
        rtLabSteps(rt, 120)
        let frozenAnim = rt.animating
        let badge = rt.elements().first(where: { $0.key == "badge" })
        #expect(!frozenAnim)
        #expect(badge != nil)
        if let b = badge {
            #expect(b.exiting && b.opacity == 1.0)
        }

        rtLabSet(rt) { s in s.inner = 1.0 }
        rtLabSteps(rt, 3)
        let runningOp = rtLabOpacity(rt, "badge")
        #expect((runningOp ?? 1.0) < 1.0)

        rtLabSteps(rt, 120)
        let endAnim = rt.animating
        let endOp = rtLabOpacity(rt, "badge")
        #expect(!endAnim)
        #expect(endOp == nil)
    }

    @Test
    func aNodeUnmountedAtOnceInAScaledSubtreeDropsItsClock() {
        let rt = RtSpringsLab.at(1.0, 0.5).runtime()
        let badgeId = rt.nodes.first(where: { $0.key == "badge" })!.nodeId
        let tsBefore = rt.scene.store().nodeTimeScale(badgeId)
        #expect(tsBefore == 0.5)

        rtLabSet(rt) { s in s.badge = false }
        rt.settleAll()
        _ = rt.frame(rtLabDt)
        let opAfter = rtLabOpacity(rt, "badge")
        let tsAfter = rt.scene.store().nodeTimeScale(badgeId)
        #expect(opAfter == nil)
        #expect(tsAfter == 1.0)
    }

    @Test
    func anExitingElementDropsItsOwnTimeScale() {
        func view(_ show: Bool, _: Cx<Bool>) -> El {
            var root = col().key("root").size(200.0, 100.0)
            if show {
                let card = rtSpringsTimeScale(
                    el().key("card").size(80.0, 30.0).bg(Color.WHITE).transition(.opacity()),
                    0.0
                )
                root = root.child(card)
            }
            return root
        }
        let rt = Runtime.new(true, view, (200.0, 100.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)
        let anim0 = rt.animating
        #expect(!anim0)

        rt.state = false
        rt.dirty = true
        for _ in 0..<3 {
            _ = rt.frame(rtLabDt)
        }
        let card = rt.elements().first(where: { $0.key == "card" })
        #expect(card != nil)
        if let c = card {
            #expect(c.exiting && c.opacity < 1.0)
        }
        for _ in 0..<120 {
            _ = rt.frame(rtLabDt)
        }
        let remaining = rt.elements().contains(where: { $0.key == "card" })
        #expect(!remaining)
    }

    @Test
    func removingWhatDrawsNothingSkipsItsExit() {
        struct HiddenState {
            var shown: Bool
            var glowOpacity: Float
            var parentHidden: Bool
        }
        func view(_ s: HiddenState, _: Cx<HiddenState>) -> El {
            var group = rtSpringsOpacityMotion(
                col().key("group").size(100.0, 100.0).opacity(s.parentHidden ? 0.0 : 1.0),
                Anim.instant
            )
            if s.shown {
                group = group.child(
                    el().key("dot").size(10.0, 10.0).bg(Color.WHITE).transition(.opacity())
                )
            }
            var root = col().key("root").size(200.0, 200.0).child(group)
            if s.shown {
                root = root.child(
                    el().key("glow").size(50.0, 50.0).bg(Color.WHITE).opacity(s.glowOpacity).transition(.opacity())
                )
            }
            return root
        }
        func hasElement(_ rt: Runtime<HiddenState>, _ k: String) -> Bool {
            rt.elements().contains(where: { $0.key == k })
        }

        let rt = Runtime.new(
            HiddenState(shown: true, glowOpacity: 1.0, parentHidden: false),
            view,
            (200.0, 200.0),
            Env.new(true, 1.0)
        )
        _ = rt.frame(0.0)
        for _ in 0..<60 { _ = rt.frame(1.0 / 60.0) }

        // Visible: both fade out.
        rt.update { s, _ in s.shown = false }
        _ = rt.frame(1.0 / 60.0)
        let dotVis = hasElement(rt, "dot")
        let glowVis = hasElement(rt, "glow")
        #expect(dotVis && glowVis)
        for _ in 0..<60 { _ = rt.frame(1.0 / 60.0) }

        // Faded out already, or under a hidden parent: gone in the frame.
        rt.update { s, _ in s = HiddenState(shown: true, glowOpacity: 0.0, parentHidden: true) }
        for _ in 0..<60 { _ = rt.frame(1.0 / 60.0) }
        rt.update { s, _ in s.shown = false }
        _ = rt.frame(1.0 / 60.0)
        let glowGone = !hasElement(rt, "glow")
        let dotGone = !hasElement(rt, "dot")
        let animHidden = rt.animating
        #expect(glowGone)
        #expect(dotGone)
        #expect(!animHidden)

        // The parent hides at once in the same commit: the dot's exit stops when it draws nothing.
        rt.update { s, _ in s = HiddenState(shown: true, glowOpacity: 1.0, parentHidden: false) }
        for _ in 0..<60 { _ = rt.frame(1.0 / 60.0) }
        rt.update { s, _ in s = HiddenState(shown: false, glowOpacity: 1.0, parentHidden: true) }
        _ = rt.frame(1.0 / 60.0)
        _ = rt.frame(1.0 / 60.0)
        let dotStopped = !hasElement(rt, "dot")
        #expect(dotStopped)
    }
}
