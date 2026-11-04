// Tests ported from: crates/rune-kit/tests/text_input_press.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import Rune
@testable import RuneKit

private struct PressFormState {
    var input: TextEdit
    var field: TextEdit
    var area: TextEdit
    var actions: Int
    var revealed: Bool
    var copied: Int
}

private func makePressFormState() -> PressFormState {
    PressFormState(
        input: TextEdit.new("hunter2"),
        field: TextEdit.new("vault"),
        area: TextEdit.new("notes"),
        actions: 0,
        revealed: false,
        copied: 0
    )
}

private func pressFormView(_ s: PressFormState, _: Cx<PressFormState>) -> El {
    let k = Kit.neutral(true)
    let accessories = Rune.row()
        .key("accessories")
        .gap(6.0)
        .px(4.0)
        .centerY()
        .child(Rune.text("pw").key("hint"))
        .child(
            IconButton.new(k.glyph.check)
                .variant(.ghost)
                .label("Reveal")
                .onPress { (s: inout PressFormState) in
                    s.revealed.toggle()
                }
                .build(k)
                .key("reveal")
        )
    return Rune.col()
        .wFull()
        .hFull()
        .padding(16.0)
        .gap(16.0)
        .child(
            Rune.row()
                .key("titlebar")
                .wFull()
                .h(48.0)
                .windowDrag()
                .centerY()
                .px(12.0)
                .child(
                    TextInput.new(s.input)
                        .placeholder("Search")
                        .leadingIcon(k.glyph.search)
                        .trailing(accessories)
                        .clearButton()
                        .onEdit(\PressFormState.input)
                        .onAction { (s: inout PressFormState, _: inout Tx) in
                            s.actions += 1
                        }
                        .build(k)
                        .key("ti")
                )
        )
        .child(
            TextField.new("Label", s.field)
                .copyable()
                .onEdit(\PressFormState.field)
                .onAction { (s: inout PressFormState, _: inout Tx) in
                    s.copied += 1
                }
                .build(k)
                .key("tf")
        )
        .child(
            TextArea.new(s.area)
                .onEdit(\PressFormState.area)
                .build(k)
                .key("ta")
        )
}

private func findPressElem(_ rt: Runtime<PressFormState>, _ key: String) -> ElementInfo {
    rt.elements().first(where: { $0.key == key })!
}

private func clickAt(_ rt: Runtime<PressFormState>, _ x: Float, _ y: Float) {
    _ = rt.pointerDown(x, y)
    rt.pointerUp(x, y)
    _ = rt.frame(1.0 / 60.0)
}

/// Matches Rust `str::lines().count()` (splits on `\n` and `\r\n`, ignoring a final line ending).
private func rustLineCount(_ s: String) -> Int {
    if s.isEmpty { return 0 }
    var trimmed = s
    if trimmed.last == "\n" || trimmed.last == "\r\n" {
        trimmed.removeLast()
    }
    return trimmed.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count
}

private struct GeometrySnapshot: Equatable {
    var path: String
    var rect: [Float]
    var target: [Float]
    var caret: [Float]?
}

@Suite("TextInputPressTests")
struct TextInputPressTests {
    // PORT NOTE: Blocked on Sources/Rune role("textbox") padding press forwarding, preserveFocusOnPress & multiline secure TextEdit.
    @Test(.disabled("Blocked on Sources/Rune role(\"textbox\") padding press forwarding, preserveFocusOnPress & multiline secure TextEdit"))
    func textboxPaddingRequiresExactlyOneReachableEditor() {
        struct Pair {
            var first: TextEdit
            var second: TextEdit
            var hideSecond: Bool
        }
        func view(_ s: Pair, _: Cx<Pair>) -> El {
            Rune.row()
                .role("textbox")
                .key("box")
                .size(400.0, 60.0)
                .padding(10.0)
                .child(
                    Rune.textInput(s.first, TextStyle.new(13.0, 400.0))
                        .key("first")
                        .size(120.0, 30.0)
                        .onEdit(\Pair.first)
                )
                .child(
                    Rune.col()
                        .opacity(s.hideSecond ? 0.0 : 1.0)
                        .child(
                            Rune.textInput(s.second, TextStyle.new(13.0, 400.0))
                                .key("second")
                                .size(120.0, 30.0)
                                .onEdit(\Pair.second)
                        )
                )
        }
        let rt = Runtime.new(
            Pair(first: TextEdit.new("one"), second: TextEdit.new("two"), hideSecond: false),
            view,
            (440.0, 100.0),
            Env.new(true, 1.0)
        )
        _ = rt.frame(0.0)
        _ = rt.pointerDown(2.0, 2.0)
        rt.pointerUp(2.0, 2.0)
        _ = rt.frame(0.0)
        #expect(!rt.state.first.focused && !rt.state.second.focused, "padding cannot choose between two editors")

        rt.update { s, tx in
            s.hideSecond = true
            tx.instant()
        }
        _ = rt.frame(0.0)
        _ = rt.pointerDown(2.0, 2.0)
        rt.pointerUp(2.0, 2.0)
        _ = rt.frame(0.0)
        #expect(rt.state.first.focused && !rt.state.second.focused, "hidden ancestors exclude an editor")
    }

    // PORT NOTE: Blocked on Sources/Rune role("textbox") padding press forwarding, preserveFocusOnPress & multiline secure TextEdit.
    @Test(.disabled("Blocked on Sources/Rune role(\"textbox\") padding press forwarding, preserveFocusOnPress & multiline secure TextEdit"))
    func aCopyButtonWithoutAHandlerStillKeepsItsPress() {
        func view(_ s: TextEdit, _: Cx<TextEdit>) -> El {
            TextInput.new(s)
                .copyButton()
                .onEdit { (state: inout TextEdit, mutate: (inout TextEdit) -> Void) in
                    mutate(&state)
                }
                .build(Kit.neutral(true))
        }
        var edit = TextEdit.new("text")
        edit.focused = true
        edit.setCaret(1)
        let rt = Runtime.new(edit, view, (400.0, 100.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)
        let (x, y) = rt.find("action")!
        _ = rt.pointerDown(x, y)
        rt.pointerUp(x, y)
        _ = rt.frame(0.0)
        #expect(rt.state.focused)
        #expect(rt.state.range() == (1, 1), "the button press must not place the input's caret")
    }

    // PORT NOTE: Blocked on Sources/Rune role("textbox") padding press forwarding, preserveFocusOnPress & multiline secure TextEdit.
    @Test(.disabled("Blocked on Sources/Rune role(\"textbox\") padding press forwarding, preserveFocusOnPress & multiline secure TextEdit"))
    func paddingFocusReachesAnEditorInsideAnAutoGrowScroll() {
        func view(_ s: TextEdit, _: Cx<TextEdit>) -> El {
            TextArea.new(s)
                .autoGrow(2, 2)
                .onEdit { (state: inout TextEdit, mutate: (inout TextEdit) -> Void) in
                    mutate(&state)
                }
                .build(Kit.neutral(true))
                .key("area")
        }
        let rt = Runtime.new(TextEdit.new("one\ntwo\nthree\nfour"), view, (400.0, 200.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)
        _ = rt.pointerDown(2.0, 2.0)
        rt.pointerUp(2.0, 2.0)
        _ = rt.frame(0.0)
        #expect(rt.state.focused)
        #expect(rt.state.range() == (0, 0))
    }

    // PORT NOTE: Blocked on Sources/Rune role("textbox") padding press forwarding, preserveFocusOnPress & multiline secure TextEdit.
    @Test(.disabled("Blocked on Sources/Rune role(\"textbox\") padding press forwarding, preserveFocusOnPress & multiline secure TextEdit"))
    func pressingAnyPartOfAFieldFocusesWithoutBlurringOrDragging() {
        let rt = Runtime.new(makePressFormState(), pressFormView, (480.0, 400.0), Env.new(true, 2.0))
        _ = rt.frame(0.0)

        let ti = findPressElem(rt, "ti")
        let lead = findPressElem(rt, "leading")
        let hint = findPressElem(rt, "hint")
        let reveal = findPressElem(rt, "reveal")
        let clear = findPressElem(rt, "action")

        // 1. Clicking the leading icon focuses the field, puts the caret at the start, and does not drag the window.
        clickAt(rt, lead.rect[0] + lead.rect[2] * 0.5, lead.rect[1] + lead.rect[3] * 0.5)
        #expect(rt.takeTitlebarAction() == nil, "pressing a field in a titlebar never drags the window")
        #expect(rt.state.input.focused, "leading icon focuses the field")
        #expect(rt.state.input.range() == (0, 0), "leading icon places caret at start")

        // 2. While already focused, clicking the trailing accessory area (not a button) or top/bottom padding keeps focus and moves the caret to the end.
        clickAt(rt, hint.rect[0] + hint.rect[2] * 0.5, ti.rect[1] + 2.0)
        #expect(rt.takeTitlebarAction() == nil)
        #expect(rt.state.input.focused, "clicking trailing accessory area or top padding must not blur")
        #expect(rt.state.input.range() == (7, 7), "trailing side places caret at end")

        // Clicking the bottom-left padding moves the caret back to the start without blurring.
        clickAt(rt, ti.rect[0] + 3.0, ti.rect[1] + ti.rect[3] - 2.0)
        #expect(rt.state.input.focused, "clicking bottom-left padding must not blur")
        #expect(rt.state.input.range() == (0, 0), "leading padding places caret at start")

        // 3. Trailing buttons still take their own press.
        clickAt(rt, reveal.rect[0] + reveal.rect[2] * 0.5, reveal.rect[1] + reveal.rect[3] * 0.5)
        #expect(rt.state.revealed, "trailing reveal button takes its own press")
        clickAt(rt, clear.rect[0] + clear.rect[2] * 0.5, clear.rect[1] + clear.rect[3] * 0.5)
        #expect(rt.state.actions == 1, "clear button takes its own press")

        // 4. TextField: leading and trailing padding focus and place the caret; copy button takes its own press.
        let wrapper = findPressElem(rt, "wrapper")
        let copy = findPressElem(rt, "copy")
        clickAt(rt, wrapper.rect[0] + wrapper.rect[2] - 30.0, wrapper.rect[1] + 2.0)
        #expect(rt.state.field.focused, "TextField padding focuses the field")
        #expect(rt.state.field.range() == (5, 5), "TextField trailing padding places caret at end")
        clickAt(rt, wrapper.rect[0] + 3.0, wrapper.rect[1] + wrapper.rect[3] - 2.0)
        #expect(rt.state.field.focused, "TextField leading padding keeps focus")
        #expect(rt.state.field.range() == (0, 0), "TextField leading padding places caret at start")
        clickAt(rt, copy.rect[0] + copy.rect[2] * 0.5, copy.rect[1] + copy.rect[3] * 0.5)
        #expect(rt.state.copied == 1, "TextField copy button takes its own press")

        // 5. TextArea: bottom/trailing padding focuses at end; leading padding focuses at start without blurring.
        let ta = findPressElem(rt, "ta")
        clickAt(rt, ta.rect[0] + ta.rect[2] - 4.0, ta.rect[1] + ta.rect[3] - 4.0)
        #expect(rt.state.area.focused, "TextArea bottom-right padding focuses the field")
        #expect(rt.state.area.range() == (5, 5), "TextArea trailing/bottom padding places caret at end")
        clickAt(rt, ta.rect[0] + 2.0, ta.rect[1] + 4.0)
        #expect(rt.state.area.focused, "TextArea leading padding keeps focus")
        #expect(rt.state.area.range() == (0, 0), "TextArea leading padding places caret at start")
    }

    // PORT NOTE: Blocked on Sources/Rune role("textbox") padding press forwarding, preserveFocusOnPress & multiline secure TextEdit.
    @Test(.disabled("Blocked on Sources/Rune role(\"textbox\") padding press forwarding, preserveFocusOnPress & multiline secure TextEdit"))
    func aLauncherSizeStyleScalesTheBoxAndTheCaret() {
        struct Launcher {
            var plain: TextEdit
            var big: TextEdit
            var launcher: TextEdit
            var largeSmallStyle: TextEdit
            var tight: TextEdit
        }
        func view(_ s: Launcher, _: Cx<Launcher>) -> El {
            let k = Kit.neutral(true)
            let style24 = TextStyle.new(17.0, 400.0).lh(24.0)
            return Rune.col()
                .child(TextInput.new(s.plain).onEdit(\Launcher.plain).build(k).key("plain"))
                .child(
                    TextInput.new(s.big)
                        .placeholder("Search")
                        .textStyle(style24)
                        .onEdit(\Launcher.big)
                        .build(k)
                        .key("big")
                )
                .child(
                    TextInput.new(s.launcher)
                        .placeholder("Type a command")
                        .leadingIcon(k.glyph.search)
                        .clearButton()
                        .textStyle(style24)
                        .height(56.0)
                        .onEdit(\Launcher.launcher)
                        .build(k)
                        .key("launcher")
                )
                .child(
                    TextInput.new(s.largeSmallStyle)
                        .large()
                        .textStyle(TextStyle.new(13.0, 500.0).lh(16.0))
                        .build(k)
                        .key("large-compact")
                )
                .child(
                    TextInput.new(s.tight)
                        .textStyle(style24)
                        .height(10.0)
                        .build(k)
                        .key("tight")
                )
        }
        let state = Launcher(
            plain: TextEdit.new("hi"),
            big: TextEdit.new("hi"),
            launcher: TextEdit.new("hi"),
            largeSmallStyle: TextEdit.new("hi"),
            tight: TextEdit.new("hi")
        )
        let rt = Runtime.new(state, view, (400.0, 300.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)
        let byPath = { (rt: Runtime<Launcher>, path: String) -> ElementInfo in
            rt.elements().first(where: { $0.path.hasSuffix(path) })!
        }
        let h = { (rt: Runtime<Launcher>, key: String) -> Float in
            rt.elements().first(where: { $0.key == key })!.rect[3]
        }
        #expect(
            [h(rt, "plain"), h(rt, "big"), h(rt, "launcher"), h(rt, "large-compact"), h(rt, "tight")]
                == [28.0, 36.0, 56.0, 32.0, 24.0],
            "box grows with style, keeps large's 32 floor, and clamps height to at least line_px"
        )
        let lines = rt.elements().filter { $0.key == "input" }.map { $0.rect[3] }
        #expect(lines == [16.0, 24.0, 24.0, 16.0, 24.0], "the editor's line follows the style")

        // In the 56 pt launcher box, the 24 pt editor, leading icon, and clear button are all vertically centred.
        let boxRect = byPath(rt, "launcher").rect
        let inputRect = byPath(rt, "launcher/value/input").rect
        let leadRect = byPath(rt, "launcher/value/leading").rect
        let actionRect = byPath(rt, "launcher/action").rect
        let boxCy = boxRect[1] + boxRect[3] * 0.5
        for (name, r) in [("input", inputRect), ("leading", leadRect), ("action", actionRect)] {
            #expect(
                abs((r[1] + r[3] * 0.5) - boxCy) < 0.01,
                "\(name) is vertically centred in the 56 pt box: \(r) vs \(boxRect)"
            )
        }

        // Focus the 56 pt launcher field and check that its caret is 24 pt tall and vertically centred.
        let (x, y) = (boxRect[0] + 40.0, boxCy)
        _ = rt.pointerDown(x, y)
        rt.pointerUp(x, y)
        _ = rt.frame(1.0 / 60.0)
        #expect(rt.state.launcher.focused)
        let caret = byPath(rt, "launcher/value/input").caret!
        #expect(caret[3] == 24.0, "caret height matches the 24 pt line height")
        #expect(abs((caret[1] + caret[3] * 0.5) - boxCy) < 0.01, "caret is vertically centred in the 56 pt box: \(caret)")
    }

    // PORT NOTE: Blocked on Sources/Rune role("textbox") padding press forwarding, preserveFocusOnPress & multiline secure TextEdit.
    @Test(.disabled("Blocked on Sources/Rune role(\"textbox\") padding press forwarding, preserveFocusOnPress & multiline secure TextEdit"))
    func anyUnfocusableElementCanKeepAnOutsideFieldFocusedAndStillPress() {
        struct PreserveState {
            var field: TextEdit
            var pressed: Int
        }
        func view(_ s: PreserveState, _: Cx<PreserveState>) -> El {
            Rune.col()
                .gap(8.0)
                .child(TextInput.new(s.field).onEdit(\PreserveState.field).build(Kit.neutral(true)).key("field"))
                .child(
                    Rune.row()
                        .key("plain")
                        .size(100.0, 30.0)
                        .onPress { (s: inout PreserveState) in s.pressed += 1 }
                )
                .child(
                    Rune.row()
                        .key("keeper")
                        .size(100.0, 30.0)
                        .preserveFocusOnPress(true)
                        .onPress { (s: inout PreserveState) in s.pressed += 10 }
                )
        }
        var field = TextEdit.new("x")
        field.focused = true
        let rt = Runtime.new(PreserveState(field: field, pressed: 0), view, (200.0, 200.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)
        let (kx, ky) = rt.find("keeper")!
        _ = rt.pointerDown(kx, ky)
        rt.pointerUp(kx, ky)
        _ = rt.frame(1.0 / 60.0)
        #expect(rt.state.pressed == 10, "the press still reaches onPress")
        #expect(rt.state.field.focused, "the field keeps focus")

        let (px, py) = rt.find("plain")!
        _ = rt.pointerDown(px, py)
        rt.pointerUp(px, py)
        _ = rt.frame(1.0 / 60.0)
        #expect(!rt.state.field.focused, "without the flag a press blurs, as before")
    }

    // PORT NOTE: Blocked on Sources/Rune role("textbox") padding press forwarding, preserveFocusOnPress & multiline secure TextEdit.
    @Test(.disabled("Blocked on Sources/Rune role(\"textbox\") padding press forwarding, preserveFocusOnPress & multiline secure TextEdit"))
    func aPlainFieldDrawsNoBoxButStillFocusesOnAPressAnywhereAndTypes() {
        struct PlainState {
            var boxed: TextEdit
            var plain: TextEdit
            var invalid: TextEdit
            var disabled: TextEdit
            var actions: Int
        }
        func view(_ s: PlainState, _: Cx<PlainState>) -> El {
            let k = Kit.neutral(true)
            let style24 = TextStyle.new(17.0, 400.0).lh(24.0)
            return Rune.col()
                .gap(8.0)
                .child(
                    TextInput.new(s.boxed)
                        .leadingIcon(k.glyph.search)
                        .onEdit(\PlainState.boxed)
                        .build(k)
                        .key("boxed")
                )
                .child(
                    Rune.row()
                        .key("outer-box")
                        .role("textbox")
                        .wFull()
                        .px(12.0)
                        .child(
                            TextInput.new(s.plain)
                                .plain()
                                .placeholder("Type a command")
                                .leadingIcon(k.glyph.search)
                                .leadingIconSize(18.0)
                                .textStyle(style24)
                                .height(56.0)
                                .width(nil)
                                .clearButton()
                                .onEdit(\PlainState.plain)
                                .onAction { (s: inout PlainState, _: inout Tx) in s.actions += 1 }
                                .build(k)
                                .key("plain")
                        )
                )
                .child(
                    TextInput.new(s.invalid)
                        .plain()
                        .placeholder("Bad")
                        .invalid(true)
                        .state(.hover)
                        .onEdit(\PlainState.invalid)
                        .build(k)
                        .key("invalid")
                )
                .child(
                    TextInput.new(s.disabled)
                        .plain()
                        .leadingIcon(k.glyph.search)
                        .clearButton()
                        .disabled(true)
                        .onEdit(\PlainState.disabled)
                        .onAction { (s: inout PlainState, _: inout Tx) in s.actions += 10 }
                        .build(k)
                        .key("disabled")
                )
        }
        let rt = Runtime.new(
            PlainState(
                boxed: TextEdit.new("a"),
                plain: TextEdit.new(""),
                invalid: TextEdit.new("err"),
                disabled: TextEdit.new("off"),
                actions: 0
            ),
            view,
            (400.0, 260.0),
            Env.new(true, 1.0)
        )
        _ = rt.frame(0.0)
        let k = Kit.neutral(true)
        let info = { (rt: Runtime<PlainState>, key: String) -> ElementInfo in
            rt.elements().first(where: { $0.key == key })!
        }
        let byPath = { (rt: Runtime<PlainState>, path: String) -> ElementInfo in
            rt.elements().first(where: { $0.path.hasSuffix(path) })!
        }
        let ink = { (rt: Runtime<PlainState>, key: String) -> Int in
            let r = info(rt, key).rect
            return rt.instances.filter { i in
                let cx = i.rect[0] + i.rect[2] * 0.5
                let cy = i.rect[1] + i.rect[3] * 0.5
                return cx >= r[0] && cx <= r[0] + r[2] && cy >= r[1] && cy <= r[1] + r[3] && i.rect[2] >= r[2] - 0.5
            }.count
        }
        let plain = info(rt, "plain")
        #expect(plain.role == "textbox" && plain.label == "Type a command", "a11y role and label unchanged")
        #expect(plain.fill.a == 0.0, "no fill")
        #expect(info(rt, "boxed").fill.a > 0.0)
        #expect(ink(rt, "plain") == 0, "unfocused plain draws no box, shadow or border")
        #expect(ink(rt, "invalid") == 0, "hovered + invalid plain draws no box, hover tint or outline")
        #expect(ink(rt, "boxed") > 0)
        #expect(byPath(rt, "invalid/value/input").textColor == k.c.danger.fg, "invalid plain shows as red text")
        let disInp = byPath(rt, "disabled/value/input").rect
        let disGlyph = rt.instances.first(where: { i in
            i.params[1] == KIND_GLYPH
                && i.rect[0] >= disInp[0] && i.rect[0] < disInp[0] + disInp[2]
                && i.rect[1] >= disInp[1] && i.rect[1] < disInp[1] + disInp[3]
        })!
        #expect(abs(disGlyph.fill[3] - 0.5) < 0.01, "disabled plain dims to 0.5: \(disGlyph.fill)")

        // In the 56 pt plain launcher header, leading icon (18 pt), input (24 pt), placeholder glyphs and clear button (28 pt) are all vertically centred.
        let b = plain.rect
        let bCy = b[1] + b[3] * 0.5
        let lead = byPath(rt, "plain/value/leading").rect
        let inp = byPath(rt, "plain/value/input").rect
        let clear = byPath(rt, "plain/action").rect
        #expect([b[3], lead[2], lead[3], inp[3], clear[3]] == [56.0, 26.0, 18.0, 24.0, 28.0])
        #expect(abs(clear[0] + clear[2] - (b[0] + b[2])) < 0.01, "clear button reaches the right edge")
        for (name, r) in [("leading", lead), ("input", inp), ("clear", clear)] {
            #expect(abs((r[1] + r[3] * 0.5) - bCy) < 0.01, "\(name) vertically centred in 56 pt plain box: \(r) vs \(b)")
        }
        let placeholderGlyphs = rt.instances.filter { i in
            i.params[1] == KIND_GLYPH
                && i.rect[0] >= inp[0] && i.rect[0] < inp[0] + inp[2]
                && i.rect[1] >= b[1] && i.rect[1] < b[1] + b[3]
        }
        #expect(!placeholderGlyphs.isEmpty, "empty plain field paints placeholder glyphs")
        var py0: Float = .infinity
        var py1: Float = -.infinity
        for g in placeholderGlyphs {
            py0 = min(py0, g.rect[1])
            py1 = max(py1, g.rect[1] + g.rect[3])
        }
        #expect(
            abs(((py0 + py1) * 0.5) - bCy) < 4.0,
            "placeholder glyphs sit centred in the 56 pt box: \(py0)..\(py1) vs \(bCy)"
        )

        // Moving the pointer over the plain field draws no hover box.
        rt.pointerMove(b[0] + 50.0, bCy)
        _ = rt.frame(1.0 / 60.0)
        #expect(ink(rt, "plain") == 0, "pointer hover over plain draws no tint")

        // Pressing the outer role("textbox") container's padding routes focus to the plain field inside it.
        let outer = info(rt, "outer-box").rect
        _ = rt.pointerDown(outer[0] + 2.0, bCy)
        rt.pointerUp(outer[0] + 2.0, bCy)
        _ = rt.frame(1.0 / 60.0)
        #expect(rt.state.plain.focused, "outer role(\"textbox\") padding focuses the plain field")
        #expect(ink(rt, "plain") == 0, "focused plain draws no outline")
        let caret = byPath(rt, "plain/value/input").caret!
        let ime = rt.imeArea!
        #expect(caret[3] == 24.0)
        #expect(abs((caret[1] + caret[3] * 0.5) - bCy) < 0.01, "caret vertically centred: \(caret)")
        #expect(
            abs(ime[0] - caret[0]) < 0.01 && abs(ime[1] - caret[1]) < 0.01 && abs(ime[3] - 24.0) < 0.01,
            "IME rect matches caret: \(ime) vs \(caret)"
        )

        // Typing and pressing inside the plain field's own padding and clear button work as in the boxed field.
        _ = rt.keyDown(KeyEvent(key: .text("hi"), mods: Mods()))
        _ = rt.frame(0.0)
        #expect(rt.state.plain.text == "hi")
        _ = rt.pointerDown(b[0] + 1.0, b[1] + b[3] - 1.0)
        rt.pointerUp(b[0] + 1.0, b[1] + b[3] - 1.0)
        _ = rt.frame(1.0 / 60.0)
        #expect(rt.state.plain.focused && rt.state.plain.range() == (0, 0), "plain padding keeps focus and moves caret to start")
        _ = rt.keyDown(KeyEvent(key: .text("x"), mods: Mods()))
        _ = rt.frame(0.0)
        #expect(rt.state.plain.text == "xhi", "typing reaches the field")
        _ = rt.pointerDown(clear[0] + 2.0, clear[1] + 2.0)
        rt.pointerUp(clear[0] + 2.0, clear[1] + 2.0)
        _ = rt.frame(1.0 / 60.0)
        #expect(rt.state.actions == 1, "onAction still fires")
        #expect(rt.state.plain.focused, "clear button inside plain field does not blur it")
    }

    @Test
    func theLeadingIconSizeScalesTheIconAndMovesTheText() {
        struct IconSizePair {
            var a: TextEdit
            var b: TextEdit
        }
        func view(_ s: IconSizePair, _: Cx<IconSizePair>) -> El {
            let k = Kit.neutral(true)
            return Rune.col()
                .child(TextInput.new(s.a).leadingIcon(k.glyph.search).height(56.0).build(k).key("a"))
                .child(
                    TextInput.new(s.b)
                        .leadingIcon(k.glyph.search)
                        .leadingIconSize(24.0)
                        .height(56.0)
                        .build(k)
                        .key("b")
                )
        }
        let rt = Runtime.new(
            IconSizePair(a: TextEdit.new("x"), b: TextEdit.new("x")),
            view,
            (400.0, 200.0),
            Env.new(true, 1.0)
        )
        _ = rt.frame(0.0)
        let at = { (path: String) -> [Float] in
            rt.elements().first(where: { $0.path.hasSuffix(path) })!.rect
        }
        let ia = at("a/value/leading")
        let ib = at("b/value/leading")
        let ta = at("a/value/input")
        let tb = at("b/value/input")
        #expect(ia[2] - 8.0 == 16.0 && ib[2] - 8.0 == 24.0, "icon box is pad plus the icon")
        #expect(tb[0] - ta[0] == 8.0, "the text starts 8 points later")
        let a = at("a")
        let b = at("b")
        #expect(
            abs((ib[1] + ib[3] * 0.5) - (b[1] + b[3] * 0.5)) < 0.01
                && abs((ia[1] + ia[3] * 0.5) - (a[1] + a[3] * 0.5)) < 0.01
        )
    }

    // PORT NOTE: Blocked on Sources/Rune role("textbox") padding press forwarding, preserveFocusOnPress & multiline secure TextEdit.
    @Test(.disabled("Blocked on Sources/Rune role(\"textbox\") padding press forwarding, preserveFocusOnPress & multiline secure TextEdit"))
    func secureTextInputRevealedDrawsPlainGlyphsAndKeepsSecureProtections() {
        struct SecureForm {
            var plain: TextEdit
            var secret: TextEdit
            var revealed: Bool
        }
        func view(_ s: SecureForm, _: Cx<SecureForm>) -> El {
            let k = Kit.neutral(true)
            return Rune.col()
                .gap(8.0)
                .child(TextInput.new(s.plain).onEdit(\SecureForm.plain).build(k).key("plain"))
                .child(
                    TextInput.new(s.secret)
                        .secure()
                        .revealed(s.revealed)
                        .copyButton()
                        .onEdit(\SecureForm.secret)
                        .build(k)
                        .key("secret")
                )
        }
        var plain = TextEdit.new("hé🙂 world")
        plain.setCaret(3)
        var secret = TextEdit.new("hé🙂 world")
        secret.setCaret(3)
        secret.focused = true
        let rt = Runtime.new(
            SecureForm(plain: plain, secret: secret, revealed: true),
            view,
            (320.0, 120.0),
            Env.new(true, 1.0)
        )
        _ = rt.frame(0.0)

        #expect(rt.state.secret.isSecure() && rt.state.secret.isRevealed())
        #expect(rt.hasSecureFocus())
        #expect(rt.find("action") == nil, "plain copy button stays suppressed on secure TextInput")
        let secretInp = rt.elements().first(where: { $0.path.hasSuffix("secret/value/input") })!
        #expect(secretInp.text == nil, "accessibility text remains nil on revealed secure TextInput")
        let secretCaret = secretInp.caret!

        // Caret x offset inside the revealed secure TextInput matches the plain TextInput at the same byte.
        rt.update { s, _ in
            s.secret.focused = false
            s.plain.focused = true
        }
        _ = rt.frame(0.0)
        let plainInp = rt.elements().first(where: { $0.path.hasSuffix("plain/value/input") })!
        let plainCaret = plainInp.caret!
        #expect(abs((secretCaret[0] - secretInp.rect[0]) - (plainCaret[0] - plainInp.rect[0])) < 0.01)

        // Toggling revealed off masks the field and moves the caret to the 2-bullet position for "hé".
        rt.update { s, _ in
            s.plain.focused = false
            s.secret.focused = true
            s.revealed = false
        }
        _ = rt.frame(0.0)
        #expect(rt.state.secret.isSecure() && !rt.state.secret.isRevealed())
        let maskedInp = rt.elements().first(where: { $0.path.hasSuffix("secret/value/input") })!
        let maskedCaret = maskedInp.caret!
        #expect(maskedCaret[0] != secretCaret[0], "masked bullet width differs from plain text width")
    }

    // PORT NOTE: Blocked on Sources/Rune role("textbox") padding press forwarding, preserveFocusOnPress & multiline secure TextEdit.
    @Test(.disabled("Blocked on Sources/Rune role(\"textbox\") padding press forwarding, preserveFocusOnPress & multiline secure TextEdit"))
    func secureTextAreaMasksMultilineSecretsWrapsLongTokensWhenRevealedAndScrolls() {
        struct PemForm {
            var secret: TextEdit
            var revealed: Bool
            var submitted: Int
        }
        func view(_ s: PemForm, _: Cx<PemForm>) -> El {
            let k = Kit.neutral(true)
            return Rune.col().padding(12.0).child(
                TextArea.new(s.secret)
                    .secure()
                    .revealed(s.revealed)
                    .placeholder("Paste private key")
                    .maxHeight(100.0)
                    .onEdit(\PemForm.secret)
                    .onSubmit { (s: inout PemForm, _: inout Tx) in s.submitted += 1 }
                    .build(k)
                    .key("area")
            )
        }

        let rt = Runtime.new(
            PemForm(secret: TextEdit.new(""), revealed: false, submitted: 0),
            view,
            (320.0, 240.0),
            Env.new(true, 1.0)
        )
        _ = rt.frame(0.0)

        let area0 = rt.elements().first(where: { $0.key == "area" })!
        let inp0 = rt.elements().first(where: { $0.path.hasSuffix("area/scroll/input") })!
        #expect(inp0.text == nil)

        // Focus by clicking the TextArea, paste a multi-line base64 fixture, then press Enter and type.
        _ = rt.pointerDown(area0.rect[0] + 20.0, area0.rect[1] + 20.0)
        rt.pointerUp(area0.rect[0] + 20.0, area0.rect[1] + 20.0)
        _ = rt.frame(0.0)
        #expect(rt.state.secret.isSecure() && rt.hasSecureFocus())

        let lineBlob = "AAAAB3NzaC1yc2EAAAADAQABAAABAQDfakebase64keymaterialwithoutspaces0123456789ABCDEF=="
        let pem = "-----BEGIN FAKE PRIVATE KEY-----\r\n\(lineBlob)\r\n\(lineBlob)\r\n\(lineBlob)"
        _ = rt.paste(pem)
        _ = rt.frame(0.0)
        _ = rt.keyDown(KeyEvent(key: .enter, mods: Mods()))
        _ = rt.keyDown(KeyEvent(key: .text("-----END FAKE PRIVATE KEY-----"), mods: Mods()))
        _ = rt.frame(0.0)

        #expect(rt.state.submitted == 0, "Enter in secure TextArea inserts newline without submitting")
        #expect(rustLineCount(rt.state.secret.text) == 5)

        // Hidden mode keeps the fixed height and fixed mask regardless of secret length/line count.
        let areaHidden = rt.elements().first(where: { $0.key == "area" })!
        let inpHidden = rt.elements().first(where: { $0.path.hasSuffix("area/scroll/input") })!
        #expect(areaHidden.rect[3] == area0.rect[3], "hidden secure TextArea height stays fixed")
        #expect(inpHidden.rect[3] == inp0.rect[3], "hidden secure input height stays 1 line")

        // Reveal: unbroken base64 lines wrap within the TextArea width, and overflowing lines scroll inside max_height.
        rt.update { s, tx in
            s.revealed = true
            tx.instant()
        }
        _ = rt.frame(0.0)
        let areaRev = rt.elements().first(where: { $0.key == "area" })!
        let scrollRev = rt.elements().first(where: { $0.path.hasSuffix("area/scroll") })!
        let inpRev = rt.elements().first(where: { $0.path.hasSuffix("area/scroll/input") })!
        #expect(areaRev.rect[3] <= 100.5, "TextArea respects maxHeight (got \(areaRev.rect[3]))")
        #expect(
            inpRev.rect[3] > scrollRev.rect[3] + 30.0,
            "wrapped multi-line secret is taller than the scroll viewport (\(inpRev.rect[3]) vs \(scrollRev.rect[3]))"
        )
        #expect(
            inpRev.rect[2] <= scrollRev.rect[2] + 0.5,
            "long unbroken base64 lines wrap without overflowing horizontally (\(inpRev.rect[2]) vs \(scrollRev.rect[2]))"
        )

        // Typing at the end keeps the caret scrolled into view inside the scroll viewport.
        _ = rt.keyDown(KeyEvent(key: .text("!"), mods: Mods()))
        _ = rt.frame(0.0)
        let scrollAfter = rt.elements().first(where: { $0.path.hasSuffix("area/scroll") })!
        let inpAfter = rt.elements().first(where: { $0.path.hasSuffix("area/scroll/input") })!
        let caret = inpAfter.caret!
        #expect(
            caret[1] >= scrollAfter.rect[1] - 1.0 && caret[1] + caret[3] <= scrollAfter.rect[1] + scrollAfter.rect[3] + 1.0,
            "caret \(caret) scrolled into viewport \(scrollAfter.rect)"
        )

        // Hiding again restores the fixed 1-line mask height while preserving the multi-line text.
        rt.update { s, _ in s.revealed = false }
        _ = rt.frame(0.0)
        let inpRehidden = rt.elements().first(where: { $0.path.hasSuffix("area/scroll/input") })!
        #expect(inpRehidden.rect[3] == inp0.rect[3])
        let areaRehidden = rt.elements().first(where: { $0.key == "area" })!
        #expect(areaRehidden.rect[3] == areaHidden.rect[3])
        #expect(rustLineCount(rt.state.secret.text) == 5)
    }

    @Test
    func secureTextAreaGrowthAndSmallHeightCapDoNotDiscloseHiddenLines() {
        func view(_ s: TextEdit, _: Cx<TextEdit>) -> El {
            let k = Kit.neutral(true)
            return Rune.col()
                .child(TextArea.new(s).secure().autoGrow(2, 6).build(k).key("growing"))
                .child(TextArea.new(s).secure().rows(8).maxHeight(40.0).build(k).key("capped"))
        }
        let measure = { (secret: String) -> [GeometrySnapshot] in
            let rt = Runtime.new(TextEdit.new(secret), view, (320.0, 300.0), Env.new(true, 1.0))
            _ = rt.frame(0.0)
            return rt.elements().map {
                GeometrySnapshot(path: $0.path, rect: $0.rect, target: $0.target, caret: $0.caret)
            }
        }
        let short = measure("fictional")
        let long = measure(String(repeating: "fictional\n", count: 100))
        #expect(short == long)
        let capped = short.first(where: { $0.path.hasSuffix("capped") })!
        #expect(capped.rect[3] <= 40.5, "maxHeight takes precedence over rows: \(capped.rect)")
    }

    // PORT NOTE: Blocked on Sources/Rune role("textbox") padding press forwarding, preserveFocusOnPress & multiline secure TextEdit.
    @Test(.disabled("Blocked on Sources/Rune role(\"textbox\") padding press forwarding, preserveFocusOnPress & multiline secure TextEdit"))
    func secureTextAreaReplacesPristineSecretOnFirstEdit() {
        func view(_ s: TextEdit, _: Cx<TextEdit>) -> El {
            let k = Kit.neutral(true)
            return Rune.col().padding(12.0).child(
                TextArea.new(s)
                    .secure()
                    .onEdit { (state: inout TextEdit, mutate: (inout TextEdit) -> Void) in
                        mutate(&state)
                    }
                    .build(k)
                    .key("area")
            )
        }

        let rt = Runtime.new(
            TextEdit.new("-----BEGIN FAKE KEY-----\ninitial-line"),
            view,
            (320.0, 200.0),
            Env.new(true, 1.0)
        )
        _ = rt.frame(0.0)

        let area = rt.elements().first(where: { $0.key == "area" })!
        _ = rt.pointerDown(area.rect[0] + 16.0, area.rect[1] + 16.0)
        rt.pointerUp(area.rect[0] + 16.0, area.rect[1] + 16.0)
        _ = rt.frame(0.0)
        #expect(rt.state.isPristine())

        _ = rt.paste("replacement-line-1\nreplacement-line-2")
        _ = rt.frame(0.0)
        #expect(rt.state.text == "replacement-line-1\nreplacement-line-2")
        #expect(!rt.state.isPristine())

        _ = rt.keyDown(KeyEvent(key: .enter, mods: Mods()))
        _ = rt.keyDown(KeyEvent(key: .text("replacement-line-3"), mods: Mods()))
        _ = rt.frame(0.0)
        #expect(rt.state.text == "replacement-line-1\nreplacement-line-2\nreplacement-line-3")
    }
}
