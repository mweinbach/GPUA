// Tests ported from: crates/rune/src/runtime/tests/secure_text.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import RuneMotion
import Testing
@testable import Rune

@Suite struct RtSecureTextTests {
    @Test
    func secureInputMasksInspectorClipboardImeAndEventLog() {
        var initEdit = TextEdit("hé🙂").secure()
        initEdit.focused = true

        let rt = Runtime.new(initEdit, { edit, _ in
            var inp = textInput(edit, TextStyle.new(16.0, 400.0))
                .key("secret")
                .size(200.0, 40.0)
                .singleLine(true)
            inp.input?.edit.setSingleLine(true)
            return col().size(200.0, 40.0).child(inp)
        }, (200.0, 40.0), Env.new(true, 1.0))
        rt.bindEdit("secret", EditAccess { ed, mutate in mutate(&ed) })

        _ = rt.frame(0.0)
        rt.focus("secret")
        _ = rt.frame(0.0)

        let secFocus = rt.hasSecureFocus()
        #expect(secFocus)
        let imeArea = rt.imeCursorArea()
        #expect(imeArea == nil)
        let allTextsNil = rt.elements().allSatisfy { $0.text == nil }
        #expect(allTextsNil)

        let secretContent = rt.nodes.first { $0.key == "secret" }?.textSpec?.content
        #expect(secretContent == "•••")

        // Step left by one grapheme (`🙂` -> byte index 3) and paste cleanly into secure field
        _ = rt.keyDown(KeyEvent(key: .left, mods: Mods()))
        _ = rt.frame(0.0)
        let focusBeforePaste = rt.state.focus
        #expect(focusBeforePaste == 3)
        _ = rt.paste("界")
        _ = rt.frame(0.0)
        let afterPaste = rt.state.text
        #expect(afterPaste == "hé界🙂")

        // Cmd+A + Cmd+C writes nothing to clipboard when unrevealed
        _ = rt.keyDown(KeyEvent(key: .command(Character("a")), mods: Mods(cmd: true)))
        _ = rt.frame(0.0)
        _ = rt.keyDown(KeyEvent(key: .command(Character("c")), mods: Mods(cmd: true)))
        _ = rt.frame(0.0)
        let clipWrite = rt.takeClipboardWrite()
        #expect(clipWrite == nil)

        // IME commits are ignored while secure field has focus
        _ = rt.ime(.commit("ignored"))
        _ = rt.frame(0.0)
        let afterIme = rt.state.text
        #expect(afterIme == "hé界🙂")

        // Typing into secure field never logs plaintext in eventLog
        _ = rt.keyDown(KeyEvent(key: .text("Z"), mods: Mods()))
        _ = rt.frame(0.0)
        let events = rt.eventMarkers()
        #expect(events.allSatisfy { !$0.detail.contains("hé") && !$0.detail.contains("Z") })
    }

    @Test
    func exitingSecureFieldAndMultiLineMaskLeaveNoSecretBehind() {
        struct CardState {
            var pw: TextEdit
            var open: Bool
        }
        let rt = Runtime.new(
            CardState(pw: TextEdit("hunter2").secure(), open: true),
            { s, _ in
                var root = col().key("root").size(200.0, 100.0)
                if s.open {
                    let inp = textInput(s.pw, TextStyle.new(14.0, 400.0))
                        .key("pw")
                        .size(200.0, 40.0)
                        .singleLine(true)
                        .transition(.opacity())
                    root = root.child(inp)
                }
                return root
            },
            (200.0, 100.0),
            Env.new(true, 2.0)
        )

        _ = rt.frame(0.0)
        rt.update { s, _ in
            s.pw = TextEdit("").secure()
            s.open = false
        }
        _ = rt.frame(1.0 / 60.0)
        let hasExiting = !rt.exitingNodes.isEmpty
        #expect(hasExiting)
        let exitingTexts = rt.exitingNodes.compactMap { $0.textSpec?.content }
        #expect(exitingTexts == [String(repeating: "•", count: 7)])
        let elTexts = rt.elements().compactMap { $0.text }
        #expect(elTexts.allSatisfy { !$0.contains("hunter2") })

        // Multi-line secure `TextEdit` uses fixed `MULTILINE_SECURE_MASK` regardless of secret length
        var shortEdit = TextEdit("ab\ncd").secure()
        shortEdit.setSingleLine(false)
        var longEdit = TextEdit(String(repeating: "secret-line\n", count: 200)).secure()
        longEdit.setSingleLine(false)
        let (shortShown, _) = shortEdit.display()
        let (longShown, _) = longEdit.display()
        #expect(shortShown == MULTILINE_SECURE_MASK)
        #expect(longShown == MULTILINE_SECURE_MASK)
        #expect(shortShown.count == 12)
    }

    @Test
    func redactedStaticTextConcealsInspectorSelectionAndExit() {
        let rt = Runtime.new(true, { shown, _ in
            var root = col().size(200.0, 80.0)
            if shown {
                var secret = text("hunter2").font(TextStyle.new(16.0, 400.0)).key("sec").transition(.opacity())
                secret.textSpec?.value.redacted = true
                secret.textSpec?.value.selectable = true
                root = root.child(secret)
            }
            return root
        }, (200.0, 80.0), Env.new(true, 1.0))

        _ = rt.frame(0.0)
        let info = rtElement(rt, "sec")!
        #expect(info.text == nil)
        let isSec = rt.elementIsSecure(info.path)
        #expect(isSec)

        rt.update { shown, _ in shown = false }
        _ = rt.frame(1.0 / 60.0)
        let exitingNoLeak = rt.exitingNodes.allSatisfy { ($0.textSpec?.content ?? "").contains("hunter2") == false }
        #expect(exitingNoLeak)
    }
}
