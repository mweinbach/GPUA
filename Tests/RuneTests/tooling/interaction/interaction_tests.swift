// Tests ported from: crates/rune/src/tooling/interaction/tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if !os(WASI)
import Foundation
#endif
import Testing
@testable import Rune

private func norm(_ path: String, _ keep: Int) -> String {
    var out = ""
    interactionNormalize(path, keep: keep, out: &out)
    return out
}

private struct InteractionTestApp {
    var note = TextEdit()
    var presses: UInt32 = 0
    var slow: Bool = false
}

private func interactionTestView(_ s: InteractionTestApp, _ cx: Cx<InteractionTestApp>) -> El {
    _ = cx
    var list = col().key("list")
    for i in 0..<30 {
        list = list.child(el().key("row-\(i)").h(4.0))
    }
    return col().key("settings").wFull().hFull()
        .child(
            el().key("save-42").size(80.0, 30.0).onPress { (state: inout InteractionTestApp, _: inout Tx) in
                state.presses += 1
                #if !os(WASI)
                if state.slow {
                    Thread.sleep(forTimeInterval: 0.025)
                }
                #endif
            }
        )
        .child(
            el().key("note").role("textbox").focusable(true).size(200.0, 24.0)
        )
        .child(el().key("count").child(text("\(s.presses)")))
        .child(list)
}

@Suite("InteractionTests", .serialized)
struct InteractionTests {
    private func makeRuntime(slow: Bool) -> Runtime<InteractionTestApp> {
        interactionGateForceOnForTests(true)
        _ = interactionTakeSentSlowForTests()
        _ = interactionTakeSentFramesForTests()
        let rt = Runtime(InteractionTestApp(slow: slow), interactionTestView, (400.0, 300.0), Env.new(true, 1.0))
        _ = rt.hostFrame(0.0)
        return rt
    }

    private func click(_ rt: Runtime<InteractionTestApp>, _ key: String) {
        let elems = rt.hostElements()
        guard let e = elems.first(where: { $0.key == key }) else {
            Issue.record("Missing element \(key)")
            return
        }
        let cx = e.rect[0] + e.rect[2] * 0.5
        let cy = e.rect[1] + e.rect[3] * 0.5
        _ = rt.hostPointerDown(cx, cy)
        _ = rt.hostPointerUp(cx, cy)
        _ = rt.hostFrame(1.0 / 60.0)
        rt.hostInteractionPresented(submitted: RuneInstant.now(), presentsAt: nil)
    }

    @Test func namesDropUnkeyedSegmentsIdsAndProse() {
        #expect(norm("#0/sidebar/row-x1208", 4) == "sidebar/row-x*")
        #expect(norm("#0/#2/list/item-3f9a2c41d7e0/open", 4) == "list/item-*/open")
        #expect(norm("#0/a/b/c/d/e", 4) == "b/c/d/e")
        #expect(norm("#0/notes/Buy milk tomorrow", 4) == "notes/~")
        #expect(norm("#0/k-palette", 4) == "k-palette")
        #expect(norm("#0/a\u{e9}b", 4) == "a_b")
        #expect(norm("#0/" + String(repeating: "x", count: 50), 4).count == 32)
    }

    @Test func namesAreInterned() {
        var names = InteractionNames()
        let a = names.control("#0/list/row-1/open")
        let b = names.control("#0/list/row-22/open")
        #expect(a.hash == b.hash)
        #expect(a.textBox === b.textBox)
        #expect(names.route("#0/settings", "#0/settings/confirm-7").text == "settings+modal:confirm-*")
        #expect(names.route(nil, nil).text == "root")
    }

    @Test func theGateWantsPerfOrALoopbackCollector() {
        #expect(interactionGateWanted(perf: "1", otel: nil, headless: true))
        #expect(!interactionGateWanted(perf: "0", otel: "http://127.0.0.1:27686", headless: false))
        #expect(interactionGateWanted(perf: nil, otel: "http://127.0.0.1:27686", headless: false))
        #expect(interactionGateWanted(perf: nil, otel: "http://localhost:4318/", headless: false))
        #expect(!interactionGateWanted(perf: nil, otel: "http://127.0.0.1:27686", headless: true))
        #expect(!interactionGateWanted(perf: nil, otel: "https://otel.example.com:4318", headless: false))
        #expect(!interactionGateWanted(perf: nil, otel: nil, headless: false))
        #expect(interactionGateLoopback("[::1]:4318")?.port == 4318)
        #expect(interactionGateEndpoint(otel: nil)?.description == INTERACTION_DEFAULT_ENDPOINT)
    }

    @Test func rollupQuantilesLandWithinABucket() {
        var names = InteractionNames()
        let route = names.fixed("root")
        let control = names.fixed("save")
        var rollup = InteractionRollup()
        for i in 1...100 {
            rollup.add(route: route, control: control, action: "on_press", ms: Double(i), slow: i > 98, contended: false)
        }
        let rolls = rollup.take()
        #expect(rolls.count == 1)
        let r = rolls[0]
        #expect(r.count == 100 && r.slow == 2 && r.maxMs == 100.0)
        #expect(abs(r.quantile(0.5) - 50.0) / 50.0 < 0.16)
        #expect(abs(r.quantile(0.98) - 98.0) / 98.0 < 0.16)
        #expect(rollup.isEmpty)
    }

    #if !os(WASI)
    @Test func aSlowClickNamesItsPageAndControl() {
        interactionSetOverloadedForTests(false)
        let rt = makeRuntime(slow: true)
        defer {
            interactionSetOverloadedForTests(nil)
            interactionGateForceOnForTests(nil)
        }
        click(rt, "save-42")
        let sent = interactionTakeSentSlowForTests()
        #expect(sent.count == 1)
        let s = sent[0]
        #expect(s.route == "settings")
        #expect(s.control == "settings/save-*")
        #expect(s.action == "on_press")
        #expect(s.handlerMs >= 24.0)
        let tracker = rt.hostInteractionTracker()
        let note = InteractionNote(
            route: tracker.names.route("#0/settings", nil),
            control: tracker.names.control("#0/settings/save-42"),
            action: "on_press",
            rank: 3
        )
        #expect(tracker.breached(note))
        #expect(s.commits >= 1 && (s.why & ToolingCommitWhy.INPUT) != 0)
        #expect(s.phases[ToolingProfilePhase.view.rawValue] > 0.0)
        #expect(s.present >= s.submitted && s.submitted >= s.built && s.built >= s.frameStart && s.frameStart >= s.arrived)
        #expect(s.rebuilt.first?.0 == "settings")
        #expect(!interactionActive())
    }

    @Test func aSlowClickSaysWhoseTimeItTook() {
        interactionSetOverloadedForTests(false)
        defer {
            interactionSetOverloadedForTests(nil)
            interactionGateForceOnForTests(nil)
        }
        let rt = makeRuntime(slow: true)
        click(rt, "save-42")
        let sent1 = interactionTakeSentSlowForTests()
        #expect(sent1.last?.cause == .blocked)
        if let cpu = sent1.last?.cpuMs {
            #expect(cpu < 25.0)
        }
        let rolls1 = rt.hostInteractionTracker().rollup.take()
        #expect(rolls1.first?.slow == 1 && rolls1.first?.contended == 0)

        interactionSetOverloadedForTests(true)
        let rt2 = makeRuntime(slow: true)
        click(rt2, "save-42")
        interactionSetOverloadedForTests(false)
        let sent2 = interactionTakeSentSlowForTests()
        #expect(sent2.last?.cause == .schedulerWait)
        let tracker2 = rt2.hostInteractionTracker()
        let rolls2 = tracker2.rollup.take()
        #expect(rolls2.first?.slow == 0 && rolls2.first?.contended == 1)
        #expect(tracker2.breachedSignatures.isEmpty)
    }

    @Test func aFastClickOnlyCounts() {
        let rt = makeRuntime(slow: false)
        defer { interactionGateForceOnForTests(nil) }
        click(rt, "save-42")
        #expect(interactionTakeSentSlowForTests().isEmpty)
        let rolls = rt.hostInteractionTracker().rollup.take()
        #expect(rolls.count == 1)
        #expect(rolls[0].control.text == "settings/save-*" && rolls[0].count == 1)
    }

    @Test func typingInAFieldSaysKeyEditNeverTheText() {
        let rt = makeRuntime(slow: false)
        defer { interactionGateForceOnForTests(nil) }
        click(rt, "note")
        _ = rt.hostInteractionTracker().rollup.take()
        _ = rt.hostIme(.commit("secret"))
        _ = rt.hostFrame(1.0 / 60.0)
        rt.hostInteractionPresented(submitted: RuneInstant.now(), presentsAt: nil)
        let rolls = rt.hostInteractionTracker().rollup.take()
        #expect(rolls.count == 1)
        #expect(rolls[0].control.text == "settings/note" && rolls[0].action == "key_edit")
    }

    @Test func aFrameNoHostPresentsEndsAtItsBuild() {
        let rt = makeRuntime(slow: true)
        defer { interactionGateForceOnForTests(nil) }
        let elems = rt.hostElements()
        let e = elems.first(where: { $0.key == "save-42" })!
        let cx = e.rect[0] + e.rect[2] * 0.5
        let cy = e.rect[1] + e.rect[3] * 0.5
        _ = rt.hostPointerDown(cx, cy)
        _ = rt.hostPointerUp(cx, cy)
        _ = rt.hostFrame(1.0 / 60.0)
        #expect(interactionTakeSentSlowForTests().isEmpty)
        _ = rt.hostFrame(1.0 / 60.0)
        let sent = interactionTakeSentSlowForTests()
        #expect(sent.count == 1)
        #expect(sent[0].present == sent[0].built)
    }

    @Test func offNothingIsTimed() {
        interactionGateForceOnForTests(false)
        defer { interactionGateForceOnForTests(nil) }
        _ = interactionTakeSentSlowForTests()
        let rt = Runtime(InteractionTestApp(slow: true), interactionTestView, (400.0, 300.0), Env.new(true, 1.0))
        _ = rt.hostFrame(0.0)
        click(rt, "save-42")
        #expect(interactionTakeSentSlowForTests().isEmpty)
        let tracker = rt.hostInteractionTracker()
        #expect(tracker.rollup.isEmpty && tracker.timed == nil)
    }

    @Test func slowSpansCarryTheSignatureAndStretches() {
        let rt = makeRuntime(slow: true)
        defer { interactionGateForceOnForTests(nil) }
        click(rt, "save-42")
        let slow = interactionTakeSentSlowForTests().last!
        let spans = interactionSlowSpans(slow)
        let names = spans.compactMap { $0["name"].stringValue }
        #expect(names.first == "ui.interaction")
        #expect(names.contains("update"))
        let attrs = spans[0]["attributes"].arrayValue ?? []
        func attr(_ key: String) -> ToolingJson? {
            attrs.first(where: { $0["key"].stringValue == key })?["value"]
        }
        #expect(attr("rune.route")?["stringValue"].stringValue == "settings")
        #expect(attr("rune.control")?["stringValue"].stringValue == "settings/save-*")
        let rootId = spans[0]["spanId"].stringValue
        let traceId = spans[0]["traceId"].stringValue
        #expect(spans.dropFirst().allSatisfy {
            $0["parentSpanId"].stringValue == rootId && $0["traceId"].stringValue == traceId
        })
    }
    #endif
}
