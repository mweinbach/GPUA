// Ported from: crates/rune/src/runtime/commit/watch.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Layout & scroll watch callback dispatch after commit layout settles.

struct LayoutWatchEntry<S> {
    var key: String
    var windowSpace: Bool
    var lastRect: [Float]?
    var callback: (inout S, [Float], inout Tx) -> Void
}

extension Runtime {
    func buildLayoutReadSnapshot() -> LayoutReadSnapshot {
        var snap = LayoutReadSnapshot()
        for node in nodes {
            if let key = node.key {
                let local: [Float] = [
                    node.localRect[0],
                    node.localRect[1],
                    node.layoutRect[2],
                    node.layoutRect[3],
                ]
                var win = node.layoutRect
                var scrollAnc = node.parent
                while let pIdx = scrollAnc {
                    if nodes[pIdx].scrollSpec != nil {
                        let sKey = nodes[pIdx].key ?? nodes[pIdx].path
                        win[0] -= scrollsX[sKey]?.offset ?? 0.0
                        win[1] -= scrolls[sKey]?.offset ?? 0.0
                    }
                    scrollAnc = nodes[pIdx].parent
                }
                if snap.layoutRects[key] == nil {
                    snap.layoutRects[key] = local
                }
                if snap.windowRects[key] == nil {
                    snap.windowRects[key] = win
                }

                // Populate scoped ancestor selectors (e.g. `"panel/cell3"`, `"r27/label"`), first occurrence wins.
                var ancKeys: [String] = []
                var curParent = node.parent
                while let pIdx = curParent {
                    if let pk = nodes[pIdx].key {
                        ancKeys.append(pk)
                    }
                    curParent = nodes[pIdx].parent
                }
                if !ancKeys.isEmpty {
                    var suffix = key
                    for ak in ancKeys {
                        suffix = "\(ak)/\(suffix)"
                        if snap.layoutRects[suffix] == nil {
                            snap.layoutRects[suffix] = local
                        }
                        if snap.windowRects[suffix] == nil {
                            snap.windowRects[suffix] = win
                        }
                        let pair = "\(ak)/\(key)"
                        if snap.layoutRects[pair] == nil {
                            snap.layoutRects[pair] = local
                        }
                        if snap.windowRects[pair] == nil {
                            snap.windowRects[pair] = win
                        }
                    }
                }
            }
        }
        snap.caret = computeFocusedCaretEntry(useLayoutRect: true)
        return snap
    }

    func syncMemoLayoutSnapshot(from oldSnap: LayoutReadSnapshot, to snap: LayoutReadSnapshot) {
        for k in oldSnap.layoutRects.keys where snap.layoutRects[k] == nil {
            memo.layoutRects.removeValue(forKey: k)
        }
        for (k, v) in snap.layoutRects {
            memo.layoutRects[k] = v
        }
        for k in oldSnap.windowRects.keys where snap.windowRects[k] == nil {
            memo.windowRects.removeValue(forKey: k)
        }
        for (k, v) in snap.windowRects {
            memo.windowRects[k] = v
        }
        if snap.caret != nil || oldSnap.caret != nil {
            memo.caretRect = snap.caret
        }
    }
}
