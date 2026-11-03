// Tests ported from: crates/rune/src/window/covered_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import RuneMotion
import Testing
@testable import Rune

@Suite("WindowCoveredTests")
struct WindowCoveredTests {
    struct Chat {
        var messages: UInt32 = 0
        var read: UInt32 = 0
        var polls: UInt32 = 0
    }

    @Test("a covered window builds nothing until it uncovers")
    func aCoveredWindowBuildsNothingUntilItUncovers() {
        var builds: UInt32 = 0
        let view: (Chat, Cx<Chat>) -> El = { chat, _ in
            builds += 1
            return el().child(text("\(chat.messages) \(chat.read)").key("n"))
        }
        func shownText(_ rt: Runtime<Chat>) -> String? {
            rt.hostElements().first { $0.key == "n" }?.text
        }

        let rt = Runtime<Chat>(Chat(), view, (200.0, 50.0), Env(systemDark: true, scale: 1.0))
        rt.poll = { chat, _, _ in
            chat.polls += 1
            let unread = chat.read < chat.messages
            chat.read = chat.messages
            return unread
        }
        _ = rt.hostFrame(0.0)
        #expect(shownText(rt) == "0 0")

        rt.hostSetLiveVisible(false)
        let baseBuilds = builds
        let basePolls = rt.state.polls
        var clock = HostFrameClock()
        var firstFrame = FirstFrame(deferred: false)

        for k in 1...100 {
            rt.hostUpdate { chat, tx in
                chat.messages += 1
                tx.wakeAfter(0.01)
            }
            coveredStep(rt: rt, clock: &clock, firstFrame: &firstFrame)
            rt.clock = Double(k) * 0.02
            coveredStep(rt: rt, clock: &clock, firstFrame: &firstFrame)
        }

        #expect(rt.state.messages == 100 && rt.state.read == 100)
        #expect(rt.state.polls - basePolls >= 100)
        #expect(rt.hostWakeDeadline() == nil)
        #expect(builds - baseBuilds == 0)
        let isStale = rt.hostStale()
        #expect(isStale)

        rt.hostSetLiveVisible(true)
        rt.hostSettleAll()
        _ = rt.hostFrame(1.0 / 120.0)
        #expect(builds - baseBuilds == 1)
        #expect(shownText(rt) == "100 100")
    }

    @Test("a covered window lands its motion when it uncovers")
    func aCoveredWindowLandsItsMotionWhenItUncovers() {
        let view: (Float, Cx<Float>) -> El = { x, _ in
            row().child(el().w(x)).child(el().key("box").size(10.0, 10.0).motion(Spring.new(0.3, 0.0)))
        }
        func boxX(_ rt: Runtime<Float>) -> Float {
            rt.hostPresented("box")!.rect.x
        }

        let rt = Runtime<Float>(0.0, view, (100.0, 100.0), Env(systemDark: true, scale: 1.0))
        _ = rt.hostFrame(0.0)
        rt.hostUpdate { x, tx in
            x = 80.0
            tx.motion(Spring.new(0.3, 0.0))
        }
        _ = rt.hostFrame(1.0 / 120.0)
        let anim = rt.hostFrame(0.05).2.animating
        let mid = boxX(rt)
        #expect(mid > 0.0 && mid < 80.0 && anim)

        rt.hostSetLiveVisible(false)
        var clock = HostFrameClock()
        var firstFrame = FirstFrame(deferred: false)
        rt.hostUpdate { x, tx in
            x = 40.0
            tx.motion(Spring.new(0.3, 0.0))
        }
        coveredStep(rt: rt, clock: &clock, firstFrame: &firstFrame)
        #expect(boxX(rt) == mid)

        rt.hostSetLiveVisible(true)
        rt.hostSettleAll()
        let finalStats = rt.hostFrame(1.0 / 120.0).2
        #expect(boxX(rt) == 40.0)
        #expect(!finalStats.animating)
    }
}
