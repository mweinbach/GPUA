// Tests ported from: crates/rune/src/runtime/input_click_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("InputClickTests")
struct InputClickTests {
    private struct Form {
        var single: TextEdit
        var multi: TextEdit
        var other: TextEdit
        var secret: TextEdit
        var presses: Int = 0
        var drags: [Phase] = []
    }

    private func makeRuntime() -> Runtime<Form> {
        var secret = TextEdit.new("correct horse battery")
        secret.setSecure(true)
        let form = Form(
            single: TextEdit.new("make the title smaller"),
            multi: TextEdit.new("first line here\nsecond line there\nthird line end"),
            other: TextEdit.new("other words"),
            secret: secret
        )
        let st = TextStyle.new(14.0, 400.0).lh(20.0)
        let rt = Runtime.new(form, { s, _ in
            col().wFull().hFull().pad(8.0).gap(8.0)
                .child(
                    textInput(s.single, st).singleLine().key("single").size(280.0, 24.0)
                        .onPress { (f: inout Form, _) in f.presses += 1 }
                        .onDrag { (f: inout Form, d: inout Drag, _) in f.drags.append(d.phase) }
                )
                .child(textInput(s.multi, st).key("multi").size(280.0, 80.0))
                .child(textInput(s.other, st).singleLine().key("other").size(280.0, 24.0))
                .child(textInput(s.secret, st).singleLine().key("secret").size(280.0, 24.0))
        }, (320.0, 300.0), Env.new(true, 1.0))

        rt.bindEdit("single", EditAccess(\.single))
        rt.bindEdit("multi", EditAccess(\.multi))
        rt.bindEdit("other", EditAccess(\.other))
        rt.bindEdit("secret", EditAccess(\.secret))
        _ = rt.frame(0.0)
        return rt
    }

    private func click(_ rt: Runtime<Form>, _ pt: (Float, Float)) {
        rt.pointerDown(pt.0, pt.1)
        rt.pointerUp(pt.0, pt.1)
        _ = rt.frame(1.0 / 60.0)
    }

    @Test("Double and triple click select word and line in single-line input")
    func doubleAndTripleClickSelectWordAndLine() {
        let rt = makeRuntime()
        let r = rtElement(rt, "single")!.rect
        let pt = (r[0] + 12.0, r[1] + r[3] * 0.5)

        // Single click places collapsed caret inside "make"
        click(rt, pt)
        #expect(rt.state.single.anchor == rt.state.single.focus)
        #expect(rt.state.single.focus >= 0 && rt.state.single.focus <= 4)

        // Double click selects "make" (0..4)
        click(rt, pt)
        #expect(rt.state.single.anchor == 0 && rt.state.single.focus == 4)
        #expect(rt.state.single.selectedText() == "make")

        // Triple click selects entire single-line text
        click(rt, pt)
        #expect(rt.state.single.anchor == 0 && rt.state.single.focus == rt.state.single.text.utf8.count)
    }

    @Test("Shift-click extends selection from anchor")
    func shiftClickExtendsSelection() {
        let rt = makeRuntime()
        let r = rtElement(rt, "single")!.rect
        let p0 = (r[0] + 2.0, r[1] + r[3] * 0.5)
        let p1 = (r[0] + 90.0, r[1] + r[3] * 0.5)

        click(rt, p0)
        let anchor = rt.state.single.anchor
        _ = rt.frame(1.0) // advance past double-click window
        rt.pointerDown(p1.0, p1.1, mods: Mods(shift: true))
        rt.pointerUp(p1.0, p1.1, mods: Mods())
        _ = rt.frame(1.0 / 60.0)
        #expect(rt.state.single.anchor == anchor)
        #expect(rt.state.single.focus > anchor)
    }

    @Test("Secure inputs select all on double click rather than leaking word boundaries")
    func secureInputDoubleClickSelectsAll() {
        let rt = makeRuntime()
        let r = rtElement(rt, "secret")!.rect
        let pt = (r[0] + 16.0, r[1] + r[3] * 0.5)

        click(rt, pt)
        #expect(rt.state.secret.anchor == rt.state.secret.focus)

        click(rt, pt)
        #expect(rt.state.secret.anchor == 0)
        #expect(rt.state.secret.focus == rt.state.secret.text.utf8.count)
    }

    @Test("Input press and drag selection do not fire onPress or onDrag handlers")
    func inputPressAndDragDoNotFirePressOrDragHandlers() {
        let rt = makeRuntime()
        let r = rtElement(rt, "single")!.rect
        let p0 = (r[0] + 8.0, r[1] + r[3] * 0.5)
        let p1 = (r[0] + 95.0, r[1] + r[3] * 0.5)

        click(rt, p0)
        #expect(rt.state.presses == 0)
        #expect(rt.state.drags.isEmpty)

        _ = rt.frame(1.0)
        rt.pointerDown(p0.0, p0.1)
        rt.pointerMove(p1.0, p1.1)
        rt.pointerUp(p1.0, p1.1)
        _ = rt.frame(1.0 / 60.0)
        #expect(rt.state.single.anchor < rt.state.single.focus)
        #expect(rt.state.presses == 0)
        #expect(rt.state.drags.isEmpty)
    }

    @Test("Presses land on targets inside a scrolled viewport")
    func pressesLandOnTargetsInsideScrolledViewport() {
        let rt: Runtime<[Int]> = Runtime.new([], { _, _ in
            let rows = (0..<10).map { i in
                el().key("row\(i)").wFull().h(50.0).onPress { (s: inout [Int], _) in s.append(i) }
            }
            return col().size(200.0, 100.0).scroll(ScrollSpec(stickBottom: false))
                .child(col().wFull().children(rows))
        }, (200.0, 100.0), Env.new(true, 1.0))

        _ = rt.frame(0.0)
        rt.pointerMove(100.0, 25.0)
        rt.wheel(100.0, 25.0, -200.0)
        rtStepFrames(rt, 120)

        rt.pointerMove(100.0, 25.0)
        rt.pointerDown(100.0, 25.0)
        rt.pointerUp(100.0, 25.0)
        _ = rt.frame(1.0 / 120.0)
        #expect(rt.state == [4])
    }
}
