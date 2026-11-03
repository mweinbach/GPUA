// Tests ported from: crates/rune/src/runtime/tests/input_clipboard.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

@testable import Rune
import RuneMotion
import Testing

@Suite
struct RtInputClipboardTests {
    @Test
    func pageDownAndPageUpScrollNearestScrollableAncestorByNinetyPercent() {
        struct PageState {
            var seenKeys: [Key] = []
        }

        let rt: Runtime<PageState> = Runtime.new(PageState(), { _, _ in
            let items = (0..<30).map { i in el().key("item-\(i)").wFull().h(40.0).bg(.WHITE) }
            let focusTarget = el()
                .key("btn")
                .size(80.0, 30.0)
                .focusable(true)
                .onKey { (s: inout PageState, ev, _) in
                    s.seenKeys.append(ev.key)
                    return false
                }
            return col()
                .key("scroll")
                .size(200.0, 200.0)
                .scroll(ScrollSpec(stickBottom: false))
                .child(focusTarget)
                .children(items)
        }, (200.0, 200.0), Env.new(true, 1.0))

        _ = rt.frame(0.0)
        rt.update { _, tx in tx.focus("btn") }
        _ = rt.frame(1.0 / 120.0)
        #expect(rt.focused() == "btn")

        _ = rt.keyDown(KeyEvent(key: .pageDown))
        rtStepFrames(rt, 90)
        #expect(rt.state.seenKeys == [.pageDown])
        #expect(abs(rt.scrollOffset("scroll") - 180.0) < 2.0)

        _ = rt.keyDown(KeyEvent(key: .pageUp))
        rtStepFrames(rt, 90)
        #expect(rt.state.seenKeys == [.pageDown, .pageUp])
        #expect(abs(rt.scrollOffset("scroll") - 0.0) < 2.0)
    }

    @Test
    func pageDownPagesFocusedFieldsColumnEvenWhenPointerHoversSiblingColumn() {
        let rt: Runtime<TextEdit> = Runtime.new(TextEdit("hi"), { edit, _ in
            let makeRows = { (prefix: String) -> [El] in
                (0..<20).map { i in el().key("\(prefix)-\(i)").wFull().h(40.0) }
            }
            let left = col()
                .key("left")
                .size(120.0, 200.0)
                .scroll(ScrollSpec(stickBottom: false))
                .child(textInput(edit, TextStyle(size: 14.0, weight: 400.0)).key("field").wFull().h(28.0))
                .children(makeRows("l"))
            let right = col()
                .key("right")
                .size(120.0, 200.0)
                .scroll(ScrollSpec(stickBottom: false))
                .children(makeRows("r"))
            return row().size(240.0, 200.0).child(left).child(right)
        }, (240.0, 200.0), Env.new(true, 1.0))

        _ = rt.frame(0.0)
        rtClick(rt, "field")
        _ = rt.frame(1.0 / 120.0)
        #expect(rt.focused() == "field")

        // Move pointer over the right scroll column, then press PageDown
        rt.pointerMove(180.0, 100.0)
        _ = rt.keyDown(KeyEvent(key: .pageDown))
        rtStepFrames(rt, 90)

        #expect(abs(rt.scrollOffset("left") - 180.0) < 2.0)
        #expect(rt.scrollOffset("right") == 0.0)
    }

    @Test
    func singleLineInputScrollsHorizontallyWithCaretAndResetsOnBlur() {
        let longText = "abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        var initial = TextEdit(longText)
        let endByte = longText.utf8.count
        initial.anchor = endByte
        initial.focus = endByte

        let rt: Runtime<TextEdit> = Runtime.new(initial, { edit, _ in
            var field = textInput(edit, TextStyle(size: 14.0, weight: 400.0, family: .mono)).key("field").size(100.0, 28.0)
            field.input?.singleLine = true
            field.textSpec?.value.wrap = false
            return col()
                .size(200.0, 80.0)
                .child(field)
                .child(el().key("other").size(60.0, 24.0).focusable(true))
        }, (200.0, 80.0), Env.new(true, 1.0))

        _ = rt.frame(0.0)
        rt.update { _, tx in tx.focus("field") }
        _ = rt.frame(1.0 / 120.0)

        let scrolledX = rt.inputScrollOffsets["root/field"] ?? 0.0
        #expect(scrolledX > 10.0)
        if let ime = rt.imeCursorArea() {
            #expect(ime[0] >= 0.0 && ime[0] <= 100.0)
        } else {
            Issue.record("Expected non-nil imeCursorArea for focused field")
        }

        // Blurring resets horizontal scroll offset back to 0
        rt.update { _, tx in tx.focus("other") }
        _ = rt.frame(1.0 / 120.0)
        #expect((rt.inputScrollOffsets["root/field"] ?? 0.0) == 0.0)
    }

    @Test
    func multiGraphemeClustersAdvanceCleanlyByArrowKeys() {
        let sample = "👨‍👩‍👧‍👦🇺🇸👍🏽e\u{0301}Z"
        var initial = TextEdit(sample)
        initial.anchor = 0
        initial.focus = 0

        let rt: Runtime<TextEdit> = Runtime.new(initial, { edit, _ in
            var field = textInput(edit, TextStyle(size: 16.0, weight: 400.0)).key("field").size(240.0, 32.0)
            field.input?.singleLine = true
            return col().size(240.0, 60.0).child(field)
        }, (240.0, 60.0), Env.new(true, 1.0))

        _ = rt.frame(0.0)
        rt.update { _, tx in tx.focus("field") }
        _ = rt.frame(1.0 / 120.0)

        var stops: [Int] = [rt.state.focus]
        for _ in 0..<5 {
            _ = rt.keyDown(KeyEvent(key: .right))
            _ = rt.frame(1.0 / 120.0)
            stops.append(rt.state.focus)
        }
        #expect(stops.first == 0)
        #expect(stops.last == sample.utf8.count)
        for i in 1..<stops.count {
            #expect(stops[i] > stops[i - 1])
            let validBoundary = String(decoding: sample.utf8.prefix(stops[i]), as: UTF8.self).utf8.count == stops[i]
            #expect(validBoundary)
        }
    }

    @Test
    func pasteAndClipboardWritesConsumeCleanlyIncludingSecrets() {
        // PORT NOTE: Host clipboard integration on `main` uses `rt.paste(_:)` and `rt.takeClipboardWrite()`
        // (`ClipboardWrite.text` / `.secret(SecretCopy)`).
        struct ClipState {
            var edit: TextEdit = TextEdit("")
        }

        let rt: Runtime<ClipState> = Runtime.new(ClipState(), { s, _ in
            col()
                .size(240.0, 120.0)
                .child(textInput(s.edit, TextStyle(size: 14.0, weight: 400.0)).key("field").size(200.0, 28.0))
                .child(
                    el().key("copy-btn").size(80.0, 28.0).onPress { (_: inout ClipState, tx) in
                        tx.copy("first")
                        tx.copy("second")
                    }
                )
                .child(
                    el().key("secret-btn").size(80.0, 28.0).onPress { (_: inout ClipState, tx) in
                        tx.copyWrite = .secret(SecretCopy(text: "hunter2", ttlSeconds: 20.0))
                    }
                )
        }, (240.0, 120.0), Env.new(true, 1.0))
        rt.bindEdit("field", EditAccess(\ClipState.edit))

        _ = rt.frame(0.0)
        rtClick(rt, "field")
        _ = rt.frame(1.0 / 120.0)
        let pasted = rt.paste("hello clipboard")
        #expect(pasted)
        _ = rt.frame(1.0 / 120.0)
        #expect(rt.state.edit.text == "hello clipboard")

        // Later write in the same handler wins and `takeClipboardWrite()` consumes once
        rtClick(rt, "copy-btn")
        #expect(rt.takeClipboardWrite() == .text("second"))
        #expect(rt.takeClipboardWrite() == nil)

        rtClick(rt, "secret-btn")
        #expect(rt.takeClipboardWrite() == .secret(SecretCopy(text: "hunter2", ttlSeconds: 20.0)))
        #expect(rt.takeClipboardWrite() == nil)
    }
}
