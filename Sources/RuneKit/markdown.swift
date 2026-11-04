// Ported from: crates/rune-kit/src/markdown.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Markdown: headings, paragraphs, emphasis, inline code, code blocks, lists (with GFM task
//! checkboxes; see ``Markdown/onTask(_:)``), block quotes, rules, links, GFM tables,
//! ```` ```diff ```` fences and ```` ```mermaid ```` diagrams, rendered from a ``MarkdownStyle``.
//! Fences in rust, js, ts, tsx, json, python, go, swift, sh, sql, html, css and yaml are
//! syntax-coloured by ``syntax``, or by an app's own highlighter (``Markdown/highlight(_:file:line:column:)``).
//! Partial input while streaming is fine: an unclosed fence is a code block that keeps growing (a
//! diagram fence draws as it grows).

import Rune

/// An inline style run.
public enum MarkdownInlineStyle: Sendable, Equatable, Hashable {
    case code
    /// The narrow no-break spaces around inline code (CSS's `padding: 0 4px`).
    case codePad
    case strong
    case em
    case strike
    case link
}

/// Text with styled and linked byte ranges.
public struct MarkdownInline: Sendable, Equatable, Hashable {
    public var text: String
    /// Byte ranges into `text`.
    public var spans: [(Int, Int, MarkdownInlineStyle)]
    /// Byte ranges into `text` and the destination of each link.
    public var links: [(Int, Int, String)]

    public init(
        text: String = "",
        spans: [(Int, Int, MarkdownInlineStyle)] = [],
        links: [(Int, Int, String)] = []
    ) {
        self.text = text
        self.spans = spans
        self.links = links
    }

    public static func == (lhs: MarkdownInline, rhs: MarkdownInline) -> Bool {
        guard lhs.text == rhs.text,
              lhs.spans.count == rhs.spans.count,
              lhs.links.count == rhs.links.count
        else { return false }
        for (a, b) in zip(lhs.spans, rhs.spans) where a.0 != b.0 || a.1 != b.1 || a.2 != b.2 {
            return false
        }
        for (a, b) in zip(lhs.links, rhs.links) where a.0 != b.0 || a.1 != b.1 || a.2 != b.2 {
            return false
        }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
        hasher.combine(spans.count)
        for (a, b, st) in spans {
            hasher.combine(a)
            hasher.combine(b)
            hasher.combine(st)
        }
        hasher.combine(links.count)
        for (a, b, url) in links {
            hasher.combine(a)
            hasher.combine(b)
            hasher.combine(url)
        }
    }
}

/// A GFM table. Rows may have fewer cells than there are columns.
public struct MarkdownTable: Sendable, Equatable, Hashable {
    /// One per column: `:--` and none are `.start`, `:-:` is `.center`, `--:` is `.end`.
    public var align: [Align]
    public var head: [MarkdownInline]
    public var rows: [[MarkdownInline]]
    /// The source ends inside the last row (or the header), so it may still grow.
    public var open: Bool

    public init(
        align: [Align] = [],
        head: [MarkdownInline] = [],
        rows: [[MarkdownInline]] = [],
        open: Bool = false
    ) {
        self.align = align
        self.head = head
        self.rows = rows
        self.open = open
    }
}

/// A block of the parsed document.
public enum MarkdownBlock: Sendable, Equatable, Hashable {
    case para(MarkdownInline)
    case heading(UInt8, MarkdownInline)
    case code(String)
    case list(start: UInt64?, items: [[MarkdownBlock]])
    case quote([MarkdownBlock])
    case rule
    /// A GFM table.
    case table(MarkdownTable)
    /// A ```` ```diff ```` (or `patch`) fence.
    case diff(String)
    /// A ```` ```mermaid ```` fence, closed or still arriving.
    case mermaid(String)
}

typealias TaskWire = (El, String, Int, Bool) -> El

/// Markdown source as an element. See module docs for cost and keys.
public struct Markdown {
    var src: String
    var styleOverride: MarkdownStyle?
    var blockKeysList: [(Int, String)]
    var highlightsList: [([Range<Int>], Highlight)]
    var autolinkFlag: Bool
    var revealFade: Float
    var streamingFlag: Bool
    var onLinkWire: LinkWire?
    var onLinkSecondaryWire: LinkWire?
    var linkLookFn: LinkLook?
    var onTaskWire: TaskWire?
    var tasksReadOnlyFlag: Bool
    var linkRingFn: LinkRing?
    var selectableFlag: Bool
    var copySourceFlag: Bool
    var scrollWideFlag: Bool
    var highlighterValue: Highlighter

    public init(_ src: String) {
        self.src = src
        self.styleOverride = nil
        self.blockKeysList = []
        self.highlightsList = []
        self.autolinkFlag = true
        self.revealFade = 0.0
        self.streamingFlag = false
        self.onLinkWire = nil
        self.onLinkSecondaryWire = nil
        self.linkLookFn = nil
        self.onTaskWire = nil
        self.tasksReadOnlyFlag = false
        self.linkRingFn = nil
        self.selectableFlag = false
        self.copySourceFlag = false
        self.scrollWideFlag = false
        self.highlighterValue = Highlighter.builtin()
    }

    public static func new(_ src: String) -> Markdown {
        Markdown(src)
    }

    /// Highlight UTF-8 byte ranges of the Markdown source string (see ``markdown/find(_:_:_:)``).
    public func highlights(_ highlights: [Range<Int>]) -> Markdown {
        var copy = self
        copy.highlightsList = highlights.map { ($0.intoRanges()) }
        return copy
    }

    /// Highlight items (`Range<Int>` or `[Range<Int>]` matches from ``markdown/find(_:_:_:)``).
    public func highlights<S: Swift.Sequence>(_ highlights: S) -> Markdown where S.Element: HighlightItem {
        var copy = self
        copy.highlightsList = highlights.map { $0.intoRanges() }
        return copy
    }

    /// Highlight paired `(Range<Int>, Highlight)` ranges.
    public func highlights<S: Swift.Sequence>(_ highlights: S) -> Markdown where S.Element == (Range<Int>, Highlight) {
        var copy = self
        copy.highlightsList = highlights.map { ([$0.0], $0.1) }
        return copy
    }

    /// Highlight paired `([Range<Int>], Highlight)` multi-range matches.
    public func highlights<S: Swift.Sequence>(_ highlights: S) -> Markdown where S.Element == ([Range<Int>], Highlight) {
        var copy = self
        copy.highlightsList = highlights.map { (normalizeRanges($0.0), $0.1) }
        return copy
    }

    /// Highlight paired `(ArraySlice<Range<Int>>, Highlight)` multi-range matches.
    public func highlights<S: Swift.Sequence>(_ highlights: S) -> Markdown where S.Element == (ArraySlice<Range<Int>>, Highlight) {
        var copy = self
        copy.highlightsList = highlights.map { (normalizeRanges(Array($0.0)), $0.1) }
        return copy
    }

    /// Default key (`"md-mark-{index}"`) for the `index`-th highlight in ``highlights(_:)-([Range<Int>])``
    /// when ``Highlight/key(_:)`` was not set on it.
    public static func highlightKey(_ index: Int) -> String {
        "md-mark-\(index)"
    }

    /// Whether bare `https://…`, `http://…` and `www.…` URLs in plain text are autolinked
    /// (`true` by default).
    /// This is URL-only: bare email addresses remain text; `<name@example.org>` still links.
    public func autolink(_ on: Bool) -> Markdown {
        var copy = self
        copy.autolinkFlag = on
        return copy
    }

    /// Stable keys as `(sourceByteOffset, key)` pairs. The offset is the start of the first
    /// source line of a rendered top-level block (including any indentation), not its ordinal.
    public func blockKeys<S: Swift.Sequence>(_ keys: S) -> Markdown where S.Element == (Int, String) {
        var copy = self
        copy.blockKeysList = Array(keys)
        return copy
    }

    /// Replaces the kit-derived style in ``build(_:)``.
    public func style(_ style: MarkdownStyle) -> Markdown {
        var copy = self
        copy.styleOverride = style
        return copy
    }

    /// Streaming word reveal in seconds (see `El.reveal`); 0 shows words at once.
    public func reveal(_ wordFade: Float) -> Markdown {
        var copy = self
        copy.revealFade = wordFade
        return copy
    }

    /// The source is still arriving: a table's last row, with no newline after it yet, is left
    /// out of the column widths until it ends, and a diagram brings in each node and edge as
    /// its line arrives. The tail draws as what it's about to become.
    public func streaming(_ on: Bool) -> Markdown {
        var copy = self
        copy.streamingFlag = on
        return copy
    }

    /// Called when a GFM task list item (`- [ ]` or `- [x]`) is clicked, or pressed with Space
    /// while focused: `(state, blockKey, markerOffset, checked)`. Enter does not toggle.
    public func onTask<S>(_ f: @escaping (inout S, String, Int, Bool) -> Void) -> Markdown {
        onTaskTx { (s: inout S, key: String, item: Int, checked: Bool, _: inout Tx) in
            f(&s, key, item, checked)
        }
    }

    /// ``onTask(_:)`` with the `Tx` of the press. Replaces any earlier `onTask` or `onTaskTx`
    /// handler (the later call wins).
    public func onTaskTx<S>(_ f: @escaping (inout S, String, Int, Bool, inout Tx) -> Void) -> Markdown {
        var copy = self
        copy.onTaskWire = { e, key, item, checked in
            e.onPressTx { (s: inout S, tx: inout Tx) in
                f(&s, key, item, checked, &tx)
            }
        }
        return copy
    }

    /// Keeps GFM task list checkboxes read-only (unfocusable and unpressable), even when an
    /// ``onTask(_:)`` or ``onTaskTx(_:)`` handler was set.
    public func tasksReadOnly() -> Markdown {
        var copy = self
        copy.tasksReadOnlyFlag = true
        return copy
    }

    /// Lets people select and copy the text (see `El.selectable`) as one selection across
    /// paragraphs, headings, list items, quotes, code blocks and table cells (`El.selectionGroup`).
    public func selectable(_ on: Bool) -> Markdown {
        var copy = self
        copy.selectableFlag = on
        return copy
    }

    /// With ``selectable(_:)``, copying a selection copies the Markdown source instead of the
    /// text as drawn (`El.selectionCopy`), by whole top-level blocks.
    public func copySource(_ on: Bool) -> Markdown {
        var copy = self
        copy.copySourceFlag = on
        return copy
    }

    /// Code blocks keep their lines whole and tables their columns' natural widths, each
    /// scrolling sideways in its own `El.scrollX` viewport when wider than the text column.
    public func scrollWide(_ on: Bool) -> Markdown {
        var copy = self
        copy.scrollWideFlag = on
        return copy
    }

    /// Colours code blocks with `f` instead of the built-in scanners.
    public func highlight(
        _ f: @escaping (String?, String) -> [syntax.Highlight],
        file: StaticString = #fileID,
        line: UInt = #line,
        column: UInt = #column
    ) -> Markdown {
        highlighter(Highlighter.new(f, file: file, line: line, column: column))
    }

    /// Colours code blocks with `h` (by default ``Highlighter/builtin()``).
    public func highlighter(_ h: Highlighter) -> Markdown {
        var copy = self
        copy.highlighterValue = h
        return copy
    }

    public func build(_ k: Kit) -> El {
        let resolved = styleOverride ?? MarkdownStyle.fromKit(k)
        var copy = self
        copy.styleOverride = nil
        return copy.render(resolved)
    }

    /// Builds with `style`, for apps without a ``Kit`` (see ``MarkdownStyle/neutral(_:)`` and
    /// ``MarkdownStyle/fromSeed(_:)``).
    public func render(_ style: MarkdownStyle) -> El {
        let blocks: [MarkdownBlock]
        let sources: [Source]
        let tasks: [(Bool, Int)?]
        let starts: [Int]
        let maps: [BlockMap]
        switch (autolinkFlag, streamingFlag) {
        case (true, false):
            let doc = docCached(src)
            blocks = doc.blocks
            sources = doc.sources
            tasks = doc.tasks
            starts = doc.starts
            maps = doc.maps
        case (true, true):
            let doc = streamCached(src)
            blocks = doc.blocks
            sources = doc.sources
            tasks = doc.tasks
            starts = doc.starts
            maps = doc.maps
        case (false, let isStreaming):
            let parsed = isStreaming ? parseStreaming(src, false) : parseDoc(src, false)
            blocks = parsed.blocks
            sources = parsed.sources
            tasks = parsed.tasks
            starts = parsed.starts
            maps = parsed.maps
        }

        let keys: [String]
        if blockKeysList.isEmpty {
            keys = []
        } else {
            keys = starts.map { at in
                blockKeysList.first(where: { $0.0 == at })?.1 ?? ""
            }
        }

        let r = Renderer(
            s: style,
            highlights: highlightsList,
            reveal: revealFade,
            streaming: streamingFlag,
            onLink: onLinkWire,
            onLinkSecondary: onLinkSecondaryWire,
            linkLook: linkLookFn,
            onTask: onTaskWire,
            tasksReadOnly: tasksReadOnlyFlag,
            linkRing: linkRingFn,
            selectable: selectableFlag,
            scrollWide: scrollWideFlag,
            highlighter: highlighterValue,
            sources: sources,
            tasks: tasks
        )
        let root = r.blocks(blocks, maps, keys, true).selectionGroup(selectableFlag)
        if !(selectableFlag && copySourceFlag) {
            return root
        }
        let names = renderedKeys(blocks.count, keys)
        let capturedSrc = src
        let capturedStarts = starts
        return root.selectionCopy { sel in
            sourceCopy(capturedSrc, capturedStarts, names, sel)
        }
    }
}

/// Namespace mirroring `rune_kit::markdown` module exports.
public enum markdown {
    public typealias Style = MarkdownInlineStyle
    public typealias Inline = MarkdownInline
    public typealias Block = MarkdownBlock
    public typealias Table = MarkdownTable
    public typealias Case = RuneKit.Case
    public typealias Highlight = RuneKit.Highlight
    public typealias HighlightItem = RuneKit.HighlightItem
    public typealias Markdown = RuneKit.Markdown
    public typealias MarkdownStyle = RuneKit.MarkdownStyle
    public typealias Syntax = RuneKit.Syntax

    /// Parses `src` into blocks. Unclosed constructs are closed at the end of input.
    public static func parse(_ src: String) -> [MarkdownBlock] {
        parseMarkdown(src)
    }

    /// ``parse(_:)`` memoised by source on this thread.
    public static func parseCached(_ src: String) -> [MarkdownBlock] {
        parseMarkdownCached(src)
    }

    /// Finds non-overlapping matches of `query` in the rendered text of `src`, in document order.
    public static func find(_ src: String, _ query: String, _ caseSensitivity: Case) -> [[Range<Int>]] {
        findMarkdown(src, query, caseSensitivity)
    }
}
