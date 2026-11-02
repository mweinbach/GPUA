// Ported from: crates/rune/src/edit.rs
// Upstream commit: 5f6d53ddae78
// Port status: in-progress

//! Single and rich text-field editing: the attributed model an app owns (`TextEdit`) and the
//! key/IME events the shell routes to the focused field.

let MULTILINE_SECURE_MASK: String = "••••••••••••"

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
    public var text: String
    public var anchor: Int
    public var focus: Int
    /// IME composition shown at the caret, with its selected UTF-8 byte range.
    public var preedit: (String, (Int, Int)?)?
    public var focused: Bool

    var marksStorage: [MarkRange]
    var blocksStorage: [Block]
    var softBreaksStorage: [UInt32]
    var pendingStyle: ((Int, Int), [Mark])?
    var secureFlag: Bool
    var revealedFlag: Bool
    var lineMode: TextEditLineMode
    var richFlag: Bool
    var allowedMarks: UInt16?
    var allowedBlocks: UInt8?
    var editedFlag: Bool

    public init(_ text: String = "") {
        let utf8Len = text.utf8.count
        let lineCount = 1 + text.utf8.filter { $0 == UInt8(ascii: "\n") }.count
        self.text = text
        self.anchor = utf8Len
        self.focus = utf8Len
        self.preedit = nil
        self.focused = false
        self.marksStorage = []
        self.blocksStorage = Array(repeating: .paragraph, count: lineCount)
        self.softBreaksStorage = []
        self.pendingStyle = nil
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

    public static func fromParts(_ text: String, _ marks: [MarkRange], _ blocks: [Block]) -> TextEdit {
        var edit = TextEdit(text).rich()
        edit.marksStorage = marks
        edit.blocksStorage = blocks
        edit.syncInvariants()
        return edit
    }

    public var debugDescription: String {
        let shown = secureFlag ? "[redacted]" : text
        return "TextEdit(text: \(shown.debugDescription), anchor: \(anchor), focus: \(focus), focused: \(focused), secure: \(secureFlag), revealed: \(revealedFlag))"
    }

    public static func == (lhs: TextEdit, rhs: TextEdit) -> Bool {
        guard lhs.text == rhs.text,
              lhs.anchor == rhs.anchor,
              lhs.focus == rhs.focus,
              lhs.focused == rhs.focused,
              lhs.marksStorage == rhs.marksStorage,
              lhs.blocksStorage == rhs.blocksStorage,
              lhs.softBreaksStorage == rhs.softBreaksStorage,
              lhs.secureFlag == rhs.secureFlag,
              lhs.revealedFlag == rhs.revealedFlag,
              lhs.lineMode == rhs.lineMode,
              lhs.richFlag == rhs.richFlag,
              lhs.allowedMarks == rhs.allowedMarks,
              lhs.allowedBlocks == rhs.allowedBlocks
        else { return false }
        switch (lhs.preedit, rhs.preedit) {
        case (nil, nil): return true
        case (let lp?, let rp?):
            guard lp.0 == rp.0 else { return false }
            switch (lp.1, rp.1) {
            case (nil, nil): return true
            case (let lr?, let rr?): return lr.0 == rr.0 && lr.1 == rr.1
            default: return false
            }
        default: return false
        }
    }

    public func hash(into hasher: inout Hasher) {
        if isHiddenMultiline {
            hasher.combine(!text.isEmpty)
            hasher.combine(anchor != focus)
        } else if secureFlag && !revealedFlag {
            hasher.combine(text.count)
            hasher.combine(anchor)
            hasher.combine(focus)
        } else {
            hasher.combine(text)
            hasher.combine(anchor)
            hasher.combine(focus)
        }
        hasher.combine(preedit?.0)
        hasher.combine(preedit?.1?.0)
        hasher.combine(preedit?.1?.1)
        hasher.combine(focused)
        hasher.combine(marksStorage)
        if !secureFlag {
            hasher.combine(blocksStorage)
        }
        hasher.combine(softBreaksStorage)
        hasher.combine(secureFlag)
        hasher.combine(revealedFlag)
        hasher.combine(isSingleLine)
    }

    var isSingleLine: Bool {
        switch lineMode {
        case .single: return true
        case .multi: return false
        case .default: return secureFlag
        }
    }

    var isHiddenMultiline: Bool {
        secureFlag && !revealedFlag && !isSingleLine
    }

    mutating func setSingleLine(_ single: Bool) {
        lineMode = single ? .single : .multi
    }

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
            marksStorage.removeAll()
            blocksStorage.removeAll()
            softBreaksStorage.removeAll()
            pendingStyle = nil
            preedit = nil
        } else {
            syncInvariants()
        }
    }

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

    public func marks() -> [MarkRange] {
        marksStorage
    }

    public func blocks() -> [Block] {
        blocksStorage.isEmpty ? [.paragraph] : blocksStorage
    }

    public func softBreaks() -> [UInt32] {
        softBreaksStorage
    }

    public func range() -> (Int, Int) {
        (min(anchor, focus), max(anchor, focus))
    }

    public func selectedText() -> String {
        let (a, b) = range()
        guard a < b, !secureFlag else { return "" }
        let utf8 = Array(text.utf8)
        let clampedA = min(max(a, 0), utf8.count)
        let clampedB = min(max(b, clampedA), utf8.count)
        return String(decoding: utf8[clampedA..<clampedB], as: UTF8.self)
    }

    public mutating func replaceText(_ next: String) {
        text = next
        let n = text.utf8.count
        anchor = n
        focus = n
        preedit = nil
        editedFlag = false
        syncInvariants()
    }

    public mutating func insert(_ fragment: String) {
        let (a, b) = range()
        let utf8 = Array(text.utf8)
        let lo = min(max(a, 0), utf8.count)
        let hi = min(max(b, lo), utf8.count)
        var out = Array(utf8[0..<lo])
        let ins = Array(fragment.utf8)
        out.append(contentsOf: ins)
        out.append(contentsOf: utf8[hi..<utf8.count])
        text = String(decoding: out, as: UTF8.self)
        let caret = lo + ins.count
        anchor = caret
        focus = caret
        editedFlag = true
        syncInvariants()
    }

    public func paragraphs() -> [ParagraphInfo] {
        var out: [ParagraphInfo] = []
        var lineStart = 0
        var idx = 0
        let bytes = Array(text.utf8)
        for (i, b) in bytes.enumerated() where b == UInt8(ascii: "\n") {
            let block = idx < blocksStorage.count ? blocksStorage[idx] : .paragraph
            let sb = softBreaksStorage.contains(UInt32(idx))
            out.append(ParagraphInfo(index: idx, range: lineStart..<i, block: block, softBreak: sb))
            lineStart = i + 1
            idx += 1
        }
        let block = idx < blocksStorage.count ? blocksStorage[idx] : .paragraph
        let sb = softBreaksStorage.contains(UInt32(idx))
        out.append(ParagraphInfo(index: idx, range: lineStart..<bytes.count, block: block, softBreak: sb))
        return out
    }

    mutating func syncInvariants() {
        let n = text.utf8.count
        anchor = min(max(anchor, 0), n)
        focus = min(max(focus, 0), n)
        let lineCount = 1 + text.utf8.filter { $0 == UInt8(ascii: "\n") }.count
        if blocksStorage.count < lineCount {
            blocksStorage.append(contentsOf: repeatElement(.paragraph, count: lineCount - blocksStorage.count))
        } else if blocksStorage.count > lineCount {
            blocksStorage.removeLast(blocksStorage.count - lineCount)
        }
    }

    func display() -> (String, Int) {
        if isHiddenMultiline {
            return (text.isEmpty ? "" : MULTILINE_SECURE_MASK, 0)
        }
        if secureFlag && !revealedFlag {
            let bullets = String(repeating: "•", count: text.count)
            return (bullets, bullets.utf8.count)
        }
        return (text, focus)
    }
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
