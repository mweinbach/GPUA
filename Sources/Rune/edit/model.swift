// Ported from: crates/rune/src/edit/model.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! The rich-text model's value types: inline marks, paragraph blocks and their palette.

/// Maximum nesting level (`0...MAX_LIST_LEVEL`) for `Block.bullet` and `Block.numbered`.
public let MAX_LIST_LEVEL: UInt8 = 3

/// An inline formatting mark stored alongside `TextEdit.text`.
public enum Mark: Sendable, Equatable, Hashable {
    case bold
    case italic
    case underline
    case strike
    case code
    case link(String)
    /// An atomic inline object carrying the app's id; its text is the label.
    case pill(String)

    /// Whether `self` and `other` are the same kind of mark (`link(_)` matches any `link(_)`).
    public func sameKind(_ other: Mark) -> Bool {
        switch (self, other) {
        case (.bold, .bold),
             (.italic, .italic),
             (.underline, .underline),
             (.strike, .strike),
             (.code, .code),
             (.link, .link),
             (.pill, .pill):
            return true
        default:
            return false
        }
    }

    /// The URL when `self` is `.link`.
    public func linkUrl() -> String? {
        if case .link(let url) = self { return url }
        return nil
    }

    /// The app's id when `self` is `.pill`.
    public func pillId() -> String? {
        if case .pill(let id) = self { return id }
        return nil
    }

    var isPill: Bool {
        if case .pill = self { return true }
        return false
    }

    var kindOrder: UInt8 {
        switch self {
        case .bold: return 0
        case .italic: return 1
        case .underline: return 2
        case .strike: return 3
        case .code: return 4
        case .link: return 5
        case .pill: return 6
        }
    }
}

/// A non-empty UTF-8 byte range `[start, end)` in `TextEdit.text` carrying an inline `Mark`.
public struct MarkRange: Sendable, Equatable, Hashable {
    public var start: Int
    public var end: Int
    public var mark: Mark

    public init(start: Int, end: Int, mark: Mark) {
        self.start = start
        self.end = end
        self.mark = mark
    }

    public init(_ range: Range<Int>, _ mark: Mark) {
        self.start = range.lowerBound
        self.end = range.upperBound
        self.mark = mark
    }

    public static func new(_ range: Range<Int>, _ mark: Mark) -> MarkRange {
        MarkRange(range, mark)
    }

    public func range() -> Range<Int> {
        start..<end
    }
}

/// Paragraph-level block attribute for a `\n`-delimited line in `TextEdit`.
public enum Block: Sendable, Equatable, Hashable {
    case paragraph
    case bullet(UInt8)
    case numbered(UInt8)
    case quote
    case code

    public func isList() -> Bool {
        switch self {
        case .bullet, .numbered: return true
        default: return false
        }
    }

    public func listLevel() -> UInt8? {
        switch self {
        case .bullet(let l), .numbered(let l): return l
        default: return nil
        }
    }

    public func withLevel(_ level: UInt8) -> Block {
        let l = min(level, MAX_LIST_LEVEL)
        switch self {
        case .bullet: return .bullet(l)
        case .numbered: return .numbered(l)
        default: return self
        }
    }

    public func sameKind(_ other: Block) -> Bool {
        switch (self, other) {
        case (.paragraph, .paragraph),
             (.bullet, .bullet),
             (.numbered, .numbered),
             (.quote, .quote),
             (.code, .code):
            return true
        default:
            return false
        }
    }

    var kindBit: UInt8 {
        switch self {
        case .paragraph: return 1 << 0
        case .bullet: return 1 << 1
        case .numbered: return 1 << 2
        case .quote: return 1 << 3
        case .code: return 1 << 4
        }
    }

    func indentPt(_ fontSize: Float) -> Float {
        let unit = max((fontSize * 1.45).rounded(), 18.0)
        switch self {
        case .paragraph:
            return 0.0
        case .bullet(let l), .numbered(let l):
            return unit * (Float(min(l, MAX_LIST_LEVEL)) + 1.0)
        case .quote:
            return max((fontSize * 1.1).rounded(), 14.0)
        case .code:
            return max((fontSize * 0.75).rounded(), 10.0)
        }
    }
}

/// A paragraph slice of `TextEdit`, returned by `TextEdit.paragraphs()`.
public struct ParagraphInfo: Sendable, Equatable {
    public var index: Int
    public var range: Range<Int>
    public var block: Block
    /// True when this line was split from the previous line by `Shift+Return` (`<br>`).
    public var softBreak: Bool

    public init(index: Int, range: Range<Int>, block: Block, softBreak: Bool) {
        self.index = index
        self.range = range
        self.block = block
        self.softBreak = softBreak
    }
}

/// Visual palette for rich marks and block attributes inside `textInput`.
public struct RichStyle: Sendable, Equatable {
    public var codeFg: Color?
    public var codeBg: Color
    public var codeBlockBg: Color
    public var link: Color
    public var quoteBar: Color
    public var marker: Color?

    public init(
        codeFg: Color? = nil,
        codeBg: Color = oklcha(0.55, 0.02, 260.0, 0.16),
        codeBlockBg: Color = oklcha(0.5, 0.02, 260.0, 0.12),
        link: Color = oklch(0.68, 0.16, 250.0),
        quoteBar: Color = oklcha(0.6, 0.04, 255.0, 0.45),
        marker: Color? = nil
    ) {
        self.codeFg = codeFg
        self.codeBg = codeBg
        self.codeBlockBg = codeBlockBg
        self.link = link
        self.quoteBar = quoteBar
        self.marker = marker
    }
}
