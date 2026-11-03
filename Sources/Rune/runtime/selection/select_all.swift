// Ported from: crates/rune/src/runtime/selection/select_all.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! `Cmd+A` / `selectAllText` scoping to the active `selectionGroup` or entire window's selectable texts.

extension Runtime {
    /// Nearest `selectionGroup` ancestor of `nodeIdx` (stopping before an inner nested group boundary), or `nil` if ungrouped.
    func groupOfSelectable(_ nodeIdx: Int) -> Int? {
        guard nodes.indices.contains(nodeIdx) else { return nil }
        var cur: Int? = nodeIdx
        while let idx = cur {
            if nodes[idx].selectionGroup {
                return idx
            }
            cur = nodes[idx].parent
        }
        return nil
    }

    /// The selection unit of `nodeIdx`: its enclosing `selectionGroup` if any, otherwise `nodeIdx` itself.
    func selectUnit(for nodeIdx: Int) -> Int {
        groupOfSelectable(nodeIdx) ?? nodeIdx
    }

    func selectionScopeRoot(for nodeIdx: Int) -> Int {
        groupOfSelectable(nodeIdx) ?? 0
    }

    func rememberSelectionPick(nodeIdx: Int) {
        guard nodes.indices.contains(nodeIdx) else { return }
        let unit = selectUnit(for: nodeIdx)
        lastPickedSelectionUnitPath = nodes[unit].path
    }

    func selectableNodeIndices(under rootIdx: Int) -> [Int] {
        var out: [Int] = []
        let rootIsGroup = nodes.indices.contains(rootIdx) && nodes[rootIdx].selectionGroup
        func walk(_ idx: Int) {
            if nodes[idx].inert || subtreeExiting(idx) { return }
            if idx != rootIdx && rootIsGroup && nodes[idx].selectionGroup {
                return
            }
            if let spec = nodes[idx].textSpec, spec.selectable, !spec.content.isEmpty {
                out.append(idx)
            }
            for c in nodes[idx].children {
                walk(c)
            }
        }
        if nodes.indices.contains(rootIdx) {
            walk(rootIdx)
        }
        return out
    }

    private func selectAllTargetUnit() -> Int? {
        if let curAnchor = staticSelectionAnchor,
           let aIdx = keyIndex.nodeByPath(curAnchor.0),
           !nodes[aIdx].inert,
           !subtreeExiting(aIdx)
        {
            return selectUnit(for: aIdx)
        }
        if let pickPath = lastPickedSelectionUnitPath,
           let uIdx = keyIndex.nodeByPath(pickPath),
           !nodes[uIdx].inert,
           !subtreeExiting(uIdx)
        {
            let members = selectableNodeIndices(under: uIdx)
            if !members.isEmpty {
                return uIdx
            }
        }
        var firstUnit: Int? = nil
        for i in nodes.indices {
            guard let spec = nodes[i].textSpec, spec.selectable, !spec.content.isEmpty,
                  !nodes[i].inert, !subtreeExiting(i)
            else { continue }
            let u = selectUnit(for: i)
            if let existing = firstUnit {
                if u != existing {
                    return nil
                }
            } else {
                firstUnit = u
            }
        }
        return firstUnit
    }

    @discardableResult
    public func selectAllSelectableText(inScope scopeKey: String? = nil) -> Bool {
        ensureClean()
        let scopeRoot: Int
        if let key = scopeKey {
            guard let idx = keyIndex.findMatching(key, in: nodes) else { return false }
            if nodes[idx].textSpec?.selectable == true && nodes[idx].children.isEmpty {
                let len = nodes[idx].textSpec?.content.utf8.count ?? 0
                guard len > 0 else { return false }
                rememberSelectionPick(nodeIdx: idx)
                setStaticSelection(
                    anchorPath: nodes[idx].path,
                    anchorByte: 0,
                    focusPath: nodes[idx].path,
                    focusByte: len,
                    dragging: false
                )
                return true
            }
            scopeRoot = idx
        } else {
            guard let target = selectAllTargetUnit() else { return false }
            scopeRoot = target
        }

        let candidates = selectableNodeIndices(under: scopeRoot)
        guard let first = candidates.first, let last = candidates.last else { return false }
        let lastLen = nodes[last].textSpec?.content.utf8.count ?? 0
        rememberSelectionPick(nodeIdx: first)
        setStaticSelection(
            anchorPath: nodes[first].path,
            anchorByte: 0,
            focusPath: nodes[last].path,
            focusByte: lastLen,
            dragging: false
        )
        return true
    }
}
