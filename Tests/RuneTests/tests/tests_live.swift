// Tests ported from: crates/rune/tests/live.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if !os(WASI)
import Foundation
#endif
import Testing
@testable import Rune

private final class LiveWakeCounter: @unchecked Sendable {
    private let lock = LiveLock()
    private var value: Int = 0

    func increment() {
        lock.withLock { value += 1 }
    }

    func load() -> Int {
        lock.withLock { value }
    }
}

private struct LiveTestState {
    var opacity: Live<Float>
    var offset: Live<[Float]>
    var scale: Live<Float>
    var fill: Live<Color>
    var bound: Bool
    var smooth: Bool
}

private func makeLiveTestState() -> LiveTestState {
    LiveTestState(
        opacity: Live.new(0.8),
        offset: Live.new([10.0, 20.0]),
        scale: Live.new(1.0),
        fill: Live.new(.WHITE),
        bound: true,
        smooth: false
    )
}

private func liveTestView(_ s: LiveTestState, _: Cx<LiveTestState>) -> El {
    var child = el().key("live").size(40.0, 20.0).fill(.BLACK)
    if s.bound {
        child = child
            .liveOpacity(Binding(live: s.opacity))
            .liveScale(Binding(live: s.scale))
            .liveFill(Binding(live: s.fill))
        if s.smooth {
            child = child.liveOffset(s.offset.smooth(Spring.new(0.25, 0.0)))
        } else {
            child = child.liveOffset(Binding(live: s.offset))
        }
    }
    return el().size(300.0, 300.0).child(child)
}

private func makeLiveRuntime(_ s: LiveTestState) -> Runtime<LiveTestState> {
    Runtime(s, liveTestView, (300.0, 300.0), Env(systemDark: true, scale: 2.0))
}

private struct LiveRectState {
    var rect: Live<[Float]>
    var bound: Bool
}

private func liveRectView(_ s: LiveRectState, _: Cx<LiveRectState>) -> El {
    let box = el().key("box").size(40.0, 20.0).fill(.WHITE)
    return el().size(300.0, 300.0)
        .child(s.bound ? box.liveRect(Binding(live: s.rect)) : box)
        .child(el().key("sibling").size(20.0, 20.0))
}

private func liveCountdownView(_ s: Tween<[Float]>, _: Cx<Tween<[Float]>>) -> El {
    el().key("bar").size(272.0, 4.0).fill(.WHITE).liveRect(Binding(live: s.live))
}

private struct LivePixelsState {
    var pixels: Pixels
    var shown: Bool
}

private func livePixelsView(_ s: LivePixelsState, _: Cx<LivePixelsState>) -> El {
    let root = el().size(8.0, 8.0)
    if s.shown {
        return root.child(el().key("picture").size(4.0, 4.0).pixels(s.pixels))
    }
    return root
}

private func makePixelsRuntime(_ pixels: Pixels, _ shown: Bool) -> (Runtime<LivePixelsState>, LiveWakeCounter) {
    let rt = Runtime(
        LivePixelsState(pixels: pixels, shown: shown),
        livePixelsView,
        (8.0, 8.0),
        Env(systemDark: true, scale: 1.0)
    )
    let wakes = LiveWakeCounter()
    rt.hostSetLiveWaker { wakes.increment() }
    _ = rt.hostFrame(0.0)
    return (rt, wakes)
}

private struct LiveTweenOpacityState {
    var tween: Tween<Float>
    var shown: Bool
}

private func liveTweenOpacityView(_ s: LiveTweenOpacityState, _: Cx<LiveTweenOpacityState>) -> El {
    let root = el().size(100.0, 100.0)
    if s.shown {
        return root.child(el().key("countdown").size(20.0, 20.0).liveOpacity(Binding(live: s.tween.live)))
    }
    return root
}

@Suite("LiveIntegrationTests")
struct LiveIntegrationTests {
    @Test func propertiesChangeWithoutViewLayoutOrShapingAndStopAtRest() throws {
        let rt = makeLiveRuntime(makeLiveTestState())
        _ = rt.hostFrame(0.0)
        let commits = rt.hostCommits()

        rt.state.offset.set([60.0, 80.0])
        rt.state.opacity.set(0.4)
        rt.state.scale.set(1.5)
        rt.state.fill.set(Color(r: 0.2, g: 0.4, b: 0.6, a: 1.0))

        let pendingBefore = rt.hostLivePending()
        #expect(pendingBefore)
        let (_, _, stats) = rt.hostFrame(1.0 / 120.0)
        #expect(!stats.animating)
        let pendingAfter = rt.hostLivePending()
        #expect(!pendingAfter)
        let commitsAfter = rt.hostCommits()
        #expect(commitsAfter == commits)

        let n = try #require(rt.hostElements().first(where: { $0.key == "live" }))
        #expect(n.rect == [50.0, 75.0, 60.0, 30.0])
        #expect(abs(n.opacity - 0.4) < 0.001)
        #expect(abs(n.fill.r - 0.2) < 0.001)

        rt.hostInvalidate()
        _ = rt.hostFrame(0.0)
        let nRebuilt = try #require(rt.hostElements().first(where: { $0.key == "live" }))
        #expect(abs(nRebuilt.fill.r - 0.2) < 0.001)

        let changedSame = rt.state.opacity.set(0.4)
        #expect(!changedSame)
        let pendingSame = rt.hostLivePending()
        #expect(!pendingSame)
    }

    @Test func oneSourceWakesTwoWindowsIndependentlyAndUnbindingStopsWakes() {
        let a = makeLiveRuntime(makeLiveTestState())
        var bState = makeLiveTestState()
        bState.opacity = a.state.opacity
        let b = makeLiveRuntime(bState)
        let count = LiveWakeCounter()

        a.hostSetLiveWaker { count.increment() }
        _ = a.hostFrame(0.0)
        b.hostSetLiveWaker { count.increment() }
        _ = b.hostFrame(0.0)

        a.state.opacity.set(0.2)
        #expect(count.load() == 2)
        _ = a.hostFrame(0.01)
        _ = b.hostFrame(0.01)

        b.hostSetLiveVisible(false)
        a.state.opacity.set(0.3)
        #expect(count.load() == 3)
        _ = a.hostFrame(0.01)

        b.hostSetLiveVisible(true)
        #expect(count.load() == 4)
        _ = b.hostFrame(0.01)

        b.state.bound = false
        b.hostInvalidate()
        _ = b.hostFrame(0.01)

        a.state.opacity.set(0.4)
        #expect(count.load() == 5)
        let bPending = b.hostLivePending()
        #expect(!bPending)
    }

    @Test func smoothingSurvivesRebuildAndRetargetsThenSettles() throws {
        var s = makeLiveTestState()
        s.smooth = true
        let rt = makeLiveRuntime(s)
        let (_, _, s0) = rt.hostFrame(0.0)
        #expect(!s0.animating)

        rt.state.offset.set([160.0, 20.0])
        let (_, _, s1) = rt.hostFrame(0.05)
        #expect(s1.animating)

        let before = try #require(rt.hostElements().first(where: { $0.key == "live" })).rect[0]
        #expect(before > 10.0 && before < 160.0)

        rt.hostInvalidate()
        _ = rt.hostFrame(0.0)
        let afterRebuild = try #require(rt.hostElements().first(where: { $0.key == "live" })).rect[0]
        #expect(afterRebuild == before)

        rt.state.offset.set([80.0, 20.0])
        _ = rt.hostFrame(0.01)
        var lastStats = FrameStats()
        for _ in 0..<240 {
            let (_, _, st) = rt.hostFrame(1.0 / 120.0)
            lastStats = st
        }
        let settledX = try #require(rt.hostElements().first(where: { $0.key == "live" })).rect[0]
        #expect(abs(settledX - 80.0) < 0.01)
        #expect(!lastStats.animating)
    }

    @Test func removingLastBindingConsumesAnAlreadyPendingWake() {
        let rt = makeLiveRuntime(makeLiveTestState())
        _ = rt.hostFrame(0.0)
        rt.state.opacity.set(0.3)
        let pendingBefore = rt.hostLivePending()
        #expect(pendingBefore)

        rt.state.bound = false
        rt.hostInvalidate()
        _ = rt.hostFrame(0.0)
        let pendingAfter = rt.hostLivePending()
        #expect(!pendingAfter)

        rt.state.offset.set([200.0, 200.0])
        let pendingUnbound = rt.hostLivePending()
        #expect(!pendingUnbound)
    }

    @Test func connectingAWakerToAHiddenRuntimeKeepsPublicationsAsleep() {
        let rt = makeLiveRuntime(makeLiveTestState())
        rt.hostSetLiveVisible(false)
        let count = LiveWakeCounter()
        rt.hostSetLiveWaker { count.increment() }
        _ = rt.hostFrame(0.0)

        rt.state.opacity.set(0.2)
        #expect(count.load() == 0)
        let pendingHidden = rt.hostLivePending()
        #expect(!pendingHidden)

        rt.hostSetLiveVisible(true)
        #expect(count.load() == 1)
        _ = rt.hostFrame(0.0)
        let pendingShown = rt.hostLivePending()
        #expect(!pendingShown)
    }

    @Test func liveRectChangesPresentationWithoutReflowAndUnbindingRestoresLayout() throws {
        let rt = Runtime(
            LiveRectState(rect: Live.new([10.0, 20.0, 80.0, 40.0]), bound: true),
            liveRectView,
            (300.0, 300.0),
            Env(systemDark: true, scale: 2.0)
        )
        _ = rt.hostFrame(0.0)
        let box0 = try #require(rt.hostElements().first(where: { $0.key == "box" })).rect
        let sib0 = try #require(rt.hostElements().first(where: { $0.key == "sibling" })).rect
        #expect(box0 == [10.0, 20.0, 80.0, 40.0])
        #expect(sib0[0] == 40.0)

        rt.state.rect.set([20.0, 30.0, 60.0, 50.0])
        _ = rt.hostFrame(0.01)
        let commits = rt.hostCommits()
        #expect(commits == 1)

        rt.hostInvalidate()
        _ = rt.hostFrame(0.0)
        let box1 = try #require(rt.hostElements().first(where: { $0.key == "box" })).rect
        #expect(box1 == [20.0, 30.0, 60.0, 50.0])

        rt.state.bound = false
        rt.hostInvalidate()
        rt.hostSettleAll()
        _ = rt.hostFrame(0.0)
        let box2 = try #require(rt.hostElements().first(where: { $0.key == "box" })).rect
        #expect(box2 == [0.0, 0.0, 40.0, 20.0])
    }

    @Test func linearCountdownUsesRenderTimeWithoutCommitsWakesOrHiddenSamples() throws {
        let makeTween = { Tween.linear([0.0, 0.0, 272.0, 4.0], [0.0, 0.0, 0.0, 4.0], .seconds(30)) }
        let rt = Runtime(makeTween(), liveCountdownView, (300.0, 20.0), Env(systemDark: true, scale: 1.0))
        let wakes = LiveWakeCounter()
        rt.hostSetLiveWaker { wakes.increment() }

        let (_, _, st0) = rt.hostFrame(0.0)
        #expect(st0.animating)
        let w0 = try #require(rt.hostElements().first(where: { $0.key == "bar" })).rect[2]
        #expect(w0 == 272.0)

        for _ in 0..<120 {
            let (_, _, st) = rt.hostFrame(0.1)
            #expect(st.animating)
        }
        let w1 = try #require(rt.hostElements().first(where: { $0.key == "bar" })).rect[2]
        #expect(abs(w1 - 163.2) < 0.05)
        let commits = rt.hostCommits()
        #expect(commits == 1)
        #expect(wakes.load() == 0)
        let deadline = rt.hostWakeDeadline()
        #expect(deadline == nil)

        rt.hostInvalidate()
        _ = rt.hostFrame(0.0)
        let wRebuilt = try #require(rt.hostElements().first(where: { $0.key == "bar" })).rect[2]
        #expect(abs(wRebuilt - 163.2) < 0.05)

        rt.hostSetLiveVisible(false)
        let beforeHidden = try #require(rt.hostElements().first(where: { $0.key == "bar" })).rect[2]
        let (_, _, stHidden) = rt.hostFrame(10.0)
        #expect(!stHidden.animating)
        let whileHidden = try #require(rt.hostElements().first(where: { $0.key == "bar" })).rect[2]
        #expect(whileHidden == beforeHidden)
        let pendingHidden = rt.hostLivePending()
        #expect(!pendingHidden)

        rt.hostSetLiveVisible(true)
        let (_, _, stResumed) = rt.hostFrame(0.0)
        #expect(stResumed.animating)
        let wResumed = try #require(rt.hostElements().first(where: { $0.key == "bar" })).rect[2]
        #expect(abs(wResumed - 272.0 * 8.0 / 30.0) < 0.05)

        let (_, _, stDone) = rt.hostFrame(8.01)
        #expect(!stDone.animating)
        let wDone = try #require(rt.hostElements().first(where: { $0.key == "bar" })).rect[2]
        #expect(wDone == 0.0)
        let pendingDone = rt.hostLivePending()
        #expect(!pendingDone)

        rt.hostUpdate { s, _ in s = makeTween() }
        let (_, _, stRestart) = rt.hostFrame(0.0)
        #expect(stRestart.animating)
        let wRestart = try #require(rt.hostElements().first(where: { $0.key == "bar" })).rect[2]
        #expect(wRestart == 272.0)
        #expect(wakes.load() == 0)
    }

    @Test func pixelsSetWakesOnlyTheRuntimeShowingIt() {
        let pixels = Pixels.new()
        let (shown, shownWakes) = makePixelsRuntime(pixels, true)
        let (other, otherWakes) = makePixelsRuntime(pixels, false)

        #if !os(WASI)
        let done = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            pixels.set(1, 1, [255, 255, 255, 255])
            done.signal()
        }
        done.wait()
        #else
        pixels.set(1, 1, [255, 255, 255, 255])
        #endif

        #expect(shownWakes.load() == 1)
        let shownPending = shown.hostLivePending()
        #expect(shownPending)
        #expect(otherWakes.load() == 0)
        let otherPending = other.hostLivePending()
        #expect(!otherPending)

        _ = shown.hostFrame(0.01)
        _ = other.hostFrame(0.01)
        let shownCleared = shown.hostLivePending()
        #expect(!shownCleared)

        shown.hostSetLiveVisible(false)
        pixels.set(1, 1, [0, 0, 0, 0])
        #expect(shownWakes.load() == 1)
        let (_, _, hiddenStats) = shown.hostFrame(0.01)
        #expect(!hiddenStats.animating)

        shown.hostSetLiveVisible(true)
        #expect(shownWakes.load() == 2)
        _ = shown.hostFrame(0.01)
        let head = Array(shown.images.pages[0].data.prefix(4))
        #expect(head == [0, 0, 0, 0])
    }

    @Test func repeatedPixelSetsCoalesceIntoOneWakeAndOneUpload() {
        let pixels = Pixels.new()
        pixels.set(2, 1, [UInt8](repeating: 1, count: 8))
        let (rt, wakes) = makePixelsRuntime(pixels, true)
        rt.images.pages[0].dirty = nil

        for n in 0..<UInt8(50) {
            pixels.set(2, 1, [UInt8](repeating: n, count: 8))
        }
        #expect(wakes.load() == 1)
        _ = rt.hostFrame(0.01)
        let dirty0 = rt.images.pages[0].dirty
        #expect(dirty0?.0 == 0 && dirty0?.1 == 1)
        let uploaded = Array(rt.images.pages[0].data.prefix(8))
        #expect(uploaded == [UInt8](repeating: 49, count: 8))
        let pending = rt.hostLivePending()
        #expect(!pending)

        rt.images.pages[0].dirty = nil
        _ = rt.hostFrame(0.01)
        let dirty1 = rt.images.pages[0].dirty
        #expect(dirty1 == nil)

        pixels.set(2, 1, [UInt8](repeating: 50, count: 8))
        #expect(wakes.load() == 2)
    }

    @Test func aRemovedPixelsElementOrClosedWindowStopsWaking() {
        let pixels = Pixels.new()
        var rtOpt: Runtime<LivePixelsState>? = nil
        let wakes: LiveWakeCounter
        do {
            let (rt, counter) = makePixelsRuntime(pixels, true)
            rtOpt = rt
            wakes = counter
        }

        if let rt = rtOpt {
            rt.hostUpdate { s, tx in
                s.shown = false
                tx.settle()
            }
            _ = rt.hostFrame(0.0)
            let hasPicture = rt.hostElements().contains(where: { $0.key == "picture" })
            #expect(!hasPicture)

            pixels.set(1, 1, [255, 255, 255, 255])
            #expect(wakes.load() == 0)
            let pending = rt.hostLivePending()
            #expect(!pending)

            rt.hostUpdate { s, _ in s.shown = true }
            _ = rt.hostFrame(0.0)
            pixels.set(1, 1, [0, 0, 0, 0])
            #expect(wakes.load() == 1)
            _ = rt.hostFrame(0.01)
        }

        rtOpt = nil
        pixels.set(1, 1, [9, 9, 9, 9])
        #expect(wakes.load() == 1)
    }

    @Test func tweenHandleKeepsItsStartAcrossUnmountAndRemount() throws {
        let tween = Tween.linear(Float(1.0), Float(0.0), .seconds(10))
        let rt = Runtime(
            LiveTweenOpacityState(tween: tween, shown: true),
            liveTweenOpacityView,
            (100.0, 100.0),
            Env(systemDark: true, scale: 1.0)
        )
        _ = rt.hostFrame(0.0)
        _ = rt.hostFrame(2.0)
        rt.hostUpdate { s, tx in
            s.shown = false
            tx.settle()
        }
        _ = rt.hostFrame(0.0)
        let presentWhileHidden = rt.hostElements().contains(where: { $0.key == "countdown" })
        #expect(!presentWhileHidden)

        _ = rt.hostFrame(3.0)
        rt.hostUpdate { s, tx in
            s.shown = true
            tx.settle()
        }
        _ = rt.hostFrame(0.0)
        let opacity = try #require(rt.hostElements().first(where: { $0.key == "countdown" })).opacity
        #expect(abs(opacity - 0.5) < 0.001)

        let other = Runtime(
            LiveTweenOpacityState(tween: tween, shown: true),
            liveTweenOpacityView,
            (100.0, 100.0),
            Env(systemDark: true, scale: 1.0)
        )
        _ = other.hostFrame(0.0)
        let otherOpacity = try #require(other.hostElements().first(where: { $0.key == "countdown" })).opacity
        #expect(otherOpacity == 1.0)
    }
}
