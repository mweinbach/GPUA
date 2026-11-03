// Ported from: crates/rune/src/runtime/input/keys.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Keyboard event routing: modifier tracking -> focused element -> ancestor `onKey` bubble ->
//! `TextEdit` editing -> app-level `Runtime.onKey` -> default shortcuts (`Cmd+A`, `Cmd+C`, `Cmd+V`, `Tab`, `Enter`, `Escape`).

extension Runtime {
    /// Register an `EditAccess<S>` binding for a `textInput` keyed `key` so runtime keyboard/IME/pointer edits mutate `state`.
    public func bindEdit(_ key: String, _ access: EditAccess<S>) {
        editAccessors[key] = access.erase()
    }

    func mutateNodeTextEdit(nodeIdx: Int, _ mutate: (inout TextEdit) -> Void) {
        guard nodes.indices.contains(nodeIdx), var inp = nodes[nodeIdx].input else { return }
        var handledViaState = false
        let states = makeStates()
        if let k = nodes[nodeIdx].key, let accessor = editAccessors[k] {
            handledViaState = accessor(states, mutate)
        }
        if !handledViaState, let accessor = editAccessors[nodes[nodeIdx].path] {
            handledViaState = accessor(states, mutate)
        }
        if !handledViaState {
            // Direct fallback when `S == TextEdit`
            handledViaState = (states.withMutable { (ed: inout TextEdit) in
                mutate(&ed)
            } != nil)
        }
        if handledViaState {
            commitStates(states)
        }
        mutate(&inp.edit)
        nodes[nodeIdx].input = inp
    }

    /// Dispatch a logical `KeyEvent` into the runtime; returns `true` if handled.
    @discardableResult
    public func keyDown(_ ev: KeyEvent, isRepeat: Bool = false) -> Bool {
        ensureClean()
        heldMods = ev.mods
        let keyDetail: String
        if hasSecureFocus(), case .text = ev.key {
            keyDetail = "text(•••)"
        } else {
            keyDetail = "\(ev.key)"
        }
        pushEventMarker(kind: "key", detail: keyDetail)

        // Standalone modifier key press/release
        if case .modifier(let mod, let pressed) = ev.key {
            return handleModifierKeyEvent(mod, pressed: pressed, mods: ev.mods)
        }

        // While an app-drawn editor has an IME composition open, Return and Escape belong to the input method.
        if onIme != nil && appImeComposing && (ev.key == .enter || ev.key == .escape) {
            return false
        }

        // Keyboard navigation makes focus ring visible
        switch ev.key {
        case .tab, .up, .down, .left, .right:
            if focusedPath != nil {
                focusVisible = true
            }
        default:
            break
        }

        // 1. Focused element's own `onKeyHandler`, then `TextEdit` if it is a `textInput`,
        //    then bubble `onKeyHandler` up ancestors to root.
        if let fPath = focusedPath, let startIdx = keyIndex.nodeByPath(fPath) {
            if !nodes[startIdx].inert, let ownHandler = nodes[startIdx].onKeyHandler {
                var tx = newTx()
                tx.keyRepeatFlag = isRepeat
                let states = makeStates()
                let handled = ownHandler(states, ev, &tx)
                commitStates(states)
                applyTx(&tx, why: CommitWhy.KEY)
                if handled {
                    return true
                }
            }

            if nodes[startIdx].input != nil, !nodes[startIdx].inert {
                if handleFocusedTextInputKey(nodeIdx: startIdx, ev: ev) {
                    return true
                }
            }

            var cur: Int? = nodes[startIdx].parent
            while let idx = cur {
                if !nodes[idx].inert, let handler = nodes[idx].onKeyHandler {
                    var tx = newTx()
                    tx.keyRepeatFlag = isRepeat
                    let states = makeStates()
                    let handled = handler(states, ev, &tx)
                    commitStates(states)
                    applyTx(&tx, why: CommitWhy.KEY)
                    if handled {
                        return true
                    }
                }
                cur = nodes[idx].parent
            }
        }

        // 3. App-level `Runtime.onKey` handler
        if let appKeyHandler = onKey {
            var tx = newTx()
            tx.keyRepeatFlag = isRepeat
            let handled = appKeyHandler(&state, ev, &tx)
            applyTx(&tx, why: CommitWhy.KEY)
            if handled {
                return true
            }
        }

        // 4. Built-in selection & focus shortcuts
        if ev.isCommand("c") {
            if let sel = currentTextSelection(), !sel.copied.isEmpty {
                pendingWindowRequests.clipboardWrite = .text(sel.copied)
                return true
            }
        }
        if ev.isCommand("a") {
            if selectAllSelectableText() {
                return true
            }
        }
        if ev.key == .escape {
            if activeDragNodePath != nil {
                pointerCancel()
                if dirty { performCommit() }
                return true
            }
            if hasActiveTextSelection() {
                clearTextSelection()
                return true
            }
            if dismissTopPopupIfPresent() {
                return true
            }
        }
        if ev.key == .tab && !ev.mods.cmd && !ev.mods.ctrl && !ev.mods.alt {
            return advanceFocus(backward: ev.mods.shift)
        }
        if ev.key == .contextMenu || (ev.key == .function(10) && ev.mods.shift) {
            return triggerKeyboardContextMenu()
        }
        if ev.key == .enter && !ev.mods.cmd && !ev.mods.alt {
            // Activate focused pressable control or default button
            if let fPath = focusedPath, let idx = keyIndex.nodeByPath(fPath), nodes[idx].onPressHandler != nil {
                return dispatchPress(nodeIdx: idx)
            }
            if let defIdx = nodes.indices.first(where: { nodes[$0].focusSpec.defaultButton && !nodes[$0].inert }) {
                return dispatchPress(nodeIdx: defIdx)
            }
        }
        if (ev.key == .pageDown || ev.key == .pageUp) && !ev.mods.cmd && !ev.mods.ctrl && !ev.mods.alt {
            func isPageable(_ i: Int) -> Bool {
                guard nodes[i].scrollSpec != nil, !nodes[i].inert else { return false }
                let sKey = nodes[i].key ?? nodes[i].path
                return (scrolls[sKey]?.maxScroll ?? 0.0) > 0.5
            }
            func nearestPageable(from start: Int) -> Int? {
                var cur: Int? = start
                while let i = cur {
                    if isPageable(i) { return i }
                    cur = nodes[i].parent
                }
                return nil
            }
            let focusedAncestorIdx: Int? = {
                guard var path = focusedPath else { return nil }
                while true {
                    if let idx = keyIndex.nodeByPath(path) { return idx }
                    guard let slash = path.lastIndex(of: "/") else { return nil }
                    path = String(path[..<slash])
                }
            }()
            let targetScrollIdx = focusedAncestorIdx.flatMap(nearestPageable)
                ?? lastPointer.flatMap { hitTestScrollContainer($0.0, $0.1) }.flatMap(nearestPageable)
                ?? nodes.indices.first(where: isPageable)
            if let scrollIdx = targetScrollIdx {
                let sKey = nodes[scrollIdx].key ?? nodes[scrollIdx].path
                scrollByPages(sKey, pages: ev.key == .pageDown ? 1 : -1)
                refreshPresentedGeometries()
                return true
            }
        }

        return false
    }

    public func key(_ key: Key, mods: Mods = Mods()) -> Bool {
        keyDown(KeyEvent(key: key, mods: mods))
    }

    private func handleFocusedTextInputKey(nodeIdx: Int, ev: KeyEvent) -> Bool {
        guard let inp = nodes[nodeIdx].input else { return false }
        let singleLine = inp.singleLine || inp.edit.isSingleLine
        // Tab in single-line inputs moves focus rather than inserting a tab
        if ev.key == .tab && singleLine {
            return false
        }

        var handled = false
        var copyOut: String? = nil
        var pasteRequested = false
        var blurRequested = false

        mutateNodeTextEdit(nodeIdx: nodeIdx) { edit in
            let res = rtApplyKeyToTextEdit(&edit, ev, singleLine: singleLine)
            handled = res.handled
            copyOut = res.copy
            pasteRequested = res.paste
            blurRequested = res.blur
        }

        if let copied = copyOut {
            if inp.edit.isSecure() {
                pendingWindowRequests.clipboardWrite = .secret(SecretCopy(text: copied))
            } else {
                pendingWindowRequests.clipboardWrite = .text(copied)
            }
        }
        if pasteRequested {
            pendingWindowRequests.pasteRequested = true
        }
        if blurRequested {
            setFocusedPath(nil, visible: false)
        }
        if handled {
            markDirty(CommitWhy.KEY)
        }
        return handled
    }

    /// Paste `content` into the focused `textInput` (or trigger `paste` state handling).
    @discardableResult
    public func paste(_ text: String) -> Bool {
        ensureClean()
        guard let fPath = focusedPath,
              let idx = keyIndex.nodeByPath(fPath),
              let inp = nodes[idx].input,
              !nodes[idx].inert
        else { return false }

        let sanitized: String
        if inp.singleLine || inp.edit.isSingleLine {
            sanitized = text
                .replacingOccurrences(of: "\r\n", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
        } else {
            sanitized = text.replacingOccurrences(of: "\r\n", with: "\n")
        }

        mutateNodeTextEdit(nodeIdx: idx) { edit in
            edit.preedit = nil
            edit.insert(sanitized)
        }
        markDirty(CommitWhy.PASTE)
        return true
    }

    @discardableResult
    public func copy() -> String? {
        ensureClean()
        if let fPath = focusedPath,
           let idx = keyIndex.nodeByPath(fPath),
           let inp = nodes[idx].input
        {
            if inp.edit.isSecure() && !inp.edit.isRevealed() {
                return nil
            }
            let sel = inp.edit.selectedText()
            if !sel.isEmpty {
                pendingWindowRequests.clipboardWrite = .text(sel)
                return sel
            }
        }
        if let sel = currentTextSelection(), !sel.copied.isEmpty {
            pendingWindowRequests.clipboardWrite = .text(sel.copied)
            return sel.copied
        }
        return nil
    }

    @discardableResult
    public func cut() -> String? {
        ensureClean()
        guard let fPath = focusedPath,
              let idx = keyIndex.nodeByPath(fPath),
              let inp = nodes[idx].input,
              !nodes[idx].inert
        else { return nil }
        if inp.edit.isSecure() && !inp.edit.isRevealed() {
            return nil
        }
        let sel = inp.edit.selectedText()
        guard !sel.isEmpty else { return nil }
        mutateNodeTextEdit(nodeIdx: idx) { edit in
            edit.insert("")
        }
        pendingWindowRequests.clipboardWrite = .text(sel)
        markDirty(CommitWhy.CUT)
        return sel
    }

    /// Whether the focused editor requires secure native keyboard input.
    public func hasSecureFocus() -> Bool {
        ensureClean()
        guard let fPath = focusedPath,
              let idx = keyIndex.nodeByPath(fPath),
              let inp = nodes[idx].input
        else { return false }
        return inp.edit.isSecure()
    }

    /// Whether any element currently holds keyboard focus.
    public func hasFocus() -> Bool {
        ensureClean()
        return focusedPath != nil
    }
}

private struct RtKeyEditResult {
    var handled: Bool = false
    var copy: String? = nil
    var paste: Bool = false
    var blur: Bool = false
}

private func rtUtf8PrevBoundary(_ s: String, before byteOffset: Int) -> Int {
    let utf8 = s.utf8
    let clamped = min(max(byteOffset, 0), utf8.count)
    guard clamped > 0 else { return 0 }
    let idx = utf8.index(utf8.startIndex, offsetBy: clamped)
    let charIdx = String.Index(idx, within: s) ?? s.endIndex
    guard charIdx > s.startIndex else { return 0 }
    let prev = s.index(before: charIdx)
    return s.utf8.distance(from: s.utf8.startIndex, to: prev.samePosition(in: s.utf8) ?? s.utf8.startIndex)
}

private func rtUtf8NextBoundary(_ s: String, after byteOffset: Int) -> Int {
    let utf8 = s.utf8
    let clamped = min(max(byteOffset, 0), utf8.count)
    guard clamped < utf8.count else { return utf8.count }
    let idx = utf8.index(utf8.startIndex, offsetBy: clamped)
    let charIdx = String.Index(idx, within: s) ?? s.startIndex
    guard charIdx < s.endIndex else { return utf8.count }
    let next = s.index(after: charIdx)
    return s.utf8.distance(from: s.utf8.startIndex, to: next.samePosition(in: s.utf8) ?? s.utf8.endIndex)
}

private func rtWordPrevBoundary(_ s: String, before byteOffset: Int) -> Int {
    var pos = min(max(byteOffset, 0), s.utf8.count)
    while pos > 0 {
        let prev = rtUtf8PrevBoundary(s, before: pos)
        let sub = sliceUtf8Safely(s, prev..<pos)
        if sub.first?.isWhitespace == true {
            pos = prev
        } else {
            break
        }
    }
    while pos > 0 {
        let prev = rtUtf8PrevBoundary(s, before: pos)
        let sub = sliceUtf8Safely(s, prev..<pos)
        if sub.first?.isWhitespace == true {
            break
        }
        pos = prev
    }
    return pos
}

private func rtWordNextBoundary(_ s: String, after byteOffset: Int) -> Int {
    let total = s.utf8.count
    var pos = min(max(byteOffset, 0), total)
    while pos < total {
        let next = rtUtf8NextBoundary(s, after: pos)
        let sub = sliceUtf8Safely(s, pos..<next)
        if sub.first?.isWhitespace == true {
            pos = next
        } else {
            break
        }
    }
    while pos < total {
        let next = rtUtf8NextBoundary(s, after: pos)
        let sub = sliceUtf8Safely(s, pos..<next)
        if sub.first?.isWhitespace == true {
            break
        }
        pos = next
    }
    return pos
}

private func rtLineBounds(_ s: String, at byteOffset: Int) -> (Int, Int) {
    let bytes = Array(s.utf8)
    let pos = min(max(byteOffset, 0), bytes.count)
    var start = pos
    while start > 0 && bytes[start - 1] != 0x0A {
        start -= 1
    }
    var end = pos
    while end < bytes.count && bytes[end] != 0x0A {
        end += 1
    }
    return (start, end)
}

private func rtApplyKeyToTextEdit(_ edit: inout TextEdit, _ ev: KeyEvent, singleLine: Bool) -> RtKeyEditResult {
    let total = edit.text.utf8.count
    let (selLo, selHi) = edit.range()
    let hasSel = selLo < selHi

    func moveCaret(_ target: Int, extend: Bool) {
        let clamped = min(max(target, 0), edit.text.utf8.count)
        edit.focus = clamped
        if !extend {
            edit.anchor = clamped
        }
    }

    // Command shortcuts (`Cmd+A`, `Cmd+C`, `Cmd+X`, `Cmd+V`)
    if ev.isCommand("a") {
        edit.anchor = 0
        edit.focus = total
        return RtKeyEditResult(handled: true)
    }
    if ev.isCommand("c") {
        if edit.isSecure() && !edit.isRevealed() {
            return RtKeyEditResult(handled: true)
        }
        let s = edit.selectedText()
        return RtKeyEditResult(handled: true, copy: s.isEmpty ? nil : s)
    }
    if ev.isCommand("x") {
        if edit.isSecure() && !edit.isRevealed() {
            return RtKeyEditResult(handled: true)
        }
        let s = edit.selectedText()
        if !s.isEmpty {
            edit.insert("")
        }
        return RtKeyEditResult(handled: true, copy: s.isEmpty ? nil : s)
    }
    if ev.isCommand("v") {
        return RtKeyEditResult(handled: true, paste: true)
    }

    // macOS Emacs control bindings (`Ctrl+A/E/B/F/D/H/K`)
    if let ctrl = ev.controlBinding() {
        switch ctrl {
        case "a":
            let (ls, _) = rtLineBounds(edit.text, at: edit.focus)
            moveCaret(ls, extend: ev.mods.shift)
            return RtKeyEditResult(handled: true)
        case "e":
            let (_, le) = rtLineBounds(edit.text, at: edit.focus)
            moveCaret(le, extend: ev.mods.shift)
            return RtKeyEditResult(handled: true)
        case "b":
            moveCaret(rtUtf8PrevBoundary(edit.text, before: edit.focus), extend: ev.mods.shift)
            return RtKeyEditResult(handled: true)
        case "f":
            moveCaret(rtUtf8NextBoundary(edit.text, after: edit.focus), extend: ev.mods.shift)
            return RtKeyEditResult(handled: true)
        case "h":
            if hasSel {
                edit.insert("")
            } else if edit.focus > 0 {
                edit.anchor = rtUtf8PrevBoundary(edit.text, before: edit.focus)
                edit.insert("")
            }
            return RtKeyEditResult(handled: true)
        case "d":
            if hasSel {
                edit.insert("")
            } else if edit.focus < total {
                edit.anchor = edit.focus
                edit.focus = rtUtf8NextBoundary(edit.text, after: edit.focus)
                edit.insert("")
            }
            return RtKeyEditResult(handled: true)
        case "k":
            let (_, le) = rtLineBounds(edit.text, at: edit.focus)
            if le > edit.focus {
                edit.anchor = edit.focus
                edit.focus = le
                edit.insert("")
            }
            return RtKeyEditResult(handled: true)
        default:
            break
        }
    }

    switch ev.key {
    case .left:
        if !ev.mods.shift && hasSel && !ev.mods.cmd && !ev.mods.alt {
            moveCaret(selLo, extend: false)
        } else if ev.mods.cmd {
            let (ls, _) = rtLineBounds(edit.text, at: edit.focus)
            moveCaret(ls, extend: ev.mods.shift)
        } else if ev.mods.alt && !(edit.isSecure() && !edit.isRevealed()) {
            moveCaret(rtWordPrevBoundary(edit.text, before: edit.focus), extend: ev.mods.shift)
        } else {
            moveCaret(rtUtf8PrevBoundary(edit.text, before: edit.focus), extend: ev.mods.shift)
        }
        return RtKeyEditResult(handled: true)

    case .right:
        if !ev.mods.shift && hasSel && !ev.mods.cmd && !ev.mods.alt {
            moveCaret(selHi, extend: false)
        } else if ev.mods.cmd {
            let (_, le) = rtLineBounds(edit.text, at: edit.focus)
            moveCaret(le, extend: ev.mods.shift)
        } else if ev.mods.alt && !(edit.isSecure() && !edit.isRevealed()) {
            moveCaret(rtWordNextBoundary(edit.text, after: edit.focus), extend: ev.mods.shift)
        } else {
            moveCaret(rtUtf8NextBoundary(edit.text, after: edit.focus), extend: ev.mods.shift)
        }
        return RtKeyEditResult(handled: true)

    case .home:
        let target = ev.mods.cmd ? 0 : rtLineBounds(edit.text, at: edit.focus).0
        moveCaret(target, extend: ev.mods.shift)
        return RtKeyEditResult(handled: true)

    case .end:
        let target = ev.mods.cmd ? total : rtLineBounds(edit.text, at: edit.focus).1
        moveCaret(target, extend: ev.mods.shift)
        return RtKeyEditResult(handled: true)

    case .up:
        if ev.mods.cmd {
            moveCaret(0, extend: ev.mods.shift)
            return RtKeyEditResult(handled: true)
        }
        let (ls, _) = rtLineBounds(edit.text, at: edit.focus)
        if ls == 0 {
            moveCaret(0, extend: ev.mods.shift)
        } else {
            let colBytes = edit.focus - ls
            let (prevLs, prevLe) = rtLineBounds(edit.text, at: ls - 1)
            moveCaret(min(prevLs + colBytes, prevLe), extend: ev.mods.shift)
        }
        return RtKeyEditResult(handled: true)

    case .down:
        if ev.mods.cmd {
            moveCaret(total, extend: ev.mods.shift)
            return RtKeyEditResult(handled: true)
        }
        let (ls, le) = rtLineBounds(edit.text, at: edit.focus)
        if le >= total {
            moveCaret(total, extend: ev.mods.shift)
        } else {
            let colBytes = edit.focus - ls
            let (nextLs, nextLe) = rtLineBounds(edit.text, at: le + 1)
            moveCaret(min(nextLs + colBytes, nextLe), extend: ev.mods.shift)
        }
        return RtKeyEditResult(handled: true)

    case .backspace:
        if hasSel {
            edit.insert("")
        } else if edit.focus > 0 {
            if ev.mods.cmd {
                let (ls, _) = rtLineBounds(edit.text, at: edit.focus)
                edit.anchor = ls < edit.focus ? ls : rtUtf8PrevBoundary(edit.text, before: edit.focus)
            } else if ev.mods.alt && !(edit.isSecure() && !edit.isRevealed()) {
                edit.anchor = rtWordPrevBoundary(edit.text, before: edit.focus)
            } else {
                edit.anchor = rtUtf8PrevBoundary(edit.text, before: edit.focus)
            }
            edit.insert("")
        }
        return RtKeyEditResult(handled: true)

    case .delete:
        if hasSel {
            edit.insert("")
        } else if edit.focus < total {
            edit.anchor = edit.focus
            if ev.mods.alt && !(edit.isSecure() && !edit.isRevealed()) {
                edit.focus = rtWordNextBoundary(edit.text, after: edit.focus)
            } else {
                edit.focus = rtUtf8NextBoundary(edit.text, after: edit.focus)
            }
            edit.insert("")
        }
        return RtKeyEditResult(handled: true)

    case .enter:
        if singleLine {
            return RtKeyEditResult(handled: false)
        }
        edit.insert("\n")
        return RtKeyEditResult(handled: true)

    case .escape:
        if edit.preedit != nil {
            edit.preedit = nil
            return RtKeyEditResult(handled: true)
        }
        return RtKeyEditResult(handled: true, blur: true)

    case .text(let fragment):
        if ev.isCommandChord() {
            return RtKeyEditResult(handled: false)
        }
        edit.preedit = nil
        edit.insert(fragment)
        return RtKeyEditResult(handled: true)

    default:
        return RtKeyEditResult(handled: false)
    }
}
