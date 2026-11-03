// Ported from: crates/rune/src/runtime/input/secondary.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Right-click / secondary press & keyboard `Key.contextMenu` (`Shift+F10`) routing.

extension Runtime {
    @discardableResult
    public func secondaryPointerDown(_ x: Float, _ y: Float) -> Bool {
        ensureClean()
        guard let hitIdx = hitTestNode(x, y, includeTransparent: false, requireInteractive: false) else {
            return false
        }
        let handled = dispatchSecondaryPress(nodeIdx: hitIdx, windowX: x, windowY: y)
        if dirty { performCommit() }
        return handled
    }

    public func secondaryDown(_ x: Float, _ y: Float) {
        ensureClean()
        lastPointer = (x, y)
        secondaryPressedPath = nil
        guard let hitIdx = hitTestNode(x, y, includeTransparent: false, requireInteractive: false) else {
            return
        }
        var cur: Int? = hitIdx
        while let idx = cur {
            if !nodes[idx].inert, nodes[idx].onSecondaryPressHandler != nil {
                secondaryPressedPath = nodes[idx].path
                return
            }
            cur = nodes[idx].parent
        }
    }

    public func secondaryUp(_ x: Float, _ y: Float) {
        ensureClean()
        lastPointer = (x, y)
        guard let armedPath = secondaryPressedPath else { return }
        secondaryPressedPath = nil
        guard let armedIdx = keyIndex.nodeByPath(armedPath), !nodes[armedIdx].inert else { return }
        guard let releaseHit = hitTestNode(x, y, includeTransparent: false, requireInteractive: false) else { return }
        var cur: Int? = releaseHit
        while let idx = cur {
            if idx == armedIdx {
                _ = dispatchSecondaryPress(nodeIdx: armedIdx, windowX: x, windowY: y)
                if dirty { performCommit() }
                return
            }
            cur = nodes[idx].parent
        }
    }

    func triggerKeyboardContextMenu() -> Bool {
        // 1. Focused element or its ancestors with `onSecondaryPressHandler`
        if let fPath = focusedPath, let idx = keyIndex.nodeByPath(fPath) {
            let r = nodes[idx].presentedRect
            let cx = r[0] + r[2] * 0.5
            let cy = r[1] + r[3] * 0.5
            if dispatchSecondaryPress(nodeIdx: idx, windowX: cx, windowY: cy) {
                if dirty { performCommit() }
                return true
            }
        }
        // 2. Hovered element under pointer
        if let (px, py) = lastPointer,
           let hitIdx = hitTestNode(px, py, includeTransparent: false, requireInteractive: false)
        {
            if dispatchSecondaryPress(nodeIdx: hitIdx, windowX: px, windowY: py) {
                if dirty { performCommit() }
                return true
            }
        }
        return false
    }
}
