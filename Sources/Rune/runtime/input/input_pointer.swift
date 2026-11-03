// Ported from: crates/rune/src/runtime/input/pointer.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Primary & secondary pointer move / down / drag / up / cancel routing.

extension Runtime {
    public func pointerMove(_ x: Float, _ y: Float, mods: Mods? = nil) {
        ensureClean()
        if let mods { heldMods = mods }
        lastPointer = (x, y)
        clearScrollHoverHolds()

        if x >= 0.0 && y >= 0.0 && x < viewport.0 && y < viewport.1 {
            pointerLeftInCapture = false
        }

        // Active `onDragHandler` gesture
        if let dragPath = activeDragNodePath, let idx = keyIndex.nodeByPath(dragPath) {
            let r = nodes[idx].presentedRect
            let dx = x - activeDragOrigin.0
            let dy = y - activeDragOrigin.1
            activeDragPrev = (x, y)
            if abs(dx) > 4.0 || abs(dy) > 4.0 {
                if !activeDragMoved {
                    clickTracker.reset()
                }
                activeDragMoved = true
            }
            if let handler = nodes[idx].onDragHandler {
                var drag = Drag(
                    phase: .move,
                    x: x - r[0],
                    y: y - r[1],
                    w: r[2],
                    h: r[3],
                    startX: activeDragStartLocal.0,
                    startY: activeDragStartLocal.1,
                    dx: dx,
                    dy: dy,
                    data: activeDragData,
                    clicks: activeDragClicks,
                    cancelled: false
                )
                var tx = newTx()
                let states = makeStates()
                handler(states, &drag, &tx)
                commitStates(states)
                activeDragData = drag.data
                applyTx(&tx, why: CommitWhy.DRAG)
                if dirty { performCommit() }
            }
            return
        }

        // Active `textInput` drag selection
        if let inputPath = activeInputDragPath, let idx = keyIndex.nodeByPath(inputPath) {
            extendInputPointerSelection(nodeIdx: idx, windowX: x, windowY: y)
            return
        }

        // Active selectable text drag selection
        if isDraggingTextSelection {
            updateTextSelectionDrag(windowX: x, windowY: y)
            return
        }

        updateHoverAt(x, y, commitIfChanged: true)
    }

    @discardableResult
    public func pointerDown(_ x: Float, _ y: Float, button: PointerButton = .primary, mods: Mods? = nil) -> TitlebarAction {
        ensureClean()
        if let mods { heldMods = mods }
        lastPointer = (x, y)
        clearScrollHoverHolds()
        updateHoverAt(x, y, commitIfChanged: false)

        if button == .secondary {
            let clicks = clickTracker.record(x: x, y: y, button: button, now: t, maxInterval: doubleClickInterval)
            pushEventMarker(kind: "pointerDown", detail: "secondary:\(x),\(y)#\(clicks)")
            _ = secondaryPointerDown(x, y)
            return .none
        }

        guard button == .primary else { return .none }
        let clicks = clickTracker.record(x: x, y: y, button: .primary, now: t, maxInterval: doubleClickInterval)
        pushEventMarker(kind: "pointerDown", detail: "\(x),\(y)#\(clicks)")

        // Dismiss open popups if clicking outside them
        if handlePopupOutsideClick(x: x, y: y) {
            return .none
        }

        // Titlebar drag / double-click zoom check
        let tbAction = checkTitlebarPointerDown(x: x, y: y, clicks: clicks)
        if tbAction != .none {
            return tbAction
        }

        guard let hitIdx = hitTestNode(x, y, includeTransparent: false, requireInteractive: false) else {
            clearTextSelection()
            return .none
        }

        // Walk ancestor chain from `hitIdx` up to find interactive targets
        var cur: Int? = hitIdx
        var dragIdx: Int? = nil
        var pressIdx: Int? = nil
        var inputIdx: Int? = nil
        var focusIdx: Int? = nil
        var linkHit: (Int, Int)? = nil
        var selectableIdx: Int? = nil

        if let lIdx = hitLinkInNode(nodeIdx: hitIdx, windowX: x, windowY: y) {
            linkHit = (hitIdx, lIdx)
        }

        while let idx = cur {
            let n = nodes[idx]
            if !n.inert {
                if dragIdx == nil && n.onDragHandler != nil { dragIdx = idx }
                if pressIdx == nil && n.onPressHandler != nil { pressIdx = idx }
                if inputIdx == nil && n.input != nil { inputIdx = idx }
                if focusIdx == nil && (n.focusSpec.enabled || n.input != nil) { focusIdx = idx }
                if selectableIdx == nil && n.textSpec?.selectable == true { selectableIdx = idx }
            }
            cur = n.parent
        }

        // Focus management on pointer down: pointer focus does NOT show keyboard focus ring unless it's a text input
        if let fIdx = focusIdx {
            setFocusedPath(nodes[fIdx].path, visible: false)
        } else if focusedPath != nil {
            // Clicking outside a textInput blurs it
            if let fp = focusedPath, let curFIdx = keyIndex.nodeByPath(fp), nodes[curFIdx].input != nil {
                setFocusedPath(nil, visible: false)
            }
        }

        // Clear static text selection if clicking outside selectable text (or starting fresh click)
        if selectableIdx == nil && linkHit == nil && hasActiveTextSelection() {
            clearTextSelection()
        }

        // 1. Link press candidate
        if let (lnodeIdx, lIdx) = linkHit {
            pressedLinkTarget = (nodes[lnodeIdx].path, lIdx)
            pressedPath = nodes[lnodeIdx].path
            return .none
        }

        // 2. `textInput` caret / word / line click & drag selection
        if let iIdx = inputIdx {
            handleInputPointerDown(nodeIdx: iIdx, windowX: x, windowY: y, clicks: clicks, shift: heldMods.shift)
            return .none
        }

        // 3. `onDragHandler` start
        if let dIdx = dragIdx {
            let r = nodes[dIdx].presentedRect
            let lx = x - r[0]
            let ly = y - r[1]
            activeDragNodePath = nodes[dIdx].path
            activeDragOrigin = (x, y)
            activeDragPrev = (x, y)
            activeDragStartLocal = (lx, ly)
            activeDragData = 0.0
            activeDragClicks = clicks
            activeDragMoved = false
            pressedPath = nodes[dIdx].path
            scene.animate(nodes[dIdx].nodeId, P_PRESS, 1.0, tok.motion.INSTANT)

            if let handler = nodes[dIdx].onDragHandler {
                var drag = Drag(
                    phase: .down,
                    x: lx,
                    y: ly,
                    w: r[2],
                    h: r[3],
                    startX: lx,
                    startY: ly,
                    dx: 0.0,
                    dy: 0.0,
                    data: 0.0,
                    clicks: clicks,
                    cancelled: false
                )
                var tx = newTx()
                let states = makeStates()
                handler(states, &drag, &tx)
                commitStates(states)
                activeDragData = drag.data
                applyTx(&tx, why: CommitWhy.DRAG)
                if dirty { performCommit() }
            }
            return .none
        }

        // 4. `onPressHandler` arm
        if let pIdx = pressIdx {
            pressedPath = nodes[pIdx].path
            if reducedMotion {
                scene.set(nodes[pIdx].nodeId, P_PRESS, 1.0)
            } else {
                scene.animate(nodes[pIdx].nodeId, P_PRESS, 1.0, tok.motion.INSTANT)
            }
            return .none
        }

        // 5. Selectable static text click / double-click / triple-click / drag
        if let sIdx = selectableIdx {
            beginSelectablePointerDown(nodeIdx: sIdx, windowX: x, windowY: y, clicks: clicks, shift: heldMods.shift)
            return .none
        }

        return .none
    }

    public func pointerUp(_ x: Float, _ y: Float, button: PointerButton = .primary, mods: Mods? = nil) {
        ensureClean()
        if let mods { heldMods = mods }
        lastPointer = (x, y)
        clearScrollHoverHolds()
        guard button == .primary else { return }

        pushEventMarker(kind: "pointerUp", detail: "\(x),\(y)")

        // Release `P_PRESS` track
        let prevPressed = pressedPath
        pressedPath = nil
        if let pp = prevPressed, let idx = keyIndex.nodeByPath(pp) {
            if reducedMotion {
                scene.set(nodes[idx].nodeId, P_PRESS, 0.0)
            } else {
                scene.animate(nodes[idx].nodeId, P_PRESS, 0.0, tok.motion.INSTANT)
            }
        }

        // Finish link click
        if let (lPath, lIdx) = pressedLinkTarget {
            pressedLinkTarget = nil
            if let nodeIdx = keyIndex.nodeByPath(lPath),
               hitLinkInNode(nodeIdx: nodeIdx, windowX: x, windowY: y) == lIdx
            {
                activateLinkInNode(nodeIdx: nodeIdx, linkIdx: lIdx)
            }
            return
        }

        // Finish `textInput` drag
        if activeInputDragPath != nil {
            activeInputDragPath = nil
            return
        }

        // Finish selectable text drag
        if isDraggingTextSelection {
            finishTextSelectionDrag()
            return
        }

        // Finish `onDragHandler`
        if let dragPath = activeDragNodePath {
            let moved = activeDragMoved
            activeDragNodePath = nil
            if let idx = keyIndex.nodeByPath(dragPath) {
                let r = nodes[idx].presentedRect
                if let handler = nodes[idx].onDragHandler {
                    var drag = Drag(
                        phase: .up,
                        x: x - r[0],
                        y: y - r[1],
                        w: r[2],
                        h: r[3],
                        startX: activeDragStartLocal.0,
                        startY: activeDragStartLocal.1,
                        dx: x - activeDragOrigin.0,
                        dy: y - activeDragOrigin.1,
                        data: activeDragData,
                        clicks: activeDragClicks,
                        cancelled: false
                    )
                    var tx = newTx()
                    let states = makeStates()
                    handler(states, &drag, &tx)
                    commitStates(states)
                    applyTx(&tx, why: CommitWhy.DRAG)
                    if dirty { performCommit() }
                }
                // If the element ALSO has `onPressHandler` and did not drag past slop, fire `onPress` if still inside!
                if !moved, nodes[idx].onPressHandler != nil,
                   pointInRoundedRect(x, y, rect: nodes[idx].presentedRect, corners: nodes[idx].vis.corners)
                {
                    _ = dispatchPress(nodeIdx: idx)
                    if dirty { performCommit() }
                }
            }
            if pointerLeftInCapture || x < 0.0 || y < 0.0 || x >= viewport.0 || y >= viewport.1 {
                pointerLeftInCapture = false
                pointerLeave()
            } else {
                updateHoverAt(x, y, commitIfChanged: true)
            }
            return
        }

        // Fire `onPressHandler` if pointer released over the same armed element!
        if let pp = prevPressed, let armedIdx = keyIndex.nodeByPath(pp) {
            if let releaseHit = hitTestNode(x, y, includeTransparent: false, requireInteractive: false) {
                var cur: Int? = releaseHit
                var stillInsideArmed = false
                while let c = cur {
                    if c == armedIdx {
                        stillInsideArmed = true
                        break
                    }
                    cur = nodes[c].parent
                }
                if stillInsideArmed {
                    _ = dispatchPress(nodeIdx: armedIdx)
                    if dirty { performCommit() }
                }
            }
        }

        if pointerLeftInCapture || x < 0.0 || y < 0.0 || x >= viewport.0 || y >= viewport.1 {
            pointerLeftInCapture = false
            pointerLeave()
        } else if !hasActiveScrollHoverHold {
            updateHoverAt(x, y, commitIfChanged: true)
        }
    }

    /// Shift tracked pointer and drag-press origin when the host window moves by `(dx, dy)` under a still pointer.
    public func windowMoved(_ dx: Float, _ dy: Float) {
        if let (px, py) = lastPointer {
            lastPointer = (px - dx, py - dy)
        }
        activeDragOrigin = (activeDragOrigin.0 - dx, activeDragOrigin.1 - dy)
        activeDragPrev = (activeDragPrev.0 - dx, activeDragPrev.1 - dy)
    }

    public func cancelPointer() {
        pointerCancel()
        pointerLeftInCapture = false
        pointerLeave()
    }

    public func pointerCancel() {
        clickTracker.reset()
        pressedLinkTarget = nil
        secondaryPressedPath = nil
        activeInputDragPath = nil
        if isDraggingTextSelection {
            isDraggingTextSelection = false
        }
        if let pp = pressedPath, let idx = keyIndex.nodeByPath(pp) {
            scene.animate(nodes[idx].nodeId, P_PRESS, 0.0, tok.motion.INSTANT)
        }
        pressedPath = nil

        if let dragPath = activeDragNodePath {
            activeDragNodePath = nil
            if let idx = keyIndex.nodeByPath(dragPath), let handler = nodes[idx].onDragHandler {
                let r = nodes[idx].presentedRect
                let p = lastPointer ?? activeDragPrev
                var drag = Drag(
                    phase: .up,
                    x: p.0 - r[0],
                    y: p.1 - r[1],
                    w: r[2],
                    h: r[3],
                    startX: activeDragStartLocal.0,
                    startY: activeDragStartLocal.1,
                    dx: p.0 - activeDragOrigin.0,
                    dy: p.1 - activeDragOrigin.1,
                    data: activeDragData,
                    clicks: activeDragClicks,
                    cancelled: true
                )
                var tx = newTx()
                let states = makeStates()
                handler(states, &drag, &tx)
                commitStates(states)
                applyTx(&tx, why: CommitWhy.DRAG)
            }
        }
    }
}
