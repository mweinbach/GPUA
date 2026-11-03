// Ported from: crates/rune/src/runtime/selection/text_selection.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Public `TextSelection`, `SelectedText`, `SelectionChange` methods and programmatic selection API on `Runtime`.

extension SelectedText {
    public func isWhole() -> Bool {
        whole
    }
}

extension TextSelection {
    public func texts() -> [SelectedText] {
        items
    }

    public func text() -> String {
        copied
    }

    public var isEmpty: Bool {
        items.isEmpty || copied.isEmpty
    }
}

extension SelectionChange {
    public func started() -> Bool {
        was == nil && selection != nil
    }

    public func cleared() -> Bool {
        was != nil && selection == nil
    }

    public func isDragging() -> Bool {
        dragging
    }
}

extension Runtime {
    public func onSelectionChange(_ callback: @escaping (inout S, SelectionChange, inout Tx) -> Void) {
        selectionChangeHandler = callback
    }

    public func textSelection() -> TextSelection? {
        ensureClean()
        return currentTextSelection()
    }

    public func selectedText() -> String? {
        guard let sel = textSelection(), !sel.isEmpty else { return nil }
        return sel.text()
    }

    public func selectText(_ key: String, _ range: Range<Int>) {
        ensureClean()
        guard let idx = keyIndex.findMatching(key, in: nodes),
              let spec = nodes[idx].textSpec,
              spec.selectable
        else { return }
        let total = spec.content.utf8.count
        let lo = min(max(range.lowerBound, 0), total)
        let hi = min(max(range.upperBound, lo), total)
        rememberSelectionPick(nodeIdx: idx)
        if lo < hi {
            setStaticSelection(
                anchorPath: nodes[idx].path,
                anchorByte: lo,
                focusPath: nodes[idx].path,
                focusByte: hi,
                dragging: false
            )
        } else {
            clearTextSelection()
        }
    }

    public func clearTextSelection() {
        let prev = currentTextSelection()
        staticSelectionAnchor = nil
        staticSelectionFocus = nil
        isDraggingTextSelection = false
        virtualSelection.clear()
        memo.selectionRects = []
        if prev != nil {
            emitSelectionChange(was: prev, now: nil, dragging: false)
            markDirty(CommitWhy.SELECTION)
        }
    }

    func applySelectRequest(_ req: SelectRequest) {
        switch req {
        case .range(let key, let range):
            selectText(key, range)
        case .all(let key):
            _ = selectAllSelectableText(inScope: key)
        case .clear:
            clearTextSelection()
        }
    }

    func hasActiveTextSelection() -> Bool {
        guard let sel = currentTextSelection() else { return false }
        return !sel.isEmpty
    }

    func setStaticSelection(
        anchorPath: String,
        anchorByte: Int,
        focusPath: String,
        focusByte: Int,
        dragging: Bool
    ) {
        let prev = currentTextSelection()
        staticSelectionAnchor = (anchorPath, anchorByte)
        staticSelectionFocus = (focusPath, focusByte)
        let now = currentTextSelection()
        memo.selectionRects = selectionRectsWithoutEnsureClean()
        if prev != now || dragging != lastSelectionDragging {
            lastSelectionDragging = dragging
            emitSelectionChange(was: prev, now: now, dragging: dragging)
            markDirty(CommitWhy.SELECTION)
        }
    }

    private func selectionRectsWithoutEnsureClean() -> [[Float]] {
        guard let sel = currentTextSelection() else { return [] }
        var out: [[Float]] = []
        for item in sel.items {
            guard let idx = keyIndex.nodeByPath(item.path),
                  let layout = nodes[idx].textLayout
            else { continue }
            let nr = nodes[idx].presentedRect
            for lr in selectionRectsInTextLayout(layout, byteRange: item.range) {
                out.append([nr[0] + lr[0], nr[1] + lr[1], lr[2], lr[3]])
            }
        }
        return out
    }

    func currentTextSelection() -> TextSelection? {
        guard let anchor = staticSelectionAnchor, let focus = staticSelectionFocus else {
            return nil
        }
        guard let aIdx = keyIndex.nodeByPath(anchor.0),
              let fIdx = keyIndex.nodeByPath(focus.0)
        else { return nil }

        let backward = (aIdx > fIdx) || (aIdx == fIdx && anchor.1 > focus.1)
        let startIdx = backward ? fIdx : aIdx
        let endIdx = backward ? aIdx : fIdx
        let startByte = backward ? focus.1 : anchor.1
        let endByte = backward ? anchor.1 : focus.1

        var items: [SelectedText] = []
        for idx in startIdx...endIdx {
            guard let spec = nodes[idx].textSpec, spec.selectable else { continue }
            let total = spec.content.utf8.count
            let lo = (idx == startIdx) ? min(max(startByte, 0), total) : 0
            let hi = (idx == endIdx) ? min(max(endByte, 0), total) : total
            guard lo < hi else { continue }
            let sub = sliceUtf8Safely(spec.content, lo..<hi)
            items.append(
                SelectedText(
                    path: nodes[idx].path,
                    key: nodes[idx].key,
                    range: lo..<hi,
                    text: sub,
                    len: total,
                    whole: lo == 0 && hi == total
                )
            )
        }

        guard !items.isEmpty else { return nil }
        let joined = items.map(\.text).joined(separator: "\n")
        return TextSelection(items: items, copied: joined, backward: backward)
    }

    private func emitSelectionChange(was: TextSelection?, now: TextSelection?, dragging: Bool) {
        guard let cb = selectionChangeHandler else { return }
        var change = SelectionChange(selection: now)
        change.was = was
        change.dragging = dragging
        var tx = newTx()
        tx.selectFromChange = true
        cb(&state, change, &tx)
        applyTx(&tx, why: CommitWhy.SELECTION)
    }
}
