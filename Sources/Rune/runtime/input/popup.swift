// Ported from: crates/rune/src/runtime/input/popup.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Anchored popup dismissal (`Escape` or outside click) and top-most overlay tracking.

extension Runtime {
    public func registerPopupDismiss(_ overlayKey: String, _ onDismiss: @escaping (inout S, inout Tx) -> Void) {
        popupDismissHandlers[overlayKey] = onDismiss
    }

    func dismissTopPopupIfPresent() -> Bool {
        // Walk overlays from top-most to bottom-most
        for idx in nodes.indices.reversed() where nodes[idx].aboveAnchor != nil && !nodes[idx].inert {
            if let k = nodes[idx].key, let handler = popupDismissHandlers[k] {
                var tx = newTx()
                handler(&state, &tx)
                applyTx(&tx, why: CommitWhy.KEY)
                return true
            }
        }
        return false
    }

    func handlePopupOutsideClick(x: Float, y: Float) -> Bool {
        guard !popupDismissHandlers.isEmpty else { return false }
        for idx in nodes.indices.reversed() where nodes[idx].aboveAnchor != nil && !nodes[idx].inert {
            guard let k = nodes[idx].key, let handler = popupDismissHandlers[k] else { continue }
            // Check if `(x, y)` is inside the overlay or its trigger
            if pointInRoundedRect(x, y, rect: nodes[idx].presentedRect, corners: nodes[idx].vis.corners) {
                return false
            }
            if let trigKey = nodes[idx].aboveAnchor?.key,
               let tIdx = keyIndex.findMatching(trigKey, in: nodes),
               pointInRoundedRect(x, y, rect: nodes[tIdx].presentedRect, corners: nodes[tIdx].vis.corners)
            {
                return false
            }
            var tx = newTx()
            handler(&state, &tx)
            applyTx(&tx, why: CommitWhy.PRESS)
            if dirty { performCommit() }
            return true
        }
        return false
    }
}
