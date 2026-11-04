// Ported from: crates/rune-kit/src/markdown/parser.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Markdown source to blocks: the CommonMark + GFM event walk, code spans, GFM tables, and the
//! maps from source bytes to rendered text.
// PORT NOTE: Replaces Rust's `pulldown-cmark` (`ENABLE_STRIKETHROUGH | ENABLE_TABLES |
// ENABLE_TASKLISTS`) with a zero-dependency CommonMark + GFM event scanner feeding the exact
// upstream `Builder` state machine so no external SwiftPM dependencies are required.

import Rune

/// Maps source UTF-8 byte ranges to rendered text UTF-8 byte ranges.
struct SpanMap: Sendable, Equatable {
    var pairs: [(Range<Int>, Range<Int>)]

    init(_ pairs: [(Range<Int>, Range<Int>)] = []) {
        self.pairs = pairs
    }

    static func == (lhs: SpanMap, rhs: SpanMap) -> Bool {
        guard lhs.pairs.count == rhs.pairs.count else { return false }
        for (a, b) in zip(lhs.pairs, rhs.pairs) where a.0 != b.0 || a.1 != b.1 {
            return false
        }
        return true
    }

    mutating func push(_ src: Range<Int>, _ out: Range<Int>) {
        if src.lowerBound >= src.upperBound || out.lowerBound >= out.upperBound {
            return
        }
        if let lastIdx = pairs.indices.last {
            let lastSrc = pairs[lastIdx].0
            let lastOut = pairs[lastIdx].1
            if lastSrc.upperBound == src.lowerBound,
               lastOut.upperBound == out.lowerBound,
               lastSrc.count == lastOut.count,
               src.count == out.count
            {
                pairs[lastIdx] = (lastSrc.lowerBound..<src.upperBound, lastOut.lowerBound..<out.upperBound)
                return
            }
        }
        pairs.append((src, out))
    }

    mutating func truncateOut(_ len: Int) {
        var kept: [(Range<Int>, Range<Int>)] = []
        kept.reserveCapacity(pairs.count)
        for var (src, out) in pairs {
            if out.lowerBound >= len {
                continue
            }
            if out.upperBound > len {
                let cut = out.upperBound - len
                if src.count == out.count {
                    src = src.lowerBound..<max(0, src.upperBound - cut)
                }
                out = out.lowerBound..<len
            }
            if src.lowerBound < src.upperBound && out.lowerBound < out.upperBound {
                kept.append((src, out))
            }
        }
        pairs = kept
    }

    mutating func shiftSrc(_ offset: Int) {
        guard offset != 0 else { return }
        for i in pairs.indices {
            let s = pairs[i].0
            pairs[i].0 = (s.lowerBound + offset)..<(s.upperBound + offset)
        }
    }
}

/// Source-to-rendered byte mappings parallel to ``MarkdownBlock``, kept beside `MarkdownBlock`
/// so `MarkdownBlock` keeps its shape.
enum BlockMap: Sendable, Equatable {
    case inline(SpanMap)
    case code(SpanMap)
    case list([[BlockMap]])
    case quote([BlockMap])
    case table(head: [SpanMap], rows: [[SpanMap]])
    case none

    func shiftSrc(_ offset: Int) -> BlockMap {
        guard offset != 0 else { return self }
        switch self {
        case var .inline(m):
            m.shiftSrc(offset)
            return .inline(m)
        case var .code(m):
            m.shiftSrc(offset)
            return .code(m)
        case let .list(items):
            return .list(items.map { $0.map { $0.shiftSrc(offset) } })
        case let .quote(inner):
            return .quote(inner.map { $0.shiftSrc(offset) })
        case let .table(head, rows):
            let shiftedHead = head.map { m -> SpanMap in
                var copy = m
                copy.shiftSrc(offset)
                return copy
            }
            let shiftedRows = rows.map { row in
                row.map { m -> SpanMap in
                    var copy = m
                    copy.shiftSrc(offset)
                    return copy
                }
            }
            return .table(head: shiftedHead, rows: shiftedRows)
        case .none:
            return .none
        }
    }
}

/// What the source ends inside, from the last block-level start the walk met.
enum Tail: Sendable, Equatable {
    case none
    /// A code or HTML block: its text is literal.
    case code
    /// Inline text from this source byte on (a paragraph, a tight list item, a heading or a
    /// table cell).
    case inline(Int, Scope)
}

/// How far an inline run can reach.
enum Scope: Sendable, Equatable {
    /// Across lines, until a blank one.
    case para
    /// To the end of its line (a heading).
    case line
    /// To the next `|` or the end of its line.
    case cell
}

/// Parsed document bundle parallel to Rust's `ParsedDoc` tuple.
struct ParsedDoc {
    var blocks: [MarkdownBlock]
    var sources: [Source]
    var tasks: [(Bool, Int)?]
    var cuts: [Cut]
    var starts: [Int]
    var maps: [BlockMap]
}

/// Where a top-level block starts: the start of its first line, and how many top-level blocks,
/// ``Source``s and list items come before it.
struct Cut: Sendable, Equatable {
    var at: Int
    var blocks: Int
    var sources: Int
    var tasks: Int
}

/// What colours a ``MarkdownBlock/code(_:)`` and which lines of a ``MarkdownBlock/mermaid(_:)``
/// draw, one per block in document order (the order the renderer meets them).
struct Source: Sendable, Equatable {
    /// The fence's language as written (its info string's first word), if it names one.
    var lang: String?
    /// The code's length, to check this belongs to the block it is matched with.
    var len: Int
    /// How many leading bytes get colour: all of them, or while an unclosed fence streams in,
    /// the complete lines (the line still arriving draws plain until its newline).
    var coloured: Int
    /// The fence's closing line hasn't arrived.
    var open: Bool
}

let PAD = "\u{202F}\u{202F}"

private enum Fence: Equatable {
    case plain(String?, Bool)
    case diff
    case mermaid(Bool)
}

/// An emphasis, strong, strike or link run that has started and not yet ended.
private struct OpenRun {
    var start: Int
    var style: MarkdownInlineStyle
    var url: String?
}

private enum Container {
    case root
    case quote
    case list(UInt64?, [[MarkdownBlock]], [[BlockMap]])
    case item(Int)
    case table(MarkdownTable, [MarkdownInline], [SpanMap], [[SpanMap]], [SpanMap])
}

private enum InlineKind {
    case para
    case heading(UInt8)
    case cell
}

private struct Frame {
    var container: Container
    var blocks: [MarkdownBlock]
    var maps: [BlockMap]
}

private struct InlineState {
    var kind: InlineKind
    var inl: MarkdownInline
    var open: [OpenRun]
    var map: SpanMap
}

private struct Builder {
    var stack: [Frame]
    var inlineState: InlineState?
    var code: (String, Fence, SpanMap)?
    var lastRootPara: Range<Int>?
    var sources: [Source]
    var tasks: [(Bool, Int)?]
    var blockStarts: [Int]
    var rootStart: Int
    var cuts: [Cut]
    var autolink: Bool
    var imageStarts: [Int]
    var imageRanges: [(Int, Int)]
    var tail: Tail

    mutating func push(_ b: MarkdownBlock, _ map: BlockMap) {
        if stack.count == 1 {
            blockStarts.append(rootStart)
        }
        let topIdx = stack.count - 1
        stack[topIdx].blocks.append(b)
        stack[topIdx].maps.append(map)
    }

    mutating func pushCode(_ rawText: String, _ fence: Fence, _ rawMap: SpanMap, _ eof: Bool) {
        var text = rawText
        var map = rawMap
        let lineEnded = text.hasSuffix("\n")
        if eof {
            while text.last == "\n" || text.last == "\r" {
                text.removeLast()
            }
        } else if lineEnded {
            text.removeLast()
            if text.last == "\r" {
                text.removeLast()
            }
        }
        let byteLen = text.utf8.count
        map.truncateOut(byteLen)
        let block = codeBlock(text, fence)
        switch block {
        case let .code(codeStr), let .mermaid(codeStr):
            let lang: String?
            let closed: Bool
            switch fence {
            case let .plain(l, c):
                lang = l
                closed = c
            case let .mermaid(c):
                lang = "mermaid"
                closed = c
            case .diff:
                lang = nil
                closed = true
            }
            let codeLen = codeStr.utf8.count
            let coloured: Int
            if closed || lineEnded {
                coloured = codeLen
            } else {
                coloured = lastNewlineOffset(codeStr) ?? 0
            }
            sources.append(Source(lang: lang, len: codeLen, coloured: coloured, open: !closed))
        default:
            break
        }
        push(block, .code(map))
    }

    mutating func ensureInline() {
        if inlineState == nil {
            inlineState = InlineState(kind: .para, inl: MarkdownInline(), open: [], map: SpanMap())
        }
    }

    mutating func flushInline() {
        guard var state = inlineState else { return }
        inlineState = nil
        for o in state.open {
            endRun(&state.inl, o)
        }
        let trimmedText = String(trimEndUnicodeWhitespace(state.inl.text))
        let trimmed = trimmedText.utf8.count
        state.inl.text = trimmedText
        state.map.truncateOut(trimmed)
        state.inl.spans = state.inl.spans.compactMap { s in
            let end = min(s.1, trimmed)
            return s.0 < end ? (s.0, end, s.2) : nil
        }
        state.inl.links = state.inl.links.compactMap { l in
            let end = min(l.1, trimmed)
            return l.0 < end ? (l.0, end, l.2) : nil
        }
        if autolink {
            autolinkInline(&state.inl, imageRanges)
        }
        imageRanges.removeAll()
        imageStarts.removeAll()
        if case .cell = state.kind {
            if let lastIdx = stack.indices.last,
               case .table(let t, var cells, let head, let rows, var cellMaps) = stack[lastIdx].container
            {
                cells.append(state.inl)
                cellMaps.append(state.map)
                stack[lastIdx].container = .table(t, cells, head, rows, cellMaps)
            }
            return
        }
        if state.inl.text.isEmpty {
            return
        }
        let block: MarkdownBlock
        switch state.kind {
        case .para, .cell:
            block = .para(state.inl)
        case let .heading(l):
            block = .heading(l, state.inl)
        }
        push(block, .inline(state.map))
    }

    mutating func popContainer() {
        flushInline()
        guard let popped = stack.popLast() else { return }
        switch popped.container {
        case .item:
            if let lastIdx = stack.indices.last,
               case .list(let start, var items, var itemMaps) = stack[lastIdx].container
            {
                items.append(popped.blocks)
                itemMaps.append(popped.maps)
                stack[lastIdx].container = .list(start, items, itemMaps)
            }
        case let .list(start, items, itemMaps):
            push(.list(start: start, items: items), .list(itemMaps))
        case .quote:
            push(.quote(popped.blocks), .quote(popped.maps))
        case .table(var t, let cells, let head, var rows, let cellMaps):
            if !cells.isEmpty {
                t.rows.append(cells)
                rows.append(cellMaps)
            }
            push(.table(t), .table(head: head, rows: rows))
        case .root:
            break
        }
    }

    mutating func openSpan(_ style: MarkdownInlineStyle, _ url: String?) {
        ensureInline()
        let start = inlineState!.inl.text.utf8.count
        inlineState!.open.append(OpenRun(start: start, style: style, url: url))
    }

    mutating func closeSpan() {
        ensureInline()
        if let o = inlineState!.open.popLast() {
            endRun(&inlineState!.inl, o)
        }
    }
}

private func endRun(_ inl: inout MarkdownInline, _ o: OpenRun) {
    let end = inl.text.utf8.count
    if let url = o.url {
        inl.links.append((o.start, end, url))
    }
    inl.spans.append((o.start, end, o.style))
}

private func codeBlock(_ text: String, _ fence: Fence) -> MarkdownBlock {
    switch fence {
    case .plain:
        return .code(text)
    case .diff:
        return .diff(text)
    case .mermaid:
        return .mermaid(text)
    }
}

private func lastNewlineOffset(_ s: String) -> Int? {
    let bytes = Array(s.utf8)
    for i in stride(from: bytes.count - 1, through: 0, by: -1) where bytes[i] == 0x0A {
        return i
    }
    return nil
}

private func lastNewlineBefore(_ bytes: [UInt8], _ limit: Int) -> Int? {
    guard limit > 0 else { return nil }
    let hi = min(limit, bytes.count)
    for i in stride(from: hi - 1, through: 0, by: -1) where bytes[i] == 0x0A {
        return i
    }
    return nil
}

private func sliceUtf8(_ src: String, _ range: Range<Int>) -> String? {
    let utf8 = src.utf8
    guard range.lowerBound >= 0, range.upperBound <= utf8.count, range.lowerBound <= range.upperBound else {
        return nil
    }
    let startIdx = utf8.index(utf8.startIndex, offsetBy: range.lowerBound)
    let endIdx = utf8.index(utf8.startIndex, offsetBy: range.upperBound)
    guard let s = startIdx.samePosition(in: src), let e = endIdx.samePosition(in: src) else {
        return nil
    }
    return String(src[s..<e])
}

/// Source byte range of the inner code text inside a backtick code span `src[range]`.
private func codeSpanContentRange(_ srcBytes: [UInt8], _ range: Range<Int>, _ rendered: String) -> Range<Int> {
    guard range.lowerBound >= 0, range.upperBound <= srcBytes.count, range.lowerBound <= range.upperBound else {
        return range
    }
    var open = 0
    while range.lowerBound + open < range.upperBound && srcBytes[range.lowerBound + open] == 0x60 {
        open += 1
    }
    var close = 0
    while range.upperBound - 1 - close >= range.lowerBound + open && srcBytes[range.upperBound - 1 - close] == 0x60 {
        close += 1
    }
    var start = range.lowerBound + open
    var end = max(0, range.upperBound - close)
    let allSpaces = rendered.unicodeScalars.allSatisfy { $0 == " " }
    if !allSpaces,
       start < srcBytes.count,
       end > 0,
       end - 1 < srcBytes.count
    {
        let first = srcBytes[start]
        let last = srcBytes[end - 1]
        let firstWs = first == 0x20 || first == 0x0D || first == 0x0A
        let lastWs = last == 0x20 || last == 0x0D || last == 0x0A
        if firstWs && lastWs {
            start += 1
            end -= 1
        }
    }
    return start < end ? (start..<end) : range
}

private func splitInclusiveCrLf(_ s: String) -> [String] {
    guard !s.isEmpty else { return [] }
    var out: [String] = []
    var current = ""
    for ch in s {
        current.append(ch)
        if ch == "\r" || ch == "\n" {
            out.append(current)
            current = ""
        }
    }
    if !current.isEmpty {
        out.append(current)
    }
    return out
}

private func charByteOffsets(_ s: String) -> [(Int, Character, Int)] {
    var out: [(Int, Character, Int)] = []
    var byteOff = 0
    for ch in s {
        let len = String(ch).utf8.count
        out.append((byteOff, ch, len))
        byteOff += len
    }
    return out
}

private func utf8StartsWithChar(_ bytes: [UInt8], _ at: Int, _ ch: Character) -> Bool {
    let chBytes = Array(String(ch).utf8)
    guard at + chBytes.count <= bytes.count else { return false }
    for k in 0..<chBytes.count where bytes[at + k] != chBytes[k] {
        return false
    }
    return true
}

/// Code spans normalize newlines and omit continuation-line container prefixes. Map the
/// actual surviving characters, not a ratio of the source and displayed byte lengths.
private func mapCodeSpan(
    _ src: String,
    _ range: Range<Int>,
    _ rendered: String,
    _ offset: Int,
    _ map: inout SpanMap
) {
    guard let raw = sliceUtf8(src, range) else { return }
    let renderedBytes = Array(rendered.utf8)
    if raw == rendered {
        map.push(range, offset..<(offset + renderedBytes.count))
        return
    }
    var out = 0
    var at = range.lowerBound
    for line in splitInclusiveCrLf(raw) {
        let lineByteLen = line.utf8.count
        var body = line
        while body.last == "\r" || body.last == "\n" {
            body.removeLast()
        }
        let bodyByteLen = body.utf8.count
        let bodyChars = charByteOffsets(body)
        var matched: (Int, [(Range<Int>, Range<Int>)])? = nil
        for startIdx in bodyChars.indices {
            let skip = bodyChars[startIdx].0
            var idx = startIdx
            var consumed = 0
            var pairs: [(Range<Int>, Range<Int>)] = []
            var ok = true
            while idx < bodyChars.count {
                let relOff = bodyChars[idx].0 - skip
                var ch = bodyChars[idx].1
                var chLen = bodyChars[idx].2
                var relEnd = relOff + chLen
                if ch == "\\",
                   idx + 1 < bodyChars.count,
                   bodyChars[idx + 1].1 == "|",
                   out + consumed < renderedBytes.count,
                   renderedBytes[out + consumed] == 0x7C
                {
                    idx += 1
                    ch = bodyChars[idx].1
                    chLen = bodyChars[idx].2
                    relEnd = (bodyChars[idx].0 - skip) + chLen
                }
                if !utf8StartsWithChar(renderedBytes, out + consumed, ch) {
                    ok = false
                    break
                }
                let sRange = (at + skip + relOff)..<(at + skip + relEnd)
                let dRange = (offset + out + consumed)..<(offset + out + consumed + chLen)
                pairs.append((sRange, dRange))
                consumed += chLen
                idx += 1
            }
            if ok {
                matched = (consumed, pairs)
                break
            }
        }
        if let (consumed, pairs) = matched {
            for (s, d) in pairs {
                map.push(s, d)
            }
            out += consumed
        }
        let endedCrLf = line.last == "\r" || line.last == "\n"
        if endedCrLf, out < renderedBytes.count, renderedBytes[out] == 0x20 {
            map.push((at + bodyByteLen)..<(at + lineByteLen), (offset + out)..<(offset + out + 1))
            out += 1
        }
        at += lineByteLen
    }
}

/// Parses `src` into blocks. Unclosed constructs are closed at the end of input.
public func parse(_ src: String) -> [MarkdownBlock] {
    parseDoc(src, true).blocks
}

func parseMarkdown(_ src: String) -> [MarkdownBlock] {
    parse(src)
}

func parseDoc(_ src: String, _ autolink: Bool) -> ParsedDoc {
    parseDocTail(src, autolink).0
}

/// ``parseDoc(_:_:)``, and what the source ends inside.
func parseDocTail(_ src: String, _ autolink: Bool) -> (ParsedDoc, Tail) {
    let srcBytes = Array(src.utf8)
    var b = Builder(
        stack: [Frame(container: .root, blocks: [], maps: [])],
        inlineState: nil,
        code: nil,
        lastRootPara: nil,
        sources: [],
        tasks: [],
        blockStarts: [],
        rootStart: 0,
        cuts: [],
        autolink: autolink,
        imageStarts: [],
        imageRanges: [],
        tail: .none
    )

    let events = emitMarkdownEvents(src, srcBytes)
    for (ev, range) in events {
        let startsBlock: Bool
        switch ev {
        case .startParagraph, .startHeading, .startCodeBlock, .startBlockQuote, .startList, .startTable, .startHtmlBlock, .rule:
            startsBlock = true
        default:
            startsBlock = false
        }
        if startsBlock && b.stack.count == 1 && b.code == nil {
            b.flushInline()
            let at = lastNewlineBefore(srcBytes, range.lowerBound).map { $0 + 1 } ?? 0
            b.rootStart = at
            b.cuts.append(Cut(
                at: at,
                blocks: b.stack[0].blocks.count,
                sources: b.sources.count,
                tasks: b.tasks.count
            ))
        }
        switch ev {
        case .startParagraph, .startItem:
            b.tail = .inline(range.lowerBound, .para)
        case .startHeading:
            b.tail = .inline(range.lowerBound, .line)
        case .startTableCell:
            if !range.isEmpty {
                b.tail = .inline(range.lowerBound, .cell)
            }
        case .startCodeBlock, .startHtmlBlock:
            b.tail = .code
        case .startTable, .rule:
            b.tail = .none
        default:
            break
        }

        switch ev {
        case .startParagraph:
            b.flushInline()
            if b.stack.count == 1 {
                b.lastRootPara = range
            }
            b.inlineState = InlineState(kind: .para, inl: MarkdownInline(), open: [], map: SpanMap())

        case let .startHeading(level):
            b.flushInline()
            let clamped: UInt8 = level <= 3 ? level : 4
            b.inlineState = InlineState(kind: .heading(clamped), inl: MarkdownInline(), open: [], map: SpanMap())

        case let .startCodeBlock(info):
            b.flushInline()
            let fence: Fence
            if let info {
                let word = firstFenceWord(info)
                let lower = word.lowercased()
                let blockSlice = sliceUtf8(src, range) ?? ""
                if lower == "diff" || lower == "patch" {
                    fence = .diff
                } else if lower == "mermaid" {
                    fence = .mermaid(fenceClosed(blockSlice))
                } else {
                    fence = .plain(word.isEmpty ? nil : word, fenceClosed(blockSlice))
                }
            } else {
                fence = .plain(nil, true)
            }
            b.code = ("", fence, SpanMap())

        case .startBlockQuote:
            b.flushInline()
            b.stack.append(Frame(container: .quote, blocks: [], maps: []))

        case let .startList(start):
            b.flushInline()
            b.stack.append(Frame(container: .list(start, [], []), blocks: [], maps: []))

        case .startItem:
            b.flushInline()
            let idx = b.tasks.count
            b.tasks.append(nil)
            b.stack.append(Frame(container: .item(idx), blocks: [], maps: []))

        case let .startTable(aligns):
            b.flushInline()
            let t = MarkdownTable(align: aligns, head: [], rows: [], open: false)
            b.stack.append(Frame(container: .table(t, [], [], [], []), blocks: [], maps: []))

        case .startTableHead, .startTableRow:
            let open = !sliceContainsNewline(srcBytes, from: range.lowerBound)
            if let lastIdx = b.stack.indices.last,
               case .table(var t, let cells, let head, let rows, let cellMaps) = b.stack[lastIdx].container
            {
                t.open = open
                b.stack[lastIdx].container = .table(t, cells, head, rows, cellMaps)
            }

        case .startTableCell:
            b.flushInline()
            b.inlineState = InlineState(kind: .cell, inl: MarkdownInline(), open: [], map: SpanMap())

        case .startStrong:
            b.openSpan(.strong, nil)
        case .startEmphasis:
            b.openSpan(.em, nil)
        case .startStrikethrough:
            b.openSpan(.strike, nil)
        case let .startLink(destUrl):
            b.openSpan(.link, destUrl)
        case .startImage:
            b.ensureInline()
            b.imageStarts.append(b.inlineState!.inl.text.utf8.count)
        case .startHtmlBlock:
            break

        case .endParagraph, .endHeading, .endTableCell:
            b.flushInline()

        case .endCodeBlock:
            if let (text, fence, map) = b.code {
                b.code = nil
                b.pushCode(text, fence, map, false)
            }

        case .endTableHead:
            b.flushInline()
            if let lastIdx = b.stack.indices.last,
               case .table(var t, let cells, _, let rows, let cellMaps) = b.stack[lastIdx].container
            {
                t.head = cells
                b.stack[lastIdx].container = .table(t, [], cellMaps, rows, [])
            }

        case .endTableRow:
            b.flushInline()
            if let lastIdx = b.stack.indices.last,
               case .table(var t, let cells, let head, var rows, let cellMaps) = b.stack[lastIdx].container
            {
                t.rows.append(cells)
                rows.append(cellMaps)
                b.stack[lastIdx].container = .table(t, [], head, rows, [])
            }

        case .endBlockQuote, .endItem, .endList, .endTable:
            b.popContainer()

        case .endStrong, .endEmphasis, .endStrikethrough, .endLink:
            b.closeSpan()

        case .endImage:
            if let start = b.imageStarts.popLast() {
                b.ensureInline()
                let end = b.inlineState!.inl.text.utf8.count
                b.imageRanges.append((start, end))
            }

        case .endHtmlBlock:
            break

        case let .text(t):
            if var codeState = b.code {
                let start = codeState.0.utf8.count
                codeState.0.append(t)
                codeState.2.push(range, start..<codeState.0.utf8.count)
                b.code = codeState
            } else {
                b.ensureInline()
                let start = b.inlineState!.inl.text.utf8.count
                b.inlineState!.inl.text.append(t)
                b.inlineState!.map.push(range, start..<b.inlineState!.inl.text.utf8.count)
            }

        case let .code(t):
            let codeSrc = codeSpanContentRange(srcBytes, range, t)
            b.ensureInline()
            let a = b.inlineState!.inl.text.utf8.count
            b.inlineState!.inl.text.append(PAD)
            let start = b.inlineState!.inl.text.utf8.count
            b.inlineState!.inl.text.append(t)
            let end = b.inlineState!.inl.text.utf8.count
            b.inlineState!.inl.text.append(PAD)
            let afterPad = b.inlineState!.inl.text.utf8.count
            b.inlineState!.inl.spans.append((a, start, .codePad))
            b.inlineState!.inl.spans.append((start, end, .code))
            b.inlineState!.inl.spans.append((end, afterPad, .codePad))
            mapCodeSpan(src, codeSrc, t, start, &b.inlineState!.map)

        case .softBreak:
            b.ensureInline()
            let start = b.inlineState!.inl.text.utf8.count
            b.inlineState!.inl.text.append(" ")
            b.inlineState!.map.push(range, start..<b.inlineState!.inl.text.utf8.count)

        case .hardBreak:
            b.ensureInline()
            let start = b.inlineState!.inl.text.utf8.count
            b.inlineState!.inl.text.append("\n")
            b.inlineState!.map.push(range, start..<b.inlineState!.inl.text.utf8.count)

        case let .taskListMarker(checked):
            for frame in b.stack.reversed() {
                if case let .item(idx) = frame.container {
                    b.tasks[idx] = (checked, range.lowerBound)
                    break
                }
            }

        case .rule:
            b.flushInline()
            b.push(.rule, .none)
        }
    }

    b.flushInline()
    if let (text, fence, map) = b.code {
        b.code = nil
        b.pushCode(text, fence, map, true)
    }
    while b.stack.count > 1 {
        b.popContainer()
    }
    let lastPara = b.lastRootPara
    let rootFrame = b.stack.removeLast()
    var blocks = rootFrame.blocks
    var maps = rootFrame.maps
    if let lastBlock = blocks.last,
       case .para = lastBlock,
       let range = lastPara,
       let tailSrc = sliceUtf8(src, range.lowerBound..<srcBytes.count),
       let (t, map) = pendingTable(tailSrc, range.lowerBound, autolink)
    {
        blocks[blocks.count - 1] = .table(t)
        maps[maps.count - 1] = map
    }
    let doc = ParsedDoc(
        blocks: blocks,
        sources: b.sources,
        tasks: b.tasks,
        cuts: b.cuts,
        starts: b.blockStarts,
        maps: maps
    )
    return (doc, b.tail)
}

private func firstFenceWord(_ info: String) -> String {
    var out = ""
    for ch in info {
        if ch.isWhitespace || ch == "," {
            break
        }
        out.append(ch)
    }
    return out
}

private func sliceContainsNewline(_ bytes: [UInt8], from start: Int) -> Bool {
    guard start < bytes.count else { return false }
    for i in max(0, start)..<bytes.count where bytes[i] == 0x0A {
        return true
    }
    return false
}

private func rustLines(_ s: String) -> [Substring] {
    guard !s.isEmpty else { return [] }
    var parts = s.split(separator: "\n", omittingEmptySubsequences: false)
    if s.hasSuffix("\n") {
        parts.removeLast()
    }
    for i in parts.indices where parts[i].hasSuffix("\r") {
        parts[i] = parts[i].dropLast()
    }
    return parts
}

/// Whether a fenced code block's source (from its opening fence) has its closing fence.
private func fenceClosed(_ block: String) -> Bool {
    func strip(_ l: Substring) -> String {
        var s = l
        while let first = s.first, first == ">" || first.isWhitespace {
            s = s.dropFirst()
        }
        return trimEndUnicodeWhitespace(String(s))
    }
    let lines = rustLines(block)
    guard lines.count >= 2 else { return false }
    let first = strip(lines[0])
    guard let ch = first.first else { return false }
    var n = 0
    for c in first {
        if c == ch {
            n += 1
        } else {
            break
        }
    }
    let last = strip(lines[lines.count - 1])
    return last.utf8.count >= n && !last.isEmpty && last.allSatisfy { $0 == ch }
}

/// The header (and partial delimiter row) of a table still streaming in, from the source of the
/// document's last paragraph: `| a | b |` alone, or followed by a delimiter row in progress.
private func pendingTable(_ src: String, _ baseOffset: Int, _ autolink: Bool) -> (MarkdownTable, BlockMap)? {
    let trimmedSrc = trimEndUnicodeWhitespace(src)
    let lines = rustLines(trimmedSrc)
    guard !lines.isEmpty, lines.count <= 2 else { return nil }
    let rawHead = String(lines[0])
    let trimmedStartHead = trimStartUnicodeWhitespace(rawHead)
    let leadWs = rawHead.utf8.count - trimmedStartHead.utf8.count
    let head = trimEndUnicodeWhitespace(trimmedStartHead)
    let delim: String? = lines.count == 2 ? trimUnicodeWhitespace(String(lines[1])) : nil
    guard head.hasPrefix("|") else { return nil }
    let cells = splitRow(head, baseOffset + leadWs)
    if cells.count < 2 {
        return nil
    }
    if let d = delim {
        if !d.hasPrefix("|") || !d.allSatisfy({ $0 == "|" || $0 == ":" || $0 == "-" || $0 == " " }) {
            return nil
        }
    }
    var align = Array(repeating: Align.start, count: cells.count)
    if let d = delim {
        for (idx, (_, spec)) in splitRow(d, 0).enumerated() where idx < align.count {
            let left = spec.hasPrefix(":")
            let right = spec.utf8.count > 1 && spec.hasSuffix(":")
            if left && right {
                align[idx] = .center
            } else if !left && right {
                align[idx] = .end
            } else {
                align[idx] = .start
            }
        }
    }
    var headInlines: [MarkdownInline] = []
    var headMaps: [SpanMap] = []
    headInlines.reserveCapacity(cells.count)
    headMaps.reserveCapacity(cells.count)
    for (cellOff, c) in cells {
        let (inl, map) = inlineOf(c, cellOff, autolink)
        headInlines.append(inl)
        headMaps.append(map)
    }
    return (
        MarkdownTable(align: align, head: headInlines, rows: [], open: true),
        .table(head: headMaps, rows: [])
    )
}

/// The cells of a `| a | b |` line (a trailing pipe is optional; `\|` doesn't split, and stays
/// escaped for `inlineOf` to unescape), with each trimmed cell's starting byte offset.
private func splitRow(_ line: String, _ baseOffset: Int) -> [(Int, String)] {
    let pipeOff = line.hasPrefix("|") ? 1 : 0
    let inner = pipeOff == 1 ? String(line.dropFirst()) : line
    var cells: [(Int, String)] = [(baseOffset + pipeOff, "")]
    let chars = charByteOffsets(inner)
    var i = 0
    while i < chars.count {
        let (byteIdx, ch, _) = chars[i]
        if ch == "\\", i + 1 < chars.count, chars[i + 1].1 == "|" {
            cells[cells.count - 1].1.append("\\")
            cells[cells.count - 1].1.append("|")
            i += 2
        } else if ch == "|" {
            cells.append((baseOffset + pipeOff + byteIdx + 1, ""))
            i += 1
        } else {
            cells[cells.count - 1].1.append(ch)
            i += 1
        }
    }
    if let last = cells.last,
       trimUnicodeWhitespace(last.1).isEmpty,
       trimEndUnicodeWhitespace(inner).hasSuffix("|")
    {
        cells.removeLast()
    }
    return cells.map { (off, c) in
        let trimmedStart = trimStartUnicodeWhitespace(c)
        let lead = c.utf8.count - trimmedStart.utf8.count
        return (off + lead, String(trimEndUnicodeWhitespace(trimmedStart)))
    }
}

private func inlineOf(_ src: String, _ offset: Int, _ autolink: Bool) -> (MarkdownInline, SpanMap) {
    let doc = parseDoc(src, autolink)
    if let firstBlock = doc.blocks.first,
       case let .para(inl) = firstBlock,
       let firstMap = doc.maps.first,
       case var .inline(m) = firstMap
    {
        m.shiftSrc(offset)
        return (inl, m)
    }
    var m = SpanMap()
    m.push(offset..<(offset + src.utf8.count), 0..<src.utf8.count)
    return (MarkdownInline(text: src), m)
}

// MARK: - Zero-Dependency CommonMark + GFM Event Scanner

private enum MdEvent {
    case startParagraph
    case endParagraph
    case startHeading(UInt8)
    case endHeading
    case startCodeBlock(String?)
    case endCodeBlock
    case startBlockQuote
    case endBlockQuote
    case startList(UInt64?)
    case endList
    case startItem
    case endItem
    case startTable([Align])
    case endTable
    case startTableHead
    case endTableHead
    case startTableRow
    case endTableRow
    case startTableCell
    case endTableCell
    case startHtmlBlock
    case endHtmlBlock
    case startStrong
    case endStrong
    case startEmphasis
    case endEmphasis
    case startStrikethrough
    case endStrikethrough
    case startLink(String)
    case endLink
    case startImage
    case endImage
    case text(String)
    case code(String)
    case softBreak
    case hardBreak
    case taskListMarker(Bool)
    case rule
}

private struct RawLine {
    var start: Int
    var contentEnd: Int
    var end: Int
}

private struct LineCursor {
    var pos: Int
    var lineEnd: Int
    var lineFullEnd: Int
    var col: Int
    /// Spaces remaining from a partially consumed `\t`.
    var tabSpaces: Int

    mutating func advanceCols(_ bytes: [UInt8], _ count: Int) {
        var rem = count
        while rem > 0 {
            if tabSpaces > 0 {
                if tabSpaces <= rem {
                    rem -= tabSpaces
                    tabSpaces = 0
                } else {
                    tabSpaces -= rem
                    rem = 0
                }
                col += count - rem
                continue
            }
            guard pos < lineEnd else { break }
            let b = bytes[pos]
            if b == 0x20 {
                pos += 1
                col += 1
                rem -= 1
            } else if b == 0x09 {
                let width = 4 - (col % 4)
                pos += 1
                if width <= rem {
                    col += width
                    rem -= width
                } else {
                    tabSpaces = width - rem
                    col += rem
                    rem = 0
                }
            } else {
                break
            }
        }
    }

    func peekIndent(_ bytes: [UInt8]) -> (cols: Int, nextPos: Int, nextCol: Int) {
        var cols = tabSpaces
        var p = pos
        var c = col + tabSpaces
        while p < lineEnd {
            let b = bytes[p]
            if b == 0x20 {
                cols += 1
                c += 1
                p += 1
            } else if b == 0x09 {
                let w = 4 - (c % 4)
                cols += w
                c += w
                p += 1
            } else {
                break
            }
        }
        return (cols, p, c)
    }

    func isBlank(_ bytes: [UInt8]) -> Bool {
        let (_, nextPos, _) = peekIndent(bytes)
        return nextPos >= lineEnd
    }
}

private struct ParaLine {
    var start: Int
    var contentEnd: Int
    var fullEnd: Int
}

private struct CodeLine {
    var virtualSpaces: Int
    var start: Int
    var contentEnd: Int
    var fullEnd: Int
}

private enum ListKind: Equatable {
    case bullet(UInt8)
    case ordered(UInt8)
}

private final class BlockNode {
    enum Kind {
        case document
        case blockQuote
        case list(kind: ListKind, start: UInt64?)
        case listItem(padding: Int, emptyFirstLine: Bool, sawBlankAfterFirst: Bool)
        case paragraph([ParaLine])
        case heading(level: UInt8, slice: Range<Int>)
        case fencedCode(fenceChar: UInt8, fenceLen: Int, fenceIndent: Int, info: String, closed: Bool, lines: [CodeLine])
        case indentedCode(lines: [CodeLine], pendingBlanks: [CodeLine])
        case htmlBlock(htmlType: Int, closed: Bool)
        case rule
        case table(aligns: [Align], headLine: ParaLine, bodyLines: [ParaLine])
    }

    var kind: Kind
    var startByte: Int
    var endByte: Int
    var children: [BlockNode] = []

    init(kind: Kind, startByte: Int, endByte: Int) {
        self.kind = kind
        self.startByte = startByte
        self.endByte = endByte
    }
}

private func scanLines(_ bytes: [UInt8]) -> [RawLine] {
    guard !bytes.isEmpty else { return [] }
    var lines: [RawLine] = []
    var i = 0
    while i < bytes.count {
        let start = i
        while i < bytes.count && bytes[i] != 0x0A && bytes[i] != 0x0D {
            i += 1
        }
        let contentEnd = i
        if i < bytes.count {
            if bytes[i] == 0x0D, i + 1 < bytes.count, bytes[i + 1] == 0x0A {
                i += 2
            } else {
                i += 1
            }
        }
        lines.append(RawLine(start: start, contentEnd: contentEnd, end: i))
    }
    return lines
}

private func isAsciiPunct(_ b: UInt8) -> Bool {
    switch b {
    case 0x21...0x2F, 0x3A...0x40, 0x5B...0x60, 0x7B...0x7E:
        return true
    default:
        return false
    }
}

private func isAsciiSpaceOrTab(_ b: UInt8) -> Bool {
    b == 0x20 || b == 0x09
}

private func isAsciiAlpha(_ b: UInt8) -> Bool {
    (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A)
}

private func isAsciiAlnum(_ b: UInt8) -> Bool {
    isAsciiAlpha(b) || (b >= 0x30 && b <= 0x39)
}

private func asciiLower(_ b: UInt8) -> UInt8 {
    (b >= 0x41 && b <= 0x5A) ? (b + 32) : b
}

private func matchThematicBreak(_ bytes: [UInt8], _ pos: Int, _ end: Int) -> Bool {
    guard pos < end else { return false }
    let ch = bytes[pos]
    guard ch == 0x2A || ch == 0x2D || ch == 0x5F else { return false }
    var count = 0
    var i = pos
    while i < end {
        let b = bytes[i]
        if b == ch {
            count += 1
        } else if !isAsciiSpaceOrTab(b) {
            return false
        }
        i += 1
    }
    return count >= 3
}

private func matchSetextUnderline(_ bytes: [UInt8], _ pos: Int, _ end: Int) -> UInt8? {
    guard pos < end else { return nil }
    let ch = bytes[pos]
    guard ch == 0x3D || ch == 0x2D else { return nil }
    var i = pos
    while i < end && bytes[i] == ch {
        i += 1
    }
    while i < end && isAsciiSpaceOrTab(bytes[i]) {
        i += 1
    }
    guard i == end else { return nil }
    return ch == 0x3D ? 1 : 2
}

private func matchAtxHeading(_ bytes: [UInt8], _ pos: Int, _ end: Int) -> (UInt8, Range<Int>)? {
    var i = pos
    var hashes = 0
    while i < end && bytes[i] == 0x23 && hashes < 7 {
        hashes += 1
        i += 1
    }
    guard hashes >= 1 && hashes <= 6 else { return nil }
    if i < end && !isAsciiSpaceOrTab(bytes[i]) {
        return nil
    }
    while i < end && isAsciiSpaceOrTab(bytes[i]) {
        i += 1
    }
    var contentEnd = end
    while contentEnd > i && isAsciiSpaceOrTab(bytes[contentEnd - 1]) {
        contentEnd -= 1
    }
    var scanHash = contentEnd
    while scanHash > i && bytes[scanHash - 1] == 0x23 {
        scanHash -= 1
    }
    if scanHash < contentEnd {
        if scanHash == i || isAsciiSpaceOrTab(bytes[scanHash - 1]) {
            contentEnd = scanHash
            while contentEnd > i && isAsciiSpaceOrTab(bytes[contentEnd - 1]) {
                contentEnd -= 1
            }
        }
    }
    return (UInt8(hashes), i..<contentEnd)
}

private func unescapeString(_ src: String, _ bytes: [UInt8], _ range: Range<Int>) -> String {
    var out = ""
    var i = range.lowerBound
    while i < range.upperBound {
        if bytes[i] == 0x5C, i + 1 < range.upperBound, isAsciiPunct(bytes[i + 1]) {
            out.append(Character(UnicodeScalar(bytes[i + 1])))
            i += 2
        } else if bytes[i] == 0x26, let (decoded, afterAmp) = decodeHtmlEntity(bytes, i, range.upperBound) {
            out.append(decoded)
            i = afterAmp
        } else {
            let start = i
            i += 1
            while i < range.upperBound && bytes[i] != 0x5C && bytes[i] != 0x26 {
                i += 1
            }
            if let chunk = sliceUtf8(src, start..<i) {
                out.append(chunk)
            }
        }
    }
    return out
}

private func matchCodeFence(
    _ src: String,
    _ bytes: [UInt8],
    _ pos: Int,
    _ end: Int,
    _ indent: Int
) -> (UInt8, Int, Int, String)? {
    guard pos < end else { return nil }
    let ch = bytes[pos]
    guard ch == 0x60 || ch == 0x7E else { return nil }
    var i = pos
    while i < end && bytes[i] == ch {
        i += 1
    }
    let len = i - pos
    guard len >= 3 else { return nil }
    if ch == 0x60 {
        for k in i..<end where bytes[k] == 0x60 {
            return nil
        }
    }
    var infoStart = i
    var infoEnd = end
    while infoStart < infoEnd && isAsciiSpaceOrTab(bytes[infoStart]) {
        infoStart += 1
    }
    while infoEnd > infoStart && isAsciiSpaceOrTab(bytes[infoEnd - 1]) {
        infoEnd -= 1
    }
    let info = unescapeString(src, bytes, infoStart..<infoEnd)
    return (ch, len, indent, info)
}

private func isClosingCodeFence(_ bytes: [UInt8], _ pos: Int, _ end: Int, _ ch: UInt8, _ minLen: Int) -> Bool {
    var i = pos
    while i < end && bytes[i] == ch {
        i += 1
    }
    guard i - pos >= minLen else { return false }
    while i < end && isAsciiSpaceOrTab(bytes[i]) {
        i += 1
    }
    return i == end
}

private let HTML_BLOCK_TYPE1_TAGS: Set<String> = ["pre", "script", "style", "textarea"]
private let HTML_BLOCK_TYPE6_TAGS: Set<String> = [
    "address", "article", "aside", "base", "basefont", "blockquote", "body", "caption", "center",
    "col", "colgroup", "dd", "details", "dialog", "dir", "div", "dl", "dt", "fieldset", "figcaption",
    "figure", "footer", "form", "frame", "frameset", "h1", "h2", "h3", "h4", "h5", "h6", "head",
    "header", "hr", "html", "iframe", "legend", "li", "link", "main", "menu", "menuitem", "nav",
    "noframes", "ol", "optgroup", "option", "p", "param", "search", "section", "summary", "table",
    "tbody", "td", "tfoot", "th", "thead", "title", "tr", "track", "ul",
]

private func matchHtmlBlockStart(_ bytes: [UInt8], _ pos: Int, _ end: Int, _ inParagraph: Bool) -> Int? {
    guard pos + 1 < end && bytes[pos] == 0x3C else { return nil }
    let next = bytes[pos + 1]
    if next == 0x21 {
        if pos + 3 < end && bytes[pos + 2] == 0x2D && bytes[pos + 3] == 0x2D {
            return 2
        }
        if pos + 2 < end && isAsciiAlpha(bytes[pos + 2]) {
            return 4
        }
        if pos + 8 < end,
           bytes[pos + 2] == 0x5B,
           bytes[pos + 3] == 0x43,
           bytes[pos + 4] == 0x44,
           bytes[pos + 5] == 0x41,
           bytes[pos + 6] == 0x54,
           bytes[pos + 7] == 0x41,
           bytes[pos + 8] == 0x5B
        {
            return 5
        }
        return nil
    }
    if next == 0x3F {
        return 3
    }
    var i = pos + 1
    let isClose = bytes[i] == 0x2F
    if isClose {
        i += 1
    }
    guard i < end && isAsciiAlpha(bytes[i]) else { return nil }
    let nameStart = i
    while i < end && (isAsciiAlnum(bytes[i]) || bytes[i] == 0x2D) {
        i += 1
    }
    let tagName = String(bytes[nameStart..<i].map { Character(UnicodeScalar(asciiLower($0))) })
    if !isClose && HTML_BLOCK_TYPE1_TAGS.contains(tagName) {
        if i == end || isAsciiSpaceOrTab(bytes[i]) || bytes[i] == 0x3E {
            return 1
        }
    }
    if HTML_BLOCK_TYPE6_TAGS.contains(tagName) {
        if i == end || isAsciiSpaceOrTab(bytes[i]) || bytes[i] == 0x3E || (bytes[i] == 0x2F && i + 1 < end && bytes[i + 1] == 0x3E) {
            return 6
        }
    }
    if !inParagraph, let tagEnd = scanCompleteHtmlTag(bytes, pos, end) {
        var trail = tagEnd
        while trail < end && isAsciiSpaceOrTab(bytes[trail]) {
            trail += 1
        }
        if trail == end {
            return 7
        }
    }
    return nil
}

private func htmlBlockEndsOnLine(_ bytes: [UInt8], _ start: Int, _ end: Int, _ htmlType: Int) -> Bool {
    guard start <= end else { return false }
    switch htmlType {
    case 1:
        let lower = bytes[start..<end].map(asciiLower)
        for needle in ["</pre>", "</script>", "</style>", "</textarea>"] {
            let pat = Array(needle.utf8)
            if lower.count >= pat.count {
                for idx in 0...(lower.count - pat.count) where Array(lower[idx..<(idx + pat.count)]) == pat {
                    return true
                }
            }
        }
        return false
    case 2:
        guard end - start >= 3 else { return false }
        for i in start...(end - 3) where bytes[i] == 0x2D && bytes[i + 1] == 0x2D && bytes[i + 2] == 0x3E {
            return true
        }
        return false
    case 3:
        guard end - start >= 2 else { return false }
        for i in start...(end - 2) where bytes[i] == 0x3F && bytes[i + 1] == 0x3E {
            return true
        }
        return false
    case 4:
        for i in start..<end where bytes[i] == 0x3E {
            return true
        }
        return false
    case 5:
        guard end - start >= 3 else { return false }
        for i in start...(end - 3) where bytes[i] == 0x5D && bytes[i + 1] == 0x5D && bytes[i + 2] == 0x3E {
            return true
        }
        return false
    default:
        return false
    }
}

private func scanCompleteHtmlTag(_ bytes: [UInt8], _ pos: Int, _ limit: Int) -> Int? {
    guard pos + 2 < limit && bytes[pos] == 0x3C else { return nil }
    var i = pos + 1
    let closing = bytes[i] == 0x2F
    if closing {
        i += 1
    }
    guard i < limit && isAsciiAlpha(bytes[i]) else { return nil }
    i += 1
    while i < limit && (isAsciiAlnum(bytes[i]) || bytes[i] == 0x2D) {
        i += 1
    }
    if closing {
        while i < limit && isAsciiSpaceOrTab(bytes[i]) {
            i += 1
        }
        return (i < limit && bytes[i] == 0x3E) ? (i + 1) : nil
    }
    while i < limit {
        var ws = 0
        while i < limit && isAsciiSpaceOrTab(bytes[i]) {
            ws += 1
            i += 1
        }
        if i < limit && bytes[i] == 0x3E {
            return i + 1
        }
        if i + 1 < limit && bytes[i] == 0x2F && bytes[i + 1] == 0x3E {
            return i + 2
        }
        guard ws > 0 && i < limit else { return nil }
        let b = bytes[i]
        guard isAsciiAlpha(b) || b == 0x5F || b == 0x3A else { return nil }
        i += 1
        while i < limit {
            let c = bytes[i]
            if isAsciiAlnum(c) || c == 0x5F || c == 0x2E || c == 0x3A || c == 0x2D {
                i += 1
            } else {
                break
            }
        }
        let saved = i
        while i < limit && isAsciiSpaceOrTab(bytes[i]) {
            i += 1
        }
        if i < limit && bytes[i] == 0x3D {
            i += 1
            while i < limit && isAsciiSpaceOrTab(bytes[i]) {
                i += 1
            }
            guard i < limit else { return nil }
            let q = bytes[i]
            if q == 0x22 || q == 0x27 {
                i += 1
                while i < limit && bytes[i] != q {
                    i += 1
                }
                guard i < limit else { return nil }
                i += 1
            } else {
                var valLen = 0
                while i < limit {
                    let vc = bytes[i]
                    if isAsciiSpaceOrTab(vc) || vc == 0x22 || vc == 0x27 || vc == 0x3D || vc == 0x3C || vc == 0x3E || vc == 0x60 {
                        break
                    }
                    valLen += 1
                    i += 1
                }
                guard valLen > 0 else { return nil }
            }
        } else {
            i = saved
        }
    }
    return nil
}

private struct ListMarkerMatch {
    var kind: ListKind
    var startNum: UInt64?
    var markerByteStart: Int
    var paddingCols: Int
    var consumeColsAfterMarker: Int
    var markerByteLen: Int
    var isEmptyItem: Bool
}

private func matchListMarker(
    _ bytes: [UInt8],
    _ cursor: LineCursor,
    _ indentCols: Int,
    _ markerPos: Int,
    _ markerCol: Int,
    _ inParagraph: Bool
) -> ListMarkerMatch? {
    guard markerPos < cursor.lineEnd else { return nil }
    let b = bytes[markerPos]
    let kind: ListKind
    let startNum: UInt64?
    let markerLen: Int
    if b == 0x2D || b == 0x2B || b == 0x2A {
        kind = .bullet(b)
        startNum = nil
        markerLen = 1
    } else if b >= 0x30 && b <= 0x39 {
        var p = markerPos
        var digits = 0
        var value: UInt64 = 0
        while p < cursor.lineEnd && bytes[p] >= 0x30 && bytes[p] <= 0x39 && digits < 10 {
            value = value * 10 + UInt64(bytes[p] - 0x30)
            p += 1
            digits += 1
        }
        guard digits >= 1 && digits <= 9 && p < cursor.lineEnd else { return nil }
        let delim = bytes[p]
        guard delim == 0x2E || delim == 0x29 else { return nil }
        kind = .ordered(delim)
        startNum = value
        markerLen = digits + 1
    } else {
        return nil
    }

    let afterMarkerPos = markerPos + markerLen
    let afterMarkerCol = markerCol + markerLen
    if afterMarkerPos < cursor.lineEnd && !isAsciiSpaceOrTab(bytes[afterMarkerPos]) {
        return nil
    }
    var afterCursor = LineCursor(
        pos: afterMarkerPos,
        lineEnd: cursor.lineEnd,
        lineFullEnd: cursor.lineFullEnd,
        col: afterMarkerCol,
        tabSpaces: 0
    )
    let (spacesAfter, contentPos, _) = afterCursor.peekIndent(bytes)
    let isEmpty = contentPos >= cursor.lineEnd
    if inParagraph {
        if isEmpty {
            return nil
        }
        if let num = startNum, num != 1 {
            return nil
        }
    }
    let spacesConsumed: Int
    if isEmpty {
        spacesConsumed = min(spacesAfter, 1)
    } else if spacesAfter >= 1 && spacesAfter <= 4 {
        spacesConsumed = spacesAfter
    } else {
        spacesConsumed = 1
    }
    let padding = indentCols + markerLen + spacesConsumed
    afterCursor.advanceCols(bytes, spacesConsumed)
    return ListMarkerMatch(
        kind: kind,
        startNum: startNum,
        markerByteStart: markerPos,
        paddingCols: padding,
        consumeColsAfterMarker: spacesConsumed,
        markerByteLen: markerLen,
        isEmptyItem: isEmpty
    )
}

// MARK: - Link Reference Definitions & GFM Table Detection

private func normalizeLinkLabel(_ raw: String) -> String {
    var out = ""
    var inSpace = false
    for scalar in raw.unicodeScalars {
        if scalar.properties.isWhitespace {
            if !out.isEmpty {
                inSpace = true
            }
        } else {
            if inSpace {
                out.append(" ")
                inSpace = false
            }
            if scalar == "ẞ" {
                out.append("ß")
            } else {
                for folded in String(scalar).lowercased().unicodeScalars {
                    out.unicodeScalars.append(folded == "ς" ? "σ" : folded)
                }
            }
        }
    }
    return out
}

/// Consumes leading `[label]: url "title"` link reference definitions from `paraLines`.
private func consumeLinkRefDefs(
    _ src: String,
    _ bytes: [UInt8],
    _ paraLines: inout [ParaLine],
    _ defs: inout [String: String]
) {
    while !paraLines.isEmpty {
        var joinedBytes: [UInt8] = []
        var lineMap: [(joinedEnd: Int, lineIdx: Int)] = []
        for (idx, pl) in paraLines.enumerated() {
            if pl.start < pl.contentEnd {
                joinedBytes.append(contentsOf: bytes[pl.start..<pl.contentEnd])
            }
            if idx + 1 < paraLines.count {
                joinedBytes.append(0x0A)
            }
            lineMap.append((joinedBytes.count, idx))
        }
        guard let (label, url, consumedBytes) = parseOneLinkRefDef(src, joinedBytes) else {
            break
        }
        let norm = normalizeLinkLabel(label)
        if !norm.isEmpty && defs[norm] == nil {
            defs[norm] = url
        }
        var dropCount = paraLines.count
        for entry in lineMap where entry.joinedEnd >= consumedBytes {
            dropCount = entry.lineIdx + 1
            break
        }
        paraLines.removeFirst(min(dropCount, paraLines.count))
    }
}

private func parseOneLinkRefDef(_ src: String, _ jb: [UInt8]) -> (String, String, Int)? {
    var i = 0
    var spaces = 0
    while i < jb.count && jb[i] == 0x20 && spaces < 4 {
        i += 1
        spaces += 1
    }
    guard spaces < 4, i < jb.count, jb[i] == 0x5B else { return nil }
    i += 1
    let labelStart = i
    var labelChars = 0
    var hasNonWs = false
    while i < jb.count && jb[i] != 0x5D {
        if jb[i] == 0x5B {
            return nil
        }
        if jb[i] == 0x5C && i + 1 < jb.count {
            hasNonWs = true
            i += 2
            labelChars += 2
            continue
        }
        if !isAsciiSpaceOrTab(jb[i]) && jb[i] != 0x0A {
            hasNonWs = true
        }
        i += 1
        labelChars += 1
        if labelChars > 999 {
            return nil
        }
    }
    guard hasNonWs, i + 1 < jb.count, jb[i] == 0x5D, jb[i + 1] == 0x3A else { return nil }
    let labelStr = String(decoding: jb[labelStart..<i], as: UTF8.self)
    i += 2
    var sawNewline = false
    while i < jb.count {
        if isAsciiSpaceOrTab(jb[i]) {
            i += 1
        } else if jb[i] == 0x0A && !sawNewline {
            sawNewline = true
            i += 1
        } else {
            break
        }
    }
    guard i < jb.count else { return nil }
    let destRaw: [UInt8]
    if jb[i] == 0x3C {
        i += 1
        let dStart = i
        while i < jb.count && jb[i] != 0x3E && jb[i] != 0x0A {
            if jb[i] == 0x5C && i + 1 < jb.count {
                i += 2
            } else {
                i += 1
            }
        }
        guard i < jb.count && jb[i] == 0x3E else { return nil }
        destRaw = Array(jb[dStart..<i])
        i += 1
    } else {
        let dStart = i
        var parens = 0
        while i < jb.count {
            let b = jb[i]
            if b <= 0x20 || b == 0x7F {
                break
            }
            if b == 0x5C && i + 1 < jb.count {
                i += 2
                continue
            }
            if b == 0x28 {
                parens += 1
                if parens > 32 { return nil }
            } else if b == 0x29 {
                if parens == 0 { return nil }
                parens -= 1
            }
            i += 1
        }
        guard i > dStart && parens == 0 else { return nil }
        destRaw = Array(jb[dStart..<i])
    }

    let afterDest = i
    var wsCount = 0
    var nlBeforeTitle = false
    while i < jb.count {
        if isAsciiSpaceOrTab(jb[i]) {
            wsCount += 1
            i += 1
        } else if jb[i] == 0x0A && !nlBeforeTitle {
            nlBeforeTitle = true
            wsCount += 1
            i += 1
        } else {
            break
        }
    }

    var endAfterDest: Int? = nil
    var p = afterDest
    while p < jb.count && isAsciiSpaceOrTab(jb[p]) {
        p += 1
    }
    if p == jb.count {
        endAfterDest = p
    } else if jb[p] == 0x0A {
        endAfterDest = p + 1
    }

    if wsCount > 0 && i < jb.count && (jb[i] == 0x22 || jb[i] == 0x27 || jb[i] == 0x28) {
        let openQ = jb[i]
        let closeQ: UInt8 = openQ == 0x28 ? 0x29 : openQ
        i += 1
        var validTitle = true
        while i < jb.count && jb[i] != closeQ {
            if openQ == 0x28 && jb[i] == 0x28 {
                validTitle = false
                break
            }
            if jb[i] == 0x5C && i + 1 < jb.count {
                i += 2
            } else {
                i += 1
            }
        }
        if validTitle && i < jb.count && jb[i] == closeQ {
            i += 1
            while i < jb.count && isAsciiSpaceOrTab(jb[i]) {
                i += 1
            }
            if i == jb.count {
                let destStr = unescapeDestBytes(destRaw)
                return (labelStr, destStr, i)
            } else if jb[i] == 0x0A {
                let destStr = unescapeDestBytes(destRaw)
                return (labelStr, destStr, i + 1)
            }
        }
    }

    if let endPos = endAfterDest {
        let destStr = unescapeDestBytes(destRaw)
        return (labelStr, destStr, endPos)
    }
    return nil
}

private func unescapeDestBytes(_ raw: [UInt8]) -> String {
    let s = String(decoding: raw, as: UTF8.self)
    return unescapeString(s, raw, 0..<raw.count)
}

private func splitGfmTableCells(_ bytes: [UInt8], _ range: Range<Int>) -> [Range<Int>] {
    var start = range.lowerBound
    let end = range.upperBound
    while start < end && isAsciiSpaceOrTab(bytes[start]) {
        start += 1
    }
    var trimmedEnd = end
    while trimmedEnd > start && isAsciiSpaceOrTab(bytes[trimmedEnd - 1]) {
        trimmedEnd -= 1
    }
    guard start < trimmedEnd else { return [] }
    if bytes[start] == 0x7C {
        start += 1
    }
    var rawCells: [Range<Int>] = []
    var cellStart = start
    var i = start
    var trailingPipe = false
    while i < trimmedEnd {
        if bytes[i] == 0x5C && i + 1 < trimmedEnd && bytes[i + 1] == 0x7C {
            i += 2
            continue
        }
        if bytes[i] == 0x7C {
            rawCells.append(cellStart..<i)
            cellStart = i + 1
            if i + 1 == trimmedEnd {
                trailingPipe = true
            }
        }
        i += 1
    }
    if !trailingPipe {
        rawCells.append(cellStart..<trimmedEnd)
    }
    return rawCells.map { r in
        var lo = r.lowerBound
        var hi = r.upperBound
        while lo < hi && isAsciiSpaceOrTab(bytes[lo]) {
            lo += 1
        }
        while hi > lo && isAsciiSpaceOrTab(bytes[hi - 1]) {
            hi -= 1
        }
        return lo..<hi
    }
}

private func parseGfmDelimiterRow(_ bytes: [UInt8], _ headRange: Range<Int>, _ delimRange: Range<Int>) -> [Align]? {
    var hasPipe = false
    for i in headRange where bytes[i] == 0x7C {
        if i == headRange.lowerBound || bytes[i - 1] != 0x5C {
            hasPipe = true
            break
        }
    }
    if !hasPipe {
        for i in delimRange where bytes[i] == 0x7C {
            hasPipe = true
            break
        }
    }
    guard hasPipe else { return nil }
    let headCells = splitGfmTableCells(bytes, headRange)
    let delimCells = splitGfmTableCells(bytes, delimRange)
    guard !headCells.isEmpty && headCells.count == delimCells.count else { return nil }
    var aligns: [Align] = []
    aligns.reserveCapacity(delimCells.count)
    for cell in delimCells {
        guard !cell.isEmpty else { return nil }
        var p = cell.lowerBound
        let left = bytes[p] == 0x3A
        if left { p += 1 }
        var dashes = 0
        while p < cell.upperBound && bytes[p] == 0x2D {
            dashes += 1
            p += 1
        }
        guard dashes >= 1 else { return nil }
        var right = false
        if p < cell.upperBound && bytes[p] == 0x3A {
            right = true
            p += 1
        }
        guard p == cell.upperBound else { return nil }
        if left && right {
            aligns.append(.center)
        } else if right {
            aligns.append(.end)
        } else {
            aligns.append(.start)
        }
    }
    return aligns
}

// MARK: - Pass 1: Block Tree Construction

private func finalizeParagraphIntoParent(
    _ src: String,
    _ bytes: [UInt8],
    _ paraNode: BlockNode,
    _ parent: BlockNode,
    _ linkDefs: inout [String: String]
) {
    guard case var .paragraph(lines) = paraNode.kind else {
        parent.children.append(paraNode)
        return
    }
    consumeLinkRefDefs(src, bytes, &lines, &linkDefs)
    guard !lines.isEmpty else { return }

    var idx = 0
    while idx < lines.count {
        if idx + 1 < lines.count,
           let aligns = parseGfmDelimiterRow(
               bytes,
               lines[idx].start..<lines[idx].contentEnd,
               lines[idx + 1].start..<lines[idx + 1].contentEnd
           )
        {
            if idx > 0 {
                let prefix = Array(lines[0..<idx])
                parent.children.append(BlockNode(
                    kind: .paragraph(prefix),
                    startByte: prefix[0].start,
                    endByte: prefix[prefix.count - 1].fullEnd
                ))
            }
            let headLine = lines[idx]
            let bodyLines = idx + 2 < lines.count ? Array(lines[(idx + 2)...]) : []
            let tableEnd = bodyLines.last?.fullEnd ?? lines[idx + 1].fullEnd
            parent.children.append(BlockNode(
                kind: .table(aligns: aligns, headLine: headLine, bodyLines: bodyLines),
                startByte: headLine.start,
                endByte: tableEnd
            ))
            return
        }
        idx += 1
    }

    parent.children.append(BlockNode(
        kind: .paragraph(lines),
        startByte: lines[0].start,
        endByte: lines[lines.count - 1].fullEnd
    ))
}

private func closeOpenBlocksDownTo(
    _ src: String,
    _ bytes: [UInt8],
    _ openStack: inout [BlockNode],
    _ targetCount: Int,
    _ endByte: Int,
    _ linkDefs: inout [String: String]
) {
    while openStack.count > targetCount {
        let node = openStack.removeLast()
        node.endByte = max(node.endByte, endByte)
        let parent = openStack[openStack.count - 1]
        if case .paragraph = node.kind {
            finalizeParagraphIntoParent(src, bytes, node, parent, &linkDefs)
        } else {
            parent.children.append(node)
        }
    }
}

private func buildBlockTree(_ src: String, _ bytes: [UInt8]) -> (BlockNode, [String: String]) {
    let rawLines = scanLines(bytes)
    let root = BlockNode(kind: .document, startByte: 0, endByte: bytes.count)
    var openStack: [BlockNode] = [root]
    var linkDefs: [String: String] = [:]

    for rawLine in rawLines {
        var cursor = LineCursor(
            pos: rawLine.start,
            lineEnd: rawLine.contentEnd,
            lineFullEnd: rawLine.end,
            col: 0,
            tabSpaces: 0
        )

        var matched = 1
        while matched < openStack.count {
            let node = openStack[matched]
            switch node.kind {
            case .blockQuote:
                let (indent, nextPos, _) = cursor.peekIndent(bytes)
                if indent < 4 && nextPos < cursor.lineEnd && bytes[nextPos] == 0x3E {
                    cursor.advanceCols(bytes, indent)
                    cursor.pos += 1
                    cursor.col += 1
                    if cursor.pos < cursor.lineEnd && isAsciiSpaceOrTab(bytes[cursor.pos]) {
                        cursor.advanceCols(bytes, 1)
                    }
                    matched += 1
                } else {
                    break
                }

            case let .listItem(padding, emptyFirstLine, sawBlankAfterFirst):
                if cursor.isBlank(bytes) {
                    if emptyFirstLine && node.children.isEmpty && matched == openStack.count - 1 {
                        if sawBlankAfterFirst {
                            break
                        }
                        node.kind = .listItem(padding: padding, emptyFirstLine: true, sawBlankAfterFirst: true)
                    }
                    let (indent, _, _) = cursor.peekIndent(bytes)
                    cursor.advanceCols(bytes, min(indent, padding))
                    matched += 1
                } else {
                    let (indent, _, _) = cursor.peekIndent(bytes)
                    if indent >= padding {
                        cursor.advanceCols(bytes, padding)
                        if emptyFirstLine {
                            node.kind = .listItem(padding: padding, emptyFirstLine: false, sawBlankAfterFirst: false)
                        }
                        matched += 1
                    } else {
                        break
                    }
                }

            case .list:
                matched += 1

            default:
                break
            }
            if matched <= openStack.indices.last! && openStack[matched] === node {
                break
            }
        }

        let deepest = openStack[openStack.count - 1]
        let deepestIsLeaf: Bool = {
            switch deepest.kind {
            case .paragraph, .fencedCode, .indentedCode, .htmlBlock:
                return true
            default:
                return false
            }
        }()
        let allMatched = (matched == openStack.count) || (deepestIsLeaf && matched == openStack.count - 1)

        // Handle open fenced code, indented code, or HTML block if matched up to its parent.
        if allMatched {
            switch deepest.kind {
            case let .fencedCode(fenceChar, fenceLen, fenceIndent, info, _, codeLines):
                let (indent, nextPos, _) = cursor.peekIndent(bytes)
                if indent < 4 && isClosingCodeFence(bytes, nextPos, cursor.lineEnd, fenceChar, fenceLen) {
                    deepest.kind = .fencedCode(
                        fenceChar: fenceChar,
                        fenceLen: fenceLen,
                        fenceIndent: fenceIndent,
                        info: info,
                        closed: true,
                        lines: codeLines
                    )
                    deepest.endByte = rawLine.end
                    closeOpenBlocksDownTo(src, bytes, &openStack, openStack.count - 1, rawLine.end, &linkDefs)
                } else {
                    cursor.advanceCols(bytes, min(indent, fenceIndent))
                    var updated = codeLines
                    updated.append(CodeLine(
                        virtualSpaces: cursor.tabSpaces,
                        start: cursor.pos,
                        contentEnd: rawLine.contentEnd,
                        fullEnd: rawLine.end
                    ))
                    deepest.kind = .fencedCode(
                        fenceChar: fenceChar,
                        fenceLen: fenceLen,
                        fenceIndent: fenceIndent,
                        info: info,
                        closed: false,
                        lines: updated
                    )
                    deepest.endByte = rawLine.end
                }
                continue

            case let .indentedCode(codeLines, pendingBlanks):
                let (indent, _, _) = cursor.peekIndent(bytes)
                if indent >= 4 {
                    cursor.advanceCols(bytes, 4)
                    var updated = codeLines
                    updated.append(contentsOf: pendingBlanks)
                    updated.append(CodeLine(
                        virtualSpaces: cursor.tabSpaces,
                        start: cursor.pos,
                        contentEnd: rawLine.contentEnd,
                        fullEnd: rawLine.end
                    ))
                    deepest.kind = .indentedCode(lines: updated, pendingBlanks: [])
                    deepest.endByte = rawLine.end
                    continue
                } else if cursor.isBlank(bytes) {
                    cursor.advanceCols(bytes, min(indent, 4))
                    var blanks = pendingBlanks
                    blanks.append(CodeLine(
                        virtualSpaces: cursor.tabSpaces,
                        start: cursor.pos,
                        contentEnd: rawLine.contentEnd,
                        fullEnd: rawLine.end
                    ))
                    deepest.kind = .indentedCode(lines: codeLines, pendingBlanks: blanks)
                    continue
                } else {
                    closeOpenBlocksDownTo(src, bytes, &openStack, openStack.count - 1, rawLine.start, &linkDefs)
                }

            case let .htmlBlock(htmlType, _):
                if (htmlType == 6 || htmlType == 7) && cursor.isBlank(bytes) {
                    closeOpenBlocksDownTo(src, bytes, &openStack, openStack.count - 1, rawLine.start, &linkDefs)
                    continue
                }
                deepest.endByte = rawLine.end
                if htmlType >= 1 && htmlType <= 5 && htmlBlockEndsOnLine(bytes, cursor.pos, cursor.lineEnd, htmlType) {
                    deepest.kind = .htmlBlock(htmlType: htmlType, closed: true)
                    closeOpenBlocksDownTo(src, bytes, &openStack, openStack.count - 1, rawLine.end, &linkDefs)
                }
                continue

            default:
                break
            }
        }

        // Check Setext heading underline when all containers matched and deepest block is a Paragraph.
        if allMatched, case var .paragraph(pLines) = openStack[openStack.count - 1].kind {
            let (indent, nextPos, _) = cursor.peekIndent(bytes)
            if indent < 4, let setextLevel = matchSetextUnderline(bytes, nextPos, cursor.lineEnd) {
                consumeLinkRefDefs(src, bytes, &pLines, &linkDefs)
                if !pLines.isEmpty {
                    let paraNode = openStack.removeLast()
                    // Convert paragraph lines into a Setext heading node!
                    // Multi-line Setext headings join lines via soft breaks just like paragraphs,
                    // so keep the heading's full range or wrap as heading over paragraph lines.
                    let headStart = pLines[0].start
                    let headEnd = pLines[pLines.count - 1].contentEnd
                    let parent = openStack[openStack.count - 1]
                    let hNode = BlockNode(
                        kind: .heading(level: setextLevel, slice: headStart..<headEnd),
                        startByte: paraNode.startByte,
                        endByte: rawLine.end
                    )
                    // Store original lines as child paragraph if multi-line so container prefixes are stripped.
                    if pLines.count > 1 {
                        hNode.children.append(BlockNode(
                            kind: .paragraph(pLines),
                            startByte: headStart,
                            endByte: headEnd
                        ))
                    }
                    parent.children.append(hNode)
                    continue
                } else {
                    // All lines of the paragraph were link reference definitions! Close empty paragraph
                    // and let `---` fall through (where `---` will match as a thematic break `.rule`).
                    _ = openStack.removeLast()
                }
            }
        }

        // Blank line closes open paragraphs and stops container opening.
        if cursor.isBlank(bytes) {
            closeOpenBlocksDownTo(src, bytes, &openStack, matched, rawLine.start, &linkDefs)
            if case .paragraph = openStack[openStack.count - 1].kind {
                closeOpenBlocksDownTo(src, bytes, &openStack, openStack.count - 1, rawLine.start, &linkDefs)
            }
            continue
        }

        let wasLazyParagraphCandidate: Bool = {
            if case .paragraph = openStack[openStack.count - 1].kind {
                return true
            }
            return false
        }()

        // Helper: target stack count when closing unmatched containers for a non-list block.
        // If `openStack[matched - 1]` is `.list` (meaning its `.listItem` did NOT match),
        // non-list blocks close the `.list` too!
        func nonListTarget(_ m: Int) -> Int {
            if m >= 2, case .list = openStack[m - 1].kind {
                return m - 1
            }
            return m
        }

        // Scan block starts starting at `matched`.
        var openedNewBlock = false
        var scanContainers = true
        while scanContainers {
            scanContainers = false
            let (indent, nextPos, nextCol) = cursor.peekIndent(bytes)
            let inPara: Bool = {
                if matched < openStack.count, case .list = openStack[matched - 1].kind {
                    return false
                }
                if case .paragraph = openStack[openStack.count - 1].kind {
                    return true
                }
                return false
            }()

            if indent >= 4 {
                if !wasLazyParagraphCandidate {
                    closeOpenBlocksDownTo(src, bytes, &openStack, nonListTarget(matched), rawLine.start, &linkDefs)
                    cursor.advanceCols(bytes, 4)
                    let codeNode = BlockNode(
                        kind: .indentedCode(
                            lines: [CodeLine(
                                virtualSpaces: cursor.tabSpaces,
                                start: cursor.pos,
                                contentEnd: rawLine.contentEnd,
                                fullEnd: rawLine.end
                            )],
                            pendingBlanks: []
                        ),
                        startByte: cursor.pos,
                        endByte: rawLine.end
                    )
                    openStack.append(codeNode)
                    cursor.pos = cursor.lineEnd
                    cursor.tabSpaces = 0
                    openedNewBlock = true
                }
                break
            }

            // 1. Block quote `>`
            if nextPos < cursor.lineEnd && bytes[nextPos] == 0x3E {
                closeOpenBlocksDownTo(src, bytes, &openStack, nonListTarget(matched), rawLine.start, &linkDefs)
                cursor.advanceCols(bytes, indent)
                let bqStart = cursor.pos
                cursor.pos += 1
                cursor.col += 1
                if cursor.pos < cursor.lineEnd && isAsciiSpaceOrTab(bytes[cursor.pos]) {
                    cursor.advanceCols(bytes, 1)
                }
                let bq = BlockNode(kind: .blockQuote, startByte: bqStart, endByte: rawLine.end)
                openStack.append(bq)
                matched = openStack.count
                openedNewBlock = true
                if !cursor.isBlank(bytes) {
                    scanContainers = true
                }
                continue
            }

            // 2. ATX Heading
            if let (level, slice) = matchAtxHeading(bytes, nextPos, cursor.lineEnd) {
                closeOpenBlocksDownTo(src, bytes, &openStack, nonListTarget(matched), rawLine.start, &linkDefs)
                let hNode = BlockNode(
                    kind: .heading(level: level, slice: slice),
                    startByte: nextPos,
                    endByte: rawLine.end
                )
                openStack[openStack.count - 1].children.append(hNode)
                cursor.pos = cursor.lineEnd
                cursor.tabSpaces = 0
                openedNewBlock = true
                break
            }

            // 3. Fenced Code Block
            if let (fenceChar, fenceLen, fenceIndent, info) = matchCodeFence(src, bytes, nextPos, cursor.lineEnd, indent) {
                closeOpenBlocksDownTo(src, bytes, &openStack, nonListTarget(matched), rawLine.start, &linkDefs)
                let fNode = BlockNode(
                    kind: .fencedCode(
                        fenceChar: fenceChar,
                        fenceLen: fenceLen,
                        fenceIndent: fenceIndent,
                        info: info,
                        closed: false,
                        lines: []
                    ),
                    startByte: nextPos,
                    endByte: rawLine.end
                )
                openStack.append(fNode)
                cursor.pos = cursor.lineEnd
                cursor.tabSpaces = 0
                openedNewBlock = true
                break
            }

            // 4. HTML Block
            if let htmlType = matchHtmlBlockStart(bytes, nextPos, cursor.lineEnd, inPara) {
                closeOpenBlocksDownTo(src, bytes, &openStack, nonListTarget(matched), rawLine.start, &linkDefs)
                let endsNow = htmlType >= 1 && htmlType <= 5 && htmlBlockEndsOnLine(bytes, nextPos, cursor.lineEnd, htmlType)
                let htmlNode = BlockNode(
                    kind: .htmlBlock(htmlType: htmlType, closed: endsNow),
                    startByte: nextPos,
                    endByte: rawLine.end
                )
                if endsNow {
                    openStack[openStack.count - 1].children.append(htmlNode)
                } else {
                    openStack.append(htmlNode)
                }
                cursor.pos = cursor.lineEnd
                cursor.tabSpaces = 0
                openedNewBlock = true
                break
            }

            // 5. Thematic Break
            if matchThematicBreak(bytes, nextPos, cursor.lineEnd) {
                closeOpenBlocksDownTo(src, bytes, &openStack, nonListTarget(matched), rawLine.start, &linkDefs)
                let rNode = BlockNode(kind: .rule, startByte: nextPos, endByte: rawLine.end)
                openStack[openStack.count - 1].children.append(rNode)
                cursor.pos = cursor.lineEnd
                cursor.tabSpaces = 0
                openedNewBlock = true
                break
            }

            // 6. List Marker
            if let lm = matchListMarker(bytes, cursor, indent, nextPos, nextCol, inPara) {
                closeOpenBlocksDownTo(src, bytes, &openStack, matched, rawLine.start, &linkDefs)
                cursor.advanceCols(bytes, indent)
                cursor.pos += lm.markerByteLen
                cursor.col += lm.markerByteLen
                cursor.advanceCols(bytes, lm.consumeColsAfterMarker)

                // Reuse open `.list` if marker kind matches; otherwise close and open new `.list`.
                if case let .list(existingKind, _) = openStack[openStack.count - 1].kind {
                    if existingKind != lm.kind {
                        closeOpenBlocksDownTo(src, bytes, &openStack, openStack.count - 1, rawLine.start, &linkDefs)
                        let listNode = BlockNode(
                            kind: .list(kind: lm.kind, start: lm.startNum),
                            startByte: lm.markerByteStart,
                            endByte: rawLine.end
                        )
                        openStack.append(listNode)
                    }
                } else {
                    let listNode = BlockNode(
                        kind: .list(kind: lm.kind, start: lm.startNum),
                        startByte: lm.markerByteStart,
                        endByte: rawLine.end
                    )
                    openStack.append(listNode)
                }

                let itemNode = BlockNode(
                    kind: .listItem(padding: lm.paddingCols, emptyFirstLine: lm.isEmptyItem, sawBlankAfterFirst: false),
                    startByte: lm.markerByteStart,
                    endByte: rawLine.end
                )
                openStack.append(itemNode)
                matched = openStack.count
                openedNewBlock = true
                if !lm.isEmptyItem {
                    scanContainers = true
                }
                continue
            }
        }

        if openedNewBlock {
            if !cursor.isBlank(bytes) {
                let top = openStack[openStack.count - 1]
                switch top.kind {
                case .document, .blockQuote, .listItem:
                    let (_, pStart, _) = cursor.peekIndent(bytes)
                    let pLine = ParaLine(start: pStart, contentEnd: rawLine.contentEnd, fullEnd: rawLine.end)
                    openStack.append(BlockNode(
                        kind: .paragraph([pLine]),
                        startByte: pStart,
                        endByte: rawLine.end
                    ))
                default:
                    break
                }
            }
            continue
        }

        // Lazy paragraph continuation vs closing unmatched containers and starting a new paragraph.
        if wasLazyParagraphCandidate {
            let (_, pStart, _) = cursor.peekIndent(bytes)
            let pNode = openStack[openStack.count - 1]
            if case var .paragraph(pLines) = pNode.kind {
                pLines.append(ParaLine(start: pStart, contentEnd: rawLine.contentEnd, fullEnd: rawLine.end))
                pNode.kind = .paragraph(pLines)
                pNode.endByte = rawLine.end
                continue
            }
        }

        closeOpenBlocksDownTo(src, bytes, &openStack, nonListTarget(matched), rawLine.start, &linkDefs)
        let (_, pStart, _) = cursor.peekIndent(bytes)
        if pStart < rawLine.contentEnd {
            if case var .paragraph(pLines) = openStack[openStack.count - 1].kind {
                pLines.append(ParaLine(start: pStart, contentEnd: rawLine.contentEnd, fullEnd: rawLine.end))
                openStack[openStack.count - 1].kind = .paragraph(pLines)
                openStack[openStack.count - 1].endByte = rawLine.end
            } else {
                openStack.append(BlockNode(
                    kind: .paragraph([ParaLine(start: pStart, contentEnd: rawLine.contentEnd, fullEnd: rawLine.end)]),
                    startByte: pStart,
                    endByte: rawLine.end
                ))
            }
        }
    }

    closeOpenBlocksDownTo(src, bytes, &openStack, 1, bytes.count, &linkDefs)
    return (root, linkDefs)
}

// MARK: - Pass 2: Inline Parsing & Event Emission

private func emitMarkdownEvents(_ src: String, _ bytes: [UInt8]) -> [(MdEvent, Range<Int>)] {
    let (root, linkDefs) = buildBlockTree(src, bytes)
    var out: [(MdEvent, Range<Int>)] = []
    emitBlockChildren(src, bytes, root.children, linkDefs, false, &out)
    return out
}

private func emitBlockChildren(
    _ src: String,
    _ bytes: [UInt8],
    _ nodes: [BlockNode],
    _ linkDefs: [String: String],
    _ inListItemFirstSlot: Bool,
    _ out: inout [(MdEvent, Range<Int>)]
) {
    for (idx, node) in nodes.enumerated() {
        let nodeRange = node.startByte..<node.endByte
        switch node.kind {
        case .document:
            emitBlockChildren(src, bytes, node.children, linkDefs, false, &out)

        case .blockQuote:
            out.append((.startBlockQuote, nodeRange))
            emitBlockChildren(src, bytes, node.children, linkDefs, false, &out)
            out.append((.endBlockQuote, nodeRange))

        case let .list(_, start):
            out.append((.startList(start), nodeRange))
            for item in node.children {
                let itemRange = item.startByte..<item.endByte
                out.append((.startItem, itemRange))
                emitBlockChildren(src, bytes, item.children, linkDefs, true, &out)
                out.append((.endItem, itemRange))
            }
            out.append((.endList, nodeRange))

        case .listItem:
            emitBlockChildren(src, bytes, node.children, linkDefs, true, &out)

        case var .paragraph(lines):
            out.append((.startParagraph, nodeRange))
            if inListItemFirstSlot && idx == 0, !lines.isEmpty {
                let l0 = lines[0]
                if l0.start + 3 <= l0.contentEnd,
                   bytes[l0.start] == 0x5B,
                   (bytes[l0.start + 1] == 0x20 || bytes[l0.start + 1] == 0x78 || bytes[l0.start + 1] == 0x58),
                   bytes[l0.start + 2] == 0x5D,
                   (l0.start + 3 == l0.contentEnd || isAsciiSpaceOrTab(bytes[l0.start + 3]))
                {
                    let checked = bytes[l0.start + 1] != 0x20
                    out.append((.taskListMarker(checked), l0.start..<(l0.start + 3)))
                    var textStart = l0.start + 3
                    if textStart < l0.contentEnd && isAsciiSpaceOrTab(bytes[textStart]) {
                        textStart += 1
                    }
                    if textStart == l0.contentEnd && lines.count > 1 {
                        lines.removeFirst()
                    } else {
                        lines[0].start = textStart
                    }
                }
            }
            emitInlineOverLines(src, bytes, lines, linkDefs, false, &out)
            out.append((.endParagraph, nodeRange))

        case let .heading(level, slice):
            out.append((.startHeading(level), nodeRange))
            if let multi = node.children.first, case let .paragraph(hLines) = multi.kind {
                emitInlineOverLines(src, bytes, hLines, linkDefs, false, &out)
            } else {
                let hLine = ParaLine(start: slice.lowerBound, contentEnd: slice.upperBound, fullEnd: slice.upperBound)
                emitInlineOverLines(src, bytes, [hLine], linkDefs, false, &out)
            }
            out.append((.endHeading, nodeRange))

        case let .fencedCode(_, _, _, info, _, codeLines):
            out.append((.startCodeBlock(info), nodeRange))
            for cl in codeLines {
                if cl.virtualSpaces > 0 {
                    out.append((.text(String(repeating: " ", count: cl.virtualSpaces)), cl.start..<cl.start))
                }
                if cl.start < cl.contentEnd, let chunk = sliceUtf8(src, cl.start..<cl.contentEnd) {
                    out.append((.text(chunk), cl.start..<cl.contentEnd))
                }
                if cl.contentEnd < cl.fullEnd {
                    out.append((.text("\n"), cl.contentEnd..<cl.fullEnd))
                }
            }
            out.append((.endCodeBlock, nodeRange))

        case let .indentedCode(codeLines, _):
            out.append((.startCodeBlock(nil), nodeRange))
            for cl in codeLines {
                if cl.virtualSpaces > 0 {
                    out.append((.text(String(repeating: " ", count: cl.virtualSpaces)), cl.start..<cl.start))
                }
                if cl.start < cl.contentEnd, let chunk = sliceUtf8(src, cl.start..<cl.contentEnd) {
                    out.append((.text(chunk), cl.start..<cl.contentEnd))
                }
                if cl.contentEnd < cl.fullEnd {
                    out.append((.text("\n"), cl.contentEnd..<cl.fullEnd))
                }
            }
            out.append((.endCodeBlock, nodeRange))

        case .htmlBlock:
            out.append((.startHtmlBlock, nodeRange))
            out.append((.endHtmlBlock, nodeRange))

        case .rule:
            out.append((.rule, nodeRange))

        case let .table(aligns, headLine, bodyLines):
            out.append((.startTable(aligns), nodeRange))
            let colCount = aligns.count
            let headRange = headLine.start..<headLine.fullEnd
            out.append((.startTableHead, headRange))
            let headCells = splitGfmTableCells(bytes, headLine.start..<headLine.contentEnd)
            for cIdx in 0..<colCount {
                let cellRange = cIdx < headCells.count ? headCells[cIdx] : (headLine.contentEnd..<headLine.contentEnd)
                out.append((.startTableCell, cellRange))
                if !cellRange.isEmpty {
                    let pl = ParaLine(start: cellRange.lowerBound, contentEnd: cellRange.upperBound, fullEnd: cellRange.upperBound)
                    emitInlineOverLines(src, bytes, [pl], linkDefs, true, &out)
                }
                out.append((.endTableCell, cellRange))
            }
            out.append((.endTableHead, headRange))

            for rowLine in bodyLines {
                let rowRange = rowLine.start..<rowLine.fullEnd
                out.append((.startTableRow, rowRange))
                let rowCells = splitGfmTableCells(bytes, rowLine.start..<rowLine.contentEnd)
                for cIdx in 0..<colCount {
                    let cellRange = cIdx < rowCells.count ? rowCells[cIdx] : (rowLine.contentEnd..<rowLine.contentEnd)
                    out.append((.startTableCell, cellRange))
                    if !cellRange.isEmpty {
                        let pl = ParaLine(start: cellRange.lowerBound, contentEnd: cellRange.upperBound, fullEnd: rowLine.contentEnd)
                        emitInlineOverLines(src, bytes, [pl], linkDefs, true, &out)
                    }
                    out.append((.endTableCell, cellRange))
                }
                out.append((.endTableRow, rowRange))
            }
            out.append((.endTable, nodeRange))
        }
    }
}

// MARK: - Inline Tokenization & Delimiter Resolution (CommonMark §6 + GFM Strikethrough)

private enum InlineItem {
    case text(String, Range<Int>)
    case code(String, Range<Int>)
    case softBreak(Range<Int>)
    case hardBreak(Range<Int>)
    case html(Range<Int>)
    case delim(ch: UInt8, origCount: Int, count: Int, canOpen: Bool, canClose: Bool, srcStart: Int)
    case openBracket(isImage: Bool, srcStart: Int)
    case startSpan(MdEvent, Range<Int>)
    case endSpan(MdEvent, Range<Int>)
}

private struct BracketEntry {
    var itemIdx: Int
    var isImage: Bool
    var srcStart: Int
    var active: Bool
    var delimBottom: Int
}

private func emitInlineOverLines(
    _ src: String,
    _ bytes: [UInt8],
    _ lines: [ParaLine],
    _ linkDefs: [String: String],
    _ inTableCell: Bool,
    _ out: inout [(MdEvent, Range<Int>)]
) {
    guard !lines.isEmpty else { return }

    // Build flattened inline buffer with source byte mapping so multi-line constructs (links,
    // emphasis, code spans) work across soft breaks while preserving exact `src` byte offsets.
    var buf: [UInt8] = []
    var srcOffs: [Int] = []
    var lineBreakInfos: [Int: (isHard: Bool, range: Range<Int>)] = [:]

    for (lIdx, pl) in lines.enumerated() {
        var lineStart = pl.start
        var lineEnd = pl.contentEnd
        if lIdx > 0 {
            while lineStart < lineEnd && isAsciiSpaceOrTab(bytes[lineStart]) {
                lineStart += 1
            }
        }
        let isLast = (lIdx + 1 == lines.count)
        var hardRange: Range<Int>? = nil
        var softRange: Range<Int>? = nil

        if !isLast {
            if lineEnd > lineStart && bytes[lineEnd - 1] == 0x5C {
                var backslashes = 0
                var k = lineEnd - 1
                while k >= lineStart && bytes[k] == 0x5C {
                    backslashes += 1
                    if k == lineStart { break }
                    k -= 1
                }
                if backslashes % 2 == 1 {
                    hardRange = (lineEnd - 1)..<pl.fullEnd
                    lineEnd -= 1
                }
            }
            if hardRange == nil {
                var spStart = lineEnd
                while spStart > lineStart && bytes[spStart - 1] == 0x20 {
                    spStart -= 1
                }
                if lineEnd - spStart >= 2 {
                    hardRange = spStart..<pl.fullEnd
                    lineEnd = spStart
                } else {
                    while lineEnd > lineStart && isAsciiSpaceOrTab(bytes[lineEnd - 1]) {
                        lineEnd -= 1
                    }
                    softRange = pl.contentEnd..<pl.fullEnd
                }
            }
        }

        if lineStart < lineEnd {
            for pos in lineStart..<lineEnd {
                buf.append(bytes[pos])
                srcOffs.append(pos)
            }
        }
        if let hr = hardRange {
            let idx = buf.count
            buf.append(0x0A)
            srcOffs.append(hr.lowerBound)
            lineBreakInfos[idx] = (true, hr)
        } else if let sr = softRange {
            let idx = buf.count
            buf.append(0x0A)
            srcOffs.append(sr.lowerBound)
            lineBreakInfos[idx] = (false, sr)
        }
    }

    guard !buf.isEmpty else { return }
    let bufStr = String(decoding: buf, as: UTF8.self)
    var items: [InlineItem] = []
    var brackets: [BracketEntry] = []
    var delimCount = 0

    func srcRange(_ bStart: Int, _ bEnd: Int) -> Range<Int> {
        guard bStart < bEnd, bStart < srcOffs.count else {
            let p = bStart < srcOffs.count ? srcOffs[bStart] : (srcOffs.last.map { $0 + 1 } ?? 0)
            return p..<p
        }
        let lo = srcOffs[bStart]
        let hi = srcOffs[bEnd - 1] + 1
        return lo..<hi
    }

    var i = 0
    while i < buf.count {
        let b = buf[i]
        switch b {
        case 0x0A:
            if let info = lineBreakInfos[i] {
                items.append(info.isHard ? .hardBreak(info.range) : .softBreak(info.range))
            }
            i += 1

        case 0x5C:
            if i + 1 < buf.count && isAsciiPunct(buf[i + 1]) {
                let chStr = String(Character(UnicodeScalar(buf[i + 1])))
                items.append(.text(chStr, srcRange(i + 1, i + 2)))
                i += 2
            } else {
                items.append(.text("\\", srcRange(i, i + 1)))
                i += 1
            }

        case 0x60:
            var tickLen = 0
            while i + tickLen < buf.count && buf[i + tickLen] == 0x60 {
                tickLen += 1
            }
            var search = i + tickLen
            var foundClose: Int? = nil
            while search < buf.count {
                if buf[search] == 0x60 {
                    var cLen = 0
                    while search + cLen < buf.count && buf[search + cLen] == 0x60 {
                        cLen += 1
                    }
                    if cLen == tickLen {
                        foundClose = search
                        break
                    }
                    search += cLen
                } else {
                    search += 1
                }
            }
            if let closeAt = foundClose {
                var rawCodeBytes: [UInt8] = []
                rawCodeBytes.reserveCapacity(closeAt - (i + tickLen))
                var k = i + tickLen
                while k < closeAt {
                    if buf[k] == 0x0A {
                        rawCodeBytes.append(0x20)
                        k += 1
                    } else if inTableCell && buf[k] == 0x5C && k + 1 < closeAt && buf[k + 1] == 0x7C {
                        rawCodeBytes.append(0x7C)
                        k += 2
                    } else {
                        rawCodeBytes.append(buf[k])
                        k += 1
                    }
                }
                var rendered = String(decoding: rawCodeBytes, as: UTF8.self)
                if rendered.utf8.count >= 2,
                   rendered.first == " ",
                   rendered.last == " ",
                   !rendered.unicodeScalars.allSatisfy({ $0 == " " })
                {
                    rendered.removeFirst()
                    rendered.removeLast()
                }
                let fullSrcRange = srcOffs[i]..<(srcOffs[closeAt + tickLen - 1] + 1)
                items.append(.code(rendered, fullSrcRange))
                i = closeAt + tickLen
            } else {
                let ticks = String(repeating: "`", count: tickLen)
                items.append(.text(ticks, srcRange(i, i + tickLen)))
                i += tickLen
            }

        case 0x2A, 0x5F, 0x7E:
            var runLen = 0
            while i + runLen < buf.count && buf[i + runLen] == b {
                runLen += 1
            }
            if b == 0x7E && runLen > 2 {
                let tildes = String(repeating: "~", count: runLen)
                items.append(.text(tildes, srcRange(i, i + runLen)))
                i += runLen
                continue
            }
            let (leftFlank, rightFlank) = computeFlanks(bufStr, i, runLen)
            let canOpen: Bool
            let canClose: Bool
            if b == 0x5F {
                let beforePunct = prevCharIsPunct(bufStr, i)
                let afterPunct = nextCharIsPunct(bufStr, i + runLen)
                canOpen = leftFlank && (!rightFlank || beforePunct)
                canClose = rightFlank && (!leftFlank || afterPunct)
            } else if b == 0x7E {
                canOpen = runLen <= 2 && leftFlank
                canClose = runLen <= 2 && rightFlank
            } else {
                canOpen = leftFlank
                canClose = rightFlank
            }
            if !canOpen && !canClose {
                let raw = String(repeating: String(Character(UnicodeScalar(b))), count: runLen)
                items.append(.text(raw, srcRange(i, i + runLen)))
            } else {
                items.append(.delim(
                    ch: b,
                    origCount: runLen,
                    count: runLen,
                    canOpen: canOpen,
                    canClose: canClose,
                    srcStart: srcOffs[i]
                ))
                delimCount += 1
            }
            i += runLen

        case 0x21:
            if i + 1 < buf.count && buf[i + 1] == 0x5B {
                let itemIdx = items.count
                items.append(.openBracket(isImage: true, srcStart: srcOffs[i]))
                brackets.append(BracketEntry(
                    itemIdx: itemIdx,
                    isImage: true,
                    srcStart: srcOffs[i],
                    active: true,
                    delimBottom: delimCount
                ))
                i += 2
            } else {
                items.append(.text("!", srcRange(i, i + 1)))
                i += 1
            }

        case 0x5B:
            let itemIdx = items.count
            items.append(.openBracket(isImage: false, srcStart: srcOffs[i]))
            brackets.append(BracketEntry(
                itemIdx: itemIdx,
                isImage: false,
                srcStart: srcOffs[i],
                active: true,
                delimBottom: delimCount
            ))
            i += 1

        case 0x5D:
            if let entry = brackets.popLast() {
                if !entry.active {
                    items[entry.itemIdx] = .text(
                        entry.isImage ? "![" : "[",
                        entry.srcStart..<(entry.srcStart + (entry.isImage ? 2 : 1))
                    )
                    items.append(.text("]", srcRange(i, i + 1)))
                    i += 1
                    continue
                }
                if let (destUrl, afterCloseIdx) = matchLinkAfterCloseBracket(src, buf, i, entry.itemIdx, items, linkDefs) {
                    let spanRange = entry.srcStart..<(srcOffs[afterCloseIdx - 1] + 1)
                    processEmphasis(&items, fromItemIdx: entry.itemIdx + 1)
                    if entry.isImage {
                        items[entry.itemIdx] = .startSpan(.startImage, spanRange)
                        items.append(.endSpan(.endImage, spanRange))
                    } else {
                        items[entry.itemIdx] = .startSpan(.startLink(destUrl), spanRange)
                        items.append(.endSpan(.endLink, spanRange))
                        for bIdx in brackets.indices where !brackets[bIdx].isImage {
                            brackets[bIdx].active = false
                        }
                    }
                    i = afterCloseIdx
                    continue
                } else {
                    items[entry.itemIdx] = .text(
                        entry.isImage ? "![" : "[",
                        entry.srcStart..<(entry.srcStart + (entry.isImage ? 2 : 1))
                    )
                    items.append(.text("]", srcRange(i, i + 1)))
                    i += 1
                    continue
                }
            } else {
                items.append(.text("]", srcRange(i, i + 1)))
                i += 1
            }

        case 0x3C:
            if let (url, display, endIdx) = matchAngleAutolink(buf, i) {
                let linkRange = srcRange(i, endIdx)
                let innerRange = srcRange(i + 1, endIdx - 1)
                items.append(.startSpan(.startLink(url), linkRange))
                items.append(.text(display, innerRange))
                items.append(.endSpan(.endLink, linkRange))
                i = endIdx
            } else if let htmlEnd = matchInlineHtml(buf, i) {
                items.append(.html(srcRange(i, htmlEnd)))
                i = htmlEnd
            } else {
                items.append(.text("<", srcRange(i, i + 1)))
                i += 1
            }

        case 0x26:
            if let (decoded, endIdx) = decodeHtmlEntity(buf, i, buf.count) {
                items.append(.text(decoded, srcRange(i, endIdx)))
                i = endIdx
            } else {
                items.append(.text("&", srcRange(i, i + 1)))
                i += 1
            }

        default:
            let start = i
            i += 1
            while i < buf.count {
                let c = buf[i]
                if c == 0x0A || c == 0x5C || c == 0x60 || c == 0x2A || c == 0x5F || c == 0x7E
                    || c == 0x21 || c == 0x5B || c == 0x5D || c == 0x3C || c == 0x26
                {
                    break
                }
                // Check contiguous source offsets so soft-break skipped prefixes don't merge improperly.
                if srcOffs[i] != srcOffs[i - 1] + 1 {
                    break
                }
                i += 1
            }
            let textStr = String(decoding: buf[start..<i], as: UTF8.self)
            items.append(.text(textStr, srcRange(start, i)))
        }
    }

    // Any remaining unmatched `[` or `![` become literal text.
    for entry in brackets {
        items[entry.itemIdx] = .text(
            entry.isImage ? "![" : "[",
            entry.srcStart..<(entry.srcStart + (entry.isImage ? 2 : 1))
        )
    }

    processEmphasis(&items, fromItemIdx: 0)

    for item in items {
        switch item {
        case let .text(s, r):
            if !s.isEmpty {
                out.append((.text(s), r))
            }
        case let .code(s, r):
            out.append((.code(s), r))
        case let .softBreak(r):
            out.append((.softBreak, r))
        case let .hardBreak(r):
            out.append((.hardBreak, r))
        case .html:
            break
        case let .delim(ch, _, count, _, _, srcStart):
            if count > 0 {
                let s = String(repeating: String(Character(UnicodeScalar(ch))), count: count)
                out.append((.text(s), srcStart..<(srcStart + count)))
            }
        case let .openBracket(isImage, srcStart):
            let s = isImage ? "![" : "["
            out.append((.text(s), srcStart..<(srcStart + (isImage ? 2 : 1))))
        case let .startSpan(ev, r), let .endSpan(ev, r):
            out.append((ev, r))
        }
    }
}

private func computeFlanks(_ s: String, _ byteOffset: Int, _ runLen: Int) -> (Bool, Bool) {
    let utf8 = s.utf8
    let beforeScalar: UnicodeScalar? = {
        guard byteOffset > 0 else { return nil }
        let idx = utf8.index(utf8.startIndex, offsetBy: byteOffset)
        guard let strIdx = idx.samePosition(in: s), strIdx > s.startIndex else { return nil }
        return s[s.index(before: strIdx)].unicodeScalars.last
    }()
    let afterScalar: UnicodeScalar? = {
        let afterOff = byteOffset + runLen
        guard afterOff < utf8.count else { return nil }
        let idx = utf8.index(utf8.startIndex, offsetBy: afterOff)
        guard let strIdx = idx.samePosition(in: s), strIdx < s.endIndex else { return nil }
        return s[strIdx].unicodeScalars.first
    }()
    let beforeWs = beforeScalar.map { $0.properties.isWhitespace } ?? true
    let afterWs = afterScalar.map { $0.properties.isWhitespace } ?? true
    let beforePunct = beforeScalar.map { isPunctScalar($0) } ?? false
    let afterPunct = afterScalar.map { isPunctScalar($0) } ?? false
    let leftFlank = !afterWs && (!afterPunct || beforeWs || beforePunct)
    let rightFlank = !beforeWs && (!beforePunct || afterWs || afterPunct)
    return (leftFlank, rightFlank)
}

private func prevCharIsPunct(_ s: String, _ byteOffset: Int) -> Bool {
    guard byteOffset > 0 else { return false }
    let utf8 = s.utf8
    let idx = utf8.index(utf8.startIndex, offsetBy: byteOffset)
    guard let strIdx = idx.samePosition(in: s), strIdx > s.startIndex else { return false }
    let ch = s[s.index(before: strIdx)]
    return ch.unicodeScalars.first.map { isPunctScalar($0) } ?? false
}

private func nextCharIsPunct(_ s: String, _ byteOffset: Int) -> Bool {
    let utf8 = s.utf8
    guard byteOffset < utf8.count else { return false }
    let idx = utf8.index(utf8.startIndex, offsetBy: byteOffset)
    guard let strIdx = idx.samePosition(in: s), strIdx < s.endIndex else { return false }
    let ch = s[strIdx]
    return ch.unicodeScalars.first.map { isPunctScalar($0) } ?? false
}

private func isPunctScalar(_ u: UnicodeScalar) -> Bool {
    if u.value < 0x80 {
        return isAsciiPunct(UInt8(u.value))
    }
    switch u.properties.generalCategory {
    case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
         .initialPunctuation, .finalPunctuation, .otherPunctuation,
         .mathSymbol, .currencySymbol, .modifierSymbol, .otherSymbol:
        return true
    default:
        return false
    }
}

private func processEmphasis(_ items: inout [InlineItem], fromItemIdx bottom: Int) {
    var closerIdx = bottom
    while closerIdx < items.count {
        guard case let .delim(cCh, cOrig, cCount, cCanOpen, cCanClose, cSrcStart) = items[closerIdx],
              cCanClose,
              cCount > 0
        else {
            closerIdx += 1
            continue
        }

        var openerFound: Int? = nil
        if closerIdx > bottom {
            var scan = closerIdx - 1
            while true {
                if case let .delim(oCh, oOrig, oCount, oCanOpen, oCanClose, _) = items[scan],
                   oCanOpen,
                   oCount > 0,
                   oCh == cCh
                {
                    if oCh == 0x7E {
                        if oCount == cCount {
                            openerFound = scan
                            break
                        }
                    } else {
                        let oddMatch = (oCanClose || cCanOpen)
                            && (oOrig + cOrig) % 3 == 0
                            && (oOrig % 3 != 0 || cOrig % 3 != 0)
                        if !oddMatch {
                            openerFound = scan
                            break
                        }
                    }
                }
                if scan == bottom { break }
                scan -= 1
            }
        }

        guard let openIdx = openerFound,
              case let .delim(oCh, oOrig, oCount, oCanOpen, oCanClose, oSrcStart) = items[openIdx]
        else {
            closerIdx += 1
            continue
        }

        let use: Int
        let startEv: MdEvent
        let endEv: MdEvent
        if cCh == 0x7E {
            use = cCount
            startEv = .startStrikethrough
            endEv = .endStrikethrough
        } else if oCount >= 2 && cCount >= 2 {
            use = 2
            startEv = .startStrong
            endEv = .endStrong
        } else {
            use = 1
            startEv = .startEmphasis
            endEv = .endEmphasis
        }

        // Convert any non-matching delimiters strictly between `openIdx` and `closerIdx` into literal text.
        if openIdx + 1 < closerIdx {
            for mid in (openIdx + 1)..<closerIdx {
                if case let .delim(mCh, _, mCount, _, _, mSrc) = items[mid] {
                    if mCount > 0 {
                        let s = String(repeating: String(Character(UnicodeScalar(mCh))), count: mCount)
                        items[mid] = .text(s, mSrc..<(mSrc + mCount))
                    } else {
                        items[mid] = .text("", mSrc..<mSrc)
                    }
                }
            }
        }

        let newOpenCount = oCount - use
        let openUsedSrc = (oSrcStart + newOpenCount)..<(oSrcStart + oCount)
        let closeUsedSrc = cSrcStart..<(cSrcStart + use)
        let fullSpanRange = openUsedSrc.lowerBound..<closeUsedSrc.upperBound

        items[openIdx] = .delim(
            ch: oCh,
            origCount: oOrig,
            count: newOpenCount,
            canOpen: oCanOpen,
            canClose: oCanClose,
            srcStart: oSrcStart
        )
        items[closerIdx] = .delim(
            ch: cCh,
            origCount: cOrig,
            count: cCount - use,
            canOpen: cCanOpen,
            canClose: cCanClose,
            srcStart: cSrcStart + use
        )

        items.insert(.startSpan(startEv, fullSpanRange), at: openIdx + 1)
        closerIdx += 1
        items.insert(.endSpan(endEv, fullSpanRange), at: closerIdx)

        if cCount - use == 0 {
            closerIdx += 1
        }
    }

    // Remaining delimiters from `bottom` become plain text.
    for idx in bottom..<items.count {
        if case let .delim(ch, _, count, _, _, srcStart) = items[idx] {
            if count > 0 {
                let s = String(repeating: String(Character(UnicodeScalar(ch))), count: count)
                items[idx] = .text(s, srcStart..<(srcStart + count))
            } else {
                items[idx] = .text("", srcStart..<srcStart)
            }
        }
    }
}

private func matchLinkAfterCloseBracket(
    _ src: String,
    _ buf: [UInt8],
    _ closeBracketIdx: Int,
    _ openItemIdx: Int,
    _ items: [InlineItem],
    _ linkDefs: [String: String]
) -> (String, Int)? {
    let next = closeBracketIdx + 1
    // 1. Inline link `[text](dest "title")`
    if next < buf.count && buf[next] == 0x28 {
        if let (dest, endIdx) = parseInlineLinkDest(buf, next + 1) {
            return (dest, endIdx)
        }
    }

    // 2. Full or collapsed reference link `[text][ref]` or `[text][]`
    if next < buf.count && buf[next] == 0x5B {
        var k = next + 1
        while k < buf.count && buf[k] != 0x5D {
            if buf[k] == 0x5B {
                k = buf.count
                break
            }
            if buf[k] == 0x5C && k + 1 < buf.count {
                k += 2
            } else {
                k += 1
            }
        }
        if k < buf.count && buf[k] == 0x5D {
            let refLabel: String
            if k == next + 1 {
                refLabel = extractBracketRawLabel(items, from: openItemIdx + 1)
            } else {
                refLabel = String(decoding: buf[(next + 1)..<k], as: UTF8.self)
            }
            let norm = normalizeLinkLabel(refLabel)
            if let url = linkDefs[norm] {
                return (url, k + 1)
            }
            return nil
        }
    }

    // 3. Shortcut reference link `[text]`
    let rawLabel = extractBracketRawLabel(items, from: openItemIdx + 1)
    let norm = normalizeLinkLabel(rawLabel)
    if let url = linkDefs[norm] {
        return (url, next)
    }
    return nil
}

private func extractBracketRawLabel(_ items: [InlineItem], from startIdx: Int) -> String {
    var out = ""
    guard startIdx < items.count else { return out }
    for item in items[startIdx...] {
        switch item {
        case let .text(s, _):
            out.append(s)
        case let .code(s, _):
            out.append("`")
            out.append(s)
            out.append("`")
        case .softBreak, .hardBreak:
            out.append(" ")
        case let .delim(ch, _, count, _, _, _):
            out.append(String(repeating: String(Character(UnicodeScalar(ch))), count: count))
        default:
            break
        }
    }
    return out
}

private func parseInlineLinkDest(_ buf: [UInt8], _ start: Int) -> (String, Int)? {
    var i = start
    while i < buf.count && (isAsciiSpaceOrTab(buf[i]) || buf[i] == 0x0A) {
        i += 1
    }
    guard i < buf.count else { return nil }
    if buf[i] == 0x29 {
        return ("", i + 1)
    }
    let destRaw: [UInt8]
    if buf[i] == 0x3C {
        i += 1
        let dStart = i
        while i < buf.count && buf[i] != 0x3E && buf[i] != 0x0A {
            if buf[i] == 0x5C && i + 1 < buf.count {
                i += 2
            } else {
                i += 1
            }
        }
        guard i < buf.count && buf[i] == 0x3E else { return nil }
        destRaw = Array(buf[dStart..<i])
        i += 1
    } else {
        let dStart = i
        var parens = 0
        while i < buf.count {
            let b = buf[i]
            if b <= 0x20 || b == 0x7F {
                break
            }
            if b == 0x5C && i + 1 < buf.count {
                i += 2
                continue
            }
            if b == 0x28 {
                parens += 1
                if parens > 32 { return nil }
            } else if b == 0x29 {
                if parens == 0 { break }
                parens -= 1
            }
            i += 1
        }
        guard parens == 0 else { return nil }
        destRaw = Array(buf[dStart..<i])
    }

    var ws = 0
    while i < buf.count && (isAsciiSpaceOrTab(buf[i]) || buf[i] == 0x0A) {
        ws += 1
        i += 1
    }
    if i < buf.count && buf[i] == 0x29 {
        return (unescapeDestBytes(destRaw), i + 1)
    }
    guard ws > 0, i < buf.count, (buf[i] == 0x22 || buf[i] == 0x27 || buf[i] == 0x28) else {
        return nil
    }
    let openQ = buf[i]
    let closeQ: UInt8 = openQ == 0x28 ? 0x29 : openQ
    i += 1
    while i < buf.count && buf[i] != closeQ {
        if openQ == 0x28 && buf[i] == 0x28 { return nil }
        if buf[i] == 0x5C && i + 1 < buf.count {
            i += 2
        } else {
            i += 1
        }
    }
    guard i < buf.count && buf[i] == closeQ else { return nil }
    i += 1
    while i < buf.count && (isAsciiSpaceOrTab(buf[i]) || buf[i] == 0x0A) {
        i += 1
    }
    guard i < buf.count && buf[i] == 0x29 else { return nil }
    return (unescapeDestBytes(destRaw), i + 1)
}

private func matchAngleAutolink(_ buf: [UInt8], _ pos: Int) -> (String, String, Int)? {
    guard pos + 3 < buf.count && buf[pos] == 0x3C else { return nil }
    var end = pos + 1
    while end < buf.count && buf[end] != 0x3E && buf[end] != 0x3C && buf[end] > 0x20 {
        end += 1
    }
    guard end < buf.count && buf[end] == 0x3E && end > pos + 2 else { return nil }
    let inner = Array(buf[(pos + 1)..<end])
    if let colonIdx = inner.firstIndex(of: 0x3A), colonIdx >= 2 && colonIdx <= 32 {
        var validScheme = isAsciiAlpha(inner[0])
        if validScheme {
            for k in 1..<colonIdx {
                let c = inner[k]
                if !isAsciiAlnum(c) && c != 0x2B && c != 0x2E && c != 0x2D {
                    validScheme = false
                    break
                }
            }
        }
        if validScheme {
            let s = String(decoding: inner, as: UTF8.self)
            return (s, s, end + 1)
        }
    }
    if let atIdx = inner.firstIndex(of: 0x40), atIdx > 0, atIdx + 1 < inner.count {
        let localOk = inner[0..<atIdx].allSatisfy { c in
            isAsciiAlnum(c) || c == 0x2E || c == 0x21 || c == 0x23 || c == 0x24 || c == 0x25
                || c == 0x26 || c == 0x27 || c == 0x2A || c == 0x2B || c == 0x2F || c == 0x3D
                || c == 0x3F || c == 0x5E || c == 0x5F || c == 0x60 || c == 0x7B || c == 0x7C
                || c == 0x7D || c == 0x7E || c == 0x2D
        }
        let domainOk = inner[(atIdx + 1)...].allSatisfy { c in
            isAsciiAlnum(c) || c == 0x2D || c == 0x2E
        }
        if localOk && domainOk {
            let email = String(decoding: inner, as: UTF8.self)
            return ("mailto:\(email)", email, end + 1)
        }
    }
    return nil
}

private func matchInlineHtml(_ buf: [UInt8], _ pos: Int) -> Int? {
    guard pos + 2 < buf.count && buf[pos] == 0x3C else { return nil }
    let next = buf[pos + 1]
    if next == 0x21 {
        if pos + 3 < buf.count && buf[pos + 2] == 0x2D && buf[pos + 3] == 0x2D {
            var i = pos + 4
            if i < buf.count && buf[i] == 0x3E { return i + 1 }
            if i + 1 < buf.count && buf[i] == 0x2D && buf[i + 1] == 0x3E { return i + 2 }
            while i + 2 < buf.count {
                if buf[i] == 0x2D && buf[i + 1] == 0x2D && buf[i + 2] == 0x3E {
                    return i + 3
                }
                i += 1
            }
            return nil
        }
        if pos + 8 < buf.count,
           buf[pos + 2] == 0x5B, buf[pos + 3] == 0x43, buf[pos + 4] == 0x44,
           buf[pos + 5] == 0x41, buf[pos + 6] == 0x54, buf[pos + 7] == 0x41, buf[pos + 8] == 0x5B
        {
            var i = pos + 9
            while i + 2 < buf.count {
                if buf[i] == 0x5D && buf[i + 1] == 0x5D && buf[i + 2] == 0x3E {
                    return i + 3
                }
                i += 1
            }
            return nil
        }
        if pos + 2 < buf.count && isAsciiAlpha(buf[pos + 2]) {
            var i = pos + 3
            while i < buf.count && buf[i] != 0x3E {
                i += 1
            }
            return i < buf.count ? (i + 1) : nil
        }
        return nil
    }
    if next == 0x3F {
        var i = pos + 2
        while i + 1 < buf.count {
            if buf[i] == 0x3F && buf[i + 1] == 0x3E {
                return i + 2
            }
            i += 1
        }
        return nil
    }
    return scanCompleteHtmlTag(buf, pos, buf.count)
}

private let NAMED_HTML_ENTITIES: [String: String] = [
    "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
    "nbsp": "\u{00A0}", "mdash": "\u{2014}", "ndash": "\u{2013}",
    "hellip": "\u{2026}", "lsquo": "\u{2018}", "rsquo": "\u{2019}",
    "ldquo": "\u{201C}", "rdquo": "\u{201D}", "copy": "\u{00A9}",
    "reg": "\u{00AE}", "trade": "\u{2122}", "times": "\u{00D7}",
    "divide": "\u{00F7}", "plusmn": "\u{00B1}", "deg": "\u{00B0}",
    "bull": "\u{2022}", "middot": "\u{00B7}", "rarr": "\u{2192}",
    "larr": "\u{2190}", "uarr": "\u{2191}", "darr": "\u{2193}",
    "harr": "\u{2194}", "le": "\u{2264}", "ge": "\u{2265}",
    "ne": "\u{2260}", "asymp": "\u{2248}", "equiv": "\u{2261}",
    "euro": "\u{20AC}", "pound": "\u{00A3}", "yen": "\u{00A5}",
    "cent": "\u{00A2}", "sect": "\u{00A7}", "para": "\u{00B6}",
    "laquo": "\u{00AB}", "raquo": "\u{00BB}", "frac12": "\u{00BD}",
    "frac14": "\u{00BC}", "frac34": "\u{00BE}", "sup2": "\u{00B2}",
    "sup3": "\u{00B3}", "micro": "\u{00B5}",
]

private func decodeHtmlEntity(_ bytes: [UInt8], _ pos: Int, _ limit: Int) -> (String, Int)? {
    guard pos + 2 < limit && bytes[pos] == 0x26 else { return nil }
    var i = pos + 1
    if bytes[i] == 0x23 {
        i += 1
        guard i < limit else { return nil }
        let isHex = bytes[i] == 0x78 || bytes[i] == 0x58
        if isHex {
            i += 1
            let dStart = i
            var code: UInt32 = 0
            while i < limit && i - dStart < 6 {
                let c = bytes[i]
                let digit: UInt32
                if c >= 0x30 && c <= 0x39 {
                    digit = UInt32(c - 0x30)
                } else if c >= 0x41 && c <= 0x46 {
                    digit = UInt32(c - 0x41 + 10)
                } else if c >= 0x61 && c <= 0x66 {
                    digit = UInt32(c - 0x61 + 10)
                } else {
                    break
                }
                code = code * 16 + digit
                i += 1
            }
            guard i > dStart && i < limit && bytes[i] == 0x3B else { return nil }
            let scalar = (code == 0 || code > 0x10FFFF) ? UnicodeScalar(0xFFFD)! : (UnicodeScalar(code) ?? UnicodeScalar(0xFFFD)!)
            return (String(scalar), i + 1)
        } else {
            let dStart = i
            var code: UInt32 = 0
            while i < limit && i - dStart < 7 && bytes[i] >= 0x30 && bytes[i] <= 0x39 {
                code = code * 10 + UInt32(bytes[i] - 0x30)
                i += 1
            }
            guard i > dStart && i < limit && bytes[i] == 0x3B else { return nil }
            let scalar = (code == 0 || code > 0x10FFFF) ? UnicodeScalar(0xFFFD)! : (UnicodeScalar(code) ?? UnicodeScalar(0xFFFD)!)
            return (String(scalar), i + 1)
        }
    } else {
        let nStart = i
        while i < limit && i - nStart < 32 && isAsciiAlnum(bytes[i]) {
            i += 1
        }
        guard i > nStart && i < limit && bytes[i] == 0x3B else { return nil }
        let name = String(decoding: bytes[nStart..<i], as: UTF8.self)
        if let decoded = NAMED_HTML_ENTITIES[name] ?? NAMED_HTML_ENTITIES[name.lowercased()] {
            return (decoded, i + 1)
        }
        return nil
    }
}
