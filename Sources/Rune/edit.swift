// Ported from: crates/rune/src/edit.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Single and rich text-field editing: the attributed model an app owns (`TextEdit`) and the
//! key/IME events the shell routes to the focused field. Movement that depends on wrapping
//! (up/down, line start/end) uses the field's current layout, rebuilt by the runtime before each
//! event.
//!
//! Invariants: `anchor` and `focus` are UTF-8 byte offsets on Unicode scalar boundaries of `text`;
//! preedit text is never part of `text` until committed; inline `marks` are non-empty scalar-boundary
//! byte ranges sorted by start; `blocks` has one entry per `\n`-separated line of `text`.

/// Fixed mask shown by a hidden multi-line secure field when non-empty, hiding both byte length
/// and line count.
let MULTILINE_SECURE_MASK: String = "••••••••••••"

/// Mirrors whether the bound `textInput` has `El.singleLine`.
/// Before a field mounts, standalone `TextEdit.secure` defaults to single-line.
enum TextEditLineMode: Sendable, Equatable {
    case `default`
    case single
    case multi
}

/// What an edit asks of the host.
public struct EditOutcome: Sendable, Equatable {
    public var submit: Bool
    public var copy: String?
    public var blur: Bool

    public init(submit: Bool = false, copy: String? = nil, blur: Bool = false) {
        self.submit = submit
        self.copy = copy
        self.blur = blur
    }
}

/// Single and rich text-field editing model.
public struct TextEdit: Equatable, Hashable, CustomDebugStringConvertible {
    /// Use `replaceText` to replace a secret cleanly and reset history/pristine state.
    public var text: String
    public var anchor: Int
    public var focus: Int
    /// IME composition shown at the caret, with its selected UTF-8 byte range.
    public var preedit: (String, (Int, Int)?)?
    public var focused: Bool

    var marksStorage: [MarkRange]
    var blocksStorage: [Block]
    /// Line indices (`> 0`) created by `Shift+Return` (`<br>`): indented with their block,
    /// without starting a new list marker or incrementing list numbering.
    var softBreaksStorage: [UInt32]
    /// Pending typing style armed at `(anchor, focus)` when toggling marks on an empty selection.
    var pendingStyle: ((Int, Int), [Mark])?
    var historyStorage: History
    /// Set inside `TextEdit.undoGroup`: edits record nothing until the outermost group ends.
    var groupBox: ActiveGroupBox?
    var secureFlag: Bool
    var revealedFlag: Bool
    var lineMode: TextEditLineMode
    var richFlag: Bool
    var allowedMarks: UInt16?
    var allowedBlocks: UInt8?
    var editedFlag: Bool

    public init(_ text: String = "") {
        let utf8Len = text.utf8.count
        let lineCount = 1 + editCountNewlines(text)
        self.text = text
        self.anchor = utf8Len
        self.focus = utf8Len
        self.preedit = nil
        self.focused = false
        self.marksStorage = []
        self.blocksStorage = Array(repeating: .paragraph, count: lineCount)
        self.softBreaksStorage = []
        self.pendingStyle = nil
        self.historyStorage = History()
        self.groupBox = nil
        self.secureFlag = false
        self.revealedFlag = false
        self.lineMode = .default
        self.richFlag = false
        self.allowedMarks = nil
        self.allowedBlocks = nil
        self.editedFlag = false
    }

    public static func new(_ text: String = "") -> TextEdit {
        TextEdit(text)
    }

    /// Construct a `TextEdit` from plain text, inline `MarkRange`s, and per-line `Block`s.
    /// Caret starts at the end of `text`. Ranges are clamped to scalar boundaries and canonicalized,
    /// and `blocks` is padded or truncated to match the number of `\n`-separated lines in `text`.
    public static func fromParts(_ text: String, _ marks: [MarkRange], _ blocks: [Block]) -> TextEdit {
        var edit = TextEdit(text).rich()
        edit.marksStorage = marks
        edit.blocksStorage = blocks
        edit.clampListLevels()
        edit.syncInvariants()
        return edit
    }

    mutating func clampListLevels() {
        for i in blocksStorage.indices {
            let b = blocksStorage[i]
            blocksStorage[i] = b.withLevel(b.listLevel() ?? 0)
        }
    }

    public var debugDescription: String {
        let shown = secureFlag ? "[redacted]" : text
        return "TextEdit(text: \(shown.debugDescription), anchor: \(anchor), focus: \(focus), focused: \(focused), marks: \(marksStorage), blocks: \(blocksStorage), secure: \(secureFlag), revealed: \(revealedFlag))"
    }

    public static func == (lhs: TextEdit, rhs: TextEdit) -> Bool {
        guard lhs.text.utf8.elementsEqual(rhs.text.utf8),
              lhs.anchor == rhs.anchor,
              lhs.focus == rhs.focus,
              lhs.focused == rhs.focused,
              lhs.marksStorage == rhs.marksStorage,
              lhs.blocksStorage == rhs.blocksStorage,
              lhs.softBreaksStorage == rhs.softBreaksStorage,
              lhs.historyStorage == rhs.historyStorage,
              lhs.secureFlag == rhs.secureFlag,
              lhs.revealedFlag == rhs.revealedFlag,
              lhs.lineMode == rhs.lineMode,
              lhs.richFlag == rhs.richFlag,
              lhs.allowedMarks == rhs.allowedMarks,
              lhs.allowedBlocks == rhs.allowedBlocks
        else { return false }

        switch (lhs.pendingStyle, rhs.pendingStyle) {
        case (nil, nil):
            break
        case (let lp?, let rp?):
            guard lp.0.0 == rp.0.0, lp.0.1 == rp.0.1, lp.1 == rp.1 else { return false }
        default:
            return false
        }

        switch (lhs.preedit, rhs.preedit) {
        case (nil, nil):
            return true
        case (let lp?, let rp?):
            guard lp.0.utf8.elementsEqual(rp.0.utf8) else { return false }
            switch (lp.1, rp.1) {
            case (nil, nil): return true
            case (let lr?, let rr?): return lr.0 == rr.0 && lr.1 == rr.1
            default: return false
            }
        default:
            return false
        }
    }

    /// Hashes everything a field draws: text, selection, IME composition, focus, marks, blocks and
    /// whether it's secure or revealed. A hidden secure field hashes its scalar length (single-line)
    /// or non-empty state (multi-line), not its text.
    public func hash(into hasher: inout Hasher) {
        if isHiddenMultiline {
            hasher.combine(!text.isEmpty)
            hasher.combine(anchor != focus)
        } else if secureFlag && !revealedFlag {
            hasher.combine(text.unicodeScalars.count)
            hasher.combine(anchor)
            hasher.combine(focus)
        } else {
            hasher.combine(text.utf8.count)
            for b in text.utf8 { hasher.combine(b) }
            hasher.combine(anchor)
            hasher.combine(focus)
        }
        if let (pText, pRange) = preedit {
            hasher.combine(true)
            hasher.combine(pText.utf8.count)
            for b in pText.utf8 { hasher.combine(b) }
            if let (pa, pb) = pRange {
                hasher.combine(true)
                hasher.combine(pa)
                hasher.combine(pb)
            } else {
                hasher.combine(false)
            }
        } else {
            hasher.combine(false)
        }
        hasher.combine(focused)
        hasher.combine(marksStorage)
        if !secureFlag {
            hasher.combine(blocksStorage)
        }
        hasher.combine(softBreaksStorage)
        if let ((pa, pf), pMarks) = pendingStyle {
            hasher.combine(true)
            hasher.combine(pa)
            hasher.combine(pf)
            hasher.combine(pMarks)
        } else {
            hasher.combine(false)
        }
        hasher.combine(secureFlag)
        hasher.combine(revealedFlag)
        hasher.combine(isSingleLine)
    }

    /// Rich editing: `⌘B` / `⌘I` / `⌘U` toggle marks, `Shift+Return` inserts a soft break and
    /// `pasteHtml` keeps formatting.
    public func rich() -> TextEdit {
        var copy = self
        copy.richFlag = true
        return copy
    }

    public mutating func setRich(_ rich: Bool) {
        richFlag = rich
    }

    public func isRich() -> Bool {
        richFlag
    }

    /// Keep only these kinds of inline mark; `Mark.pill` is always allowed.
    public func allowMarks<S: Swift.Sequence>(_ marks: S) -> TextEdit where S.Element == Mark {
        var copy = self
        let pillBit: UInt16 = 1 << UInt16(Mark.pill("").kindOrder)
        copy.allowedMarks = marks.reduce(pillBit) { bits, m in
            bits | (1 << UInt16(m.kindOrder))
        }
        copy.syncInvariants()
        return copy
    }

    /// Keep only these kinds of paragraph block; `Block.paragraph` is always allowed.
    public func allowBlocks<S: Swift.Sequence>(_ blocks: S) -> TextEdit where S.Element == Block {
        var copy = self
        copy.allowedBlocks = blocks.reduce(Block.paragraph.kindBit) { bits, b in
            bits | b.kindBit
        }
        copy.syncInvariants()
        return copy
    }

    /// Whether this field keeps marks of `mark`'s kind.
    public func allowsMark(_ mark: Mark) -> Bool {
        guard let bits = allowedMarks else { return true }
        return (bits & (1 << UInt16(mark.kindOrder))) != 0
    }

    /// Whether this field keeps blocks of `block`'s kind.
    public func allowsBlock(_ block: Block) -> Bool {
        guard let bits = allowedBlocks else { return true }
        return (bits & block.kindBit) != 0
    }

    /// The mark a rich field's `⌘B`, `⌘I` or `⌘U` toggles, if this field takes that chord.
    func formatChord(_ ev: KeyEvent) -> Mark? {
        guard case .command(let c) = ev.key else { return nil }
        if ev.mods.shift || ev.mods.alt || !richFlag || secureFlag {
            return nil
        }
        let mark: Mark
        switch c {
        case "b": mark = .bold
        case "i": mark = .italic
        case "u": mark = .underline
        default: return nil
        }
        return allowsMark(mark) ? mark : nil
    }

    /// `frag` without the marks and blocks this field doesn't allow.
    func keepAllowed(_ frag: TextEdit) -> TextEdit {
        var out = frag
        out.allowedMarks = allowedMarks
        out.allowedBlocks = allowedBlocks
        out.syncInvariants()
        return out
    }

    /// No marks, pending style or non-paragraph blocks: draws exactly as plain text.
    func isPlain() -> Bool {
        marksStorage.isEmpty
            && pendingStyle == nil
            && blocksStorage.allSatisfy { $0 == .paragraph }
    }

    /// Parse an HTML fragment into a `TextEdit`.
    public static func fromHtml(_ htmlStr: String) -> TextEdit {
        parseHtml(htmlStr).rich()
    }

    /// Serialize the entire document's text, inline marks, and paragraph blocks to safe HTML.
    public func toHtml() -> String {
        let e = synced()
        return serializeHtml(e, 0..<e.text.utf8.count)
    }

    /// `self` with marks, blocks and caret fitted to `text`.
    func synced() -> TextEdit {
        var e = self
        e.syncInvariants()
        return e
    }

    /// Serialize the current selection (`self.range()`) to HTML, or `""` when the selection is empty.
    public func selectedHtml() -> String {
        let (a, b) = range()
        if a == b || secureFlag {
            return ""
        }
        return serializeHtml(synced(), a..<b)
    }

    /// Inline `MarkRange`s on `self.text`, sorted by start byte.
    public func marks() -> [MarkRange] {
        marksStorage
    }

    /// Paragraph `Block` attributes, one per `\n`-delimited line of `self.text`.
    public func blocks() -> [Block] {
        blocksStorage.isEmpty ? [.paragraph] : blocksStorage
    }

    /// Replace the inline `MarkRange`s on `self.text` and canonicalize them.
    public mutating func setMarks(_ marks: [MarkRange]) {
        marksStorage = marks
        syncInvariants()
    }

    /// Replace the per-line `Block` list on `self.text`.
    public mutating func setBlocks(_ blocks: [Block]) {
        blocksStorage = blocks
        clampListLevels()
        syncInvariants()
    }

    /// Line indices (`> 0`) created by `Shift+Return` (`<br>`) rather than a hard paragraph break.
    public func softBreaks() -> [UInt32] {
        softBreaksStorage
    }

    /// `self` with soft breaks before lines `lines`.
    public func withSoftBreaks(_ lines: [UInt32]) -> TextEdit {
        var copy = self
        copy.setSoftBreaks(lines)
        return copy
    }

    /// Replace the soft breaks. Like `setMarks` and `setBlocks`, this isn't an undo step.
    public mutating func setSoftBreaks(_ lines: [UInt32]) {
        softBreaksStorage = lines
        syncInvariants()
    }

    /// Iterate the `\n`-delimited paragraphs of `self.text` with their byte range and `Block`.
    public func paragraphs() -> [ParagraphInfo] {
        var out: [ParagraphInfo] = []
        var lineStart = 0
        var idx = 0
        let bytes = Array(text.utf8)
        for i in 0..<bytes.count where bytes[i] == UInt8(ascii: "\n") {
            let block = idx < blocksStorage.count ? blocksStorage[idx] : .paragraph
            let softBreak = editSortedContains(softBreaksStorage, UInt32(idx))
            out.append(ParagraphInfo(index: idx, range: lineStart..<i, block: block, softBreak: softBreak))
            lineStart = i + 1
            idx += 1
        }
        let block = idx < blocksStorage.count ? blocksStorage[idx] : .paragraph
        let softBreak = editSortedContains(softBreaksStorage, UInt32(idx))
        out.append(ParagraphInfo(index: idx, range: lineStart..<bytes.count, block: block, softBreak: softBreak))
        return out
    }

    /// Password editing: masked display, no undo, copy, cut or IME.
    public func secure() -> TextEdit {
        var copy = self
        copy.setSecure(true)
        return copy
    }

    public func isSecure() -> Bool {
        secureFlag
    }

    public mutating func setSecure(_ secure: Bool) {
        secureFlag = secure
        if secure {
            historyStorage = History()
            if let box = groupBox, box.isActive {
                box.baseline = .secure
            }
            marksStorage.removeAll()
            blocksStorage.removeAll()
            softBreaksStorage.removeAll()
            pendingStyle = nil
            clearPreedit()
        } else {
            if let box = groupBox, box.isActive, case .secure = box.baseline {
                syncInvariants()
                box.baseline = .snapshot(snapshotNow())
            } else {
                syncInvariants()
            }
        }
    }

    /// Show the plain characters of a `secure` field while keeping all other secure protections.
    public func revealed(_ on: Bool = true) -> TextEdit {
        var copy = self
        copy.setRevealed(on)
        return copy
    }

    public func isRevealed() -> Bool {
        revealedFlag
    }

    public mutating func setRevealed(_ revealed: Bool) {
        revealedFlag = revealed
    }

    mutating func clearPreedit() {
        preedit = nil
    }

    mutating func clearPending() {
        pendingStyle = nil
    }

    /// Replace the whole draft and discard its history, preserving focus and password mode.
    public mutating func replaceText(_ next: String) {
        let lineCount = secureFlag ? 0 : (1 + editCountNewlines(next))
        text = next
        anchor = text.utf8.count
        focus = anchor
        marksStorage.removeAll()
        blocksStorage = Array(repeating: .paragraph, count: lineCount)
        softBreaksStorage.removeAll()
        pendingStyle = nil
        clearPreedit()
        editedFlag = false
        historyStorage = History()
        if let box = groupBox, box.isActive {
            box.baseline = secureFlag ? .secure : .snapshot(snapshotNow())
        }
    }

    /// Whether `self.text` is non-empty and still holds the value the app last set, with no user
    /// edit since `TextEdit.new` or `replaceText`.
    public func isPristine() -> Bool {
        !text.isEmpty && !editedFlag
    }

    /// Mark the current `self.text` as user-edited (`!self.isPristine()`).
    public mutating func markEdited() {
        editedFlag = true
    }

    func hasHistory() -> Bool {
        !historyStorage.undo.isEmpty || !historyStorage.redo.isEmpty
    }

    func sameModel(_ other: TextEdit) -> Bool {
        historyStorage === other.historyStorage
    }

    func weakHistory() -> WeakHistory {
        WeakHistory(historyStorage)
    }

    func matchesHistory(_ weak: WeakHistory) -> Bool {
        weak.ref === historyStorage
    }

    var isSingleLine: Bool {
        switch lineMode {
        case .default: return secureFlag
        case .single: return true
        case .multi: return false
        }
    }

    /// Whether this is a multi-line secure field in hidden mode (`secure && !revealed && !singleLine`).
    var isHiddenMultiline: Bool {
        secureFlag && !revealedFlag && !isSingleLine
    }

    /// For a secure field that has started exiting: wipe the secret and keep only its mask.
    mutating func conceal() {
        guard secureFlag else { return }
        revealedFlag = false
        let mask: String
        if text.isEmpty {
            mask = ""
        } else if isSingleLine {
            mask = String(repeating: "•", count: text.unicodeScalars.count)
        } else {
            mask = MULTILINE_SECURE_MASK
        }
        replaceText(mask)
    }

    /// Map model UTF-8 bytes to the bullet layout's bytes and back.
    func displayIndex(_ byte: Int) -> Int {
        if isHiddenMultiline {
            return text.isEmpty ? 0 : MULTILINE_SECURE_MASK.utf8.count
        } else if secureFlag && !revealedFlag {
            let clamped = Self.clampCharBoundary(text, min(max(byte, 0), text.utf8.count))
            let prefix = editUtf8Slice(text, 0..<clamped)
            return prefix.unicodeScalars.count * 3 // "•" is 3 UTF-8 bytes
        } else {
            return min(max(byte, 0), text.utf8.count)
        }
    }

    func modelIndex(_ byte: Int) -> Int {
        let utf8Len = text.utf8.count
        if isHiddenMultiline {
            return utf8Len
        } else if secureFlag && !revealedFlag {
            let targetScalar = max(byte, 0) / 3
            var count = 0
            var byteOffset = 0
            for scalar in text.unicodeScalars {
                if count == targetScalar {
                    return byteOffset
                }
                byteOffset += scalar.utf8.count
                count += 1
            }
            return utf8Len
        } else {
            return min(max(byte, 0), utf8Len)
        }
    }

    func displaySelectionRange(_ a: Int, _ b: Int) -> (Int, Int) {
        if isHiddenMultiline {
            return (a == b || text.isEmpty) ? (0, 0) : (0, MULTILINE_SECURE_MASK.utf8.count)
        } else {
            return (displayIndex(a), displayIndex(b))
        }
    }

    mutating func normalizeHiddenSelection() {
        if isHiddenMultiline {
            let selected = anchor != focus
            focus = text.utf8.count
            anchor = selected ? 0 : focus
        }
    }

    /// Clears the draft and its history after submission, preserving keyboard focus.
    public mutating func clear() {
        replaceText("")
    }

    /// The selection as ordered UTF-8 byte offsets, clamped to scalar boundaries of `text`.
    public func range() -> (Int, Int) {
        (
            Self.clampCharBoundary(text, min(anchor, focus)),
            Self.clampCharBoundary(text, max(anchor, focus))
        )
    }

    /// Move the caret to `byte` (clamped to a scalar boundary of `self.text`) and collapse the
    /// selection, clearing any pending typing style.
    public mutating func setCaret(_ byte: Int) {
        let b = Self.clampCharBoundary(text, byte)
        anchor = b
        focus = b
        snapToPills()
        pendingStyle = nil
    }

    /// Set the selection `anchor` and `focus` UTF-8 byte indices, clearing any pending typing style.
    public mutating func setSelection(_ anchor: Int, _ focus: Int) {
        self.anchor = Self.clampCharBoundary(text, anchor)
        self.focus = Self.clampCharBoundary(text, focus)
        snapToPills()
        pendingStyle = nil
    }

    /// The `Mark.pill`s in `self.text`, in order, with their byte ranges and ids.
    public func pills() -> [(Range<Int>, String)] {
        let bytes = Array(text.utf8)
        let n = bytes.count
        var out: [(Range<Int>, String)] = []
        for m in marksStorage {
            guard let id = m.mark.pillId() else { continue }
            if m.start < m.end,
               m.start >= 0,
               m.end <= n,
               editIsCharBoundary(bytes, m.start),
               editIsCharBoundary(bytes, m.end),
               !bytes[m.start..<m.end].contains(UInt8(ascii: "\n"))
            {
                out.append((m.range(), id))
            }
        }
        return out
    }

    func pillBefore(_ j: Int) -> Int? {
        marksStorage.first(where: { $0.mark.isPill && $0.start < j && j <= $0.end })?.start
    }

    func pillAfter(_ j: Int) -> Int? {
        marksStorage.first(where: { $0.mark.isPill && $0.start <= j && j < $0.end })?.end
    }

    func prevWord(_ i: Int) -> Int {
        if secureFlag && !revealedFlag {
            return 0
        }
        let b = Array(text.utf8)
        var j = min(max(i, 0), b.count)
        while true {
            if let start = pillBefore(j) {
                return start
            }
            if j == 0 || !editIsAsciiWhitespace(b[j - 1]) {
                break
            }
            j -= 1
        }
        while j > 0 && !editIsAsciiWhitespace(b[j - 1]) {
            if marksStorage.contains(where: { $0.mark.isPill && $0.end == j }) {
                break
            }
            j = editPrevChar(text, j)
        }
        return j
    }

    func nextWord(_ i: Int) -> Int {
        let b = Array(text.utf8)
        if secureFlag && !revealedFlag {
            return b.count
        }
        var j = min(max(i, 0), b.count)
        while true {
            if let end = pillAfter(j) {
                return end
            }
            if j >= b.count || !editIsAsciiWhitespace(b[j]) {
                break
            }
            j += 1
        }
        while j < b.count && !editIsAsciiWhitespace(b[j]) {
            if marksStorage.contains(where: { $0.mark.isPill && $0.start == j }) {
                break
            }
            j = editNextChar(text, j)
        }
        return j
    }

    /// Replace the selection with `label` as one `Mark.pill` carrying `id`, and put the caret after it.
    public mutating func insertPill(_ id: String, _ label: String) {
        let (a, b) = range()
        replaceWithPill(a..<b, id, label)
    }

    /// Replace byte range `range` with `label` as one `Mark.pill` carrying `id`, and put the caret after it.
    public mutating func replaceWithPill(_ range: Range<Int>, _ id: String, _ label: String) {
        var cleanLabel = ""
        cleanLabel.reserveCapacity(label.utf8.count)
        for s in label.unicodeScalars {
            if editIsScalarControl(s) || s.value == 0x2028 || s.value == 0x2029 {
                cleanLabel.unicodeScalars.append(" ")
            } else {
                cleanLabel.unicodeScalars.append(s)
            }
        }
        if secureFlag || cleanLabel.isEmpty {
            return
        }
        syncInvariants()
        breakHistoryGroup()
        let before = snapshot()
        let rawLo = min(range.lowerBound, range.upperBound)
        let rawHi = max(range.lowerBound, range.upperBound)
        let clampedA = Self.clampCharBoundary(text, rawLo)
        let clampedB = Self.clampCharBoundary(text, rawHi)
        let (a, b) = coverPills(clampedA, clampedB)
        pendingStyle = nil
        applyTextAndAttrReplace((a, b), cleanLabel, [], nil, false)
        // Code blocks keep no inline marks: there the label stays plain text.
        marksStorage.append(MarkRange(start: a, end: a + cleanLabel.utf8.count, mark: .pill(id)))
        normalizeMarks()
        recordChange(before, typing: false)
    }

    /// The pill strictly containing byte `i` (`start < i < end`).
    func pillAround(_ i: Int) -> (Int, Int)? {
        guard let m = marksStorage.first(where: { $0.mark.isPill && $0.start < i && i < $0.end }) else {
            return nil
        }
        return (m.start, m.end)
    }

    /// `i` moved out of any pill it lands inside, to its end when `forward`, else its start.
    func outOfPill(_ i: Int, _ forward: Bool) -> Int {
        guard let (s, e) = pillAround(i) else { return i }
        return forward ? e : s
    }

    /// `a..<b` grown to cover any pill either end cuts into; an empty range inside one moves to its end.
    func coverPills(_ a: Int, _ b: Int) -> (Int, Int) {
        if a == b {
            let i = outOfPill(a, true)
            return (i, i)
        }
        return (outOfPill(a, false), outOfPill(b, true))
    }

    /// Keeps the caret off a pill's inside: a caret goes to the nearer edge, a selection grows to cover the pill.
    mutating func snapToPills() {
        guard marksStorage.contains(where: { $0.mark.isPill }) else { return }
        if anchor == focus {
            if let (s, e) = pillAround(focus) {
                let to = (focus - s < e - focus) ? s : e
                anchor = to
                focus = to
            }
        } else {
            let forward = focus > anchor
            anchor = outOfPill(anchor, !forward)
            focus = outOfPill(focus, forward)
        }
    }

    public func selected() -> String {
        let (a, b) = range()
        return editUtf8Slice(text, a..<b)
    }

    public func selectedText() -> String {
        if secureFlag { return "" }
        return selected()
    }

    public mutating func insert(_ s: String) {
        replace(range(), s, typing: false)
    }

    mutating func setSingleLine(_ single: Bool) {
        lineMode = single ? .single : .multi
    }

    /// Line index (`0..<lineCount`) containing `byte`.
    public func lineOfByte(_ byte: Int) -> Int {
        let bytes = Array(text.utf8)
        let clamped = min(max(byte, 0), bytes.count)
        return editCountNewlinesBytes(bytes[0..<clamped])
    }

    /// Byte range (`start..<end`, excluding `\n`) of 0-based `lineIdx`.
    public func lineRange(_ lineIdx: Int) -> Range<Int> {
        let bytes = Array(text.utf8)
        var cur = 0
        var start = 0
        for i in 0..<bytes.count where bytes[i] == UInt8(ascii: "\n") {
            if cur == lineIdx {
                return start..<i
            }
            start = i + 1
            cur += 1
        }
        if cur == lineIdx {
            return start..<bytes.count
        }
        return bytes.count..<bytes.count
    }

    static func clampCharBoundary(_ s: String, _ idx: Int) -> Int {
        if idx <= 0 { return 0 }
        let utf8 = s.utf8
        let n = utf8.count
        if idx >= n { return n }
        var pos = utf8.index(utf8.startIndex, offsetBy: idx)
        var out = idx
        while out > 0 && (utf8[pos] & 0b1100_0000) == 0b1000_0000 {
            pos = utf8.index(before: pos)
            out -= 1
        }
        return out
    }

    func sanitize(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        out.reserveCapacity(s.unicodeScalars.count)
        if isSingleLine {
            for c in s.unicodeScalars {
                if !editIsScalarControl(c) && c.value != 0x2028 && c.value != 0x2029 {
                    out.append(c)
                }
            }
        } else if secureFlag {
            let scalars = Array(s.unicodeScalars)
            var i = 0
            while i < scalars.count {
                let c = scalars[i]
                if c == "\r" {
                    if i + 1 >= scalars.count || scalars[i + 1] != "\n" {
                        out.append("\n")
                    }
                    i += 1
                    continue
                }
                if (!editIsScalarControl(c) || c == "\n" || c == "\t")
                    && c.value != 0x2028
                    && c.value != 0x2029
                {
                    out.append(c)
                }
                i += 1
            }
        } else {
            let scalars = Array(s.unicodeScalars)
            var i = 0
            while i < scalars.count {
                let c = scalars[i]
                if c == "\r" && i + 1 < scalars.count && scalars[i + 1] == "\n" {
                    i += 1
                    continue
                }
                out.append(c)
                i += 1
            }
        }
        return String(out)
    }

    /// Core replacement engine updating `text`, `marks`, `blocks`, and `softBreaks` together.
    mutating func applyTextAndAttrReplace(
        _ range: (Int, Int),
        _ s: String,
        _ insertedMarks: [Mark],
        _ newLineBlock: Block?,
        _ markNewLinesSoft: Bool
    ) {
        let (a, b) = range
        let delLen = b - a
        let insLen = s.utf8.count
        if marksStorage.isEmpty
            && insertedMarks.isEmpty
            && softBreaksStorage.isEmpty
            && !markNewLinesSoft
            && (newLineBlock == nil || newLineBlock == .paragraph)
            && blocksStorage.allSatisfy({ $0 == .paragraph })
        {
            let oldBytes = Array(text.utf8)
            let removed = editCountNewlinesBytes(oldBytes[a..<b])
            let added = editCountNewlines(s)
            text = editReplaceUtf8Range(oldBytes, a..<b, s)
            let nextBlockCount = max(1, blocksStorage.count + added - removed)
            if blocksStorage.count < nextBlockCount {
                blocksStorage.append(contentsOf: repeatElement(.paragraph, count: nextBlockCount - blocksStorage.count))
            } else if blocksStorage.count > nextBlockCount {
                blocksStorage.removeLast(blocksStorage.count - nextBlockCount)
            }
            anchor = a + insLen
            focus = anchor
            preedit = nil
            markEdited()
            return
        }

        let lineA = lineOfByte(a)
        let lineB = lineOfByte(b)
        let lineARange = lineRange(lineA)
        let lineBRange = lineRange(lineB)

        let mergedBlock: Block
        if lineA < lineB && lineARange.isEmpty && a == lineARange.lowerBound && b == lineBRange.lowerBound {
            mergedBlock = lineB < blocksStorage.count ? blocksStorage[lineB] : .paragraph
        } else {
            mergedBlock = lineA < blocksStorage.count ? blocksStorage[lineA] : .paragraph
        }

        let mergedSoft: Bool
        if lineA < lineB && lineARange.isEmpty && a == lineARange.lowerBound && b == lineBRange.lowerBound {
            mergedSoft = editSortedContains(softBreaksStorage, UInt32(lineB)) && lineA > 0
        } else {
            mergedSoft = editSortedContains(softBreaksStorage, UInt32(lineA))
        }

        let removedLines = lineB - lineA
        let addedLines = editCountNewlines(s)
        let nextLineBlk = newLineBlock ?? (mergedBlock == .code ? .code : .paragraph)

        if removedLines > 0 && lineA + 1 <= lineB && lineB < blocksStorage.count {
            blocksStorage.removeSubrange((lineA + 1)...lineB)
        }
        if lineA < blocksStorage.count {
            blocksStorage[lineA] = mergedBlock
        }
        if addedLines > 0 {
            let insertPos = min(lineA + 1, blocksStorage.count)
            blocksStorage.insert(contentsOf: repeatElement(nextLineBlk, count: addedLines), at: insertPos)
        }

        var nextSoft: [UInt32] = []
        for sb in softBreaksStorage {
            let idx = Int(sb)
            if idx < lineA {
                nextSoft.append(sb)
            } else if idx > lineB {
                let shifted = idx - removedLines + addedLines
                if shifted > 0 {
                    nextSoft.append(UInt32(shifted))
                }
            }
        }
        if mergedSoft && lineA > 0 {
            nextSoft.append(UInt32(lineA))
        }
        if markNewLinesSoft && addedLines > 0 {
            for k in 1...addedLines {
                nextSoft.append(UInt32(lineA + k))
            }
        }
        softBreaksStorage = nextSoft

        var updatedMarks: [MarkRange] = []
        updatedMarks.reserveCapacity(marksStorage.count + insertedMarks.count)
        for m in marksStorage {
            if m.end <= a {
                updatedMarks.append(m)
            } else if m.start >= b {
                updatedMarks.append(MarkRange(
                    start: m.start - delLen + insLen,
                    end: m.end - delLen + insLen,
                    mark: m.mark
                ))
            } else if m.mark.isPill {
                // An edit that cuts into a pill leaves its remains as plain text.
            } else {
                if m.start < a {
                    updatedMarks.append(MarkRange(start: m.start, end: a, mark: m.mark))
                }
                if m.end > b {
                    updatedMarks.append(MarkRange(
                        start: a + insLen,
                        end: m.end - delLen + insLen,
                        mark: m.mark
                    ))
                }
            }
        }
        if insLen > 0 {
            for im in insertedMarks where !im.isPill {
                if s == "\n" {
                    let wasInside = updatedMarks.contains { m in
                        m.mark == im && m.start >= a + insLen
                    }
                    if !wasInside {
                        continue
                    }
                }
                updatedMarks.append(MarkRange(start: a, end: a + insLen, mark: im))
            }
        }
        marksStorage = updatedMarks
        text = editReplaceUtf8Range(Array(text.utf8), a..<b, s)
        anchor = a + insLen
        focus = anchor
        preedit = nil
        syncInvariants()
        markEdited()
    }

    mutating func replace(_ rawRange: (Int, Int), _ s: String, typing: Bool) {
        var (a, b) = rawRange
        if isHiddenMultiline && isPristine() {
            (a, b) = (0, text.utf8.count)
        }
        if secureFlag {
            let oldBytes = Array(text.utf8)
            let lo = min(max(a, 0), oldBytes.count)
            let hi = min(max(b, lo), oldBytes.count)
            let next = editReplaceUtf8Range(oldBytes, lo..<hi, s)
            replaceText(next)
            anchor = lo + s.utf8.count
            focus = anchor
            markEdited()
            return
        }
        syncInvariants()
        (a, b) = coverPills(a, b)
        if !typing {
            breakHistoryGroup()
        }
        if editUtf8Slice(text, a..<b).utf8.elementsEqual(s.utf8)
            && pendingStyle == nil
            && !marksStorage.contains(where: { $0.mark.isPill && $0.start < b && a < $0.end })
        {
            anchor = a + s.utf8.count
            focus = anchor
            preedit = nil
            markEdited()
            return
        }
        let before = snapshot()
        let insertedMarks: [Mark]
        if s.isEmpty {
            pendingStyle = nil
            insertedMarks = []
        } else if let (armed, p) = pendingStyle {
            pendingStyle = nil
            if armed == (anchor, focus) {
                insertedMarks = p
            } else if a < b {
                let lineIdx = lineOfByte(a)
                if lineIdx < blocksStorage.count && blocksStorage[lineIdx] == .code {
                    insertedMarks = []
                } else {
                    insertedMarks = marksStorage.filter { $0.start <= a && a < $0.end }.map(\.mark)
                }
            } else {
                insertedMarks = inheritedMarksAt(a)
            }
        } else if a < b {
            let lineIdx = lineOfByte(a)
            if lineIdx < blocksStorage.count && blocksStorage[lineIdx] == .code {
                insertedMarks = []
            } else {
                insertedMarks = marksStorage.filter { $0.start <= a && a < $0.end }.map(\.mark)
            }
        } else {
            insertedMarks = inheritedMarksAt(a)
        }

        applyTextAndAttrReplace((a, b), s, insertedMarks, nil, false)
        recordChange(before, typing: typing)
    }
}

// MARK: - Internal UTF-8 & Grapheme Helpers

func editPrevChar(_ s: String, _ i: Int) -> Int {
    let clamped = TextEdit.clampCharBoundary(s, i)
    if clamped <= 0 { return 0 }
    let prefix = editUtf8Slice(s, 0..<clamped)
    guard let last = prefix.last else { return 0 }
    return max(0, clamped - last.utf8.count)
}

func editNextChar(_ s: String, _ i: Int) -> Int {
    let n = s.utf8.count
    let clamped = TextEdit.clampCharBoundary(s, i)
    if clamped >= n { return n }
    let suffix = editUtf8Slice(s, clamped..<n)
    guard let first = suffix.first else { return clamped }
    return min(n, clamped + first.utf8.count)
}

func editCountNewlines(_ s: String) -> Int {
    s.utf8.withContiguousStorageIfAvailable { buf in
        var total = 0
        for b in buf where b == UInt8(ascii: "\n") {
            total += 1
        }
        return total
    } ?? s.utf8.reduce(0) { $0 + ($1 == UInt8(ascii: "\n") ? 1 : 0) }
}

func editCountNewlinesBytes(_ slice: ArraySlice<UInt8>) -> Int {
    var total = 0
    for b in slice where b == UInt8(ascii: "\n") {
        total += 1
    }
    return total
}

func editIsCharBoundary(_ bytes: [UInt8], _ idx: Int) -> Bool {
    if idx < 0 || idx > bytes.count { return false }
    if idx == 0 || idx == bytes.count { return true }
    return (bytes[idx] & 0b1100_0000) != 0b1000_0000
}

func editIsAsciiWhitespace(_ b: UInt8) -> Bool {
    b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0C || b == 0x0D
}

func editIsScalarControl(_ s: Unicode.Scalar) -> Bool {
    let v = s.value
    return v <= 0x1F || (v >= 0x7F && v <= 0x9F)
}

func editUtf8Slice(_ s: String, _ range: Range<Int>) -> String {
    let lo = TextEdit.clampCharBoundary(s, range.lowerBound)
    let hi = max(lo, TextEdit.clampCharBoundary(s, range.upperBound))
    if lo >= hi { return "" }
    let utf8 = s.utf8
    let startIdx = utf8.index(utf8.startIndex, offsetBy: lo)
    let endIdx = utf8.index(startIdx, offsetBy: hi - lo)
    return String(decoding: utf8[startIdx..<endIdx], as: UTF8.self)
}

func editReplaceUtf8Range(_ oldBytes: [UInt8], _ range: Range<Int>, _ replacement: String) -> String {
    let repBytes = Array(replacement.utf8)
    var out: [UInt8] = []
    out.reserveCapacity(oldBytes.count - range.count + repBytes.count)
    if range.lowerBound > 0 {
        out.append(contentsOf: oldBytes[0..<range.lowerBound])
    }
    out.append(contentsOf: repBytes)
    if range.upperBound < oldBytes.count {
        out.append(contentsOf: oldBytes[range.upperBound..<oldBytes.count])
    }
    return String(decoding: out, as: UTF8.self)
}

func editSortedContains(_ sorted: [UInt32], _ target: UInt32) -> Bool {
    var lo = 0
    var hi = sorted.count
    while lo < hi {
        let mid = lo + (hi - lo) / 2
        let v = sorted[mid]
        if v == target {
            return true
        } else if v < target {
            lo = mid + 1
        } else {
            hi = mid
        }
    }
    return false
}

/// Namespace mirroring `rune::edit::*`.
public enum editNamespace {
    public typealias TextEdit = Rune.TextEdit
    public typealias EditOutcome = Rune.EditOutcome
    public typealias Ime = Rune.Ime
    public typealias Key = Rune.Key
    public typealias KeyEvent = Rune.KeyEvent
    public typealias KeySide = Rune.KeySide
    public typealias Modifier = Rune.Modifier
    public typealias Mods = Rune.Mods
    public typealias Block = Rune.Block
    public typealias Mark = Rune.Mark
    public typealias MarkRange = Rune.MarkRange
    public typealias ParagraphInfo = Rune.ParagraphInfo
    public typealias RichStyle = Rune.RichStyle
}
