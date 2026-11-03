// Ported from: crates/rune/src/runtime/selection/click.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Hit-test `(localX, localY)` to UTF-8 byte offset, word range (double-click), and line range (triple-click),
//! plus `textInput` pointer click & drag selection.

/// Map node-local `(localX, localY)` to the nearest UTF-8 byte boundary in `layout`.
func hitByteInTextLayout(_ layout: RtTextLayout, localX: Float, localY: Float) -> Int {
    guard !layout.lines.isEmpty else { return 0 }

    // Pick line containing `localY` (clamped to first/last line)
    var chosenLine = layout.lines[0]
    if localY < layout.lines[0].y {
        chosenLine = layout.lines[0]
    } else if localY >= layout.lines.last!.y + layout.lines.last!.height {
        chosenLine = layout.lines.last!
    } else {
        for line in layout.lines {
            if localY >= line.y && localY < line.y + line.height {
                chosenLine = line
                break
            }
        }
    }

    if localX <= chosenLine.x {
        return chosenLine.byteStart
    }
    for g in chosenLine.glyphs where !g.isEllipsis {
        let mid = g.x + g.advance * 0.5
        if localX < mid {
            return g.byteOffset
        }
        if localX < g.x + g.advance {
            return g.byteOffset + g.byteLen
        }
    }
    return chosenLine.byteEnd
}

/// Compute UTF-8 word byte range surrounding `byteOffset` in `text`.
func wordByteRangeAt(_ text: String, byteOffset: Int) -> Range<Int> {
    let total = text.utf8.count
    guard total > 0 else { return 0..<0 }
    let clamped = min(max(byteOffset, 0), total)

    // Collect `(start, end, isWordChar)` per character
    var chars: [(Int, Int, Bool)] = []
    var cursor = 0
    for ch in text {
        let len = ch.utf8.count
        let isWord = ch.isLetter || ch.isNumber || ch == "_"
        chars.append((cursor, cursor + len, isWord))
        cursor += len
    }
    guard !chars.isEmpty else { return 0..<0 }

    let pivotIdx = chars.firstIndex(where: { $0.0 <= clamped && clamped < $0.1 })
        ?? (clamped >= total ? chars.count - 1 : 0)
    let targetKind = chars[pivotIdx].2
    // Whitespace clicks select contiguous whitespace; punctuation selects contiguous punctuation; word selects word
    let pivotSub = sliceUtf8Safely(text, chars[pivotIdx].0..<chars[pivotIdx].1)
    let isSpace = pivotSub.first?.isWhitespace == true

    func sameClass(_ idx: Int) -> Bool {
        let sub = sliceUtf8Safely(text, chars[idx].0..<chars[idx].1)
        if sub == "\n" { return false }
        if isSpace { return sub.first?.isWhitespace == true }
        return chars[idx].2 == targetKind && sub.first?.isWhitespace != true
    }

    var lo = pivotIdx
    while lo > 0 && sameClass(lo - 1) {
        lo -= 1
    }
    var hi = pivotIdx
    while hi + 1 < chars.count && sameClass(hi + 1) {
        hi += 1
    }
    return chars[lo].0..<chars[hi].1
}

/// Compute UTF-8 paragraph/line byte range surrounding `byteOffset` in `text`.
func lineByteRangeAt(_ text: String, byteOffset: Int) -> Range<Int> {
    let bytes = Array(text.utf8)
    let total = bytes.count
    guard total > 0 else { return 0..<0 }
    let pos = min(max(byteOffset, 0), total)
    var start = pos
    while start > 0 && bytes[start - 1] != 0x0A {
        start -= 1
    }
    var end = pos
    while end < total && bytes[end] != 0x0A {
        end += 1
    }
    if end < total && bytes[end] == 0x0A {
        end += 1
    }
    return start..<end
}

extension Runtime {
    func handleInputPointerDown(
        nodeIdx: Int,
        windowX: Float,
        windowY: Float,
        clicks: UInt32,
        shift: Bool
    ) {
        let r = nodes[nodeIdx].presentedRect
        let lx = windowX - r[0]
        let ly = windowY - r[1]
        let hitByte: Int = {
            if let layout = nodes[nodeIdx].textLayout {
                return hitByteInTextLayout(layout, localX: lx, localY: ly)
            }
            return 0
        }()

        activeInputDragPath = nodes[nodeIdx].path
        activeInputClickMode = clicks

        mutateNodeTextEdit(nodeIdx: nodeIdx) { edit in
            edit.preedit = nil
            let clamped = min(max(hitByte, 0), edit.text.utf8.count)
            if clicks >= 3 {
                let lr = lineByteRangeAt(edit.text, byteOffset: clamped)
                edit.anchor = lr.lowerBound
                edit.focus = lr.upperBound
            } else if clicks == 2 {
                if edit.isSecure() && !edit.isRevealed() {
                    edit.anchor = 0
                    edit.focus = edit.text.utf8.count
                } else {
                    let wr = wordByteRangeAt(edit.text, byteOffset: clamped)
                    edit.anchor = wr.lowerBound
                    edit.focus = wr.upperBound
                }
            } else if shift {
                edit.focus = clamped
            } else {
                edit.anchor = clamped
                edit.focus = clamped
            }
        }
        markDirty(CommitWhy.PRESS)
        if dirty { performCommit() }
    }

    func extendInputPointerSelection(nodeIdx: Int, windowX: Float, windowY: Float) {
        let r = nodes[nodeIdx].presentedRect
        let lx = windowX - r[0]
        let ly = windowY - r[1]
        guard let layout = nodes[nodeIdx].textLayout else { return }
        let hitByte = hitByteInTextLayout(layout, localX: lx, localY: ly)

        mutateNodeTextEdit(nodeIdx: nodeIdx) { edit in
            let clamped = min(max(hitByte, 0), edit.text.utf8.count)
            if activeInputClickMode == 2 && !(edit.isSecure() && !edit.isRevealed()) {
                let wr = wordByteRangeAt(edit.text, byteOffset: clamped)
                if clamped >= edit.anchor {
                    edit.focus = wr.upperBound
                } else {
                    edit.focus = wr.lowerBound
                }
            } else {
                edit.focus = clamped
            }
        }
        markDirty(CommitWhy.DRAG)
        if dirty { performCommit() }
    }
}
