// Ported from: crates/rune/src/runtime/input/focus.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Keyboard focus ring, `Tab` / `Shift+Tab` traversal, focus groups, `returnTo` restoration, and `tabVisitsControls`.

extension Runtime {
    public func focused() -> String? {
        ensureClean()
        return currentFocusedKey()
    }

    public func focusedElementPath() -> String? {
        ensureClean()
        return focusedPath
    }

    public func isFocusVisible() -> Bool {
        focusVisible
    }

    func currentFocusedKey() -> String? {
        guard let fPath = focusedPath else { return nil }
        if let idx = keyIndex.nodeByPath(fPath) {
            return nodes[idx].key ?? fPath
        }
        return fPath.split(separator: "/").last.map(String.init) ?? fPath
    }

    public func focus(_ key: String) {
        ensureClean()
        focusByKey(key, visible: true)
    }

    public func blur() {
        setFocusedPath(nil, visible: false)
    }

    func focusByKey(_ key: String, visible: Bool) {
        if let idx = keyIndex.findMatching(key, in: nodes), !nodes[idx].inert {
            setFocusedPath(nodes[idx].path, visible: visible)
        } else {
            // Store pending key to resolve on next commit if newly mounted
            pendingFocusKey = key
            focusVisible = visible
            markDirty(CommitWhy.FOCUS)
        }
    }

    func captureReturnTargetForNode(_ nodeIdx: Int) {
        var cur: Int? = nodeIdx
        while let idx = cur {
            if let ret = nodes[idx].focusSpec.returnTo {
                focusReturnTarget = ret
                return
            }
            cur = nodes[idx].parent
        }
    }

    func setFocusedPath(_ newPath: String?, visible: Bool) {
        guard focusedPath != newPath || focusVisible != visible else { return }
        if let prev = focusedPath, newPath != prev {
            if let prevIdx = keyIndex.nodeByPath(prev) {
                captureReturnTargetForNode(prevIdx)
                if nodes[prevIdx].input != nil {
                    mutateNodeTextEdit(nodeIdx: prevIdx) { $0.focused = false }
                }
            }
        }
        focusedPath = newPath
        focusVisible = newPath != nil ? visible : false
        pendingFocusKey = nil
        if let np = newPath, let newIdx = keyIndex.nodeByPath(np) {
            captureReturnTargetForNode(newIdx)
            if nodes[newIdx].input != nil {
                mutateNodeTextEdit(nodeIdx: newIdx) { $0.focused = true }
            }
        }
        markDirty(CommitWhy.FOCUS)
    }

    func isNodeFocusable(_ idx: Int) -> Bool {
        guard nodes.indices.contains(idx) else { return false }
        let n = nodes[idx]
        return !n.inert && (n.input != nil || n.focusSpec.enabled)
    }

    func focusableNodeIndices(forTab: Bool) -> [Int] {
        var candidates: [(idx: Int, order: Int32, seq: Int)] = []
        for (seq, idx) in paintOrderedNodeIndices().enumerated() {
            let n = nodes[idx]
            if n.inert { continue }
            let isInput = n.input != nil
            let explicitlyFocusable = n.focusSpec.enabled
            guard isInput || explicitlyFocusable else { continue }
            if forTab && !tabVisitsControls && !isInput {
                // When `tabVisitsControls` is false, Tab still visits explicitly `.focusable()` controls if no text inputs exist or when `focusSpec.enabled` is set unless restricted to inputs.
                // Upstream: `tabVisitsControls` controls whether plain pressable buttons participate; `.focusable(true)` & `textInput` participate!
            }
            candidates.append((idx: idx, order: n.focusSpec.order, seq: seq))
        }
        candidates.sort { a, b in
            if a.order != b.order { return a.order < b.order }
            return a.seq < b.seq
        }
        return candidates.map(\.idx)
    }

    @discardableResult
    public func advanceFocus(backward: Bool) -> Bool {
        ensureClean()
        let ring = focusableNodeIndices(forTab: true)
        guard !ring.isEmpty else { return false }

        let nextIdx: Int
        if let fPath = focusedPath, let curNodeIdx = keyIndex.nodeByPath(fPath),
           let pos = ring.firstIndex(of: curNodeIdx)
        {
            let step = backward ? -1 : 1
            let wrapped = (pos + step + ring.count) % ring.count
            nextIdx = ring[wrapped]
        } else {
            nextIdx = backward ? ring.last! : ring.first!
        }

        setFocusedPath(nodes[nextIdx].path, visible: true)
        if let key = nodes[nextIdx].key {
            revealTargetInScroll(key, center: false, animated: true)
        }
        return true
    }

    func reconcileFocusAfterCommit() {
        // Synchronize model-driven `TextEdit.focused` changes into `focusedPath`
        if (commitWhy & CommitWhy.FOCUS) == 0 {
            if let modelFocusedIdx = nodes.firstIndex(where: { !$0.inert && $0.input?.edit.focused == true }) {
                let mPath = nodes[modelFocusedIdx].path
                if focusedPath != mPath {
                    focusedPath = mPath
                }
                captureReturnTargetForNode(modelFocusedIdx)
            } else if let curPath = focusedPath,
                      let curIdx = keyIndex.nodeByPath(curPath),
                      let inp = nodes[curIdx].input,
                      !inp.edit.focused
            {
                let hasBoundEdit = (nodes[curIdx].key.flatMap { editAccessors[$0] } != nil)
                    || (editAccessors[curPath] != nil)
                    || (state is TextEdit)
                if hasBoundEdit {
                    focusedPath = nil
                    focusVisible = false
                } else {
                    nodes[curIdx].input?.edit.focused = true
                }
            }
        }

        if let pending = pendingFocusKey {
            pendingFocusKey = nil
            if let idx = keyIndex.findMatching(pending, in: nodes), !nodes[idx].inert {
                focusedPath = nodes[idx].path
                if nodes[idx].input != nil {
                    mutateNodeTextEdit(nodeIdx: idx) { $0.focused = true }
                }
                captureReturnTargetForNode(idx)
                return
            }
        }

        guard let fPath = focusedPath else { return }
        if let idx = keyIndex.nodeByPath(fPath), !nodes[idx].inert {
            if nodes[idx].input != nil {
                nodes[idx].input?.edit.focused = true
            }
            captureReturnTargetForNode(idx)
            return
        }
        // Focused node vanished or became inert: try matching by trailing key, or `focusReturnTarget`, else clear
        if let tailKey = fPath.split(separator: "/").last.map(String.init),
           let movedIdx = keyIndex.firstByKey(tailKey),
           !nodes[movedIdx].inert,
           (nodes[movedIdx].focusSpec.enabled || nodes[movedIdx].input != nil)
        {
            focusedPath = nodes[movedIdx].path
            return
        }
        if let retKey = focusReturnTarget,
           let retIdx = keyIndex.findMatching(retKey, in: nodes),
           !nodes[retIdx].inert
        {
            focusReturnTarget = nil
            focusedPath = nodes[retIdx].path
            return
        }
        focusedPath = nil
        focusVisible = false
    }
}
