// Ported from: crates/rune/src/edit/input.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Keys, IME and paste on a `TextEdit`.

// PORT NOTE: Protocol abstracting wrapped line-edge and vertical line-move queries on a shaped
// paragraph layout (`parley::Layout<Ink>` in upstream), allowing `TextEdit.key(_:_:)` to accept
// `nil` or any concrete shaped layout type without coupling to Parley.
public protocol TextEditLayout {
    func lineEdge(byte: Int, end: Bool) -> Int
    func moveLine(byte: Int, down: Bool) -> Int?
}

extension TextEdit {
    mutating func insertNewline(_ blockForNewLine: Block, soft: Bool) {
        if secureFlag || isSingleLine {
            return
        }
        syncInvariants()
        breakHistoryGroup()
        let before = snapshot()
        let (a, b) = range()
        let insertedMarks: [Mark]
        if let (armed, p) = pendingStyle {
            pendingStyle = nil
            if armed == (anchor, focus) {
                insertedMarks = p
            } else {
                insertedMarks = inheritedMarksAt(a)
            }
        } else {
            insertedMarks = inheritedMarksAt(a)
        }
        applyTextAndAttrReplace((a, b), "\n", insertedMarks, blockForNewLine, soft)
        recordChange(before, typing: false)
    }

    mutating func set(_ i: Int, _ extend: Bool) {
        // A caret moving into a pill steps over it, the way it was going.
        let clamped = Self.clampCharBoundary(text, i)
        let stepped = outOfPill(clamped, clamped > focus)
        focus = stepped
        if !extend {
            anchor = stepped
        }
        snapToPills()
        pendingStyle = nil
    }

    mutating func moveH(_ i: Int, _ extend: Bool) {
        let (a, b) = range()
        if !extend && a != b {
            let to = i < focus ? a : b
            anchor = to
            focus = to
        } else {
            set(i, extend)
        }
        pendingStyle = nil
    }

    /// Applies one key. `layout` is the field's layout for the current text (device px).
    @discardableResult
    public mutating func key(_ ev: KeyEvent, _ layout: (any TextEditLayout)? = nil) -> EditOutcome {
        var out = EditOutcome()
        if case .modifier = ev.key { return out }
        syncInvariants()
        let m = ev.mods
        normalizeHiddenSelection()
        if isHiddenMultiline {
            switch ev.key {
            case .left, .right, .up, .down, .home, .end:
                focus = text.utf8.count
                anchor = m.shift ? 0 : focus
                return out
            default:
                break
            }
        }
        if let c = ev.controlBinding() {
            let mapped: (Key, Bool)?
            switch c {
            case "a": mapped = (.left, true)
            case "e": mapped = (.right, true)
            case "b": mapped = (.left, false)
            case "f": mapped = (.right, false)
            case "p": mapped = (.up, false)
            case "n": mapped = (.down, false)
            case "d": mapped = (.delete, false)
            case "h": mapped = (.backspace, false)
            default: mapped = nil
            }
            if let (mappedKey, line) = mapped {
                return key(KeyEvent(key: mappedKey, mods: Mods(shift: m.shift, cmd: line)), layout)
            } else {
                // Ctrl-K deletes to the end of the line, or the line break at its end.
                breakHistoryGroup()
                if isHiddenMultiline && isPristine() {
                    insert("")
                    return out
                }
                let (a, b) = range()
                let end = (a == b) ? lineEdge(layout, end: true) : b
                let textLen = text.utf8.count
                let to: Int
                if end > a {
                    to = end
                } else if a < textLen {
                    to = editNextChar(text, a)
                } else {
                    to = a
                }
                if to > a {
                    replace((a, to), "", typing: false)
                }
                return out
            }
        }
        if ev.isCommandChord() { return out }
        let isInlineText: Bool
        if case .text(let s) = ev.key, !s.utf8.contains(UInt8(ascii: "\r")), !s.utf8.contains(UInt8(ascii: "\n")) {
            isInlineText = true
        } else {
            isInlineText = false
        }
        if !isInlineText {
            breakHistoryGroup()
        }
        #if os(macOS)
        let word = m.alt
        #else
        let word = m.alt || m.ctrl
        #endif

        switch ev.key {
        case .text(let s):
            let hasAllowedChar = s.unicodeScalars.contains { c in
                !editIsScalarControl(c) || (!isSingleLine && (c == "\n" || c == "\r" || c == "\t"))
            }
            if hasAllowedChar {
                let sanitized = sanitize(s)
                if !sanitized.isEmpty {
                    let noBreak = !sanitized.utf8.contains(UInt8(ascii: "\r")) && !sanitized.utf8.contains(UInt8(ascii: "\n"))
                    replace(range(), sanitized, typing: noBreak)
                }
            }

        case .enter where preedit != nil, .escape where preedit != nil:
            // A composition's Return and Escape are the input method's.
            break

        case .enter:
            if isSingleLine {
                out.submit = true
            } else if secureFlag {
                if m.cmd || m.ctrl {
                    out.submit = true
                } else {
                    replace(range(), "\n", typing: false)
                }
            } else {
                let (a, b) = range()
                let lineIdx = lineOfByte(a)
                let blk = lineIdx < blocksStorage.count ? blocksStorage[lineIdx] : .paragraph
                let lr = lineRange(lineIdx)
                if m.shift && richFlag {
                    insertNewline(blk, soft: true)
                } else if m.shift || m.alt {
                    insertNewline(blk, soft: false)
                } else {
                    switch blk {
                    case .code:
                        let nextIsCode = (lineIdx + 1 < blocksStorage.count) && (blocksStorage[lineIdx + 1] == .code)
                        if a == b && lr.isEmpty && !nextIsCode {
                            setBlock(.paragraph)
                        } else {
                            insertNewline(.code, soft: false)
                        }
                    case .bullet, .numbered:
                        if a == b && lr.isEmpty {
                            setBlock(.paragraph)
                        } else {
                            insertNewline(blk, soft: false)
                        }
                    case .quote:
                        if a == b && lr.isEmpty {
                            setBlock(.paragraph)
                        } else {
                            insertNewline(.quote, soft: false)
                        }
                    case .paragraph:
                        out.submit = true
                    }
                }
            }

        case .tab:
            if !m.cmd && !m.alt && !m.ctrl && !secureFlag && !isSingleLine {
                if activeBlock() == .code && !m.shift {
                    replace(range(), "\t", typing: true)
                } else if m.shift {
                    outdentList()
                } else {
                    indentList()
                }
            }

        case .pageUp, .pageDown:
            break

        case .escape:
            out.blur = true

        case .backspace:
            let (a, b) = range()
            if a != b || (isHiddenMultiline && isPristine()) {
                insert("")
            } else {
                let lineIdx = lineOfByte(a)
                let lr = lineRange(lineIdx)
                let blk = lineIdx < blocksStorage.count ? blocksStorage[lineIdx] : .paragraph
                let isSoft = editSortedContains(softBreaksStorage, UInt32(lineIdx))
                if !m.cmd && !word && a == lr.lowerBound && !isSoft && blk != .paragraph {
                    switch blk {
                    case .bullet(let lvl), .numbered(let lvl):
                        if lvl > 0 {
                            setBlock(blk.withLevel(lvl - 1))
                        } else {
                            setBlock(.paragraph)
                        }
                    case .quote, .code:
                        if a == 0 || lr.isEmpty {
                            setBlock(.paragraph)
                        } else {
                            let from = editPrevChar(text, a)
                            replace((from, a), "", typing: false)
                        }
                    case .paragraph:
                        break
                    }
                } else if a > 0 {
                    let from: Int
                    if m.cmd {
                        if secureFlag && !revealedFlag {
                            from = 0
                        } else {
                            let bytes = Array(text.utf8)
                            var nlIdx: Int? = nil
                            var k = min(a, bytes.count)
                            while k > 0 {
                                k -= 1
                                if bytes[k] == UInt8(ascii: "\n") {
                                    nlIdx = k
                                    break
                                }
                            }
                            from = nlIdx.map { $0 + 1 } ?? 0
                        }
                    } else if word {
                        from = prevWord(a)
                    } else {
                        from = editPrevChar(text, a)
                    }
                    replace((from, a), "", typing: false)
                }
            }

        case .delete:
            let (a, b) = range()
            let textLen = text.utf8.count
            if a != b || (isHiddenMultiline && isPristine()) {
                insert("")
            } else if a < textLen {
                let to = word ? nextWord(a) : editNextChar(text, a)
                replace((a, to), "", typing: false)
            }

        case .left:
            let i: Int
            if m.cmd {
                i = lineEdge(layout, end: false)
            } else if word {
                i = prevWord(focus)
            } else {
                i = editPrevChar(text, focus)
            }
            moveH(i, m.shift)

        case .right where !m.shift && !m.cmd && !m.alt && !m.ctrl && atEndOfTrailingBlock():
            leaveTrailingBlock()

        case .down where !m.shift && !m.cmd && !m.alt && !m.ctrl && atEndOfTrailingBlock():
            leaveTrailingBlock()

        case .right:
            let i: Int
            if m.cmd {
                i = lineEdge(layout, end: true)
            } else if word {
                i = nextWord(focus)
            } else {
                i = editNextChar(text, focus)
            }
            moveH(i, m.shift)

        case .home:
            set(0, m.shift)

        case .end:
            set(text.utf8.count, m.shift)

        case .up, .down:
            let down = (ev.key == .down)
            let n = text.utf8.count
            let rawI: Int
            if m.cmd || (secureFlag && !revealedFlag) {
                rawI = down ? n : 0
            } else if let l = layout {
                if let j = l.moveLine(byte: displayIndex(focus), down: down) {
                    let mapped = modelIndex(j)
                    rawI = (mapped == focus) ? (down ? n : 0) : mapped
                } else {
                    rawI = n
                }
            } else {
                rawI = down ? n : 0
            }
            let i = min(max(rawI, 0), n)
            if m.shift {
                focus = Self.clampCharBoundary(text, i)
                snapToPills()
                pendingStyle = nil
            } else {
                setCaret(i)
            }

        case .command(let c):
            let lower = Character(String(c).lowercased())
            switch lower {
            case "z" where m.shift:
                redo()
            case "z":
                undo()
            case "a":
                anchor = 0
                focus = text.utf8.count
                pendingStyle = nil
            case "b", "i", "u":
                if let mark = formatChord(ev) {
                    toggleMark(mark)
                }
            case "c" where !secureFlag:
                out.copy = selected()
            case "x" where !secureFlag:
                out.copy = selected()
                insert("")
            default:
                break
            }

        case .function, .contextMenu, .modifier:
            break
        }
        return out
    }

    func atEndOfTrailingBlock() -> Bool {
        let n = text.utf8.count
        guard !secureFlag,
              !isSingleLine,
              preedit == nil,
              anchor == n,
              focus == n,
              let last = blocksStorage.last
        else { return false }
        return last == .code || last == .quote
    }

    mutating func leaveTrailingBlock() {
        syncInvariants()
        breakHistoryGroup()
        let before = snapshot()
        let n = text.utf8.count
        pendingStyle = nil
        applyTextAndAttrReplace((n, n), "\n", [], .paragraph, false)
        recordChange(before, typing: false)
    }

    func lineEdge(_ layout: (any TextEditLayout)?, end: Bool) -> Int {
        let bytes = Array(text.utf8)
        let n = bytes.count
        if secureFlag && !revealedFlag {
            return end ? n : 0
        }
        if let l = layout {
            return modelIndex(l.lineEdge(byte: displayIndex(focus), end: end))
        }
        let clampedFocus = min(max(focus, 0), n)
        if end {
            for idx in clampedFocus..<n where bytes[idx] == UInt8(ascii: "\n") {
                return idx
            }
            return n
        } else {
            var idx = clampedFocus
            while idx > 0 {
                idx -= 1
                if bytes[idx] == UInt8(ascii: "\n") {
                    return idx + 1
                }
            }
            return 0
        }
    }

    @discardableResult
    public mutating func ime(_ ev: Ime) -> EditOutcome {
        if secureFlag {
            clearPreedit()
            return EditOutcome()
        }
        syncInvariants()
        breakHistoryGroup()
        switch ev {
        case .preedit(let s, let cur):
            preedit = s.isEmpty ? nil : (s, cur)
        case .commit(let s):
            preedit = nil
            let sanitized = sanitize(s)
            insert(sanitized)
        case .enabled, .disabled:
            break
        }
        return EditOutcome()
    }

    @discardableResult
    public mutating func paste(_ s: String) -> EditOutcome {
        normalizeHiddenSelection()
        let sanitized = sanitize(s)
        insert(sanitized)
        return EditOutcome()
    }

    /// Paste rich HTML (`htmlStr`) with plain-text fallback (`plain`) into `self` at the current
    /// selection, recorded as a single undo step. Does not touch the OS clipboard.
    @discardableResult
    public mutating func pasteHtml(_ htmlStr: String, _ plain: String) -> EditOutcome {
        pasteRich(htmlStr, plain, pills: false)
    }

    /// `pasteHtml`, keeping the HTML's `Mark.pill`s.
    @discardableResult
    public mutating func pasteHtmlWithPills(_ htmlStr: String, _ plain: String) -> EditOutcome {
        pasteRich(htmlStr, plain, pills: true)
    }

    mutating func pasteRich(_ htmlStr: String, _ plain: String, pills: Bool) -> EditOutcome {
        if secureFlag || htmlStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return paste(plain)
        }
        var rawFrag = Self.fromHtml(htmlStr)
        if !pills {
            rawFrag.marksStorage.removeAll { $0.mark.isPill }
        }
        let frag = keepAllowed(rawFrag)
        let unformatted = frag.marksStorage.isEmpty && frag.blocksStorage.allSatisfy { $0 == .paragraph }
        if !plain.isEmpty && (frag.text.isEmpty || unformatted) {
            return paste(plain)
        }
        if !richFlag {
            return paste(plain.isEmpty ? frag.text : plain)
        }
        syncInvariants()
        if !isSingleLine {
            let (a, _) = range()
            let lineIdx = lineOfByte(a)
            if lineIdx < blocksStorage.count && blocksStorage[lineIdx] == .code {
                return paste(plain.isEmpty ? frag.text : plain)
            }
        }
        breakHistoryGroup()
        let before = snapshot()
        let (a, b) = range()

        if isSingleLine {
            let fragLen = frag.text.utf8.count
            var cleanScalars = String.UnicodeScalarView()
            cleanScalars.reserveCapacity(frag.text.unicodeScalars.count)
            var cleanByteLen = 0
            var byteMap = Array(repeating: 0, count: fragLen + 1)
            var srcByte = 0
            var lastWasSpace = false
            for ch in frag.text.unicodeScalars {
                byteMap[srcByte] = cleanByteLen
                let chLen = ch.utf8.count
                if !editIsScalarControl(ch) && ch.value != 0x2028 && ch.value != 0x2029 {
                    cleanScalars.append(ch)
                    cleanByteLen += chLen
                    lastWasSpace = (ch == " ")
                } else if ch == "\n" && !lastWasSpace && cleanByteLen > 0 {
                    cleanScalars.append(" ")
                    cleanByteLen += 1
                    lastWasSpace = true
                }
                srcByte += chLen
            }
            byteMap[fragLen] = cleanByteLen
            let clean = String(cleanScalars)
            applyTextAndAttrReplace((a, b), clean, [], nil, false)
            for m in frag.marksStorage {
                let sIdx = a + byteMap[min(max(m.start, 0), fragLen)]
                let eIdx = a + byteMap[min(max(m.end, 0), fragLen)]
                if sIdx < eIdx {
                    marksStorage.append(MarkRange(start: sIdx, end: eIdx, mark: m.mark))
                }
            }
            pendingStyle = nil
            normalizeMarks()
            recordChange(before, typing: false)
            return EditOutcome()
        }

        if a < b {
            applyTextAndAttrReplace((a, b), "", [], nil, false)
        }
        let insAt = a
        let lineIdx = lineOfByte(insAt)
        let lr = lineRange(lineIdx)
        let lineWasEmpty = lr.isEmpty
        let origBlock = lineIdx < blocksStorage.count ? blocksStorage[lineIdx] : .paragraph

        applyTextAndAttrReplace((insAt, insAt), frag.text, [], nil, false)

        let fragLines = frag.blocksStorage.count
        if fragLines == 1 {
            if lineWasEmpty && origBlock == .paragraph && frag.blocksStorage[0] != .paragraph {
                if lineIdx < blocksStorage.count {
                    blocksStorage[lineIdx] = frag.blocksStorage[0]
                }
            }
        } else if fragLines > 1 {
            if (lineWasEmpty || insAt == lr.lowerBound) && origBlock == .paragraph {
                if lineIdx < blocksStorage.count {
                    blocksStorage[lineIdx] = frag.blocksStorage[0]
                }
            }
            for k in 1..<fragLines where (lineIdx + k) < blocksStorage.count {
                blocksStorage[lineIdx + k] = frag.blocksStorage[k]
            }
            for sb in frag.softBreaksStorage {
                let target = lineIdx + Int(sb)
                if target > 0 {
                    softBreaksStorage.append(UInt32(target))
                }
            }
        }

        for m in frag.marksStorage {
            marksStorage.append(MarkRange(
                start: insAt + m.start,
                end: insAt + m.end,
                mark: m.mark
            ))
        }
        pendingStyle = nil
        syncInvariants()
        recordChange(before, typing: false)
        return EditOutcome()
    }
}
