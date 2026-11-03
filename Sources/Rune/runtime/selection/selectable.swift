// Ported from: crates/rune/src/runtime/selection/selectable.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Cross-element static text selection (`El.selectable`), pointer drag selection, and paragraph joining (`\n`).

extension Runtime {
    func beginSelectablePointerDown(
        nodeIdx: Int,
        windowX: Float,
        windowY: Float,
        clicks: UInt32,
        shift: Bool
    ) {
        guard let spec = nodes[nodeIdx].textSpec, spec.selectable else { return }
        let r = nodes[nodeIdx].presentedRect
        let lx = windowX - r[0]
        let ly = windowY - r[1]
        let byte: Int = {
            if let layout = nodes[nodeIdx].textLayout {
                return hitByteInTextLayout(layout, localX: lx, localY: ly)
            }
            return 0
        }()

        let path = nodes[nodeIdx].path
        selectionScopeNodeIdx = selectionScopeRoot(for: nodeIdx)
        rememberSelectionPick(nodeIdx: nodeIdx)

        if clicks >= 3 {
            let lr = lineByteRangeAt(spec.content, byteOffset: byte)
            isDraggingTextSelection = false
            setStaticSelection(anchorPath: path, anchorByte: lr.lowerBound, focusPath: path, focusByte: lr.upperBound, dragging: false)
        } else if clicks == 2 {
            let wr = wordByteRangeAt(spec.content, byteOffset: byte)
            isDraggingTextSelection = true
            setStaticSelection(anchorPath: path, anchorByte: wr.lowerBound, focusPath: path, focusByte: wr.upperBound, dragging: true)
        } else if shift, let existingAnchor = staticSelectionAnchor {
            isDraggingTextSelection = true
            setStaticSelection(anchorPath: existingAnchor.0, anchorByte: existingAnchor.1, focusPath: path, focusByte: byte, dragging: true)
        } else {
            isDraggingTextSelection = true
            setStaticSelection(anchorPath: path, anchorByte: byte, focusPath: path, focusByte: byte, dragging: true)
        }
    }

    func updateTextSelectionDrag(windowX: Float, windowY: Float) {
        guard let anchor = staticSelectionAnchor else { return }
        let scopeIdx = selectionScopeNodeIdx ?? 0
        let candidates = selectableNodeIndices(under: scopeIdx)
        guard !candidates.isEmpty else { return }

        // Find closest selectable node in `candidates` to `(windowX, windowY)`
        var bestIdx = candidates[0]
        var bestDistSq: Float = .greatestFiniteMagnitude
        for cIdx in candidates {
            let nr = nodes[cIdx].presentedRect
            let cx = min(max(windowX, nr[0]), nr[0] + nr[2])
            let cy = min(max(windowY, nr[1]), nr[1] + nr[3])
            let dx = windowX - cx
            let dy = windowY - cy
            let d2 = dx * dx + dy * dy
            if d2 < bestDistSq {
                bestDistSq = d2
                bestIdx = cIdx
            }
        }

        let nr = nodes[bestIdx].presentedRect
        let byte: Int = {
            if let layout = nodes[bestIdx].textLayout {
                return hitByteInTextLayout(layout, localX: windowX - nr[0], localY: windowY - nr[1])
            }
            return 0
        }()
        setStaticSelection(
            anchorPath: anchor.0,
            anchorByte: anchor.1,
            focusPath: nodes[bestIdx].path,
            focusByte: byte,
            dragging: true
        )
    }

    func finishTextSelectionDrag() {
        isDraggingTextSelection = false
        if let anchor = staticSelectionAnchor, let focus = staticSelectionFocus {
            if anchor.0 == focus.0 && anchor.1 == focus.1 {
                clearTextSelection()
            } else {
                setStaticSelection(
                    anchorPath: anchor.0,
                    anchorByte: anchor.1,
                    focusPath: focus.0,
                    focusByte: focus.1,
                    dragging: false
                )
            }
        }
    }
}
