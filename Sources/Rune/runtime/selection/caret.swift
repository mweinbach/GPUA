// Ported from: crates/rune/src/runtime/selection/caret.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Caret geometry lookup `(x, y, width, height)` inside `RtTextLayout` and focused `textInput` caret reporting.

/// Compute node-local `[x, y, w, h]` of the caret at `byteOffset` in `layout`.
func caretRectInTextLayout(_ layout: RtTextLayout, byteOffset: Int, caretWidth: Float = 1.5) -> [Float] {
    let lineH = max(layout.lineHeight, 1.0)
    guard !layout.lines.isEmpty else {
        return [0.0, 0.0, caretWidth, lineH]
    }
    let clamped = min(max(byteOffset, 0), layout.text.utf8.count)

    for (lineIdx, line) in layout.lines.enumerated() {
        let isLastLine = (lineIdx == layout.lines.count - 1)
        if clamped < line.byteStart {
            return [line.x, line.y, caretWidth, line.height]
        }
        if clamped <= line.byteEnd || isLastLine {
            for g in line.glyphs where !g.isEllipsis {
                if clamped <= g.byteOffset {
                    return [g.x, line.y, caretWidth, line.height]
                }
                if clamped < g.byteOffset + g.byteLen {
                    return [g.x, line.y, caretWidth, line.height]
                }
            }
            let endX = line.glyphs.last(where: { !$0.isEllipsis }).map { $0.x + $0.advance } ?? line.x
            return [endX, line.y, caretWidth, line.height]
        }
    }

    let last = layout.lines.last!
    return [last.x + last.width, last.y, caretWidth, last.height]
}

extension Runtime {
    func syncSingleLineInputScrollOffsets() {
        for i in nodes.indices {
            guard let inp = nodes[i].input, inp.singleLine else { continue }
            let path = nodes[i].path
            guard focusedPath == path else {
                inputScrollOffsets.removeValue(forKey: path)
                continue
            }
            guard let layout = nodes[i].textLayout else { continue }
            let (dispText, _) = inp.edit.display()
            let caretDisplayByte = caretIndex(inp.edit, dispText)
            let caretX = caretRectInTextLayout(layout, byteOffset: caretDisplayByte)[0]
            let innerW = max(nodes[i].layoutRect[2], 0.0)
            let visibleEnd = max(innerW - 2.0, 0.0)
            let maxOff = max(layout.width - visibleEnd, 0.0)
            var off = inputScrollOffsets[path] ?? 0.0
            if caretX - off > visibleEnd {
                off = caretX - visibleEnd
            } else if caretX - off < 0.0 {
                off = caretX
            }
            off = min(max(off, 0.0), maxOff)
            if off > 1e-4 {
                inputScrollOffsets[path] = off
            } else {
                inputScrollOffsets.removeValue(forKey: path)
            }
        }
    }

    func computeFocusedCaretEntry(useLayoutRect: Bool = false) -> (String, [Float])? {
        syncSingleLineInputScrollOffsets()
        guard let fPath = focusedPath,
              let idx = keyIndex.nodeByPath(fPath),
              let inp = nodes[idx].input
        else { return nil }

        let (dispText, _) = inp.edit.display()
        let caretDisplayByte = caretIndex(inp.edit, dispText)
        var nodeRect: [Float]
        if useLayoutRect || (nodes[idx].presentedRect[2] == 0.0 && nodes[idx].presentedRect[3] == 0.0) {
            nodeRect = nodes[idx].layoutRect
            var scrollAnc = nodes[idx].parent
            while let pIdx = scrollAnc {
                if nodes[pIdx].scrollSpec != nil {
                    let sKey = nodes[pIdx].key ?? nodes[pIdx].path
                    nodeRect[0] -= scrollsX[sKey]?.offset ?? 0.0
                    nodeRect[1] -= scrolls[sKey]?.offset ?? 0.0
                }
                scrollAnc = nodes[pIdx].parent
            }
        } else {
            nodeRect = nodes[idx].presentedRect
        }
        let localCaret: [Float]
        if let layout = nodes[idx].textLayout {
            localCaret = caretRectInTextLayout(layout, byteOffset: caretDisplayByte)
        } else {
            let lh = nodes[idx].textSpec?.style.linePx() ?? 16.0
            localCaret = [0.0, 0.0, 1.5, lh]
        }
        let scrollOff = inp.singleLine ? (inputScrollOffsets[fPath] ?? 0.0) : 0.0
        let worldCaret: [Float] = [
            nodeRect[0] + localCaret[0] - scrollOff,
            nodeRect[1] + localCaret[1],
            localCaret[2],
            localCaret[3],
        ]
        return (fPath, worldCaret)
    }

    public func caretRect(_ key: String) -> [Float]? {
        ensureClean()
        return caretOf(computeFocusedCaretEntry(), key)
    }
}
