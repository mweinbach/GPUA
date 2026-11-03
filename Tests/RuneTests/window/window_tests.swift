// Tests ported from: crates/rune/src/window/tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("WindowTests")
struct WindowTests {
    @Test("updates that change nothing ask no window for a frame")
    func updatesThatChangeNothingAskNoWindowForAFrame() {
        let app = App.new(AppSpec<UInt32>("t", (10.0, 10.0), { 0 }, { _, _ in el() }))
        let handle = app.handle()
        let rt = Runtime<UInt32>(0, { _, _ in el() }, (10.0, 10.0), Env())
        _ = rt.hostFrame(0.0)

        for _ in 0..<50 {
            handle.updateIf { _, _ in false }
            let requests = handle.takeAllRequests()
            var updated = false
            for f in requests.updates {
                if rt.hostUpdateIf(f) { updated = true }
            }
            let stale = rt.hostStale()
            #expect(!updated && requests.onlyUpdates() && !stale)
        }

        handle.updateIf { _, _ in false }
        handle.wake()
        #expect(!handle.takeAllRequests().onlyUpdates())
    }

    @Test("a frame that draws the same pixels is the same")
    func aFrameThatDrawsTheSamePixelsIsTheSame() {
        let view: (UInt32, Cx<UInt32>) -> El = { n, _ in
            el().key("root").size(200.0, 100.0).child(
                el().key("box").size(40.0 + Float(n), 40.0).bg(Color(0.3, 0.5, 0.9, 1.0))
            )
        }
        let rt = Runtime<UInt32>(0, view, (200.0, 100.0), Env(systemDark: false, scale: 2.0))
        let (inst0, layers0, stats0) = rt.hostFrame(0.0)
        var presented = WindowPresented()
        presented.record(size: (400, 200), clear: .BLACK, rt: rt, instances: inst0, layers: layers0)

        // Rebuild that draws the same pixels
        rt.hostUpdate { _, _ in }
        let (inst1, layers1, stats1) = rt.hostFrame(0.0)
        let same1 = presented.same(size: (400, 200), clear: .BLACK, rt: rt, instances: inst1, layers: layers1)
        let unchanged1 = presented.unchanged(size: (400, 200), clear: .BLACK, rt: rt, instances: inst1, layers: layers1, stats: stats1)
        #expect(same1)
        #expect(unchanged1)
        _ = stats0

        // Resized surface draws again
        let sameResized = presented.same(size: (402, 200), clear: .BLACK, rt: rt, instances: inst1, layers: layers1)
        #expect(!sameResized)

        // Visual state change draws again
        rt.hostUpdate { n, _ in n = 8 }
        rt.hostSettleAll()
        let (inst2, layers2, _) = rt.hostFrame(0.0)
        let sameChanged = presented.same(size: (400, 200), clear: .BLACK, rt: rt, instances: inst2, layers: layers2)
        #expect(!sameChanged)
    }

    @Test("launch drawables warm three frames or reveal early")
    func launchDrawablesWarmThreeFramesOrRevealEarly() {
        var warm = LaunchDrawables(active: true)
        #expect(warm.isWarming)
        let p1 = warm.presented()
        let p2 = warm.presented()
        let p3 = warm.presented()
        #expect(p1 && p2 && !p3)
        #expect(!warm.isWarming)

        var early = LaunchDrawables(active: true)
        let r1 = early.reveal()
        #expect(r1)
        #expect(!early.isWarming)
        let r2 = early.reveal()
        #expect(!r2)
    }

    @Test("hidden pace renders at once then at most every HIDDEN_REFRESH")
    func hiddenPaceRendersAtOnceThenAtMostEveryRefresh() {
        let t0 = RuneInstant.now()
        var pace = HiddenPace()
        let d0 = pace.takeDue(now: t0, hasPoll: true)
        #expect(d0)
        let d100 = pace.takeDue(now: t0.adding(.milliseconds(100)), hasPoll: true)
        #expect(!d100)
        #expect(pace.deadline(now: t0.adding(.milliseconds(100)), hasPoll: true) == t0.adding(HIDDEN_REFRESH))
        let d499 = pace.takeDue(now: t0.adding(.milliseconds(499)), hasPoll: true)
        #expect(!d499)
        let d500 = pace.takeDue(now: t0.adding(HIDDEN_REFRESH), hasPoll: true)
        #expect(d500)

        pace.reset()
        let dReset = pace.takeDue(now: t0.adding(HIDDEN_REFRESH), hasPoll: true)
        #expect(dReset)
        let dNoPoll = pace.takeDue(now: t0, hasPoll: false)
        #expect(!dNoPoll)
    }

    @Test("missed frames back off up to OCCLUDED_MAX")
    func missedFramesBackOffUpToOccludedMax() {
        var retry: Duration? = nil
        let d1 = nextOccludedRetry(&retry)
        let d2 = nextOccludedRetry(&retry)
        #expect(d1 == OCCLUDED_RETRY)
        #expect(d2 > d1)
        for _ in 0..<10 {
            _ = nextOccludedRetry(&retry)
        }
        #expect(retry == OCCLUDED_MAX)
    }

    @Test("a window's first updates can register shortcuts and menus on a later window")
    func aWindowsFirstUpdatesCanRegisterOnALaterWindow() {
        typealias S = [String]
        let app1 = App.new(AppSpec<S>("first", (10.0, 10.0), { [] }, { _, _ in el() }))
        let app2 = App.new(AppSpec<S>("second", (10.0, 10.0), { [] }, { _, _ in el() }))
        let second = app2.handle()

        app1.handle().update { s, _ in
            let sc = try! Shortcut.parse("ctrl+alt+shift+f18").get()
            let r1 = second.registerShortcut(sc) { _, _ in }
            let r2 = second.setMenu([MenuItem.new("Item", { (_: inout S, _: inout Tx) in })])
            s.append((try? r1.get()) != nil ? "ok" : "err")
            s.append((try? r2.get()) != nil ? "ok" : "err")
        }

        let host1 = app1.buildHost(windowHandle: WindowHandle("first"))
        let host2 = app2.buildHost(windowHandle: WindowHandle("second"))
        let loop = startAll([host1, host2])
        _ = loop.pump()
        let state1 = host1.rt.state
        loop.shutdown()
        #expect(state1 == ["ok", "ok"])
    }

    @Test("drag region policy preserves titled windows and borderless windows")
    func dragRegionPolicyPreservesTitledWindowsAndPanels() {
        for enabled in [false, true] {
            for fullSize in [false, true] {
                var chrome = Chrome.DEFAULT
                chrome.dragRegions = enabled
                chrome.fullSizeContent = fullSize
                var titled = WindowOptions()
                titled.borderless = false
                var borderless = WindowOptions()
                borderless.borderless = true
                #expect(usesDragRegions(chrome, titled) == (enabled || fullSize))
                #expect(usesDragRegions(chrome, borderless) == enabled)
            }
        }
    }
}
