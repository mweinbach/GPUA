// Tests ported from: crates/rune/src/playground_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if !os(WASI)
import Foundation
#endif
import Testing
@testable import Rune

final class PgTestInbox: @unchecked Sendable {
    #if !os(WASI)
    private let lock = NSLock()
    #endif
    private var items: [UInt32] = []

    init() {}

    func push(_ value: UInt32) {
        #if !os(WASI)
        lock.lock()
        defer { lock.unlock() }
        #endif
        items.append(value)
    }

    func drain() -> [UInt32] {
        #if !os(WASI)
        lock.lock()
        defer { lock.unlock() }
        #endif
        let out = items
        items.removeAll()
        return out
    }
}

struct PgTestReal {
    var count: UInt32 = 0
    var polls: UInt32 = 0
    var holdsEscape: Bool = false
    var field: TextEdit = TextEdit()
    var pastes: [String] = []
    var drops: Int = 0
    var focus: [Bool] = []
    var waker: Waker? = nil
    var inbox: PgTestInbox? = nil
    var typing: Bool = false
    var typed: String = ""
}

func pgTestView(_ s: PgTestReal, _: Cx<PgTestReal>) -> El {
    col().wFull().hFull()
        .pgOnPaste { (s: inout PgTestReal, pasted: String, _: inout Tx) in
            s.pastes.append(pasted)
        }
        .pgOnDropFiles { (s: inout PgTestReal, files: [String], _: inout Tx) in
            s.drops += files.count
        }
        .pgOnWindowFocus { (s: inout PgTestReal, focused: Bool, _: inout Tx) in
            s.focus.append(focused)
        }
        .child(text("count \(s.count)").key("count"))
        .child(el().key("inc").size(40.0, 20.0).onPress { (s: inout PgTestReal, _: inout Tx) in
            s.count += 1
        })
        .child(
            textInput(s.field, TextStyle(size: 14.0, weight: 400.0))
                .key("field")
                .size(200.0, 24.0)
                .pgOnEdit(EditAccess(\PgTestReal.field))
        )
}

func pgTestScenes() -> [(String, (inout PgTestReal) -> Void)] {
    [
        ("big", { s in s.count = 100 }),
        ("holding", { s in s.holdsEscape = true }),
        ("Motion/Still", { _ in }),
    ]
}

struct PgTestLab {
    var ticks: UInt32 = 0
    var presses: UInt32 = 0
}

func pgTestLabView(_ p: PgTestLab, _: Cx<PgTestLab>) -> El {
    col().wFull().hFull()
        .child(text("ticks \(p.ticks) presses \(p.presses)").key("lab"))
        .child(el().key("bump").size(40.0, 20.0).onPress { (p: inout PgTestLab, _: inout Tx) in
            p.presses += 1
        })
}

func pgTestLabPoll(_ p: inout PgTestLab, _ t: Double, _ tx: inout Tx) -> Bool {
    tx.wakeAfter(1.0)
    let due = UInt32(max(0.0, t.rounded(.down)))
    let changed = due != p.ticks
    p.ticks = due
    return changed
}

func pgTestActivity(_ s: PgTestReal, _: Cx<PgTestReal>) -> El {
    text("live \(s.count)").key("activity")
}

struct PgTestFade {
    var t0: Double = 0.0
    var log: [(String, Double)] = []
}

func pgTestFadeView(_ p: PgTestFade, _: Cx<PgTestFade>) -> El {
    let formatted = "[" + p.log.map { "\"\($0.0)\"" }.joined(separator: ", ") + "]"
    return text(formatted).key("fade")
}

func pgTestFadeStory() -> Story<PgTestFade> {
    Story<PgTestFade>.new("Motion/Fade", { PgTestFade() }, pgTestFadeView)
        .trigger("r", "Fade in") { p, play in
            p.t0 = play.now()
            p.log.append(("start", 0.0))
            play.after(0.5) { p, play in
                p.log.append(("half", play.now() - p.t0))
                play.after(0.25) { p, play in
                    p.log.append(("end", play.now() - p.t0))
                }
            }
        }
        .trigger("f", "Finish") { p, _ in
            p.log.append(("finish", 0.0))
        }
}

func pgBase() -> Playground<PgTestReal> {
    Playground<PgTestReal>.new()
        .enabled(true)
        .page("Live/Activity", pgTestActivity)
        .story(Story<PgTestLab>.new("Lab", { PgTestLab() }, pgTestLabView).poll(pgTestLabPoll))
        .story(pgTestFadeStory())
        .trigger("big", "d", "Double") { s, _ in
            s.count *= 2
        }
}

let PG_DT: Double = 1.0 / 60.0

func pgRuntimeIn(_ open: String??, windowed: Bool) -> Runtime<PgTestReal> {
    pgRuntimeWith(pgBase(), open, windowed: windowed)
}

func pgRuntimeWith(_ playground: Playground<PgTestReal>, _ open: String??, windowed: Bool) -> Runtime<PgTestReal> {
    var spec = AppSpec<PgTestReal>("playground", (800.0, 500.0), { PgTestReal() }, pgTestView)
    spec.scenes = pgTestScenes()
    spec.poll = { s, _, _ in
        s.polls += 1
        return false
    }
    spec.onKey = { s, ev, _ in
        if case .text(let t) = ev.key, s.typing {
            s.typed.append(t)
            return true
        }
        return s.holdsEscape && ev.key == .escape
    }
    var rt = toolingRuntimeFor(spec: spec, state: spec.`init`(), size: spec.size, env: Env.new(false, 1.0), waker: {})
    playgroundAttachHeadless(
        rt: &rt,
        playground: playground,
        spec: spec,
        cliPlayground: open,
        cliVariant: nil,
        windowed: windowed
    )
    _ = rt.frame(0.0)
    return rt
}

func pgRuntime(_ open: String??) -> Runtime<PgTestReal> {
    pgRuntimeIn(open, windowed: true)
}

func pgPressWith(_ rt: Runtime<PgTestReal>, _ key: Key, _ mods: Mods) {
    _ = rt.hostKey(KeyEvent(key: key, mods: mods))
    _ = rt.frame(PG_DT)
}

func pgPress(_ rt: Runtime<PgTestReal>, _ key: Key) {
    pgPressWith(rt, key, Mods())
}

func pgLetter(_ rt: Runtime<PgTestReal>, _ c: String) {
    pgPress(rt, .text(c))
}

func pgSelected(_ rt: Runtime<PgTestReal>) -> Int {
    rt.hostPlayground()?.selected ?? Int.max
}

func pgHeader(_ rt: Runtime<PgTestReal>) -> String? {
    rt.hostPlayground()?.header
}

func pgFocused(_ rt: Runtime<PgTestReal>) -> String? {
    rt.hostElements().first(where: { $0.focused })?.key
}

func pgFind(_ rt: Runtime<PgTestReal>, _ key: String) -> ElementInfo? {
    rt.hostElements().first(where: { $0.key == key && !$0.exiting })
}

func pgShows(_ rt: Runtime<PgTestReal>, _ key: String) -> String {
    guard let txt = pgFind(rt, key)?.text else {
        preconditionFailure("no \(key)")
    }
    return txt
}

func pgTap(_ rt: Runtime<PgTestReal>, _ key: String) {
    guard let r = pgFind(rt, key)?.rect, r.count >= 4 else {
        preconditionFailure("no \(key)")
    }
    let x = r[0] + r[2] * 0.5
    let y = r[1] + r[3] * 0.5
    _ = rt.hostPointerDown(x, y)
    _ = rt.hostPointerUp(x, y)
    _ = rt.frame(PG_DT)
}

func pgEscape(_ rt: Runtime<PgTestReal>) {
    _ = rt.hostKey(KeyEvent(key: .escape, mods: Mods()))
    _ = rt.frame(PG_DT)
}

func pgRegion(_ rt: Runtime<PgTestReal>) -> PlaygroundRegion {
    rt.hostPlayground()?.region() ?? .list
}

func pgIsOpen(_ rt: Runtime<PgTestReal>) -> Bool {
    rt.hostPlayground()?.isOpen() ?? false
}

func pgCenter(_ rt: Runtime<PgTestReal>, _ key: String) -> (Float, Float) {
    guard let r = pgFind(rt, key)?.rect, r.count >= 4 else {
        preconditionFailure("no \(key)")
    }
    return (r[0] + r[2] * 0.5, r[1] + r[3] * 0.5)
}

func pgOwnState<P>(_ rt: Runtime<PgTestReal>, as _: P.Type = P.self) -> P {
    guard let typed = rt.playgroundState(P.self) else {
        preconditionFailure("expected story with own state \(P.self)")
    }
    return typed
}

func pgSceneState(_ rt: Runtime<PgTestReal>) -> PgTestReal {
    guard let scene = rt.hostPlayground()?.scene else {
        preconditionFailure("expected scene stage")
    }
    return scene.state
}

private struct PgTestTip {
    var hidden: Bool = false
}

private func pgTestTipView(_ p: PgTestTip, _: Cx<PgTestTip>) -> El {
    let tipItems: [El] = p.hidden
        ? []
        : [
            el()
                .key("tip")
                .size(120.0, 120.0)
                .transition(Transition.opacity())
                .pgOnHoverChange { (_: inout PgTestTip, _: Bool, _: inout Tx) in }
        ]
    return col().wFull().hFull().children(tipItems)
}

private struct PgTestTray {
    var hovering: Bool = false
}

private func pgTestTrayView(_: PgTestTray, _: Cx<PgTestTray>) -> El {
    el()
        .key("tray")
        .wFull()
        .hFull()
        .pgOnDropFiles { (_: inout PgTestTray, _: [String], _: inout Tx) in }
        .pgOnDropHover { (p: inout PgTestTray, on: Bool, _: inout Tx) in p.hovering = on }
}

private func pgTestSlowView(_: PgTestLab, _ cx: Cx<PgTestLab>) -> El {
    cx.timeScale(0.25)
    return text("slow").key("slow")
}

private struct PgTestKnob {
    var value: Int32 = 0
}

private func pgTestKnobView(_ k: PgTestKnob, _: Cx<PgTestKnob>) -> El {
    col().wFull().hFull()
        .child(text("value \(k.value)").key("value"))
        .child(el().key("knob").size(60.0, 20.0).pgOnStep { (k: inout PgTestKnob, by: Int32, _: inout Tx) in
            k.value += by
        })
}

@Suite("PlaygroundTests")
struct PlaygroundTests {
    @Test func theBarShortensTheAppAndOpensThePlayground() {
        let rt = pgRuntime(nil)
        let barInfo = pgFind(rt, "playground-open")
        #expect(barInfo != nil)
        let barY = barInfo!.rect[1]
        #expect(barY >= 500.0 - PLAYGROUND_BAR)
        pgTap(rt, "inc")
        let countAfterInc = rt.state.count
        #expect(countAfterInc == 1)
        pgTap(rt, "playground-open")
        let openNow = pgIsOpen(rt)
        let shown = pgShows(rt, "count")
        #expect(openNow)
        #expect(shown == "count 100")
    }

    @Test func aSceneGetsAFreshStateAndBackRestoresTheRealOne() {
        let rt = pgRuntime(nil)
        pgTap(rt, "inc")
        rt.update { _, tx in tx.openPlayground() }
        _ = rt.frame(PG_DT)
        pgTap(rt, "inc")
        #expect(pgShows(rt, "count") == "count 101")
        pgTap(rt, "playground-trigger-d")
        _ = rt.frame(PG_DT)
        #expect(pgShows(rt, "count") == "count 202")
        let realCount = rt.state.count
        #expect(realCount == 1)
        pgTap(rt, "playground-back")
        #expect(!pgIsOpen(rt))
        #expect(pgShows(rt, "count") == "count 1")
        #expect(pgFind(rt, "playground-trigger-d") == nil)
    }

    @Test func theStageTakesEscapeFirst() {
        let rt = pgRuntime(.some("holding"))
        #expect(pgIsOpen(rt))
        pgEscape(rt)
        #expect(pgIsOpen(rt))
        pgTap(rt, "playground-item-0")
        pgTap(rt, "field")
        #expect(pgFocused(rt) == "field")
        pgEscape(rt)
        #expect(pgIsOpen(rt))
        pgEscape(rt)
        #expect(pgIsOpen(rt) && pgRegion(rt) == .list)
        pgEscape(rt)
        #expect(!pgIsOpen(rt))
        let realHolds = rt.state.holdsEscape
        #expect(!realHolds)
    }

    @Test func aPageKeepsItsOwnStateAndTimerWhileOpen() {
        let rt = pgRuntime(.some("lab"))
        pgTap(rt, "bump")
        pgTap(rt, "bump")
        for _ in 0..<70 { _ = rt.frame(PG_DT) }
        #expect(pgShows(rt, "lab") == "ticks 1 presses 2")
        pgTap(rt, "playground-item-0")
        pgTap(rt, "playground-item-4")
        #expect(pgShows(rt, "lab") == "ticks 1 presses 2")
        pgTap(rt, "playground-trigger-r")
        let wakeDeadline = rt.hostWakeDeadline()
        let nowClock = rt.clock
        #expect(wakeDeadline == nowClock)
        _ = rt.frame(PG_DT)
        #expect(pgShows(rt, "lab") == "ticks 1 presses 0")
        pgTap(rt, "bump")
        pgEscape(rt)
        pgEscape(rt)
        rt.update { _, tx in tx.openPlayground() }
        _ = rt.frame(PG_DT)
        #expect(pgShows(rt, "lab").hasSuffix("presses 0"))
    }

    @Test func aLivePageDrawsAndChangesTheRealState() {
        let rt = pgRuntime(.some("Activity"))
        #expect(pgShows(rt, "activity") == "live 0")
        rt.update { s, _ in s.count = 7 }
        _ = rt.frame(PG_DT)
        #expect(pgShows(rt, "activity") == "live 7")
    }

    @Test func theRealStateKeepsPollingWhileOpen() {
        let rt = pgRuntime(.some(nil))
        let before = rt.state.polls
        for _ in 0..<5 { _ = rt.frame(PG_DT) }
        let after = rt.state.polls
        #expect(after >= before + 5)
        let scenePolls = rt.hostPlayground()?.scene?.state.polls ?? 0
        #expect(scenePolls >= 5)
    }

    @Test func withoutTheBarTheAppLaysOutUntouched() {
        let spec = AppSpec<PgTestReal>("playground", (800.0, 500.0), { PgTestReal() }, pgTestView)
        let rtPlain = toolingRuntimeFor(spec: spec, state: spec.`init`(), size: spec.size, env: Env.new(false, 1.0), waker: {})
        _ = rtPlain.hostFrame(0.0)
        let plain = rtPlain.hostElements().map { "\($0.path):\($0.rect)" }

        var rtBarless = toolingRuntimeFor(spec: spec, state: spec.`init`(), size: spec.size, env: Env.new(false, 1.0), waker: {})
        playgroundAttachHeadless(
            rt: &rtBarless,
            playground: Playground<PgTestReal>.new().enabled(true).bar(false),
            spec: spec,
            cliPlayground: nil,
            cliVariant: nil,
            windowed: true
        )
        _ = rtBarless.frame(0.0)
        let barless = rtBarless.hostElements().map { "\($0.path):\($0.rect)" }
        #expect(plain == barless)
    }

    @Test func keysWalkTheStoriesInTheirGroupsOrder() {
        let rt = pgRuntime(.some(nil))
        for (i, hasGroup) in [(0, true), (1, false), (2, true), (5, false), (3, true), (4, true)] {
            let exists = pgFind(rt, "playground-group-\(i)") != nil
            #expect(exists == hasGroup)
        }
        let walk: [(Key, Int, String?)] = [
            (.down, 1, nil),
            (.down, 1, "Motion"),
            (.down, 2, nil),
            (.down, 5, nil),
            (.down, 5, "Live"),
            (.down, 3, nil),
            (.up, 3, "Live"),
            (.up, 5, nil),
        ]
        for (key, expectedAt, expectedOn) in walk {
            pgPress(rt, key)
            #expect(pgSelected(rt) == expectedAt)
            #expect(pgHeader(rt) == expectedOn)
        }
        pgLetter(rt, "j")
        #expect(pgSelected(rt) == 3 && pgHeader(rt) == nil)
        pgLetter(rt, "k")
        #expect(pgSelected(rt) == 5 && pgHeader(rt) == nil)
        let cmd = Mods(cmd: true)
        pgPressWith(rt, .down, cmd)
        #expect(pgSelected(rt) == 4)
        pgPressWith(rt, .up, cmd)
        #expect(pgSelected(rt) == 0)
        pgPress(rt, .up)
        #expect(pgHeader(rt) == "Scenes")
        pgPress(rt, .up)
        #expect(pgSelected(rt) == 4)
    }

    @Test func aReplayRunsItsStepsOnTheLogicalClockTheSameEveryTime() {
        var logs: [[String]] = []
        for (start, dt) in [(0.0, 1.0 / 60.0), (3.3, 1.0 / 24.0)] {
            let rt = pgRuntime(.some("fade"))
            _ = rt.frame(start)
            pgLetter(rt, "f")
            _ = rt.frame(dt)
            pgLetter(rt, "r")
            for _ in 0..<4 { _ = rt.frame(dt) }
            pgLetter(rt, "r")
            _ = rt.frame(dt)
            #expect(pgShows(rt, "fade") == "[\"start\"]")
            let count = Int((1.0 / dt).rounded(.down))
            for _ in 0..<count { _ = rt.frame(dt) }
            let fade = pgOwnState(rt, as: PgTestFade.self)
            let recorded = fade.log.map { name, t in "\(name):\(Int64((t * 1e6).rounded()))" }
            logs.append(recorded)
        }
        #expect(logs[0] == ["start:0", "half:500000", "end:750000"])
        #expect(logs[0] == logs[1])
    }

    @Test func rightGoesIntoTheSideColumnAndTabOrLeftComesBack() {
        let rt = pgRuntime(.some("Fade"))
        pgPress(rt, .right)
        #expect(pgFocused(rt) == "playground-trigger-r")
        pgPress(rt, .down)
        #expect(pgFocused(rt) == "playground-trigger-f")
        pgPress(rt, .down)
        #expect(pgFocused(rt) == "playground-trigger-r")
        pgLetter(rt, "j")
        #expect(pgSelected(rt) == 5)
        pgPress(rt, .tab)
        #expect(pgFocused(rt) == nil)
        pgPress(rt, .right)
        pgPress(rt, .left)
        #expect(pgFocused(rt) == nil && pgSelected(rt) == 5)
        pgPress(rt, .down)
        pgPress(rt, .down)
        #expect(pgSelected(rt) == 3)
        pgPress(rt, .right)
        #expect(pgFocused(rt) == nil)
    }

    @Test func theShortcutOpensAndClosesItWithoutAMenu() {
        let rtHeadless = pgRuntimeIn(.some(nil), windowed: false)
        #if os(macOS)
        let chord = Mods(shift: true, cmd: true)
        let hasMenu = true
        #else
        let chord = Mods(shift: true, cmd: true, ctrl: true)
        let hasMenu = false
        #endif
        #expect(pgIsOpen(rtHeadless))
        pgPressWith(rtHeadless, .command("d"), chord)
        #expect(!pgIsOpen(rtHeadless))
        pgPressWith(rtHeadless, .command("d"), chord)
        #expect(pgIsOpen(rtHeadless))

        let rtWindowed = pgRuntime(.some(nil))
        pgPressWith(rtWindowed, .command("d"), chord)
        #expect(pgIsOpen(rtWindowed) == hasMenu)
    }

    @Test func leavingAStoryPartWayDropsItsQueuedSteps() {
        let rt = pgRuntime(.some("Fade"))
        pgLetter(rt, "r")
        pgLetter(rt, "j")
        for _ in 0..<60 { _ = rt.frame(PG_DT) }
        pgLetter(rt, "k")
        for _ in 0..<60 { _ = rt.frame(PG_DT) }
        #expect(pgShows(rt, "fade") == "[\"start\"]")
    }

    @Test func aNewStageEndsTheOldOnesExits() {
        let story = Story<PgTestTip>.new("Fixes/Tip", { PgTestTip() }, pgTestTipView)
            .trigger("h", "Hide") { p, _ in p.hidden = true }
        let rt = pgRuntimeWith(pgBase().story(story), .some("Tip"), windowed: true)
        let (x, y) = pgCenter(rt, "tip")
        _ = rt.hostPointerMove(x, y)
        _ = rt.frame(PG_DT)
        pgLetter(rt, "h")
        _ = rt.frame(PG_DT)
        let isExitingBefore = rt.hostElements().contains(where: { $0.key == "tip" && $0.exiting })
        #expect(isExitingBefore)
        pgLetter(rt, "j")
        let isExitingAfter = rt.hostElements().contains(where: { $0.key == "tip" && $0.exiting })
        #expect(!isExitingAfter)
        _ = rt.hostPointerMove(x + 300.0, y)
        _ = rt.frame(PG_DT)
        _ = rt.hostPointerMove(x, y)
        _ = rt.frame(PG_DT)
    }

    @Test func rootHandlersReachTheAppAboveTheBarAndTheStage() {
        let rt = pgRuntime(nil)
        _ = rt.hostPasteText("hi")
        _ = rt.frame(PG_DT)
        _ = rt.hostFileDrop(["a.txt"])
        _ = rt.frame(PG_DT)
        rt.hostWindowFocus(false)
        _ = rt.frame(PG_DT)
        let appPastes1 = rt.state.pastes
        let appDrops1 = rt.state.drops
        let appFocus1 = rt.state.focus.last
        #expect(appPastes1 == ["hi"] && appDrops1 == 1 && appFocus1 == false)

        rt.update { _, tx in tx.openPlayground() }
        _ = rt.frame(PG_DT)
        _ = rt.hostPasteText("staged")
        _ = rt.frame(PG_DT)
        _ = rt.hostFileDrop(["b.txt", "c.txt"])
        _ = rt.frame(PG_DT)
        rt.hostWindowFocus(true)
        _ = rt.frame(PG_DT)

        let scene = pgSceneState(rt)
        #expect(scene.pastes == ["staged"] && scene.drops == 2 && scene.focus == [true])
        let appPastes2 = rt.state.pastes.count
        let appDrops2 = rt.state.drops
        #expect(appPastes2 == 1 && appDrops2 == 1)
    }

    @Test func aKeyAfterAPressThatOpensThePlaygroundReachesIt() {
        let rt = pgRuntime(nil)
        let (x, y) = pgCenter(rt, "playground-open")
        _ = rt.hostPointerDown(x, y)
        _ = rt.hostPointerUp(x, y)
        _ = rt.hostKey(KeyEvent(key: .down, mods: Mods()))
        _ = rt.frame(PG_DT)
        #expect(pgIsOpen(rt))
        #expect(pgSelected(rt) == 1)
    }

    @Test func aNewStageForgetsWhatThePointerHeldInTheOldOne() {
        let rt = pgRuntimeWith(
            pgBase().story(Story<PgTestTray>.new("Fixes/Tray", { PgTestTray() }, pgTestTrayView)),
            .some("Tray"),
            windowed: true
        )
        let at = pgCenter(rt, "tray")
        _ = rt.hostDragHover(["a.txt"])
        _ = rt.frame(PG_DT)
        #expect(pgOwnState(rt, as: PgTestTray.self).hovering)
        _ = rt.hostPointerDown(at.0, at.1)
        pgPress(rt, .escape)
        pgLetter(rt, "j")
        #expect(pgSelected(rt) == 0)
        _ = rt.hostDragLeave()
        _ = rt.frame(PG_DT)
        _ = rt.hostPointerMove(at.0 + 10.0, at.1)
        _ = rt.hostPointerUp(at.0 + 10.0, at.1)
        _ = rt.frame(PG_DT)
        let dropHov = rt.hostDropHovered()
        #expect(dropHov == nil)
    }

    @Test func aStorysTimeScaleStaysWithIt() {
        let rt = pgRuntimeWith(
            pgBase().story(Story<PgTestLab>.new("Fixes/Slow", { PgTestLab() }, pgTestSlowView)),
            .some("Slow"),
            windowed: true
        )
        let ts1 = rt.timeScale
        #expect(ts1 == 0.25)
        pgLetter(rt, "j")
        let ts2 = rt.timeScale
        #expect(ts2 == 1.0)
        pgLetter(rt, "k")
        let ts3 = rt.timeScale
        #expect(ts3 == 0.25)
        pgEscape(rt)
        #expect(!pgIsOpen(rt))
        let ts4 = rt.timeScale
        #expect(ts4 == 1.0)
    }

    @Test func anElementFocusedInTheStageKeepsItsKeysUntilEscape() {
        let rt = pgRuntimeWith(
            pgBase().story(Story<PgTestKnob>.new("Fixes/Knob", { PgTestKnob() }, pgTestKnobView)),
            .some("Knob"),
            windowed: true
        )
        let at = pgSelected(rt)
        pgTap(rt, "knob")
        #expect(pgFocused(rt) == "knob")
        pgPress(rt, .down)
        pgPress(rt, .up)
        pgPress(rt, .up)
        #expect(pgShows(rt, "value") == "value 1" && pgSelected(rt) == at)
        pgEscape(rt)
        #expect(pgIsOpen(rt) && pgFocused(rt) == nil)
        pgLetter(rt, "j")
        #expect(pgSelected(rt) != at)
    }

    @Test func aReplayFromTheSideColumnKeepsTheKeyboardThere() {
        let rt = pgRuntime(.some("Fade"))
        pgPress(rt, .right)
        pgPress(rt, .down)
        #expect(pgFocused(rt) == "playground-trigger-f")
        pgLetter(rt, "r")
        _ = rt.frame(PG_DT)
        #expect(pgShows(rt, "fade") == "[\"start\"]")
        #expect(pgFocused(rt) == "playground-trigger-f")
        pgPress(rt, .up)
        #expect(pgFocused(rt) == "playground-trigger-r")
    }

    @Test func sceneTriggersAndSidesTakeNamesAsFindDoes() {
        let playground = pgBase()
            .trigger("still", "q", "Add four") { s, _ in s.count += 4 }
            .side("STILL") { s, _ in text("side \(s.count)").key("still-side") }
        let rt = pgRuntimeWith(playground, .some("Motion/Still"), windowed: true)
        #expect(pgShows(rt, "still-side") == "side 0")
        pgLetter(rt, "q")
        _ = rt.frame(PG_DT)
        #expect(pgShows(rt, "still-side") == "side 4")
    }

    @Test func aLongStoryListScrollsAndReachesWhatWasOffScreen() {
        var p = pgBase()
        for n in 0..<30 {
            p = p.story(Story<PgTestLab>.new("Many/Story \(n)", { PgTestLab() }, pgTestLabView))
        }
        let rt = pgRuntimeWith(p, .some(nil), windowed: true)
        _ = rt.frame(PG_DT)
        let last = rt.hostPlayground()!.order.last!
        let item = "playground-item-\(last)"
        let (_, y) = pgCenter(rt, item)
        #expect(y > 500.0)
        let list = pgFind(rt, "playground-list")!.rect

        _ = rt.hostWheel(list[0] + 20.0, list[1] + 100.0, -4000.0)
        _ = rt.frame(PG_DT)
        _ = rt.frame(PG_DT)
        let (x2, y2) = pgCenter(rt, item)
        #expect(y2 < y && y2 < 500.0)
        let hitKey = rt.hostElementAt(x2, y2)?.key
        let hittable: Bool = {
            guard let k = hitKey else { return false }
            if k == item { return true }
            if let e = pgFind(rt, k) {
                return e.rect[1] >= y2 - 28.0
            }
            return false
        }()
        #expect(hittable)
    }
}
