// Ported from: crates/rune/src/runtime/input/app_ime.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Input Method Editor (`Ime`) composition (`preedit`, `commit`, `enabled`, `disabled`) and IME cursor rect reporting.

func rtApplyImeToTextEdit(_ edit: inout TextEdit, _ ime: Ime) -> Bool {
    switch ime {
    case .enabled:
        return false
    case .disabled:
        if edit.preedit != nil {
            edit.preedit = nil
            return true
        }
        return false
    case .preedit(let text, let cursorRange):
        if text.isEmpty {
            if edit.preedit != nil {
                edit.preedit = nil
                return true
            }
            return false
        }
        // If there is an active selection before starting preedit, delete selected text once
        if edit.preedit == nil && edit.anchor != edit.focus {
            edit.insert("")
        }
        edit.preedit = (text, cursorRange)
        return true
    case .commit(let committed):
        edit.preedit = nil
        guard !committed.isEmpty else { return true }
        edit.insert(committed)
        return true
    }
}

extension Runtime {
    /// Dispatch an `Ime` composition event to the currently focused `textInput` or `onIme` app hook.
    @discardableResult
    public func ime(_ ev: Ime) -> Bool {
        ensureClean()
        let secureFocused = hasSecureFocus()
        eventLog.push(t: t, frame: frameIndex, kind: "ime", detail: secureFocused ? "redacted" : "\(ev)")

        switch ev {
        case .enabled:
            imeActive = true
        case .disabled:
            imeActive = false
        default:
            break
        }

        if secureFocused {
            return false
        }

        let focusedInputIdx: Int? = focusedPath.flatMap { keyIndex.nodeByPath($0) }.flatMap {
            nodes[$0].input != nil && !nodes[$0].inert ? $0 : nil
        }
        let appComposing = onIme != nil && appImeComposing
        let isEnableOrDisable: Bool = {
            switch ev {
            case .enabled, .disabled: return true
            default: return false
            }
        }()

        // If `disabled` arrives while a focused field holds an open preedit, clear it too
        if case .disabled = ev, let fIdx = focusedInputIdx, nodes[fIdx].input?.edit.preedit != nil {
            var cleared = false
            mutateNodeTextEdit(nodeIdx: fIdx) { edit in
                cleared = rtApplyImeToTextEdit(&edit, ev)
            }
            if cleared {
                markDirty(CommitWhy.IME)
            }
            if onIme == nil {
                return cleared
            }
        }

        let routeToApp = appComposing || isEnableOrDisable || focusedInputIdx == nil
        if routeToApp {
            guard let hook = onIme else { return false }
            switch ev {
            case .preedit(let s, _):
                appImeComposing = !s.isEmpty
            case .commit:
                appImeComposing = false
            case .enabled, .disabled:
                break
            }
            var tx = newTx()
            let took = hook(&state, ev, &tx)
            if took {
                applyTx(&tx, why: CommitWhy.IME)
            } else {
                var sideTx = tx
                sideTx.liveOnlyFlag = true
                applyTx(&sideTx, why: 0)
            }
            return took
        }

        guard let idx = focusedInputIdx else { return false }
        var changed = false
        mutateNodeTextEdit(nodeIdx: idx) { edit in
            changed = rtApplyImeToTextEdit(&edit, ev)
        }
        if changed {
            markDirty(CommitWhy.IME)
        }
        return changed
    }

    /// Return the window-space `[x, y, w, h]` rectangle where the OS should anchor its IME candidate window.
    public func imeCursorArea() -> [Float]? {
        ensureClean()
        if hasSecureFocus() {
            return nil
        }
        // 1. Focused text input caret rect wins when an editable field has focus
        if let (_, caretRect) = computeFocusedCaretEntry() {
            return caretRect
        }
        // 2. Explicit `.imeCursor()` node if present
        if let customIdx = nodes.indices.first(where: { nodes[$0].imeCursor && !nodes[$0].inert }) {
            return nodes[customIdx].presentedRect
        }
        return nil
    }
}
