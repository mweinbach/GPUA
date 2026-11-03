// Tests ported from: crates/rune/src/edit/tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

func editTestKey(_ key: Key) -> KeyEvent {
    KeyEvent(key: key, mods: Mods())
}

func editTestCmd(_ c: Character) -> KeyEvent {
    KeyEvent(key: .command(c), mods: Mods(cmd: true))
}

func editTestChord(_ s: String, _ mods: Mods) -> KeyEvent {
    KeyEvent(key: .text(s), mods: mods)
}

func editTestUndo(_ e: inout TextEdit, _ redo: Bool) {
    _ = e.key(KeyEvent(key: .command("z"), mods: Mods(shift: redo, cmd: true)), nil)
}

func editTestHash(_ e: TextEdit) -> Int {
    var hasher = Hasher()
    e.hash(into: &hasher)
    return hasher.finalize()
}

/// The text under each range of `mark`.
func editTestMarked(_ e: TextEdit, _ mark: Mark) -> [String] {
    e.marks()
        .filter { $0.mark == mark }
        .map { editUtf8Slice(e.text, $0.start..<$0.end) }
}

/// What every edit path must leave behind.
func assertEditInvariants(
    _ e: TextEdit,
    _ ctx: String,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let t = e.text
    let bytes = Array(t.utf8)
    let lines = 1 + bytes.reduce(0) { $0 + ($1 == UInt8(ascii: "\n") ? 1 : 0) }
    #expect(e.blocks().count == lines, "\(ctx): one block per line", sourceLocation: sourceLocation)
    #expect(
        e.blocks().allSatisfy { b in
            guard let l = b.listLevel() else { return true }
            return l <= MAX_LIST_LEVEL
        },
        "\(ctx): list levels",
        sourceLocation: sourceLocation
    )
    let sb = e.softBreaks()
    if sb.count >= 2 {
        for i in 0..<(sb.count - 1) {
            #expect(sb[i] < sb[i + 1], "\(ctx): soft breaks sorted", sourceLocation: sourceLocation)
        }
    }
    #expect(
        sb.allSatisfy { $0 > 0 && Int($0) < lines },
        "\(ctx): soft breaks in range",
        sourceLocation: sourceLocation
    )
    #expect(
        editIsCharBoundary(bytes, e.anchor) && editIsCharBoundary(bytes, e.focus),
        "\(ctx): caret on a char boundary",
        sourceLocation: sourceLocation
    )
    let ms = e.marks()
    if ms.count >= 2 {
        for i in 0..<(ms.count - 1) {
            #expect(ms[i].start <= ms[i + 1].start, "\(ctx): marks sorted", sourceLocation: sourceLocation)
        }
    }
    for m in ms {
        #expect(m.start < m.end && m.end <= bytes.count, "\(ctx): mark \(m) in range", sourceLocation: sourceLocation)
        #expect(
            editIsCharBoundary(bytes, m.start) && editIsCharBoundary(bytes, m.end),
            "\(ctx): mark \(m) on char boundaries",
            sourceLocation: sourceLocation
        )
        for line in e.lineOfByte(m.start)...e.lineOfByte(m.end - 1) {
            #expect(
                e.blocks()[line] != .code,
                "\(ctx): mark \(m) reaches code line \(line)",
                sourceLocation: sourceLocation
            )
        }
    }
    for i in ms.indices {
        let a = ms[i]
        for b in ms[(i + 1)...] {
            if a.mark.sameKind(b.mark) {
                #expect(b.start >= a.end, "\(ctx): same-kind marks \(a) \(b) overlap", sourceLocation: sourceLocation)
                #expect(
                    !(b.start == a.end && a.mark == b.mark),
                    "\(ctx): equal marks \(a) \(b) not merged",
                    sourceLocation: sourceLocation
                )
            }
        }
    }
}

@Suite("EditTests")
struct EditTests {
    @Test("is_command matches any character and both forms of Cmd+Space")
    func isCommandMatchesAnyCharacterAndBothFormsOfCmdSpace() {
        let cmd = Mods(cmd: true)
        let ev = { (key: Key, mods: Mods) in KeyEvent(key: key, mods: mods) }
        #expect(ev(.command(","), cmd).isCommand(","))
        #expect(ev(.command("1"), cmd).isCommand("1"))
        #expect(ev(.command("k"), cmd).isCommand("K"))
        #expect(ev(.command("z"), Mods(shift: true, cmd: true)).isCommand("z"))
        #expect(!ev(.command("k"), cmd).isCommand("j"))
        #expect(ev(.text(" "), cmd).isCommand(" "))
        #expect(ev(.command(" "), cmd).isCommand(" "))
        #expect(!ev(.text(" "), Mods()).isCommand(" "))
        #expect(!ev(.text("k"), Mods()).isCommand("k"))
    }

    @Test("secure unicode editing has no history or export")
    func secureUnicodeEditingHasNoHistoryOrExport() {
        var e = TextEdit.new("hé🙂")
        e.insert("x")
        e.setSecure(true)
        #expect(e.historyStorage.undo.isEmpty)
        #expect(e.display().0 == "••••")
        for (model, display) in [(0, 0), (1, 3), (3, 6), (7, 9), (8, 12)] {
            #expect(e.displayIndex(model) == display)
            #expect(e.modelIndex(display) == model)
        }
        e.anchor = 1
        e.focus = 7
        for command: Character in ["c", "x", "z"] {
            #expect(e.key(editTestKey(.command(command)), nil).copy == nil)
            #expect(e.text == "hé🙂x")
        }
        _ = e.paste("界")
        #expect(e.text == "h界x" && e.anchor == 4 && e.focus == 4)
        _ = e.ime(.preedit("composition", nil))
        _ = e.ime(.commit("commit"))
        #expect(e.preedit == nil)
        #expect(e.text == "h界x")
        e.undo()
        e.redo()
        #expect(e.text == "h界x")
        #expect(e.historyStorage.undo.isEmpty && e.historyStorage.redo.isEmpty)
        #expect(!String(reflecting: e).contains("h界x"))
        e.clear()
        #expect(e.isSecure())
    }

    @Test("secure revealed uses plain display and words while keeping protections")
    func secureRevealedUsesPlainDisplayAndWordsWhileKeepingProtections() {
        var e = TextEdit.new("hé🙂 world").secure()
        let hiddenHash = editTestHash(e)
        #expect(!e.isRevealed())
        #expect(e.display().0 == "•••••••••")
        // Hidden secure fields treat the masked string as a single word.
        let altLeft = KeyEvent(key: .left, mods: Mods(alt: true))
        let altRight = KeyEvent(key: .right, mods: Mods(alt: true))
        e.setCaret(e.text.utf8.count)
        _ = e.key(altLeft, nil)
        #expect(e.focus == 0)
        _ = e.key(altRight, nil)
        #expect(e.focus == e.text.utf8.count)

        e.setSelection(1, 7)
        e.setRevealed(true)
        #expect(e.isSecure() && e.isRevealed())
        #expect(editTestHash(e) != hiddenHash, "Hash for TextEdit must include revealed")
        #expect(e.anchor == 1 && e.focus == 7, "toggling revealed preserves selection")
        let disp = e.display()
        #expect(disp.0 == "hé🙂 world" && disp.1 == nil)
        for idx in [0, 1, 3, 7, 8, 13] {
            #expect(e.displayIndex(idx) == idx)
            #expect(e.modelIndex(idx) == idx)
        }
        // Revealed secure fields step over words normally.
        e.setCaret(e.text.utf8.count)
        _ = e.key(altLeft, nil)
        #expect(e.focus == 8)
        _ = e.key(altLeft, nil)
        #expect(e.focus == 0)
        _ = e.key(altRight, nil)
        #expect(e.focus == 7)

        // Copy, cut, undo, redo and IME remain blocked when revealed.
        e.setSelection(1, 7)
        for command: Character in ["c", "x", "z"] {
            #expect(e.key(editTestKey(.command(command)), nil).copy == nil)
            #expect(e.text == "hé🙂 world")
        }
        _ = e.key(editTestKey(.text("!")), nil)
        #expect(e.text == "h! world")
        #expect(!e.hasHistory())
        editTestUndo(&e, false)
        e.undo()
        e.redo()
        #expect(e.text == "h! world")
        _ = e.ime(.preedit("comp", (0, 4)))
        _ = e.ime(.commit("commit"))
        #expect(e.preedit == nil)
        #expect(e.text == "h! world")
        let dbg = String(reflecting: e)
        #expect(!dbg.contains("h! world") && !dbg.contains("world") && dbg.contains("[redacted]"))

        // Toggling revealed off again preserves text and selection.
        e.setSelection(2, 8)
        e.setRevealed(false)
        #expect(e.text == "h! world" && e.anchor == 2 && e.focus == 8)
        #expect(e.display().0 == "••••••••")

        // Conceal wipes a revealed field to bullets and clears revealed.
        var exiting = TextEdit.new("hunter2").secure().revealed(true)
        exiting.conceal()
        #expect(exiting.isSecure() && !exiting.isRevealed())
        #expect(exiting.text == "•••••••")
        #expect(exiting.display().0 == "•••••••")
    }

    @Test("hidden multiline navigation and edits have no invisible interior")
    func hiddenMultilineNavigationAndEditsHaveNoInvisibleInterior() {
        var e = TextEdit.new("first\nlast").secure()
        e.setSingleLine(false)
        for key: Key in [.left, .right, .up, .down, .home, .end] {
            e.setCaret(2)
            _ = e.key(editTestKey(key), nil)
            #expect(e.range() == (e.text.utf8.count, e.text.utf8.count))
            _ = e.key(KeyEvent(key: key, mods: Mods(shift: true)), nil)
            #expect(e.range() == (0, e.text.utf8.count))
        }
        #expect(e.isPristine(), "navigation keys do not clear pristine")
        e.markEdited()
        e.setCaret(2)
        _ = e.key(editTestKey(.text("!")), nil)
        #expect(e.text == "first\nlast!")
        e.setCaret(2)
        _ = e.key(editTestKey(.backspace), nil)
        #expect(e.text == "first\nlast")
        _ = e.key(editTestKey(.delete), nil)
        #expect(e.text == "first\nlast")
        e.setCaret(2)
        _ = e.paste("\r\nnext")
        #expect(e.text == "first\nlast\nnext")
        e.setSelection(1, 3)
        _ = e.paste("replacement\nlines")
        #expect(e.text == "replacement\nlines")
        e.setRevealed(true)
        e.setSelection(1, 3)
        e.setRevealed(false)
        e.setRevealed(true)
        #expect(e.range() == (1, 3), "toggle without editing preserves revealed selection")
    }

    @Test("pristine secure backspace at start and IME do not bypass protection")
    func pristineSecureBackspaceAtStartAndImeDoNotBypassProtection() {
        var e = TextEdit.new("fictional-secret").secure()
        e.setSingleLine(false)
        e.setCaret(0)
        _ = e.key(editTestKey(.backspace), nil)
        #expect(e.text.isEmpty)
        #expect(!e.hasHistory())
        e.replaceText("fictional-secret")
        _ = e.ime(.preedit("composition", nil))
        #expect(e.preedit == nil)
        #expect(e.isPristine())
        _ = e.ime(.commit("commit"))
        #expect(e.text == "fictional-secret", "secure inputs reject IME commits too")
        #expect(e.isPristine())
        _ = e.paste("replacement")
        #expect(e.text == "replacement")
        #expect(!e.isPristine())
        e.undo()
        #expect(e.text == "replacement")
        #expect(!e.hasHistory())
    }

    @Test("hidden multiline pristine replace and delete")
    func hiddenMultilinePristineReplaceAndDelete() {
        // 1. Typing while pristine replaces the whole value, regardless of caret or navigation.
        var e = TextEdit.new("existing-fictional-key\nline-two").secure()
        e.setSingleLine(false)
        #expect(e.isPristine())
        e.setCaret(0)
        for nav: Key in [.left, .right, .up, .down, .home, .end] {
            _ = e.key(editTestKey(nav), nil)
        }
        #expect(e.isPristine())
        _ = e.key(editTestKey(.text("a")), nil)
        #expect(e.text == "a")
        #expect(!e.isPristine())
        // Subsequent edits append and delete normally.
        _ = e.key(editTestKey(.text("b")), nil)
        #expect(e.text == "ab")
        _ = e.paste("cd")
        #expect(e.text == "abcd")
        _ = e.key(editTestKey(.backspace), nil)
        #expect(e.text == "abc")

        // 2. Pasting while pristine replaces the whole value, regardless of selection.
        var e2 = TextEdit.new("existing-fictional-key\nline-two").secure()
        e2.setSingleLine(false)
        e2.setSelection(3, 7)
        _ = e2.paste("new-key\nline-2")
        #expect(e2.text == "new-key\nline-2")
        #expect(!e2.isPristine())
        _ = e2.paste("\nline-3")
        #expect(e2.text == "new-key\nline-2\nline-3")

        // 3. Deletions while pristine empty the whole value, then subsequent typing starts fresh.
        let delEvents: [KeyEvent] = [
            editTestKey(.backspace),
            editTestKey(.delete),
            KeyEvent(key: .backspace, mods: Mods(cmd: true)),
            KeyEvent(key: .backspace, mods: Mods(alt: true)),
            KeyEvent(key: .text("k"), mods: Mods(ctrl: true)),
        ]
        #if os(macOS)
        let activeDelEvents = delEvents
        #else
        // Ctrl+K is an AppKit control binding on macOS only.
        let activeDelEvents = Array(delEvents.dropLast())
        #endif
        for del in activeDelEvents {
            var d = TextEdit.new("existing-fictional-key\nline-two").secure()
            d.setSingleLine(false)
            d.setCaret(4)
            _ = d.key(del, nil)
            #expect(d.text == "", "deletion \(del) must empty pristine hidden multiline")
            #expect(d.range() == (0, 0))
            #expect(!d.isPristine())
            _ = d.key(editTestKey(.text("x")), nil)
            _ = d.key(editTestKey(.text("y")), nil)
            #expect(d.text == "xy")
        }

        // 4. Toggling revealed (Show -> Hide) without editing keeps pristine; editing while revealed clears it.
        var e4 = TextEdit.new("existing-fictional-key\nline-two").secure()
        e4.setSingleLine(false)
        e4.setRevealed(true)
        e4.setSelection(2, 5)
        e4.setRevealed(false)
        #expect(e4.isPristine(), "Show then Hide without editing keeps pristine")
        e4.setCaret(e4.text.utf8.count)
        _ = e4.paste("pasted-after-peek")
        #expect(e4.text == "pasted-after-peek")

        var rev = TextEdit.new("existing-fictional-key").secure().revealed(true)
        rev.setSingleLine(false)
        rev.setCaret(rev.text.utf8.count)
        _ = rev.key(editTestKey(.text("!")), nil)
        #expect(rev.text == "existing-fictional-key!", "revealed field edits normally at caret")
        #expect(!rev.isPristine())
        rev.setRevealed(false)
        _ = rev.key(editTestKey(.text("?")), nil)
        #expect(rev.text == "existing-fictional-key!?", "edited while revealed stays non-pristine when hidden")

        // 5. App resetting via replaceText re-arms pristine, even for identical text.
        rev.replaceText("reloaded-from-vault")
        #expect(rev.isPristine())
        _ = rev.key(editTestKey(.text("z")), nil)
        #expect(rev.text == "z")
        #expect(!rev.isPristine())
        rev.replaceText("z")
        #expect(rev.isPristine(), "same-value app replacement re-arms pristine")
        _ = rev.paste("fresh")
        #expect(rev.text == "fresh")
        #expect(!rev.isPristine())

        // 6. Empty field is never pristine; single-line secure field never applies pristine replacement.
        var empty = TextEdit.new("").secure()
        empty.setSingleLine(false)
        #expect(!empty.isPristine())
        _ = empty.key(editTestKey(.text("a")), nil)
        _ = empty.key(editTestKey(.text("b")), nil)
        #expect(empty.text == "ab")

        var single = TextEdit.new("hunter2").secure()
        single.setSingleLine(true)
        single.setCaret(7)
        _ = single.key(editTestKey(.text("!")), nil)
        #expect(single.text == "hunter2!", "single-line secure field edits at caret")
    }

    @Test("multiline secure edit inserts newlines, keeps pasted lines, and masks to fixed length")
    func multilineSecureEditInsertsNewlinesKeepsPastedLinesAndMasksToFixedLength() {
        var e = TextEdit.new("").secure()
        e.setSingleLine(false)
        #expect(!e.isSingleLine && e.isHiddenMultiline)
        #expect(e.display().0 == "")
        #expect(e.displayIndex(0) == 0)

        _ = e.paste("-----BEGIN FAKE KEY-----\r\nAAAAB3NzaC1yc2E\tline2")
        #expect(e.text == "-----BEGIN FAKE KEY-----\nAAAAB3NzaC1yc2E\tline2")
        #expect(!e.key(editTestKey(.enter), nil).submit, "plain Enter in multi-line secure field inserts a newline")
        _ = e.key(editTestKey(.text("-----END FAKE KEY-----")), nil)
        #expect(e.text == "-----BEGIN FAKE KEY-----\nAAAAB3NzaC1yc2E\tline2\n-----END FAKE KEY-----")
        #expect(
            e.key(KeyEvent(key: .enter, mods: Mods(cmd: true)), nil).submit,
            "Cmd+Enter still submits a multi-line secure field"
        )

        var short = TextEdit.new("ten-bytes!").secure()
        short.setSingleLine(false)
        let longSecret = (0..<50)
            .map { i in
                let num = i < 10 ? "0\(i)" : "\(i)"
                return "FAKEKEYLINE\(num)AAAAB3NzaC1yc2EAAAADAQABAAABAQDfakebase64payloadblock0123456789ABCDEFGH=="
            }
            .joined(separator: "\n")
        #expect(longSecret.utf8.count >= 4096)
        var long = TextEdit.new(longSecret).secure()
        long.setSingleLine(false)

        let maskLen = MULTILINE_SECURE_MASK.utf8.count
        #expect(short.display().0 == MULTILINE_SECURE_MASK)
        #expect(long.display().0 == MULTILINE_SECURE_MASK)
        #expect(editTestHash(short) == editTestHash(long), "hidden multi-line hash must not leak length or line count")
        for offset in [0, 3, 10, 500, long.text.utf8.count] {
            #expect(long.displayIndex(offset) == maskLen)
            #expect(long.modelIndex(offset) == long.text.utf8.count)
        }
        #expect(long.displaySelectionRange(5, 5) == (0, 0))
        #expect(long.displaySelectionRange(2, 100) == (0, maskLen))

        // Concealing a multi-line secure field (hidden or revealed) leaves only the fixed mask.
        var exitingRevealed = long.revealed(true)
        exitingRevealed.conceal()
        #expect(exitingRevealed.isSecure() && !exitingRevealed.isRevealed())
        #expect(exitingRevealed.text == MULTILINE_SECURE_MASK)
        #expect(exitingRevealed.display().0 == MULTILINE_SECURE_MASK)
    }

    @Test("caret and backspace step over whole emoji")
    func caretAndBackspaceStepOverWholeEmoji() {
        let family = "👨\u{200D}👩\u{200D}👧"
        let flag = "🇯🇵"
        let wave = "👋🏽"
        let text = "a\(family)\(flag)\(wave)"
        var e = TextEdit.new(text)
        _ = e.key(editTestKey(.home), nil)
        var stops = [e.focus]
        for _ in 0..<5 {
            _ = e.key(editTestKey(.right), nil)
            stops.append(e.focus)
        }
        let ends = [
            0,
            1,
            1 + family.utf8.count,
            1 + family.utf8.count + flag.utf8.count,
            text.utf8.count,
            text.utf8.count,
        ]
        #expect(stops == ends)
        for want in ["a\(family)\(flag)", "a\(family)", "a"] {
            _ = e.key(editTestKey(.backspace), nil)
            #expect(e.text == want)
        }
    }

    @Test("history groups typing and restores unicode selection")
    func historyGroupsTypingAndRestoresUnicodeSelection() {
        var e = TextEdit.new("")
        for s in ["h", "é", "🙂"] {
            _ = e.key(editTestKey(.text(s)), nil)
        }
        editTestUndo(&e, false)
        #expect(e.text == "" && e.anchor == 0 && e.focus == 0)
        editTestUndo(&e, true)
        #expect(e.text == "hé🙂" && e.anchor == 7 && e.focus == 7)
        _ = e.key(editTestKey(.left), nil)
        _ = e.key(KeyEvent(key: .left, mods: Mods(shift: true)), nil)
        #expect(e.anchor == 3 && e.focus == 1)
        _ = e.paste("界\r\n日")
        #expect(e.text == "h界\n日🙂")
        editTestUndo(&e, false)
        #expect(e.text == "hé🙂" && e.anchor == 3 && e.focus == 1)
        editTestUndo(&e, true)
        #expect(e.text == "h界\n日🙂" && e.anchor == 8 && e.focus == 8)
        editTestUndo(&e, false)
        _ = e.key(editTestKey(.text("a")), nil)
        editTestUndo(&e, true)
        #expect(e.text == "ha🙂", "new edit discards the redo branch")
        editTestUndo(&e, false)
        #expect(e.text == "hé🙂" && e.anchor == 3 && e.focus == 1)
    }

    @Test("history deletion, cut, and IME are atomic")
    func historyDeletionCutAndImeAreAtomic() {
        var e = TextEdit.new("hé🙂")
        _ = e.key(editTestKey(.backspace), nil)
        editTestUndo(&e, false)
        #expect(e.text == "hé🙂" && e.anchor == 7 && e.focus == 7)
        _ = e.key(editTestKey(.home), nil)
        _ = e.key(editTestKey(.delete), nil)
        editTestUndo(&e, false)
        #expect(e.text == "hé🙂" && e.anchor == 0 && e.focus == 0)
        e.anchor = 3
        e.focus = 1
        let out = e.key(KeyEvent(key: .command("x"), mods: Mods()), nil)
        #expect(out.copy == "é")
        editTestUndo(&e, false)
        #expect(e.anchor == 3 && e.focus == 1)
        _ = e.ime(.preedit("に", nil))
        _ = e.ime(.preedit("日本", nil))
        _ = e.ime(.commit("日本"))
        #expect(e.text == "h日本🙂")
        editTestUndo(&e, false)
        #expect(e.text == "hé🙂" && e.anchor == 3 && e.focus == 1)
        #expect(e.preedit == nil)
        editTestUndo(&e, true)
        #expect(e.text == "h日本🙂")
        _ = e.ime(.preedit("x", nil))
        editTestUndo(&e, false)
        #expect(e.text == "h日本🙂", "undo cancels preedit without undoing committed text")
        #expect(e.preedit == nil)
    }

    @Test("history is bounded, shared, and cleared after send")
    func historyIsBoundedSharedAndClearedAfterSend() {
        var e = TextEdit.new("")
        for _ in 0..<(HISTORY_STEPS + 12) {
            _ = e.paste("é")
        }
        let rendered = e
        #expect(e.historyStorage === rendered.historyStorage)
        #expect(e.historyStorage.undo.count == HISTORY_STEPS)
        for _ in 0..<(HISTORY_STEPS + 1) {
            e.undo()
        }
        #expect(e.text == String(repeating: "é", count: 12))
        #expect(rendered.text == String(repeating: "é", count: HISTORY_STEPS + 12))
        _ = e.paste(String(repeating: "a", count: HISTORY_BYTES))
        #expect(e.historyStorage.bytes <= HISTORY_BYTES)
        #expect(e.historyStorage.undo.isEmpty, "one oversized edit drops history rather than retaining unbounded text")
        e.focused = true
        e.clear()
        e.undo()
        #expect(e.focused && e.text.isEmpty)
        _ = e.paste("draft")
        e.text = "external"
        e.anchor = e.text.utf8.count
        e.focus = e.anchor
        e.undo()
        #expect(e.text == "external", "external model replacement cannot restore stale history")
    }

    @Test("command chords type nothing")
    func commandChordsTypeNothing() {
        var e = TextEdit.new("pw").secure()
        _ = e.key(editTestChord(" ", Mods(shift: true, cmd: true, logo: true)), nil)
        _ = e.key(editTestChord("a", Mods(ctrl: true)), nil)
        #expect(e.text == "pw")
        var plain = TextEdit.new("")
        _ = plain.key(editTestChord(" ", Mods(cmd: true, logo: true)), nil)
        #if os(macOS)
        _ = plain.key(editTestChord("a", Mods(ctrl: true)), nil)
        #else
        _ = plain.key(editTestChord("a", Mods(cmd: true, ctrl: true)), nil)
        #endif
        #expect(plain.text == "")
    }

    #if !os(macOS)
    @Test("AltGr text still types")
    func altgrTextStillTypes() {
        var e = TextEdit.new("")
        _ = e.key(editTestChord("€", Mods(cmd: true, alt: true, ctrl: true)), nil)
        #expect(e.text == "€")
    }
    #endif

    @Test("option text still types")
    func optionTextStillTypes() {
        var e = TextEdit.new("").secure()
        _ = e.key(editTestChord("é", Mods(alt: true)), nil)
        _ = e.key(editTestChord("ø", Mods(shift: true, alt: true)), nil)
        #expect(e.text == "éø")
    }

    @Test("paste keeps single-line fields on one line")
    func pasteKeepsSingleLineFieldsOnOneLine() {
        var secure = TextEdit.new("").secure()
        var single = TextEdit.new("")
        single.setSingleLine(true)
        var multi = TextEdit.new("")
        _ = secure.paste("a\tb\r\nc\u{2028}d")
        _ = single.paste("a\tb\r\nc\u{2028}d")
        _ = multi.paste("a\tb\r\nc\u{2028}d")
        #expect(secure.text == "abcd")
        #expect(single.text == "abcd")
        #expect(multi.text == "a\tb\nc\u{2028}d")
        _ = single.ime(.commit("x\ny"))
        #expect(single.text == "abcdxy")
    }

    @Test("Shift+Enter in a single-line field submits without a line break")
    func shiftEnterInASingleLineFieldSubmitsWithoutALineBreak() {
        let shiftEnter = KeyEvent(key: .enter, mods: Mods(shift: true))
        var single = TextEdit.new("ab")
        single.setSingleLine(true)
        var secure = TextEdit.new("ab").secure()
        #expect(single.key(shiftEnter, nil).submit)
        _ = single.key(editTestKey(.text("\n")), nil)
        _ = single.key(editTestKey(.text("\r\nc")), nil)
        #expect(single.text == "abc")

        #expect(secure.key(shiftEnter, nil).submit)
        _ = secure.key(editTestKey(.text("\n")), nil)
        _ = secure.key(editTestKey(.text("\r\nc")), nil)
        #expect(secure.text == "abc")
    }

    @Test("command chord reaches on_key without mutating text")
    func commandChordReachesOnKey() {
        // PORT NOTE: Runtime.key is not yet wired in Sources/Rune/runtime.swift (outside scope);
        // verify directly on TextEdit + textInput that command chords pass through untyped while
        // plain characters edit the focused field.
        var pw = TextEdit.new("").secure()
        pw.focused = true
        let el = textInput(pw, TextStyle.new(14.0, 400.0)).singleLine().key("pw").size(200.0, 40.0)
        #expect(el.input?.singleLine == true)

        let cmdSpace = editTestChord(" ", Mods(shift: true, cmd: true, logo: true))
        var appKeys: [Key] = []
        if cmdSpace.isCommandChord() {
            _ = pw.key(cmdSpace, nil)
            appKeys.append(cmdSpace.key)
        }
        let plainX = editTestChord("x", Mods())
        if plainX.isCommandChord() {
            appKeys.append(plainX.key)
        } else {
            _ = pw.key(plainX, nil)
        }
        #expect(pw.text == "x")
        #expect(appKeys == [.text(" ")])
    }

    #if os(macOS)
    @Test("control letters edit like AppKit fields")
    func controlLettersEditLikeAppkitFields() {
        let ctrl = { (c: String) in KeyEvent(key: .text(c), mods: Mods(ctrl: true)) }
        var e = TextEdit.new("one two\nthree")
        e.set(4, false)
        _ = e.key(ctrl("a"), nil)
        #expect(e.focus == 0)
        _ = e.key(ctrl("e"), nil)
        #expect(e.focus == 7)
        _ = e.key(ctrl("b"), nil)
        _ = e.key(ctrl("b"), nil)
        #expect(e.focus == 5)
        _ = e.key(ctrl("f"), nil)
        #expect(e.focus == 6)
        _ = e.key(ctrl("h"), nil)
        #expect(e.text == "one to\nthree")
        _ = e.key(ctrl("d"), nil)
        #expect(e.text == "one t\nthree")
        e.set(0, false)
        _ = e.key(ctrl("k"), nil)
        #expect(e.text == "\nthree")
        _ = e.key(ctrl("k"), nil)
        #expect(e.text == "three", "at a line's end Ctrl-K joins the next line")
        _ = e.key(ctrl("n"), nil)
        #expect(e.focus == 5)
        _ = e.key(ctrl("x"), nil)
        #expect(e.text == "three", "other Control letters never type")
    }
    #endif

    @Test("typing, selection, and submit")
    func typingSelectionAndSubmit() {
        var e = TextEdit()
        _ = e.key(editTestKey(.text("héllo world")), nil)
        #expect(e.text == "héllo world")
        _ = e.key(KeyEvent(key: .backspace, mods: Mods(alt: true)), nil)
        #expect(e.text == "héllo ")
        _ = e.key(editTestKey(.left), nil)
        _ = e.key(KeyEvent(key: .left, mods: Mods(shift: true)), nil)
        #expect(e.selected() == "o")
        _ = e.key(editTestKey(.text("0")), nil)
        #expect(e.text == "héll0 ")
        _ = e.ime(.preedit("に", nil))
        #expect(e.display().0 == "héll0に ")
        _ = e.ime(.commit("日"))
        #expect(e.text == "héll0日 ")
        #expect(e.key(editTestKey(.enter), nil).submit)
        _ = e.key(KeyEvent(key: .enter, mods: Mods(shift: true)), nil)
        #expect(e.text.contains("\n"))
    }

    @Test("inline marks shift, split, inherit, and respect boundaries")
    func inlineMarksShiftSplitInheritAndRespectBoundaries() {
        var e = TextEdit.new("hello world")
        // Apply bold to "hello" (0..5).
        e.anchor = 0
        e.focus = 5
        e.toggleMark(.bold)
        #expect(e.hasMark(.bold))
        #expect(e.marks() == [MarkRange.new(0..<5, .bold)])

        // Caret at right edge of bold (index 5): inherits Bold on typing!
        e.set(5, false)
        #expect(e.hasMark(.bold))
        _ = e.key(editTestKey(.text("!")), nil)
        #expect(e.text == "hello! world")
        #expect(e.marks() == [MarkRange.new(0..<6, .bold)])

        // Caret at index 0 (start of bold run): does NOT inherit Bold.
        e.set(0, false)
        #expect(!e.hasMark(.bold))
        _ = e.key(editTestKey(.text(">")), nil)
        #expect(e.text == ">hello! world")
        #expect(e.marks() == [MarkRange.new(1..<7, .bold)])

        // Split Bold by toggling it off on "ll" (3..5).
        e.anchor = 3
        e.focus = 5
        #expect(e.hasMark(.bold))
        e.toggleMark(.bold)
        #expect(!e.hasMark(.bold))
        #expect(e.marks() == [MarkRange.new(1..<3, .bold), MarkRange.new(5..<7, .bold)])

        // Selecting across the gap (1..7) reports Bold is not active on the whole range,
        // so toggling Bold applies it to the whole selection and merges the runs.
        e.anchor = 1
        e.focus = 7
        #expect(!e.hasMark(.bold))
        e.toggleMark(.bold)
        #expect(e.hasMark(.bold))
        #expect(e.marks() == [MarkRange.new(1..<7, .bold)])

        // Code and Link marks do NOT inherit at the start of their run (index 8).
        e.anchor = 8
        e.focus = 13 // "world"
        e.toggleMark(.code)
        e.setLink("https://example.com")
        // Inside "world" (index 10): both Code and Link are active and inherited.
        e.set(10, false)
        #expect(e.hasMark(.code))
        #expect(e.activeLink() == "https://example.com")
        // At start of link/code run (index 8): neither Code nor Link is inherited.
        e.set(8, false)
        #expect(!e.hasMark(.code))
        #expect(e.activeLink() == nil)
        _ = e.key(editTestKey(.text("?")), nil)
        #expect(e.text == ">hello! ?world")
        #expect(
            e.marks() == [
                MarkRange.new(1..<7, .bold),
                MarkRange.new(9..<14, .code),
                MarkRange.new(9..<14, .link("https://example.com")),
            ]
        )
    }

    @Test("pending typing style and command shortcuts")
    func pendingTypingStyleAndCommandShortcuts() {
        var e = TextEdit.new("").rich()
        // Empty selection: Cmd+B sets pending Bold, Cmd+I sets pending Italic.
        _ = e.key(KeyEvent(key: .command("b"), mods: Mods(cmd: true)), nil)
        _ = e.key(KeyEvent(key: .command("i"), mods: Mods(cmd: true)), nil)
        #expect(e.hasMark(.bold))
        #expect(e.hasMark(.italic))

        _ = e.key(editTestKey(.text("hi")), nil)
        #expect(e.text == "hi")
        #expect(e.marks() == [MarkRange.new(0..<2, .bold), MarkRange.new(0..<2, .italic)])

        // Toggle Bold off on empty selection at index 2, then type " there".
        _ = e.key(KeyEvent(key: .command("b"), mods: Mods(cmd: true)), nil)
        #expect(!e.hasMark(.bold))
        #expect(e.hasMark(.italic))
        _ = e.key(editTestKey(.text(" there")), nil)
        #expect(e.text == "hi there")
        #expect(e.marks() == [MarkRange.new(0..<2, .bold), MarkRange.new(0..<8, .italic)])

        // Moving the caret clears pending typing style.
        e.toggleMark(.underline)
        #expect(e.hasMark(.underline))
        _ = e.key(editTestKey(.left), nil)
        #expect(!e.hasMark(.underline))
    }

    @Test("unicode emoji, CJK, and combining marks across boundaries")
    func unicodeEmojiCjkAndCombiningMarksAcrossBoundaries() {
        var e = TextEdit.new("🦀a\u{0301}日本語")
        // "🦀" is 0..4, "a\u{0301}" is 4..7, "日" is 7..10, "本" is 10..13, "語" is 13..16.
        e.anchor = 0
        e.focus = 4
        e.toggleMark(.bold)
        e.anchor = 4
        e.focus = 7
        e.toggleMark(.italic)
        e.anchor = 7
        e.focus = 13
        e.toggleMark(.strike)
        e.anchor = 10
        e.focus = 16
        e.toggleMark(.underline)

        // Insert CJK right at boundary between combining mark and CJK (byte 7).
        e.set(7, false)
        _ = e.key(editTestKey(.text("★")), nil) // 3 bytes, inherits Italic from 4..7
        #expect(e.text == "🦀a\u{0301}★日本語")
        #expect(
            e.marks() == [
                MarkRange.new(0..<4, .bold),
                MarkRange.new(4..<10, .italic),
                MarkRange.new(10..<16, .strike),
                MarkRange.new(13..<19, .underline),
            ]
        )

        // Delete across boundary ("★日", bytes 7..13).
        e.anchor = 7
        e.focus = 13
        _ = e.key(editTestKey(.backspace), nil)
        #expect(e.text == "🦀a\u{0301}本語")
        #expect(
            e.marks() == [
                MarkRange.new(0..<4, .bold),
                MarkRange.new(4..<7, .italic),
                MarkRange.new(7..<10, .strike),
                MarkRange.new(7..<13, .underline),
            ]
        )

        // Round-trip through HTML preserves exact Unicode mark boundaries.
        let html = e.toHtml()
        let rt = TextEdit.fromHtml(html)
        #expect(rt.text == e.text)
        #expect(rt.marks() == e.marks())
    }

    @Test("block attributes: lists, quotes, code, and keys")
    func blockAttributesListsQuotesCodeAndKeys() {
        var e = TextEdit.new("first").rich()
        e.setBlock(.bullet(0))
        #expect(e.currentBlock() == .bullet(0))

        // Return at end of non-empty list item creates a new Bullet(0) item.
        e.set(5, false)
        #expect(!e.key(editTestKey(.enter), nil).submit)
        #expect(e.text == "first\n")
        #expect(e.blocks() == [.bullet(0), .bullet(0)])

        // Tab indents the second list item to Bullet(1).
        _ = e.key(editTestKey(.tab), nil)
        #expect(e.blocks() == [.bullet(0), .bullet(1)])
        _ = e.key(editTestKey(.text("nested")), nil)

        // Shift+Return inserts a soft break inside the same list item.
        let shiftEnter = KeyEvent(key: .enter, mods: Mods(shift: true))
        _ = e.key(shiftEnter, nil)
        _ = e.key(editTestKey(.text("cont")), nil)
        #expect(e.softBreaks() == [2])
        #expect(e.blocks() == [.bullet(0), .bullet(1), .bullet(1)])

        // Return at end of "cont" creates a new empty Bullet(1) item on line 3.
        _ = e.key(editTestKey(.enter), nil)
        #expect(e.blocks().count == 4)
        #expect(e.currentBlock() == .bullet(1))

        // Return on the empty Bullet(1) item ends the list item (converts to Paragraph) without adding a newline.
        let lenBefore = e.text.utf8.count
        _ = e.key(editTestKey(.enter), nil)
        #expect(e.text.utf8.count == lenBefore)
        #expect(e.currentBlock() == .paragraph)

        // Backspace at start of a nested list item outdents first, then exits list.
        e.setBlock(.numbered(1))
        _ = e.key(editTestKey(.backspace), nil)
        #expect(e.currentBlock() == .numbered(0))
        _ = e.key(editTestKey(.backspace), nil)
        #expect(e.currentBlock() == .paragraph)

        // Inside a Code block: Return inserts a newline, Tab inserts '\t', and inline marks do not apply.
        e.setBlock(.code)
        e.toggleMark(.bold)
        #expect(!e.hasMark(.bold))
        _ = e.key(editTestKey(.tab), nil)
        _ = e.key(editTestKey(.text("let x = 1;")), nil)
        #expect(!e.key(editTestKey(.enter), nil).submit)
        _ = e.key(editTestKey(.text("let y = 2;")), nil)
        #expect(e.text.hasSuffix("\tlet x = 1;\nlet y = 2;"))
        #expect(e.currentBlock() == .code)
        #expect(e.marks().isEmpty)
    }

    @Test("undo, redo, and IME preserve marks, blocks, and spans")
    func undoRedoAndImePreserveMarksBlocksAndSpans() {
        var e = TextEdit.new("fn main() {}")
        e.anchor = 0
        e.focus = 2
        e.toggleMark(.bold)
        e.setBlock(.quote)

        // Undo block change, then undo mark change, then redo both.
        editTestUndo(&e, false)
        #expect(e.currentBlock() == .paragraph)
        #expect(e.marks() == [MarkRange.new(0..<2, .bold)])
        editTestUndo(&e, false)
        #expect(e.marks().isEmpty)
        editTestUndo(&e, true)
        #expect(e.marks() == [MarkRange.new(0..<2, .bold)])
        editTestUndo(&e, true)
        #expect(e.currentBlock() == .quote)

        // IME preedit with pending typing style and caller-supplied span mapping.
        e.set(3, false) // right before "main"
        e.toggleMark(.italic)
        // Suppose caller supplies a syntax span covering "main" (3..7 in model).
        #expect(e.mapRangeToDisplay(3, 7).map { [$0.0, $0.1] } == [[3, 7]])
        _ = e.ime(.preedit("日", (0, 3)))
        // During preedit ("fn 日main() {}"), "main" in display is shifted by 3 bytes to 6..10!
        #expect(e.display().0 == "fn 日main() {}")
        #expect(e.mapRangeToDisplay(3, 7).map { [$0.0, $0.1] } == [[6, 10]])
        // And the preedit itself has the pending Italic mark in richDisplaySpecs.
        let (spans, _, _, _) = e.richDisplaySpecs(TextStyle.new(14.0, 400.0), RichStyle())
        #expect(spans.contains { $0.start == 3 && $0.end == 6 && $0.italic })

        // Commit IME preedit: Italic mark is committed on "日" (3..6).
        _ = e.ime(.commit("日"))
        #expect(e.text == "fn 日main() {}")
        #expect(e.marks().contains(MarkRange.new(3..<6, .italic)))

        // Undo restores "fn main() {}" and its original marks.
        editTestUndo(&e, false)
        #expect(e.text == "fn main() {}")
        #expect(e.marks() == [MarkRange.new(0..<2, .bold)])
        #expect(e.mapRangeToDisplay(3, 7).map { [$0.0, $0.1] } == [[3, 7]])
    }

    @Test("HTML import, export, and paste safe subset")
    func htmlImportExportAndPasteSafeSubset() {
        let html =
            "<p>Hello <b>bold</b>, <strong style=\"font-style: italic\">both</strong>, "
            + "<u>under</u>, <del>struck</del>, <code>inline()</code>, and "
            + "<a href=\"https://opencode.ai\">link</a>"
            + "<a href=\"javascript:alert(1)\">bad</a></p>"
            + "<ul><li>first<ul><li>nested<br>soft</li></ul></li></ul>"
            + "<ol><li>one</li><li>two</li></ol>"
            + "<blockquote>quoted</blockquote>"
            + "<pre><code>fn add(a: i32) -&gt; i32 {\n\ta + 1\n}</code></pre>"
            + "<script>evil()</script><style>body{display:none}</style>"
        let e = TextEdit.fromHtml(html)
        #expect(!e.text.contains("evil"))
        #expect(!e.text.contains("display:none"))
        #expect(e.marks().contains { $0.mark == .bold })
        #expect(e.marks().contains { $0.mark == .italic })
        #expect(e.marks().contains { $0.mark == .underline })
        #expect(e.marks().contains { $0.mark == .strike })
        #expect(e.marks().contains { $0.mark == .code })
        #expect(e.marks().contains { $0.mark == .link("https://opencode.ai") })
        #expect(!e.marks().contains {
            if case .link(let u) = $0.mark { return u.hasPrefix("javascript:") }
            return false
        })
        #expect(
            e.blocks() == [
                .paragraph,
                .bullet(0),
                .bullet(1),
                .bullet(1),
                .numbered(0),
                .numbered(0),
                .quote,
                .code,
                .code,
                .code,
            ]
        )
        #expect(e.softBreaks() == [3])

        // Round-trip via toHtml() -> fromHtml().
        let exported = e.toHtml()
        let round = TextEdit.fromHtml(exported)
        #expect(round.text == e.text)
        #expect(round.marks() == e.marks())
        #expect(round.blocks() == e.blocks())
        #expect(round.softBreaks() == e.softBreaks())

        // pasteHtml into an existing editor splices text, marks, and blocks cleanly.
        var dest = TextEdit.new("prefix  suffix").rich()
        dest.set(7, false)
        _ = dest.pasteHtml("<b>rich</b> <i>paste</i>", "rich paste")
        #expect(dest.text == "prefix rich paste suffix")
        #expect(
            dest.marks() == [
                MarkRange.new(7..<11, .bold),
                MarkRange.new(12..<17, .italic),
            ]
        )
    }

    @Test("spans on textInput hold through IME and undo")
    func spansOnTextInputHoldThroughImeAndUndo() {
        // PORT NOTE: Runtime.ime/key is not yet wired in Sources/Rune/runtime.swift (outside scope);
        // verify directly via TextEdit + textInput(...).spans(...) that TextSpec.spans shifts
        // across IME preedit and restores on undo.
        func buildEl(_ edit: TextEdit) -> El {
            let end = min(edit.text.utf8.count, 3)
            let spans = end > 0 ? [Span.new(0, end).color(.WHITE).bold()] : []
            return textInput(edit, TextStyle.new(14.0, 400.0))
                .key("ed")
                .size(240.0, 60.0)
                .spans(spans)
        }

        var edit = TextEdit.new("let x = 1;")
        edit.focused = true
        edit.set(0, false)

        // Start IME preedit at byte 0: display text becomes "あlet x = 1;", so caller's 0..3
        // span on `edit.text` shifts automatically to 3..6 in the rendered TextSpec!
        _ = edit.ime(.preedit("あ", (0, 3)))
        let preeditEl = buildEl(edit)
        let preeditSpans = preeditEl.textSpec?.value.spans ?? []
        #expect(preeditSpans.count == 1)
        #expect((preeditSpans[0].start, preeditSpans[0].end) == (3, 6))

        // Commit IME preedit, then undo back to "let x = 1;": span returns to 0..3.
        _ = edit.ime(.commit("あ"))
        _ = edit.key(KeyEvent(key: .command("z"), mods: Mods(cmd: true)), nil)
        #expect(edit.text == "let x = 1;")
        let undoneEl = buildEl(edit)
        let undoneSpans = undoneEl.textSpec?.value.spans ?? []
        #expect(undoneSpans.count == 1)
        #expect((undoneSpans[0].start, undoneSpans[0].end) == (0, 3))
    }

    @Test("mark shortcuts, list tabs, and rich textInput decorations")
    func runtimeRoutesMarkShortcutsListTabsAndRendersDecorations() {
        // PORT NOTE: Runtime.key/frame is not yet wired in Sources/Rune/runtime.swift (outside scope);
        // verify directly on TextEdit + textInput that Cmd+B/I/U toggle marks, Tab/Shift+Tab
        // indent/outdent list items while keeping list selection active, and textInput builds
        // rich blocks, strikes, and spans.
        var edit = TextEdit.fromHtml(
            "<ul><li>item</li></ul><ol><li><del>struck</del></li></ol><blockquote>quote</blockquote><pre><code>let x = 1;</code></pre>"
        )
        edit.focused = true
        edit.anchor = 0
        edit.focus = 4 // "item"
        let baseEl = textInput(edit, TextStyle.new(14.0, 400.0)).key("ed").size(300.0, 140.0)
        #expect(baseEl.textSpec?.value.blocks == [.bullet(0), .numbered(0), .quote, .code])
        #expect(baseEl.textSpec?.value.strikes.count == 1)
        #expect(!(baseEl.textSpec?.value.spans.isEmpty ?? true))

        // Cmd+B, Cmd+I, Cmd+U toggle marks on the selection.
        _ = edit.key(KeyEvent(key: .command("b"), mods: Mods(cmd: true)), nil)
        _ = edit.key(KeyEvent(key: .command("i"), mods: Mods(cmd: true)), nil)
        _ = edit.key(KeyEvent(key: .command("u"), mods: Mods(cmd: true)), nil)
        #expect(edit.hasMark(.bold))
        #expect(edit.hasMark(.italic))
        #expect(edit.hasMark(.underline))

        // Tab inside a list item indents the list item instead of moving focus!
        #expect(edit.selectionInList())
        _ = edit.key(KeyEvent(key: .tab, mods: Mods()), nil)
        #expect(edit.focused)
        #expect(edit.blocks()[0] == .bullet(1))

        // Shift+Tab outdents the list item back to Bullet(0).
        _ = edit.key(KeyEvent(key: .tab, mods: Mods(shift: true)), nil)
        #expect(edit.blocks()[0] == .bullet(0))
    }
}
