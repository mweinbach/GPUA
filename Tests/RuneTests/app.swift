// Tests ported from: crates/rune/src/app.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Foundation
import Testing
@testable import Rune

@Suite("AppTests")
struct AppTests {
    private static func spec() -> AppSpec<UInt32> {
        AppSpec("test", (100.0, 100.0), { 0 }, { _, _ in el() })
    }

    @Test("a named web canvas sits inline unless it covers the viewport")
    func aNamedWebCanvasSitsInlineUnlessItCoversTheViewport() {
        #expect(!App.new(Self.spec()).webInline())
        #expect(!App.new(Self.spec()).fullViewport().webInline())
        #expect(App.new(Self.spec()).canvasId("view").webInline())
        #expect(App.new(Self.spec()).canvasId("view").fitContentHeight().webInline())
        #expect(!App.new(Self.spec()).canvasId("route").fullViewport().webInline())
        #expect(App.new(Self.spec()).canvasId("view").fullViewport().fitContentHeight().webInline())
    }

    @Test("window panel placement and pixel position are last request wins")
    func windowPanelPlacementAndPixelPositionAreLastRequestWins() {
        let app = App.new(Self.spec())
        let handle = app.handle()
        handle.setPosition((10, 20))
        handle.place(.primary, .fullScreen)
        let q1 = handle.takeAllRequests()
        #expect(q1.position == nil)
        #expect(q1.place?.placement == .fullScreen)

        handle.place(.primary, .fullScreen)
        handle.setPosition((-10, 20))
        let q2 = handle.takeAllRequests()
        #expect(q2.place == nil)
        #expect(q2.position?.0 == -10 && q2.position?.1 == 20)
    }

    @Test("handles report the window the host publishes")
    func handlesReportTheWindowTheHostPublishes() {
        let app = App.new(Self.spec())
        let handle = app.handle()
        #expect(!handle.isVisible() && handle.windowError() == nil)
        handle.setVisibleSnapshot(true)
        handle.setWindowError("no GPU adapter")
        #expect(handle.isVisible())
        #expect(handle.windowError() == "no GPU adapter")
    }

    @Test("handles cross threads whatever the state")
    func handlesCrossThreadsWhateverTheState() {
        final class NonSendablePayload {
            var count = 0
        }
        func requireSendable<T: Sendable>(_: T.Type) {}
        requireSendable(AppHandle<NonSendablePayload>.self)
    }

    @Test("init closures replace the spec init and scenes apply on top")
    func initClosuresReplaceTheSpecInitAndScenesApplyOnTop() {
        var s = Self.spec()
        s.scenes = [("big", { n in n += 100 })]
        let captured: UInt32 = 7
        let (_, state, _) = App.new(s).`init`({ captured }).intoParts(scene: "big")
        #expect(state == 107)
        let (_, stateDefault, _) = App.new(Self.spec()).intoParts(scene: nil)
        #expect(stateDefault == 0)
    }

    @Test("handle requests queue before the loop and wake it after")
    func handleRequestsQueueBeforeTheLoopAndWakeItAfter() async {
        let app = App.new(Self.spec()).windowless()
        #expect(!app.openOnStart && app.keepRunningFlag)
        let handle = app.handle()

        await Task.detached {
            handle.update { n, _ in n += 1 }
            handle.activate("token")
        }.value

        handle.update { n, _ in n *= 10 }
        handle.close()

        let wakeBox = LiveLock()
        nonisolated(unsafe) var wakes = 0
        handle.connect {
            wakeBox.withLock { wakes += 1 }
        }
        #expect(wakeBox.withLock { wakes } == 1)

        let requests = handle.takeAllRequests()
        #expect(requests.window == .close)
        #expect(!requests.quit)
        var n: UInt32 = 0
        var tx = Tx()
        for f in requests.updates {
            _ = f(&n, &tx)
        }
        #expect(n == 10)

        handle.activate("")
        #expect(wakeBox.withLock { wakes } == 2)
        #expect(handle.takeAllRequests().window == .open(nil))
    }

    @Test("a window an update opens applies in the same drain")
    func aWindowAnUpdateOpensAppliesInTheSameDrain() {
        let app = App.new(Self.spec()).windowless()
        let handle = app.handle()
        handle.update { n, _ in
            n += 1
            handle.open()
            handle.update { m, _ in m += 10 }
        }
        var n: UInt32 = 0
        let requests = handle.drainRequests { f in
            var tx = Tx()
            _ = f(&n, &tx)
        }
        #expect(n == 1)
        #expect(requests.window == .open(nil))
        let next = handle.takeAllRequests()
        #expect(next.updates.count == 1)
        #expect(next.window == nil)
    }

    @Test("tray requests keep show focus and geometry together")
    func trayRequestsKeepShowFocusAndGeometryTogether() async {
        let app = App.new(Self.spec()).windowless()
        let handle = app.handle()
        await Task.detached {
            handle.setPosition((10, 20))
            handle.hide()
            handle.setPosition((-300, 40))
            handle.show()
            handle.focus()
        }.value
        let requests = handle.takeAllRequests()
        #expect(requests.window == .show)
        #expect(requests.focus)
        #expect(requests.position?.0 == -300 && requests.position?.1 == 40)
        let drained = handle.takeAllRequests()
        #expect(!drained.focus && drained.window == nil && drained.position == nil)
    }

    @Test("updates commit on the next frame and carry shell requests")
    func updatesCommitOnTheNextFrameAndCarryShellRequests() {
        let rt = Runtime<UInt32>(
            0,
            { n, _ in row().child(el().key("box").size(10.0 + Float(n), 10.0)) },
            (200.0, 200.0),
            Env(systemDark: true, scale: 1.0)
        )
        _ = rt.hostFrame(0.0)
        rt.hostUpdate { n, tx in
            n = 30
            tx.instant()
        }
        #expect(hostAttachment(for: rt).shellRequest == nil)
        _ = rt.hostFrame(1.0 / 120.0)
        let box = rt.hostElements().first { $0.key == "box" }
        #expect(box?.rect[2] == 40.0)

        rt.hostUpdate { _, tx in tx.closeWindow() }
        rt.hostUpdate { _, tx in tx.quit() }
        rt.hostUpdate { _, tx in tx.closeWindow() }
        #expect(hostAttachment(for: rt).shellRequest == .quit)
    }

    @Test("minimize reaches the shell from handlers updates and handles")
    func minimizeReachesTheShellFromHandlersUpdatesAndHandles() {
        let rt = Runtime<UInt32>(0, { _, _ in el() }, (100.0, 100.0), Env())
        rt.hostUpdate { _, tx in tx.minimize() }
        #expect(hostAttachment(for: rt).minimizeRequest)

        let app = App.new(Self.spec())
        app.handle().minimize()
        let requests = app.handle().takeAllRequests()
        #expect(requests.minimize && requests.window == nil)
    }

    @Test("a handles minimize and focus are last wins and hide close or open cancel it")
    func aHandlesMinimizeAndFocusAreLastWinsAndHideCloseOrOpenCancelIt() {
        let app = App.new(Self.spec())
        let h = app.handle()
        func after(_ calls: () -> Void) -> (AppWindowRequest?, Bool, Bool) {
            calls()
            let r = h.takeAllRequests()
            return (r.window, r.focus, r.minimize)
        }
        let r1 = after { h.focus(); h.minimize() }
        #expect(r1.0 == nil && r1.1 == false && r1.2 == true)
        let r2 = after { h.minimize(); h.focus() }
        #expect(r2.0 == nil && r2.1 == true && r2.2 == false)
        let r3 = after { h.show(); h.minimize() }
        #expect(r3.0 == .show && r3.1 == false && r3.2 == true)
        let r4 = after { h.minimize(); h.show() }
        #expect(r4.0 == .show && r4.1 == false && r4.2 == true)
        let r5 = after { h.minimize(); h.hide() }
        #expect(r5.0 == .hide && r5.1 == false && r5.2 == false)
        let r6 = after { h.minimize(); h.close() }
        #expect(r6.0 == .close && r6.1 == false && r6.2 == false)
        let r7 = after { h.minimize(); h.open() }
        #expect(r7.0 == .open(nil) && r7.1 == false && r7.2 == false)
    }

    @Test("updates that change nothing build nothing")
    func updatesThatChangeNothingBuildNothing() {
        var builds: UInt32 = 0
        let view: (UInt32, Cx<UInt32>) -> El = { n, _ in
            builds += 1
            return row().child(el().key("box").size(10.0 + Float(n), 10.0))
        }
        let app = App.new(AppSpec("t", (100.0, 100.0), { 0 }, view))
        let handle = app.handle()
        let rt = Runtime<UInt32>(0, view, (100.0, 100.0), Env())
        _ = rt.hostFrame(0.0)
        let baseBuilds = builds

        func drain() -> Bool {
            var updated = false
            for f in handle.takeAllRequests().updates {
                if rt.hostUpdateIf(f) { updated = true }
            }
            return updated
        }

        for _ in 0..<50 {
            handle.updateIf { _, _ in false }
            #expect(!drain())
            let stale = rt.hostStale()
            #expect(!stale)
            _ = rt.hostFrame(1.0 / 120.0)
        }
        #expect(builds - baseBuilds == 0)

        handle.updateIf { _, _ in false }
        handle.updateIf { n, tx in n = 5; tx.instant(); return true }
        handle.updateIf { _, _ in false }
        #expect(drain())
        _ = rt.hostFrame(1.0 / 120.0)
        _ = rt.hostFrame(1.0 / 120.0)
        #expect(builds - baseBuilds == 1)
        #expect(rt.hostElements().first { $0.key == "box" }?.rect[2] == 15.0)
    }

    @Test("a hidden window drains its inbox on wake and shows it when reopened")
    func aHiddenWindowDrainsItsInboxOnWakeAndShowsItWhenReopened() {
        struct LockState {
            var inbox: [UInt32] = []
            var locked: UInt32 = 0
        }
        let rt = Runtime<LockState>(
            LockState(),
            { s, _ in row().child(el().key("box").size(10.0 + Float(s.locked), 10.0)) },
            (200.0, 200.0),
            Env(systemDark: true, scale: 1.0)
        )
        rt.poll = { s, _, tx in
            guard let last = s.inbox.last else { return false }
            s.inbox.removeAll()
            s.locked = last
            tx.wakeAfter(60.0)
            return true
        }
        _ = rt.hostFrame(0.0)
        #expect(rt.hostElements().first { $0.key == "box" }?.rect[2] == 10.0)

        rt.state.inbox.append(30)
        #expect(rt.hostPollHidden())
        #expect(!rt.hostPollHidden())
        #expect(rt.state.locked == 30)
        #expect(rt.hostElements().first { $0.key == "box" }?.rect[2] == 10.0)
        #expect(rt.hostWakeDeadline() != nil)

        rt.hostSettleAll()
        _ = rt.hostFrame(1.0 / 60.0)
        #expect(rt.hostElements().first { $0.key == "box" }?.rect[2] == 40.0)
    }
}
