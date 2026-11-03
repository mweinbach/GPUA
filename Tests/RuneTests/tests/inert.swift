// Tests ported from: crates/rune/tests/inert.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private struct InertState {
    var inert: Bool = false
    var log: [String] = []
    var hover: [(String, Bool)] = []
    var field: TextEdit = TextEdit()
}

private func inertView(_ s: InertState, _: Cx<InertState>) -> El {
    let doc = el().key("doc").absolute(0.0, 0.0).size(100.0, 100.0).fill(Color.WHITE)
        .child(
            el().key("button").size(40.0, 40.0).fill(Color.BLACK).cursor(.pointer)
                .focusable(true)
                .onPress { (s: inout InertState, _: inout Tx) in s.log.append("button") }
                .onHoverChange { (s: inout InertState, inside: Bool, _: inout Tx) in s.hover.append(("button", inside)) }
        )
        .child(
            textInput(s.field, TextStyle.new(14.0, 400.0)).key("field").w(60.0)
                .onEdit(\InertState.field)
        )
    return el().key("canvas").size(200.0, 200.0).cursor(.crosshair)
        .onPress { (s: inout InertState, _: inout Tx) in s.log.append("canvas") }
        .onHoverChange { (s: inout InertState, inside: Bool, _: inout Tx) in s.hover.append(("canvas", inside)) }
        .child(s.inert ? doc.inert() : doc)
}

private func inertRuntime(_ inert: Bool) -> Runtime<InertState> {
    var initial = InertState()
    initial.inert = inert
    let rt = IntegrationSupport.runtime(initial, inertView, (200.0, 200.0), Env())
    _ = rt.hostFrame(0.0)
    return rt
}

@Suite("InertIntegrationTests")
struct InertIntegrationTests {
    @Test func pressesHoversAndCursorsFallThroughToWhatIsUnder() {
        let active = inertRuntime(false)
        IntegrationSupport.click(active, (20.0, 20.0))
        let activeLog = active.state.log
        #expect(activeLog == ["button"])
        #expect(active.hostCursor() == .pointer)

        let passthrough = inertRuntime(true)
        IntegrationSupport.click(passthrough, (20.0, 20.0))
        let passthroughLog = passthrough.state.log
        let passthroughHover = passthrough.state.hover
        #expect(passthroughLog == ["canvas"])
        #expect(passthrough.hostCursor() == .crosshair)
        #expect(passthroughHover.contains { $0.0 == "canvas" && $0.1 })
        #expect(!passthroughHover.contains { $0.0 == "button" })
        #expect(IntegrationSupport.find(passthrough, "button").hover == 0.0)
    }

    @Test func itStillDrawsAndLaysOut() {
        let rt = inertRuntime(true)
        let (instances, _, _) = rt.hostFrame(1.0 / 60.0)
        let doc = IntegrationSupport.find(rt, "doc")
        #expect(doc.rect == [0.0, 0.0, 100.0, 100.0])
        #expect(doc.opacity > 0.99)
        #expect(instances.contains { $0.rect[2] == 100.0 && $0.rect[3] == 100.0 })
        #expect(doc.inert && IntegrationSupport.find(rt, "button").inert)
        #expect(!IntegrationSupport.find(inertRuntime(false), "button").inert)
    }

    @Test func nothingInsideTakesOrKeepsFocus() {
        let active = inertRuntime(false)
        _ = active.hostKey(KeyEvent(key: .tab))
        _ = active.hostFrame(1.0 / 60.0)
        #expect(IntegrationSupport.find(active, "field").focused || IntegrationSupport.find(active, "button").focused)

        let inertRt = inertRuntime(true)
        windowHostState(for: inertRt).tabVisitsControls = true
        _ = inertRt.hostKey(KeyEvent(key: .tab))
        _ = inertRt.hostFrame(1.0 / 60.0)
        #expect(!IntegrationSupport.find(inertRt, "button").focused && !IntegrationSupport.find(inertRt, "field").focused)

        // Focus inside drops when the subtree turns inert.
        let dropRt = inertRuntime(false)
        dropRt.hostSetFocus("field", visible: true)
        _ = dropRt.hostFrame(1.0 / 60.0)
        #expect(IntegrationSupport.find(dropRt, "field").focused)
        dropRt.hostUpdate { s, _ in s.inert = true }
        _ = dropRt.hostFrame(1.0 / 60.0)
        #expect(!IntegrationSupport.find(dropRt, "field").focused)
    }

    @Test(.disabled("Requires Wave 2 El.onWheel / El.onMagnify / El.pointerButtons in Spine El"))
    func canvasGesturesHelpSelectionAndHeldHoverRespectInert() {}
}
