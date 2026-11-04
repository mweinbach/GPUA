// Ported from: crates/rune-kit/src/markdown/render.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Blocks to elements: block keys and margins, code and diff blocks, lists, quotes, tables and
//! diagrams.

import Rune

final class Renderer {
    let s: MarkdownStyle
    let highlights: [([Range<Int>], Highlight)]
    let reveal: Float
    let streaming: Bool
    let onLink: LinkWire?
    let onLinkSecondary: LinkWire?
    let linkLook: LinkLook?
    let onTask: TaskWire?
    let tasksReadOnly: Bool
    let linkRing: LinkRing?
    let selectable: Bool
    let scrollWide: Bool
    let highlighter: Highlighter
    let sources: [Source]
    var nextSource: Int = 0
    let tasks: [(Bool, Int)?]
    var nextTask: Int = 0
    var currentBlockKey: String = "b0"

    init(
        s: MarkdownStyle,
        highlights: [([Range<Int>], Highlight)],
        reveal: Float,
        streaming: Bool,
        onLink: LinkWire?,
        onLinkSecondary: LinkWire?,
        linkLook: LinkLook?,
        onTask: TaskWire?,
        tasksReadOnly: Bool,
        linkRing: LinkRing?,
        selectable: Bool,
        scrollWide: Bool,
        highlighter: Highlighter,
        sources: [Source],
        tasks: [(Bool, Int)?]
    ) {
        self.s = s
        self.highlights = highlights
        self.reveal = reveal
        self.streaming = streaming
        self.onLink = onLink
        self.onLinkSecondary = onLinkSecondary
        self.linkLook = linkLook
        self.onTask = onTask
        self.tasksReadOnly = tasksReadOnly
        self.linkRing = linkRing
        self.selectable = selectable
        self.scrollWide = scrollWide
        self.highlighter = highlighter
        self.sources = sources
        self.tasks = tasks
    }
}

/// The keys `Renderer.blocks` gives `n` blocks.
func renderedKeys(_ n: Int, _ keys: [String]) -> [String] {
    var used: [String] = []
    return (0..<n).map { i in
        if keys.isEmpty {
            return "b\(i)"
        } else {
            return resolveBlockKey(i, keys, &used)
        }
    }
}

/// ``Markdown/copySource(_:)``: the source of the top-level blocks (keyed `names`, starting at
/// `starts`) that `sel` touches, `nil` for part of one block.
func sourceCopy(_ src: String, _ starts: [Int], _ names: [String], _ sel: TextSelection) -> String? {
    func blockOf(_ path: String) -> Int? {
        var bestIdx: Int? = nil
        var bestLen = -1
        for (b, k) in names.enumerated() {
            let matches: Bool
            if path == k {
                matches = true
            } else if path.hasPrefix(k) {
                let rest = path.dropFirst(k.count)
                matches = rest.first == "/"
            } else {
                matches = false
            }
            if matches && k.utf8.count > bestLen {
                bestLen = k.utf8.count
                bestIdx = b
            }
        }
        return bestIdx
    }

    let texts = sel.texts()
    var touched: (Int, Int)? = nil
    for t in texts where !t.range.isEmpty {
        guard let b = blockOf(t.path) else { continue }
        if let (first, _) = touched {
            touched = (first, b)
        } else {
            touched = (b, b)
        }
    }
    guard let (first, last) = touched else { return nil }
    if first == last {
        let allWholeOrEmpty = texts
            .filter { blockOf($0.path) == first }
            .allSatisfy { $0.isWhole() || $0.len == 0 }
        if !allWholeOrEmpty {
            return nil
        }
    }
    if (first == 0 && last + 1 >= starts.count) || texts.allSatisfy({ $0.isWhole() || $0.len == 0 }) {
        return src
    }
    guard first < starts.count else { return nil }
    let srcBytes = Array(src.utf8)
    let start = starts[first]
    let end = (last + 1 < starts.count) ? starts[last + 1] : srcBytes.count
    guard start >= 0, end <= srcBytes.count, start <= end,
          isUtf8Boundary(srcBytes, start),
          isUtf8Boundary(srcBytes, end)
    else {
        return nil
    }
    let slice = String(decoding: srcBytes[start..<end], as: UTF8.self)
    return trimEndUnicodeWhitespace(slice)
}

private func resolveBlockKey(_ i: Int, _ keys: [String], _ used: inout [String]) -> String {
    if i < keys.count {
        let k = keys[i]
        if !k.isEmpty && !used.contains(k) {
            used.append(k)
            return k
        }
    }
    func taken(_ cand: String, _ usedList: [String]) -> Bool {
        if usedList.contains(cand) {
            return true
        }
        if i + 1 < keys.count {
            return keys[(i + 1)...].contains(cand)
        }
        return false
    }
    var cand = "b\(i)"
    var n = 0
    while taken(cand, used) {
        cand = "b\(n)"
        n += 1
    }
    used.append(cand)
    return cand
}

/// `(marginTop, marginBottom)` per block, collapsed like CSS margins.
func margins(_ b: MarkdownBlock, _ s: MarkdownStyle) -> (Float, Float) {
    switch b {
    case .para:
        return (0.0, 12.0)
    case .heading(1, _):
        return (28.0, 12.0)
    case .heading(2, _):
        return (24.0, 10.0)
    case .heading:
        return (20.0, 8.0)
    case .code, .diff, .mermaid:
        return (12.0, 24.0)
    case .list:
        return (8.0, 12.0)
    case .quote:
        return (16.0, 16.0)
    case .rule:
        return (32.0, 32.0)
    case .table:
        return (s.tableMarginPt[0], s.tableMarginPt[1])
    }
}

/// Code as rich text with `spans` and `highlights` (byte ranges of `code`).
private func tabbed(
    _ code: String,
    _ rawSpans: [Span],
    _ rawHighlights: [TextHighlight],
    _ style: TextStyle
) -> El {
    let isMono: Bool
    switch style.family {
    case .mono, .systemMono:
        isMono = true
    default:
        isMono = false
    }
    if !code.contains("\t") || isMono {
        return rich(code, rawSpans).textHighlights(rawHighlights)
    }

    var shown = ""
    shown.reserveCapacity(code.utf8.count + code.utf8.count / 8)
    // `(sourceByte, shownByte, pad, totalPaddingSoFar)`
    var tabs: [(Int, Int, Int, Int)] = []
    var column = 0
    var byteIdx = 0
    for sc in code.unicodeScalars {
        let scLen = sc.utf8.count
        if sc == "\t" {
            let pad = 3 - (column % 4)
            let total = (tabs.last?.3 ?? 0) + pad
            tabs.append((byteIdx, shown.utf8.count, pad, total))
            shown.append("\t")
            shown.append(String(repeating: " ", count: pad))
            column += pad + 1
        } else {
            column = (sc == "\n") ? 0 : (column + 1)
            shown.unicodeScalars.append(sc)
        }
        byteIdx += scLen
    }

    func shift(_ b: UInt32) -> UInt32 {
        var lo = 0
        var hi = tabs.count
        while lo < hi {
            let mid = lo + (hi - lo) / 2
            if UInt32(tabs[mid].0) < b {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        if lo == 0 {
            return b
        }
        return b + UInt32(tabs[lo - 1].3)
    }

    let spans = rawSpans.map { sp -> Span in
        var copy = sp
        copy.start = shift(sp.start)
        copy.end = shift(sp.end)
        return copy
    }
    let highlights = rawHighlights.map { hl -> TextHighlight in
        let r = hl.range()
        let a = Int(shift(UInt32(r.lowerBound)))
        let b = Int(shift(UInt32(r.upperBound)))
        return hl.withRange(a..<b)
    }
    var out = rich(shown, spans).textHighlights(highlights)
    for t in tabs {
        out = out.uncopied((t.1 + 1)..<(t.1 + 1 + t.2))
    }
    return out
}

extension Renderer {
    func spans(_ inl: MarkdownInline, _ base: Float) -> [Span] {
        let links: [Span]
        if inl.links.isEmpty {
            links = []
        } else {
            links = inl.spans.compactMap { (a, b, st) in
                st == .link ? linkSpan(a, b, inl) : nil
            }
        }
        var nextLink = 0
        var out: [Span] = []
        out.reserveCapacity(inl.spans.count)
        for (a, b, st) in inl.spans {
            if st == .link {
                let sp = links[nextLink]
                nextLink += 1
                let at = out.firstIndex(where: { p in p.start < sp.end && sp.start < p.end }) ?? out.count
                out.insert(sp, at: at)
                continue
            }
            if st == .strike {
                continue
            }
            let inLink = links.first(where: { l in l.start <= UInt32(a) && UInt32(b) <= l.end })
            var sp = Span.new(a, b)
            // Code in a link is a chip in the link's colour, not underlined as well.
            let noLine: Color? = (inLink?.underline != nil) ? Color.TRANSPARENT : nil
            switch st {
            case .code:
                let linkBase = inLink?.size ?? base
                sp.mono = true
                sp.weight = s.inlineCodeWeight
                sp.size = linkBase * s.inlineCodeScale
                sp.underline = noLine
                if inLink?.bg == nil {
                    sp = sp.bg(s.codeBg, s.inlineCodePadPt)
                }
            case .codePad where noLine == nil:
                continue
            case .codePad:
                sp.underline = noLine
            case .strong:
                sp.weight = s.strongWeightValue
            case .em:
                sp.italic = true
            case .strike, .link:
                continue
            }
            out.append(sp)
        }
        return out
    }

    /// Resolves `hl` against ``MarkdownStyle`` into a `TextHighlight` for `range`.
    private func makeTextHighlight(_ idx: Int, _ range: Range<Int>, _ hl: Highlight) -> TextHighlight {
        let bg = hl.bgColor ?? (hl.currentFlag ? s.highlightCurrentBgColor : s.highlightBgColor)
        let fg = hl.fgColor ?? (hl.currentFlag ? s.highlightCurrentFgColor : s.highlightFgColor)
        let ring: (Color, Float)?
        if let rs = hl.ringSpec {
            ring = (rs.color, rs.width)
        } else {
            ring = hl.currentFlag ? s.highlightCurrentRingSpec : s.highlightRingSpec
        }
        let key = hl.keyName ?? Markdown.highlightKey(idx)
        var th = TextHighlight.new(range, bg).key(key)
        if let fg {
            th = th.color(fg)
        }
        if let (rc, rw) = ring {
            th = th.ring(rc, rw)
        }
        return th
    }

    func textHighlightsFor(_ text: String, _ map: SpanMap?) -> [TextHighlight] {
        guard let map, !highlights.isEmpty else { return [] }
        var out: [TextHighlight] = []
        for (idx, (srcRanges, hl)) in highlights.enumerated() {
            for r in map.mapRanges(srcRanges, text) {
                out.append(makeTextHighlight(idx, r, hl))
            }
        }
        return out
    }

    /// `e`, a text, selectable when the markdown is (after its links, so it shows the I-beam).
    func select(_ e: El) -> El {
        selectable ? e.selectable(true).selectionColor(s.selectionColor) : e
    }

    /// `e`, the text of `inl`, with its strikethroughs, highlights, links and selectable, copying
    /// without inline code's padding.
    func selectInline(_ e: El, _ inl: MarkdownInline, _ map: SpanMap?) -> El {
        var out = e
        for (a, b, st) in inl.spans where st == .strike {
            out = out.strike(a, b, nil)
        }
        out = out.textHighlights(textHighlightsFor(inl.text, map))
        out = select(wireLink(out, inl))
        if !selectable {
            return out
        }
        for (a, b, st) in inl.spans where st == .codePad {
            out = out.uncopied(a..<b)
        }
        return out
    }

    func para(_ inl: MarkdownInline, _ map: SpanMap?, _ style: TextStyle, _ color: Color) -> El {
        let e = rich(inl.text, spans(inl, style.size))
            .font(style)
            .color(color)
            .reveal(reveal)
            .wFull()
        return selectInline(e, inl, map)
    }

    func blocks(_ blockList: [MarkdownBlock], _ maps: [BlockMap], _ keys: [String], _ topLevel: Bool) -> El {
        var c = col().wFull()
        var prevMb: Float = 0.0
        let names = renderedKeys(blockList.count, keys)
        for (i, b) in blockList.enumerated() {
            let key = names[i]
            // A fence still arriving with no lines yet shows nothing until its first line.
            if streaming, case .code(let codeText) = b, codeText.isEmpty {
                let n = nextSource
                if n < sources.count, sources[n].open && sources[n].len == 0 {
                    nextSource = n + 1
                    continue
                }
            }
            let (mt, mb) = margins(b, s)
            let top: Float = (i == 0) ? 0.0 : max(mt, prevMb)
            if topLevel {
                currentBlockKey = key
            }
            let bmap: BlockMap = i < maps.count ? maps[i] : .none
            c = c.child(block(b, bmap).key(key).mt(top))
            prevMb = mb
        }
        return c
    }

    func code(_ codeText: String, _ source: Source?, _ map: SpanMap?) -> El {
        let hl = textHighlightsFor(codeText, map)
        let body = tabbed(codeText, syntaxSpans(codeText, source), hl, s.codeBlockStyle)
            .font(s.codeBlockStyle)
            .color(s.textColor)
            .reveal(reveal)
        let frame = col()
            .wFull()
            .radius(6.0)
            .fill(s.codeBlockFill)
            .border(0.5, s.codeBlockBorder)
        if scrollWide {
            return frame.child(
                col()
                    .key("scroll")
                    .wFull()
                    .scrollX()
                    .scrollEdgeFade(12.0)
                    .child(col().px(s.codeBlockPad[0]).py(s.codeBlockPad[1]).child(select(body)))
            )
        }
        return frame.px(s.codeBlockPad[0]).py(s.codeBlockPad[1]).child(select(body.wFull()))
    }

    /// Colour-only spans, so highlighting never moves a glyph.
    func syntaxSpans(_ codeText: String, _ source: Source?) -> [Span] {
        guard s.highlightEnabled, let src = source else { return [] }
        let lang = src.lang
        if highlighter.isBuiltin() {
            guard let lang, syntax.known(lang) else { return [] }
        }
        let codeBytes = Array(codeText.utf8)
        guard src.coloured >= 0, src.coloured <= codeBytes.count,
              isUtf8Boundary(codeBytes, src.coloured)
        else {
            return []
        }
        let prefix = String(decoding: codeBytes[0..<src.coloured], as: UTF8.self)
        return s.syntaxThemeValue.spans(highlighter.highlight(lang, prefix), 0)
    }

    /// One row per line, so added and removed lines are tinted edge to edge.
    func diff(_ src: String, _ map: SpanMap?) -> El {
        let allHl = textHighlightsFor(src, map)
        var c = col()
            .wFull()
            .py(s.codeBlockPad[1])
            .radius(6.0)
            .fill(s.codeBlockFill)
            .border(0.5, s.codeBlockBorder)
        let lines = src.split(separator: "\n", omittingEmptySubsequences: false)
        var lineStart = 0
        for (n, rawLineSub) in lines.enumerated() {
            let rawLine = String(rawLineSub)
            let lineEnd = lineStart + rawLine.utf8.count
            let lineHl: [TextHighlight] = allHl.compactMap { h in
                let r = h.range()
                let a = max(r.lowerBound, lineStart)
                let b = min(r.upperBound, lineEnd)
                return a < b ? h.withRange((a - lineStart)..<(b - lineStart)) : nil
            }
            lineStart = lineEnd + 1
            let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
            let isHeader = line.hasPrefix("@@")
                || line.hasPrefix("diff ")
                || line.hasPrefix("index ")
                || line.hasPrefix("--- ")
                || line.hasPrefix("+++ ")
            let lineTint: Color?
            let lineColor: Color
            if isHeader {
                lineTint = nil
                lineColor = s.diffHunkColor
            } else if line.utf8.first == 0x2B { // '+'
                lineTint = s.diffAdd
                lineColor = s.diffAddText
            } else if line.utf8.first == 0x2D { // '-'
                lineTint = s.diffRemove
                lineColor = s.diffRemoveText
            } else {
                lineTint = nil
                lineColor = s.textColor
            }
            let shown = line.isEmpty ? " " : line
            var r = row()
                .key("l\(n)")
                .wFull()
                .px(s.codeBlockPad[0])
                .child(
                    select(
                        tabbed(shown, [], lineHl, s.codeBlockStyle)
                            .font(s.codeBlockStyle)
                            .color(lineColor)
                            .wrap()
                            .reveal(reveal)
                            .wFull()
                    )
                )
            if let lineTint {
                r = r.fill(lineTint)
            }
            c = c.child(r)
        }
        return c
    }

    /// A diagram, drawn from its complete lines while its fence is still open; until any read
    /// (or for a type it doesn't draw), its source as a code block.
    func mermaidBlock(_ src: String, _ source: Source?, _ map: SpanMap?) -> El {
        let open = source?.open ?? false
        let srcBytes = Array(src.utf8)
        let lines: String
        if open {
            let cut = min(source?.coloured ?? srcBytes.count, srcBytes.count)
            let safeCut = floorUtf8Boundary(srcBytes, cut)
            lines = String(decoding: srcBytes[0..<safeCut], as: UTF8.self)
        } else {
            lines = src
        }
        func holder() -> El {
            col().wFull().transition(Transition.none())
        }
        if let d = mermaid.diagram(lines, s.diagramPaint, streaming, open) {
            return holder().child(d.key("card"))
        }
        if open && streaming && mermaid.mayDraw(lines) {
            return holder()
        }
        return col().wFull().child(code(src, source, map).key("source"))
    }

    private func taskItem(
        _ k: Int,
        _ item: [MarkdownBlock],
        _ itemMaps: [BlockMap],
        _ itemIdx: Int,
        _ checked: Bool
    ) -> El {
        let t = s.task
        let interactive = onTask != nil && !tasksReadOnly
        let fill: Color = checked ? t.fillOn : Color.TRANSPARENT
        let border: Color = checked ? t.borderOn : t.borderOff
        var control = el()
            .key("control")
            .size(16.0, 16.0)
            .ml(8.0)
            .mr(8.0)
            .mt(max((s.bodyStyle.lineHeight - 16.0) * 0.5, 0.0))
            .center()
            .radius(t.radius)
            .fill(fill)
            .border(1.0, border)
            .motion(t.motion)
            .focusRing(1.0, 0.0, t.focusRing)
            .child(icon(t.check, 10.0).key("mark").color(t.mark).opacity(checked ? 1.0 : 0.0))
        if interactive {
            control = control.hover(t.hover)
        }
        var r = row()
            .key("i\(k)")
            .role("checkbox")
            .label(itemLabel(item))
            .focusSelected(checked)
            .focusable(interactive)
            .wFull()
            .child(control)
            .child(blocks(item, itemMaps, [], false).grow(1.0).shrink())
        if let onTask, !tasksReadOnly {
            let blockKey = currentBlockKey
            r = onTask(r.cursor(.pointer), blockKey, itemIdx, !checked)
        }
        return r
    }

    func block(_ b: MarkdownBlock, _ map: BlockMap) -> El {
        let inlMap: SpanMap?
        if case .inline(let m) = map {
            inlMap = m
        } else {
            inlMap = nil
        }
        let codeMap: SpanMap?
        if case .code(let m) = map {
            codeMap = m
        } else {
            codeMap = nil
        }

        switch b {
        case .para(let inl):
            return para(inl, inlMap, s.bodyStyle, s.textColor)
        case .heading(let l, let inl):
            let hIdx = min(max(Int(l) - 1, 0), 2)
            let hColor = l >= 4 ? s.mutedColor : s.textColor
            return para(inl, inlMap, s.headings[hIdx], hColor)
                .role("heading")
                .level(UInt32(l))
        case .code(let codeText):
            let n = nextSource
            nextSource = n + 1
            let srcEntry: Source? = (n < sources.count && sources[n].len == codeText.utf8.count) ? sources[n] : nil
            return code(codeText, srcEntry, codeMap)
        case .diff(let diffText):
            return diff(diffText, codeMap)
        case .mermaid(let mSrc):
            let n = nextSource
            nextSource = n + 1
            let srcEntry: Source? = (n < sources.count && sources[n].len == mSrc.utf8.count) ? sources[n] : nil
            return mermaidBlock(mSrc, srcEntry, codeMap)
        case .table(let t):
            let headMaps: [SpanMap]
            let rowMaps: [[SpanMap]]
            if case .table(let h, let r) = map {
                headMaps = h
                rowMaps = r
            } else {
                headMaps = []
                rowMaps = []
            }
            return table(t, headMaps, rowMaps)
        case .list(let start, let items):
            let itemMaps: [[BlockMap]]
            if case .list(let m) = map {
                itemMaps = m
            } else {
                itemMaps = []
            }
            var c = col().wFull().gap(s.listGap)
            for (k, item) in items.enumerated() {
                let imap = k < itemMaps.count ? itemMaps[k] : []
                let taskIdx = nextTask
                nextTask = taskIdx + 1
                if taskIdx < tasks.count, let (checked, markerOffset) = tasks[taskIdx] {
                    c = c.child(taskItem(k, item, imap, markerOffset, checked))
                    continue
                }
                let marker: String
                if let startNum = start {
                    marker = "\(startNum + UInt64(k))."
                } else {
                    marker = "•"
                }
                c = c.child(
                    row()
                        .key("i\(k)")
                        .wFull()
                        .child(
                            text(marker)
                                .font(s.bodyStyle)
                                .color(s.mutedColor)
                                .w(s.listIndent)
                                .align(.center)
                                .reveal(reveal)
                        )
                        .child(blocks(item, imap, [], false).grow(1.0).shrink())
                )
            }
            return c
        case .quote(let inner):
            let innerMaps: [BlockMap]
            if case .quote(let m) = map {
                innerMaps = m
            } else {
                innerMaps = []
            }
            return row()
                .wFull()
                .child(el().w(2.0).hFull().radius(1.0).fill(s.quoteRuleColor))
                .child(blocks(inner, innerMaps, [], false).grow(1.0).shrink().pl(12.0))
        case .rule:
            return el().wFull().h(0.5).fill(s.ruleColor)
        }
    }
}

private func itemLabel(_ blocks: [MarkdownBlock]) -> String {
    var out = ""
    for b in blocks {
        let t: String
        switch b {
        case .para(let inl), .heading(_, let inl):
            t = removeSubstring(inl.text, PAD)
        case .code(let s), .diff(let s), .mermaid(let s):
            t = s
        default:
            continue
        }
        if !t.isEmpty {
            if !out.isEmpty {
                out.append("\n")
            }
            out.append(t)
        }
    }
    return out
}

private func removeSubstring(_ s: String, _ target: String) -> String {
    guard !target.isEmpty, s.contains(target) else { return s }
    let sBytes = Array(s.utf8)
    let tBytes = Array(target.utf8)
    var out: [UInt8] = []
    out.reserveCapacity(sBytes.count)
    var i = 0
    while i < sBytes.count {
        if i + tBytes.count <= sBytes.count && sBytes[i..<(i + tBytes.count)].elementsEqual(tBytes) {
            i += tBytes.count
        } else {
            out.append(sBytes[i])
            i += 1
        }
    }
    return String(decoding: out, as: UTF8.self)
}
