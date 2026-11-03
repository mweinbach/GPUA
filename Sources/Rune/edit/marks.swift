// Ported from: crates/rune/src/edit/marks.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Inline marks and paragraph blocks on a `TextEdit`: keeping them in step with the text,
//! toggling them, and list indentation.

extension TextEdit {
    /// Synchronize `blocks`, `softBreaks`, and `marks` with `self.text`.
    mutating func syncInvariants() {
        anchor = Self.clampCharBoundary(text, anchor)
        focus = Self.clampCharBoundary(text, focus)
        if secureFlag {
            marksStorage.removeAll()
            blocksStorage.removeAll()
            softBreaksStorage.removeAll()
            pendingStyle = nil
            return
        }
        let lineCount = 1 + editCountNewlines(text)
        if blocksStorage.count < lineCount {
            blocksStorage.append(contentsOf: repeatElement(.paragraph, count: lineCount - blocksStorage.count))
        } else if blocksStorage.count > lineCount {
            blocksStorage.removeLast(blocksStorage.count - lineCount)
        }
        if let bits = allowedBlocks {
            for i in blocksStorage.indices {
                if (bits & blocksStorage[i].kindBit) == 0 {
                    blocksStorage[i] = .paragraph
                }
            }
        }
        if !softBreaksStorage.isEmpty {
            softBreaksStorage.sort()
            var deduped: [UInt32] = []
            deduped.reserveCapacity(softBreaksStorage.count)
            for idx in softBreaksStorage where idx > 0 && Int(idx) < lineCount {
                if deduped.last != idx {
                    deduped.append(idx)
                }
            }
            softBreaksStorage = deduped
        }
        normalizeMarks()
        snapToPills()
        let anchorLine = lineOfByte(anchor)
        if let (armed, currentMarks) = pendingStyle {
            if armed != (anchor, focus) || (anchorLine < blocksStorage.count && blocksStorage[anchorLine] == .code) {
                pendingStyle = nil
            } else if let bits = allowedMarks {
                let filtered = currentMarks.filter { (bits & (1 << UInt16($0.kindOrder))) != 0 }
                pendingStyle = (armed, filtered)
            }
        }
    }

    mutating func normalizeMarks() {
        if let bits = allowedMarks {
            marksStorage.removeAll { (bits & (1 << UInt16($0.mark.kindOrder))) == 0 }
        }
        if marksStorage.isEmpty {
            return
        }
        let bytes = Array(text.utf8)
        let len = bytes.count
        for i in marksStorage.indices {
            marksStorage[i].start = Self.clampCharBoundary(text, marksStorage[i].start)
            marksStorage[i].end = Self.clampCharBoundary(text, marksStorage[i].end)
        }
        marksStorage.removeAll { !($0.start < $0.end && $0.end <= len) }

        // Strip inline marks from any `Block.code` paragraph.
        if blocksStorage.contains(.code) {
            var lineStart = 0
            var idx = 0
            var codeRanges: [Range<Int>] = []
            for i in 0..<bytes.count where bytes[i] == UInt8(ascii: "\n") {
                if idx < blocksStorage.count && blocksStorage[idx] == .code {
                    codeRanges.append(lineStart..<(i + 1))
                }
                lineStart = i + 1
                idx += 1
            }
            if idx < blocksStorage.count && blocksStorage[idx] == .code {
                codeRanges.append(lineStart..<len)
            }

            var out: [MarkRange] = []
            out.reserveCapacity(marksStorage.count)
            for m in marksStorage {
                var start = m.start
                var lo = 0
                var hi = codeRanges.count
                while lo < hi {
                    let mid = lo + (hi - lo) / 2
                    if codeRanges[mid].upperBound <= start {
                        lo = mid + 1
                    } else {
                        hi = mid
                    }
                }
                for crIdx in lo..<codeRanges.count {
                    let cr = codeRanges[crIdx]
                    if cr.lowerBound >= m.end {
                        break
                    }
                    if start < cr.lowerBound {
                        out.append(MarkRange(start: start, end: cr.lowerBound, mark: m.mark))
                    }
                    start = max(start, cr.upperBound)
                }
                if start < m.end {
                    out.append(MarkRange(start: start, end: m.end, mark: m.mark))
                }
            }
            marksStorage = out
        }

        // Merge overlapping or adjacent ranges of the same mark kind.
        // For `Mark.link`, later entries win over earlier overlapping links.
        var byKind: [[MarkRange]] = Array(repeating: [], count: 7)
        for m in marksStorage where m.start < m.end {
            byKind[Int(m.mark.kindOrder)].append(m)
        }
        marksStorage.removeAll(keepingCapacity: true)

        var merged: [MarkRange] = []
        for kindIdx in 0..<7 {
            var list = byKind[kindIdx]
            if list.isEmpty { continue }
            if kindIdx == 6 {
                // `Mark.pill`: whole objects on one line that never merge; the first of two
                // overlapping pills wins.
                list.sort { ($0.start, $0.end) < ($1.start, $1.end) }
                var end = 0
                for m in list {
                    if m.start >= end && !bytes[m.start..<m.end].contains(UInt8(ascii: "\n")) {
                        end = m.end
                        merged.append(m)
                    }
                }
            } else if kindIdx == 5 {
                // `Mark.link`: resolve overlaps so later links overwrite earlier ones, then merge adjacent equal URLs.
                var bounds = list.map { ($0.start, $0.end) }
                bounds.sort { $0 < $1 }
                var overlapping = false
                if bounds.count >= 2 {
                    for i in 0..<(bounds.count - 1) where bounds[i + 1].0 < bounds[i].1 {
                        overlapping = true
                        break
                    }
                }
                var resolved: [MarkRange] = []
                if !overlapping {
                    resolved = list
                } else {
                    for link in list {
                        var nextResolved: [MarkRange] = []
                        nextResolved.reserveCapacity(resolved.count + 1)
                        for old in resolved {
                            if old.end <= link.start || old.start >= link.end {
                                nextResolved.append(old)
                            } else {
                                if old.start < link.start {
                                    nextResolved.append(MarkRange(start: old.start, end: link.start, mark: old.mark))
                                }
                                if old.end > link.end {
                                    nextResolved.append(MarkRange(start: link.end, end: old.end, mark: old.mark))
                                }
                            }
                        }
                        nextResolved.append(link)
                        resolved = nextResolved
                    }
                }
                resolved.sort { ($0.start, $0.end) < ($1.start, $1.end) }
                if var cur = resolved.first {
                    for m in resolved.dropFirst() {
                        if m.mark == cur.mark && m.start <= cur.end {
                            cur.end = max(cur.end, m.end)
                        } else {
                            merged.append(cur)
                            cur = m
                        }
                    }
                    merged.append(cur)
                }
            } else {
                list.sort { ($0.start, $0.end) < ($1.start, $1.end) }
                if var cur = list.first {
                    for m in list.dropFirst() {
                        if m.start <= cur.end {
                            cur.end = max(cur.end, m.end)
                        } else {
                            merged.append(cur)
                            cur = m
                        }
                    }
                    merged.append(cur)
                }
            }
        }

        merged.sort { ($0.start, $0.end, $0.mark.kindOrder) < ($1.start, $1.end, $1.mark.kindOrder) }
        marksStorage = merged
    }

    /// Marks inherited from the character before `pos` according to AppKit rules:
    /// typing inside (`m.start < pos < m.end`) or at the trailing edge (`m.start < pos == m.end`)
    /// of a mark inherits it; typing at the start of a mark (`pos == m.start`) does not extend it.
    func inheritedMarksAt(_ pos: Int) -> [Mark] {
        if marksStorage.isEmpty {
            return []
        }
        let lineIdx = lineOfByte(pos)
        if lineIdx < blocksStorage.count && blocksStorage[lineIdx] == .code {
            return []
        }
        let lineStart = lineRange(lineIdx).lowerBound
        if pos <= lineStart {
            return []
        }
        var out: [Mark] = []
        for m in marksStorage {
            if m.start < pos && pos <= m.end && !m.mark.isPill && !out.contains(where: { $0.sameKind(m.mark) }) {
                out.append(m.mark)
            }
        }
        return out
    }

    /// Whether `mark` covers the entire byte range `start..<end` (`start < end`).
    func rangeHasMark(_ start: Int, _ end: Int, _ mark: Mark) -> Bool {
        if start >= end {
            return false
        }
        let matchAnyLink: Bool
        if case .link(let u) = mark, u.isEmpty {
            matchAnyLink = true
        } else {
            matchAnyLink = false
        }
        return marksStorage.contains { m in
            let kindMatches: Bool
            if matchAnyLink {
                if case .link = m.mark { kindMatches = true } else { kindMatches = false }
            } else {
                kindMatches = (m.mark == mark)
            }
            return kindMatches && m.start <= start && end <= m.end
        }
    }

    /// Active inline marks at the caret (including pending typing style) or covering the whole
    /// selection, for driving a formatting bar's pressed state.
    public func activeMarks() -> [Mark] {
        let (a, b) = range()
        if a == b {
            let lineIdx = lineOfByte(a)
            if lineIdx < blocksStorage.count && blocksStorage[lineIdx] == .code {
                return []
            }
            if let (armed, p) = pendingStyle, armed == (anchor, focus) {
                return p
            }
            return inheritedMarksAt(a)
        }
        var out: [Mark] = []
        for m in marksStorage {
            if m.start <= a && b <= m.end && !out.contains(m.mark) {
                out.append(m.mark)
            }
        }
        return out
    }

    /// Whether `mark` is active at the caret or covers the whole selection.
    /// Passing `Mark.link("")` checks whether *any* link is active.
    public func hasMark(_ mark: Mark) -> Bool {
        let matchAnyLink: Bool
        if case .link(let u) = mark, u.isEmpty {
            matchAnyLink = true
        } else {
            matchAnyLink = false
        }
        return activeMarks().contains { m in
            if matchAnyLink {
                if case .link = m { return true }
                return false
            }
            return m == mark
        }
    }

    /// The URL of the active `Mark.link` at the caret or covering the selection, if any.
    public func activeLink() -> String? {
        let (a, b) = range()
        if a == b {
            if let (armed, p) = pendingStyle, armed == (anchor, focus) {
                for m in p {
                    if let u = m.linkUrl() { return u }
                }
                return nil
            }
            let lineIdx = lineOfByte(a)
            if (lineIdx < blocksStorage.count && blocksStorage[lineIdx] == .code) || a <= lineRange(lineIdx).lowerBound {
                return nil
            }
            for m in marksStorage where m.start < a && a <= m.end {
                if let u = m.mark.linkUrl() { return u }
            }
            return nil
        }
        for m in marksStorage where m.start <= a && b <= m.end {
            if let u = m.mark.linkUrl() { return u }
        }
        return nil
    }

    mutating func editPendingMarks(_ pos: Int, _ f: (inout [Mark]) -> Void) {
        let lineIdx = lineOfByte(pos)
        if lineIdx < blocksStorage.count && blocksStorage[lineIdx] == .code {
            return
        }
        var active = activeMarks()
        f(&active)
        pendingStyle = ((anchor, focus), active)
    }

    /// Toggle `mark` on the selection, or in the pending typing style when the selection is empty.
    public mutating func toggleMark(_ mark: Mark) {
        if secureFlag || !allowsMark(mark) {
            return
        }
        syncInvariants()
        let (a, b) = range()
        if a == b {
            if !mark.isPill {
                editPendingMarks(a) { active in
                    if let pos = active.firstIndex(where: { $0.sameKind(mark) }) {
                        let emptyLink: Bool
                        if case .link(let u) = mark, u.isEmpty { emptyLink = true } else { emptyLink = false }
                        if active[pos] == mark || emptyLink {
                            active.remove(at: pos)
                        } else {
                            active[pos] = mark
                        }
                    } else {
                        active.append(mark)
                    }
                }
            }
            return
        }
        if rangeHasMark(a, b, mark) {
            removeMark(mark)
        } else {
            setMark(mark)
        }
    }

    /// Apply `mark` to the current selection (or add it to pending typing style when empty).
    public mutating func setMark(_ mark: Mark) {
        if secureFlag || !allowsMark(mark) {
            return
        }
        syncInvariants()
        let (a, b) = range()
        if a == b {
            if !mark.isPill {
                editPendingMarks(a) { active in
                    if let pos = active.firstIndex(where: { $0.sameKind(mark) }) {
                        active[pos] = mark
                    } else {
                        active.append(mark)
                    }
                }
            }
            return
        }
        breakHistoryGroup()
        let before = snapshot()
        if mark.isPill {
            marksStorage.removeAll { $0.mark.isPill && !($0.end <= a || $0.start >= b) }
        }
        marksStorage.append(MarkRange(start: a, end: b, mark: mark))
        pendingStyle = nil
        normalizeMarks()
        recordChange(before, typing: false)
    }

    /// Remove `mark` (matching by `Mark.sameKind`) from the current selection, or from pending
    /// typing style when the selection is empty.
    public mutating func removeMark(_ mark: Mark) {
        if secureFlag {
            return
        }
        syncInvariants()
        let (a, b) = range()
        if a == b {
            var active = activeMarks()
            active.removeAll { $0.sameKind(mark) }
            pendingStyle = ((anchor, focus), active)
            return
        }
        breakHistoryGroup()
        let before = snapshot()
        var out: [MarkRange] = []
        out.reserveCapacity(marksStorage.count)
        for m in marksStorage {
            if !m.mark.sameKind(mark) || m.end <= a || m.start >= b {
                out.append(m)
            } else if m.mark.isPill {
                // A pill goes whole: its label stays as plain text.
            } else {
                if m.start < a {
                    out.append(MarkRange(start: m.start, end: a, mark: m.mark))
                }
                if m.end > b {
                    out.append(MarkRange(start: b, end: m.end, mark: m.mark))
                }
            }
        }
        marksStorage = out
        pendingStyle = nil
        normalizeMarks()
        recordChange(before, typing: false)
    }

    /// Apply or remove a `Mark.link` on the selection (or pending style when empty).
    /// Passing `nil` or `""` removes any link on the selection.
    public mutating func setLink(_ url: String?) {
        let trimmed = url?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let u = trimmed, !u.isEmpty {
            setMark(.link(u))
        } else {
            removeMark(.link(""))
        }
    }

    /// Line index range `(firstLine, lastLine)` covered by the current selection.
    func selectedLineRange() -> (Int, Int) {
        let (a, b) = range()
        let first = lineOfByte(a)
        let bytes = Array(text.utf8)
        let last: Int
        if b > a && b - 1 < bytes.count && bytes[b - 1] == UInt8(ascii: "\n") {
            last = lineOfByte(b - 1)
        } else {
            last = lineOfByte(b)
        }
        return (first, max(last, first))
    }

    /// The `Block` attribute of the paragraph at the caret or selection.
    public func activeBlock() -> Block {
        let (first, _) = selectedLineRange()
        return first < blocksStorage.count ? blocksStorage[first] : .paragraph
    }

    /// Alias for `TextEdit.activeBlock`: the `Block` attribute of the paragraph at the caret.
    public func currentBlock() -> Block {
        activeBlock()
    }

    /// Whether any paragraph in the current selection is a bullet or numbered list item.
    public func selectionInList() -> Bool {
        let (first, last) = selectedLineRange()
        for i in first...last {
            let blk = i < blocksStorage.count ? blocksStorage[i] : .paragraph
            if blk.isList() { return true }
        }
        return false
    }

    /// Set the `Block` attribute for all paragraphs in the current selection.
    public mutating func setBlock(_ block: Block) {
        if secureFlag || isSingleLine || !allowsBlock(block) {
            return
        }
        let clampedBlock = block.withLevel(block.listLevel() ?? 0)
        syncInvariants()
        breakHistoryGroup()
        let before = snapshot()
        let (first, last) = selectedLineRange()
        for i in first...last where i < blocksStorage.count {
            blocksStorage[i] = clampedBlock
        }
        if clampedBlock == .code {
            pendingStyle = nil
        }
        normalizeMarks()
        recordChange(before, typing: false)
    }

    /// Toggle `block` on all paragraphs in the selection.
    public mutating func toggleBlock(_ block: Block) {
        if secureFlag || isSingleLine || !allowsBlock(block) {
            return
        }
        syncInvariants()
        let (first, last) = selectedLineRange()
        let allMatch = (first...last).allSatisfy { i in
            let cur = i < blocksStorage.count ? blocksStorage[i] : .paragraph
            return cur.sameKind(block)
        }
        if allMatch {
            setBlock(.paragraph)
        } else {
            breakHistoryGroup()
            let before = snapshot()
            let clampedTarget = block.withLevel(block.listLevel() ?? 0)
            for i in first...last where i < blocksStorage.count {
                let cur = blocksStorage[i]
                switch (cur.listLevel(), clampedTarget) {
                case (let lvl?, .bullet(0)):
                    blocksStorage[i] = .bullet(lvl)
                case (let lvl?, .numbered(0)):
                    blocksStorage[i] = .numbered(lvl)
                default:
                    blocksStorage[i] = clampedTarget
                }
            }
            if clampedTarget == .code {
                pendingStyle = nil
            }
            normalizeMarks()
            recordChange(before, typing: false)
        }
    }

    /// Increase list nesting level (`Tab`) for list items in the selection, up to `MAX_LIST_LEVEL`.
    @discardableResult
    public mutating func indentList() -> Bool {
        if secureFlag || isSingleLine {
            return false
        }
        syncInvariants()
        if !selectionInList() {
            return false
        }
        breakHistoryGroup()
        let before = snapshot()
        let (first, last) = selectedLineRange()
        for i in first...last where i < blocksStorage.count {
            if let lvl = blocksStorage[i].listLevel() {
                blocksStorage[i] = blocksStorage[i].withLevel(min(lvl + 1, MAX_LIST_LEVEL))
            }
        }
        recordChange(before, typing: false)
        return true
    }

    /// Decrease list nesting level (`Shift+Tab`) for list items in the selection.
    @discardableResult
    public mutating func outdentList() -> Bool {
        if secureFlag || isSingleLine {
            return false
        }
        syncInvariants()
        if !selectionInList() {
            return false
        }
        breakHistoryGroup()
        let before = snapshot()
        let (first, last) = selectedLineRange()
        for i in first...last where i < blocksStorage.count {
            if let lvl = blocksStorage[i].listLevel() {
                blocksStorage[i] = blocksStorage[i].withLevel(lvl > 0 ? lvl - 1 : 0)
            }
        }
        recordChange(before, typing: false)
        return true
    }
}
