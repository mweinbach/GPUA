// Swift-only: Unified Shadcn-style UI ornaments across GPUI and Rune (ADR-0015).

import GPUI
import Rune
import RuneKit
import RuneKnobs
import RuneMermaid

// MARK: - UTF-8 Byte-Slice Helpers for Syntax & Inline Spans

private struct LineByteRange {
    var lineNumber: Int
    var byteRange: Range<Int>
    var text: String
}

private func splitLinesWithByteRanges(_ source: String) -> [LineByteRange] {
    let bytes = Array(source.utf8)
    var out: [LineByteRange] = []
    var start = 0
    var lineNum = 1
    var i = 0
    while i < bytes.count {
        if bytes[i] == 0x0A {
            let end = (i > start && bytes[i - 1] == 0x0D) ? (i - 1) : i
            let slice = String(decoding: bytes[start..<end], as: UTF8.self)
            out.append(LineByteRange(lineNumber: lineNum, byteRange: start..<end, text: slice))
            lineNum += 1
            start = i + 1
        }
        i += 1
    }
    if start <= bytes.count {
        let end = (bytes.count > start && bytes[bytes.count - 1] == 0x0D) ? (bytes.count - 1) : bytes.count
        if start < end || out.isEmpty {
            let slice = String(decoding: bytes[start..<end], as: UTF8.self)
            out.append(LineByteRange(lineNumber: lineNum, byteRange: start..<end, text: slice))
        }
    }
    return out
}

private func sliceUTF8(_ bytes: [UInt8], _ range: Range<Int>) -> String {
    let lo = Swift.max(0, Swift.min(range.lowerBound, bytes.count))
    let hi = Swift.max(lo, Swift.min(range.upperBound, bytes.count))
    return String(decoding: bytes[lo..<hi], as: UTF8.self)
}

// MARK: - UICodeBlock (13-Language Syntax Highlighted Code Card)

/// Shadcn-style syntax-highlighted `CodeBlock` powered by ``RuneKit/syntax`` across both ``GPUI`` and ``Rune``.
public struct UICodeBlock: GPUAOrnament {
    public var code: String
    public var language: String?
    public var filename: String?
    public var showLineNumbers: Bool
    public var highlightedLines: Set<Int>
    public var showCopyButton: Bool

    public init(
        _ code: String,
        language: String? = "swift",
        filename: String? = nil,
        showLineNumbers: Bool = true,
        highlightedLines: Set<Int> = [],
        showCopyButton: Bool = true
    ) {
        self.code = code
        self.language = language
        self.filename = filename
        self.showLineNumbers = showLineNumbers
        self.highlightedLines = highlightedLines
        self.showCopyButton = showCopyButton
    }

    public func renderGPUI(theme: OrnamentTheme) -> GPUI.AnyElement {
        let synTheme = theme.syntaxTheme()
        let highlights = RuneKit.syntax.highlight(language, code)
        let codeBytes = Array(code.utf8)
        let lines = splitLinesWithByteRanges(code)
        let codeBg = theme.appearance.isDark
            ? theme.background.mixed(with: theme.card, 0.45)
            : theme.muted.mixed(with: theme.card, 0.55)

        var card = GPUI.div()
            .flex()
            .flexCol()
            .wFull()
            .rounded(.pixels(GPUI.px(theme.radii.lg)))
            .bg(codeBg.toGPUIHsla())
            .border1()
            .borderColor(theme.border.toGPUIHsla())
            .overflowHidden()

        if filename != nil || language != nil || showCopyButton {
            var left = GPUI.div().flex().flexRow().itemsCenter().gap(.pixels(GPUI.px(8.0)))
                .child(OrnamentIcon.code.renderGPUI(sizePx: 13.5, color: theme.mutedForeground))
            if let filename {
                left = left.child(
                    GPUI.div()
                        .fontFamily(GPUI.SharedString(theme.fontMono))
                        .textSize(.pixels(GPUI.px(12.0)))
                        .fontWeight(.medium)
                        .textColor(theme.foreground.toGPUIHsla())
                        .child(filename)
                )
            }
            if let language {
                left = left.child(UIBadge(language, status: .secondary).renderGPUI(theme: theme))
            }

            var header = GPUI.div()
                .flex()
                .flexRow()
                .itemsCenter()
                .justifyBetween()
                .h(GPUI.px(36.0))
                .px(.pixels(GPUI.px(12.0)))
                .bg(theme.muted.withAlpha(0.6).toGPUIHsla())
                .borderB(.pixels(GPUI.px(1.0)))
                .borderColor(theme.border.toGPUIHsla())
                .child(left)
            if showCopyButton {
                header = header.child(
                    UIButton("Copy", variant: .ghost, size: .xs, icon: .copy).renderGPUI(theme: theme)
                )
            }
            card = card.child(header)
        }

        var linesCol = GPUI.div().flex().flexCol().py(.pixels(GPUI.px(10.0)))
        for line in lines {
            let isLit = highlightedLines.contains(line.lineNumber)
            var row = GPUI.div()
                .flex()
                .flexRow()
                .itemsCenter()
                .minH(.definite(.pixels(GPUI.px(20.0))))
                .px(.pixels(GPUI.px(12.0)))
            if isLit {
                row = row
                    .bg(theme.primary.withAlpha(theme.appearance.isDark ? 0.14 : 0.09).toGPUIHsla())
                    .borderL(.pixels(GPUI.px(2.0)))
                    .borderColor(theme.primary.toGPUIHsla())
            }
            if showLineNumbers {
                row = row.child(
                    GPUI.div()
                        .w(GPUI.px(28.0))
                        .pr(.pixels(GPUI.px(10.0)))
                        .textRight()
                        .fontFamily(GPUI.SharedString(theme.fontMono))
                        .textSize(.pixels(GPUI.px(11.5)))
                        .textColor(theme.mutedForeground.withAlpha(0.65).toGPUIHsla())
                        .flexShrink0()
                        .child("\(line.lineNumber)")
                )
            }

            var tokenRow = GPUI.div()
                .flex()
                .flexRow()
                .itemsCenter()
                .fontFamily(GPUI.SharedString(theme.fontMono))
                .textSize(.pixels(GPUI.px(12.2)))
                .lineHeight(.pixels(GPUI.px(19.0)))
                .whitespaceNowrap()

            let lo = line.byteRange.lowerBound
            let hi = line.byteRange.upperBound
            if lo == hi {
                tokenRow = tokenRow.child(" ")
            } else {
                var cursor = lo
                for (tokRange, paint) in highlights {
                    if tokRange.upperBound <= lo { continue }
                    if tokRange.lowerBound >= hi { break }
                    let s = Swift.max(tokRange.lowerBound, cursor)
                    let e = Swift.min(tokRange.upperBound, hi)
                    if s > cursor {
                        let plain = sliceUTF8(codeBytes, cursor..<s)
                        tokenRow = tokenRow.child(
                            GPUI.div()
                                .whitespaceNowrap()
                                .textColor(theme.foreground.toGPUIHsla())
                                .child(plain)
                        )
                    }
                    if e > s {
                        let tokStr = sliceUTF8(codeBytes, s..<e)
                        let tokCol = OrnamentColor(runeColor: synTheme.paint(paint))
                        tokenRow = tokenRow.child(
                            GPUI.div()
                                .whitespaceNowrap()
                                .textColor(tokCol.toGPUIHsla())
                                .child(tokStr)
                        )
                        cursor = e
                    }
                }
                if cursor < hi {
                    let rest = sliceUTF8(codeBytes, cursor..<hi)
                    tokenRow = tokenRow.child(
                        GPUI.div()
                            .whitespaceNowrap()
                            .textColor(theme.foreground.toGPUIHsla())
                            .child(rest)
                    )
                }
            }
            linesCol = linesCol.child(row.child(tokenRow))
        }
        return card.child(linesCol).intoAnyElement()
    }

    public func renderRune(theme: OrnamentTheme, layer: inout [Rune.El]) -> Rune.El {
        let synTheme = theme.syntaxTheme()
        let highlights = RuneKit.syntax.highlight(language, code)
        let lines = splitLinesWithByteRanges(code)
        let codeBg = theme.appearance.isDark
            ? theme.background.mixed(with: theme.card, 0.45)
            : theme.muted.mixed(with: theme.card, 0.55)
        let monoFont = Rune.TextStyle.new(12.2, 400.0).lh(19.0).mono()
        let numFont = Rune.TextStyle.new(11.5, 400.0).lh(19.0).mono()

        var card = Rune.col()
            .wFull()
            .radius(theme.radii.lg)
            .fill(codeBg.toRuneColor())
            .border(1.0, theme.border.toRuneColor())
            .clip()

        if filename != nil || language != nil || showCopyButton {
            var left = Rune.row().gap(8.0).centerY()
                .child(OrnamentIcon.code.renderRune(sizePx: 13.5, color: theme.mutedForeground))
            if let filename {
                left = left.child(
                    Rune.text(filename)
                        .font(Rune.TextStyle.new(12.0, 500.0).lh(16.0).mono())
                        .color(theme.foreground.toRuneColor())
                )
            }
            if let language {
                left = left.child(UIBadge(language, status: .secondary).renderRune(theme: theme, layer: &layer))
            }
            var header = Rune.row()
                .wFull()
                .h(36.0)
                .pl(12.0)
                .pr(12.0)
                .justifyBetween()
                .centerY()
                .fill(theme.muted.withAlpha(0.6).toRuneColor())
                .child(left)
            if showCopyButton {
                header = header.child(
                    UIButton("Copy", variant: .ghost, size: .xs, icon: .copy).renderRune(theme: theme, layer: &layer)
                )
            }
            card = card.child(header).child(Rune.el().wFull().h(1.0).fill(theme.border.toRuneColor()))
        }

        var linesCol = Rune.col().wFull().pt(10.0).pb(10.0)
        for line in lines {
            let isLit = highlightedLines.contains(line.lineNumber)
            let lo = line.byteRange.lowerBound
            let hi = line.byteRange.upperBound
            var lineSpans: [Rune.Span] = []
            for (tokRange, paint) in highlights {
                if tokRange.upperBound <= lo { continue }
                if tokRange.lowerBound >= hi { break }
                let s = Swift.max(tokRange.lowerBound, lo) - lo
                let e = Swift.min(tokRange.upperBound, hi) - lo
                if e > s {
                    var sp = Rune.Span.new(s, e)
                    sp.color = synTheme.paint(paint)
                    lineSpans.append(sp)
                }
            }

            var row = Rune.row().wFull().minH(20.0).pl(12.0).pr(12.0).centerY()
            if isLit {
                row = row.fill(theme.primary.withAlpha(theme.appearance.isDark ? 0.14 : 0.09).toRuneColor())
            }
            if showLineNumbers {
                row = row.child(
                    Rune.row()
                        .w(28.0)
                        .pr(10.0)
                        .justifyEnd()
                        .child(
                            Rune.text("\(line.lineNumber)")
                                .font(numFont)
                                .color(theme.mutedForeground.withAlpha(0.65).toRuneColor())
                        )
                )
            }
            let displayLine = line.text.isEmpty ? " " : line.text
            row = row.child(
                Rune.text(displayLine)
                    .font(monoFont)
                    .color(theme.foreground.toRuneColor())
                    .spans(lineSpans)
            )
            linesCol = linesCol.child(row)
        }
        return card.child(linesCol)
    }
}

// MARK: - UIDiffBlock (Myers Diff + Word-Level Changes via RuneKit)

/// Unified file diff card powered by ``RuneKit/FileDiff`` Myers diffing and word-level change spans
/// on both ``GPUI`` and ``Rune``.
public struct UIDiffBlock: GPUAOrnament {
    public var fileDiff: RuneKit.FileDiff

    public init(filename: String, old oldText: String, new newText: String) {
        self.fileDiff = RuneKit.FileDiff.fromTexts(filename, oldText, newText)
    }

    public init(patch: String) {
        self.fileDiff = RuneKit.FileDiff.parse(patch).first ?? RuneKit.FileDiff.fromTexts("patch.diff", "", "")
    }

    public init(fileDiff: RuneKit.FileDiff) {
        self.fileDiff = fileDiff
    }

    public func renderGPUI(theme: OrnamentTheme) -> GPUI.AnyElement {
        let dark = theme.appearance.isDark
        let addRowBg = theme.success.withAlpha(dark ? 0.14 : 0.10)
        let addWordBg = theme.success.withAlpha(dark ? 0.34 : 0.25)
        let addFg = dark ? OrnamentColor(hex: 0x86EFAC) : OrnamentColor(hex: 0x166534)

        let delRowBg = theme.destructive.withAlpha(dark ? 0.15 : 0.10)
        let delWordBg = theme.destructive.withAlpha(dark ? 0.36 : 0.24)
        let delFg = dark ? OrnamentColor(hex: 0xFCA5A5) : OrnamentColor(hex: 0x991B1B)

        let adds = fileDiff.additions()
        let dels = fileDiff.deletions()

        let header = GPUI.div()
            .flex()
            .flexRow()
            .itemsCenter()
            .justifyBetween()
            .h(GPUI.px(36.0))
            .px(.pixels(GPUI.px(12.0)))
            .bg(theme.muted.withAlpha(0.65).toGPUIHsla())
            .borderB(.pixels(GPUI.px(1.0)))
            .borderColor(theme.border.toGPUIHsla())
            .child(
                GPUI.div().flex().flexRow().itemsCenter().gap(.pixels(GPUI.px(8.0)))
                    .child(OrnamentIcon.gitBranch.renderGPUI(sizePx: 13.5, color: theme.primary))
                    .child(
                        GPUI.div()
                            .fontFamily(GPUI.SharedString(theme.fontMono))
                            .textSize(.pixels(GPUI.px(12.0)))
                            .fontWeight(.medium)
                            .textColor(theme.foreground.toGPUIHsla())
                            .child(fileDiff.path())
                    )
            )
            .child(
                GPUI.div().flex().flexRow().itemsCenter().gap(.pixels(GPUI.px(6.0)))
                    .child(UIBadge("+\(adds)", status: .success).renderGPUI(theme: theme))
                    .child(UIBadge("-\(dels)", status: .destructive).renderGPUI(theme: theme))
            )

        var body = GPUI.div().flex().flexCol().py(.pixels(GPUI.px(6.0)))
        for hunk in fileDiff.hunks {
            body = body.child(
                GPUI.div()
                    .flex()
                    .flexRow()
                    .itemsCenter()
                    .h(GPUI.px(22.0))
                    .px(.pixels(GPUI.px(12.0)))
                    .bg(theme.info.withAlpha(dark ? 0.10 : 0.07).toGPUIHsla())
                    .fontFamily(GPUI.SharedString(theme.fontMono))
                    .textSize(.pixels(GPUI.px(11.0)))
                    .textColor(theme.info.toGPUIHsla())
                    .child(hunk.header())
            )
            for line in hunk.lines {
                let (rowBg, wordBg, fg, sign): (OrnamentColor, OrnamentColor, OrnamentColor, String) = {
                    switch line.kind {
                    case .added:
                        return (addRowBg, addWordBg, addFg, "+")
                    case .removed:
                        return (delRowBg, delWordBg, delFg, "-")
                    case .context:
                        return (.transparent, .transparent, theme.foreground.withAlpha(0.86), " ")
                    }
                }()
                let numStr = line.new.map(String.init) ?? line.old.map(String.init) ?? ""
                var contentRow = GPUI.div()
                    .flex()
                    .flexRow()
                    .itemsCenter()
                    .fontFamily(GPUI.SharedString(theme.fontMono))
                    .textSize(.pixels(GPUI.px(12.0)))
                    .lineHeight(.pixels(GPUI.px(19.0)))
                    .whitespaceNowrap()

                let utf8 = Array(line.text.utf8)
                if line.changes.isEmpty {
                    contentRow = contentRow.child(
                        GPUI.div()
                            .whitespaceNowrap()
                            .textColor(fg.toGPUIHsla())
                            .child(line.text.isEmpty ? " " : line.text)
                    )
                } else {
                    var cur = 0
                    for ch in line.changes {
                        let s = Swift.max(ch.lowerBound, cur)
                        let e = Swift.min(ch.upperBound, utf8.count)
                        if s > cur {
                            contentRow = contentRow.child(
                                GPUI.div()
                                    .whitespaceNowrap()
                                    .textColor(fg.toGPUIHsla())
                                    .child(sliceUTF8(utf8, cur..<s))
                            )
                        }
                        if e > s {
                            contentRow = contentRow.child(
                                GPUI.div()
                                    .whitespaceNowrap()
                                    .rounded(.pixels(GPUI.px(3.0)))
                                    .bg(wordBg.toGPUIHsla())
                                    .textColor(fg.toGPUIHsla())
                                    .child(sliceUTF8(utf8, s..<e))
                            )
                            cur = e
                        }
                    }
                    if cur < utf8.count {
                        contentRow = contentRow.child(
                            GPUI.div()
                                .whitespaceNowrap()
                                .textColor(fg.toGPUIHsla())
                                .child(sliceUTF8(utf8, cur..<utf8.count))
                        )
                    }
                }

                body = body.child(
                    GPUI.div()
                        .flex()
                        .flexRow()
                        .itemsCenter()
                        .minH(.definite(.pixels(GPUI.px(20.0))))
                        .px(.pixels(GPUI.px(12.0)))
                        .bg(rowBg.toGPUIHsla())
                        .child(
                            GPUI.div()
                                .w(GPUI.px(26.0))
                                .pr(.pixels(GPUI.px(6.0)))
                                .textRight()
                                .fontFamily(GPUI.SharedString(theme.fontMono))
                                .textSize(.pixels(GPUI.px(11.0)))
                                .textColor(theme.mutedForeground.withAlpha(0.65).toGPUIHsla())
                                .flexShrink0()
                                .child(numStr)
                        )
                        .child(
                            GPUI.div()
                                .w(GPUI.px(14.0))
                                .fontFamily(GPUI.SharedString(theme.fontMono))
                                .textSize(.pixels(GPUI.px(12.0)))
                                .fontWeight(.semibold)
                                .textColor(fg.toGPUIHsla())
                                .flexShrink0()
                                .child(sign)
                        )
                        .child(contentRow)
                )
            }
        }

        return GPUI.div()
            .flex()
            .flexCol()
            .wFull()
            .rounded(.pixels(GPUI.px(theme.radii.lg)))
            .bg(theme.card.toGPUIHsla())
            .border1()
            .borderColor(theme.border.toGPUIHsla())
            .overflowHidden()
            .child(header)
            .child(body)
            .intoAnyElement()
    }

    public func renderRune(theme: OrnamentTheme, layer: inout [Rune.El]) -> Rune.El {
        let dark = theme.appearance.isDark
        let addRowBg = theme.success.withAlpha(dark ? 0.14 : 0.10)
        let addFg = dark ? OrnamentColor(hex: 0x86EFAC) : OrnamentColor(hex: 0x166534)
        let delRowBg = theme.destructive.withAlpha(dark ? 0.15 : 0.10)
        let delFg = dark ? OrnamentColor(hex: 0xFCA5A5) : OrnamentColor(hex: 0x991B1B)
        let mono = Rune.TextStyle.new(12.0, 400.0).lh(19.0).mono()

        let header = Rune.row()
            .wFull()
            .h(36.0)
            .pl(12.0)
            .pr(12.0)
            .justifyBetween()
            .centerY()
            .fill(theme.muted.withAlpha(0.65).toRuneColor())
            .child(
                Rune.row().gap(8.0).centerY()
                    .child(OrnamentIcon.gitBranch.renderRune(sizePx: 13.5, color: theme.primary))
                    .child(
                        Rune.text(fileDiff.path())
                            .font(Rune.TextStyle.new(12.0, 500.0).lh(16.0).mono())
                            .color(theme.foreground.toRuneColor())
                    )
            )
            .child(
                Rune.row().gap(6.0).centerY()
                    .child(UIBadge("+\(fileDiff.additions())", status: .success).renderRune(theme: theme, layer: &layer))
                    .child(UIBadge("-\(fileDiff.deletions())", status: .destructive).renderRune(theme: theme, layer: &layer))
            )

        var body = Rune.col().wFull().pt(6.0).pb(6.0)
        for hunk in fileDiff.hunks {
            body = body.child(
                Rune.row()
                    .wFull()
                    .h(22.0)
                    .pl(12.0)
                    .pr(12.0)
                    .centerY()
                    .fill(theme.info.withAlpha(dark ? 0.10 : 0.07).toRuneColor())
                    .child(
                        Rune.text(hunk.header())
                            .font(Rune.TextStyle.new(11.0, 400.0).lh(15.0).mono())
                            .color(theme.info.toRuneColor())
                    )
            )
            for line in hunk.lines {
                let (rowBg, fg, sign): (OrnamentColor, OrnamentColor, String) = {
                    switch line.kind {
                    case .added:
                        return (addRowBg, addFg, "+")
                    case .removed:
                        return (delRowBg, delFg, "-")
                    case .context:
                        return (.transparent, theme.foreground.withAlpha(0.86), " ")
                    }
                }()
                let numStr = line.new.map(String.init) ?? line.old.map(String.init) ?? ""
                var spans: [Rune.Span] = []
                for ch in line.changes where ch.upperBound > ch.lowerBound {
                    var sp = Rune.Span.new(ch.lowerBound, ch.upperBound)
                    sp.weight = 700.0
                    spans.append(sp)
                }
                body = body.child(
                    Rune.row()
                        .wFull()
                        .minH(20.0)
                        .pl(12.0)
                        .pr(12.0)
                        .centerY()
                        .fill(rowBg.toRuneColor())
                        .child(
                            Rune.row().w(26.0).pr(6.0).justifyEnd().child(
                                Rune.text(numStr)
                                    .font(Rune.TextStyle.new(11.0, 400.0).lh(18.0).mono())
                                    .color(theme.mutedForeground.withAlpha(0.65).toRuneColor())
                            )
                        )
                        .child(
                            Rune.row().w(14.0).child(
                                Rune.text(sign).font(mono).color(fg.toRuneColor())
                            )
                        )
                        .child(
                            Rune.text(line.text.isEmpty ? " " : line.text)
                                .font(mono)
                                .color(fg.toRuneColor())
                                .spans(spans)
                        )
                )
            }
        }

        return Rune.col()
            .wFull()
            .radius(theme.radii.lg)
            .fill(theme.card.toRuneColor())
            .border(1.0, theme.border.toRuneColor())
            .clip()
            .child(header)
            .child(Rune.el().wFull().h(1.0).fill(theme.border.toRuneColor()))
            .child(body)
    }
}

// MARK: - UIMermaidCard (17-Diagram Native Vector Engine via RuneMermaid)

/// Native vector Mermaid diagram card powered by ``RuneMermaid`` — no WebView, JavaScript, or SVG DOM.
/// Renders live interactive diagrams on ``Rune`` (`renderWithHover` / `renderStreaming`) and identical
/// GPU vector geometry + labels on ``GPUI`` (`renderScene` + `GPUI.canvas`).
public struct UIMermaidCard: GPUAOrnament {
    public var source: String
    public var title: String?
    public var maxWidthPx: Float
    public var streaming: Bool

    public init(
        _ source: String,
        title: String? = nil,
        maxWidthPx: Float = 520.0,
        streaming: Bool = false
    ) {
        self.source = source
        self.title = title
        self.maxWidthPx = maxWidthPx
        self.streaming = streaming
    }

    public func renderGPUI(theme: OrnamentTheme) -> GPUI.AnyElement {
        let diagStyle = theme.mermaidStyle(maxWidth: maxWidthPx)
        guard let scene = RuneMermaid.renderScene(source, diagStyle),
              scene.size.count >= 2,
              scene.size[0] > 0.0,
              scene.size[1] > 0.0
        else {
            return UICodeBlock(source, language: "mermaid", filename: title ?? "diagram.mmd", showCopyButton: false)
                .renderGPUI(theme: theme)
        }

        let sc = scene.scale
        let sceneW = scene.size[0]
        let sceneH = scene.size[1]
        let ops = scene.ops

        let vectorCanvas = GPUI.canvas(
            { _, _, _ in () },
            { bounds, _, window, _ in
                let ox = bounds.origin.x.value
                let oy = bounds.origin.y.value
                for op in ops {
                    switch op {
                    case let .fill(points, color):
                        guard points.count >= 3 else { continue }
                        var pb = GPUI.PathBuilder.fill()
                        let p0 = points[0]
                        pb.moveTo(GPUI.point(GPUI.px(ox + p0[0] * sc), GPUI.px(oy + p0[1] * sc)))
                        for p in points.dropFirst() {
                            pb.lineTo(GPUI.point(GPUI.px(ox + p[0] * sc), GPUI.px(oy + p[1] * sc)))
                        }
                        pb.lineTo(GPUI.point(GPUI.px(ox + p0[0] * sc), GPUI.px(oy + p0[1] * sc)))
                        if let path = try? pb.build() {
                            window.paintPath(path, color: OrnamentColor(runeColor: color).toGPUIHsla())
                        }
                    case let .stroke(points, closed, width, _, color):
                        guard points.count >= 2, width > 0.0 else { continue }
                        var pb = GPUI.PathBuilder.stroke(GPUI.px(Swift.max(1.0, width * sc)))
                        let p0 = points[0]
                        pb.moveTo(GPUI.point(GPUI.px(ox + p0[0] * sc), GPUI.px(oy + p0[1] * sc)))
                        for p in points.dropFirst() {
                            pb.lineTo(GPUI.point(GPUI.px(ox + p[0] * sc), GPUI.px(oy + p[1] * sc)))
                        }
                        if closed {
                            pb.lineTo(GPUI.point(GPUI.px(ox + p0[0] * sc), GPUI.px(oy + p0[1] * sc)))
                        }
                        if let path = try? pb.build() {
                            window.paintPath(path, color: OrnamentColor(runeColor: color).toGPUIHsla())
                        }
                    }
                }
            }
        )
        .w(GPUI.px(sceneW))
        .h(GPUI.px(sceneH))

        var stage = GPUI.div()
            .relative()
            .w(GPUI.px(sceneW))
            .h(GPUI.px(sceneH))
            .child(vectorCanvas)

        for lbl in scene.labels where lbl.at.count >= 2 && lbl.size.count >= 2 {
            let lx = lbl.at[0] * sc
            let ly = lbl.at[1] * sc
            let lw = Swift.max(lbl.size[0] * sc + 8.0, 12.0)
            let lh = Swift.max(lbl.size[1] * sc + 2.0, 12.0)
            let fPx = Swift.max(9.5, lbl.font.size * sc)
            let fg = OrnamentColor(runeColor: lbl.color).toGPUIHsla()

            var lblDiv = GPUI.div()
                .absolute()
                .left(.definite(.pixels(GPUI.px(lx - 4.0))))
                .top(.definite(.pixels(GPUI.px(ly))))
                .w(GPUI.px(lw))
                .h(GPUI.px(lh))
                .flex()
                .itemsCenter()
                .textSize(.pixels(GPUI.px(fPx)))
                .fontWeight(GPUI.FontWeight(lbl.font.weight))
                .textColor(fg)
            switch lbl.align {
            case .center:
                lblDiv = lblDiv.justifyCenter().textCenter()
            case .end:
                lblDiv = lblDiv.justifyEnd().textRight()
            default:
                lblDiv = lblDiv.justifyStart().textLeft()
            }
            if !lbl.wrap {
                lblDiv = lblDiv.whitespaceNowrap()
            }
            stage = stage.child(lblDiv.child(lbl.text))
        }

        let resolvedTitle = title ?? scene.title
        var card = GPUI.div()
            .flex()
            .flexCol()
            .rounded(.pixels(GPUI.px(theme.radii.lg)))
            .bg(theme.card.toGPUIHsla())
            .border1()
            .borderColor(theme.border.toGPUIHsla())
            .shadow(theme.gpuiCardShadows())
            .overflowHidden()

        if let resolvedTitle {
            card = card.child(
                GPUI.div()
                    .flex()
                    .flexRow()
                    .itemsCenter()
                    .justifyBetween()
                    .h(GPUI.px(36.0))
                    .px(.pixels(GPUI.px(14.0)))
                    .bg(theme.muted.withAlpha(0.55).toGPUIHsla())
                    .borderB(.pixels(GPUI.px(1.0)))
                    .borderColor(theme.border.toGPUIHsla())
                    .child(
                        GPUI.div()
                            .flex()
                            .flexRow()
                            .itemsCenter()
                            .gap(.pixels(GPUI.px(8.0)))
                            .child(OrnamentIcon.layers.renderGPUI(sizePx: 13.5, color: theme.primary))
                            .child(
                                GPUI.div()
                                    .textSize(.pixels(GPUI.px(12.5)))
                                    .fontWeight(.semibold)
                                    .textColor(theme.foreground.toGPUIHsla())
                                    .child(resolvedTitle)
                            )
                    )
                    .child(UIBadge("Mermaid", status: .secondary).renderGPUI(theme: theme))
            )
        }

        return card
            .child(
                GPUI.div()
                    .flex()
                    .itemsCenter()
                    .justifyCenter()
                    .p(GPUI.px(16.0))
                    .child(stage)
            )
            .intoAnyElement()
    }

    public func renderRune(theme: OrnamentTheme, layer: inout [Rune.El]) -> Rune.El {
        let diagStyle = theme.mermaidStyle(maxWidth: maxWidthPx)
        let hoverColor = theme.primary.toRuneColor()
        let diagramEl = streaming
            ? RuneMermaid.renderStreaming(source, diagStyle, .edges, hoverColor)
            : RuneMermaid.renderWithHover(source, diagStyle, .edges, hoverColor)
        guard let diagramEl else {
            return UICodeBlock(source, language: "mermaid", filename: title ?? "diagram.mmd", showCopyButton: false)
                .renderRune(theme: theme, layer: &layer)
        }
        var card = Rune.col()
            .wFull()
            .radius(theme.radii.lg)
            .fill(theme.card.toRuneColor())
            .border(1.0, theme.border.toRuneColor())
            .clip()
        if let title {
            let header = Rune.row()
                .wFull()
                .h(36.0)
                .pl(14.0)
                .pr(14.0)
                .justifyBetween()
                .centerY()
                .fill(theme.muted.withAlpha(0.55).toRuneColor())
                .child(
                    Rune.row().gap(8.0).centerY()
                        .child(OrnamentIcon.layers.renderRune(sizePx: 13.5, color: theme.primary))
                        .child(Rune.text(title).font(Rune.TextStyle.new(12.5, 600.0).lh(17.0)).color(theme.foreground.toRuneColor()))
                )
                .child(UIBadge("Mermaid", status: .secondary).renderRune(theme: theme, layer: &layer))
            card = card
                .child(header)
                .child(Rune.el().wFull().h(1.0).fill(theme.border.toRuneColor()))
        }
        return card.child(
            Rune.row()
                .wFull()
                .padding(16.0)
                .center()
                .child(diagramEl)
        )
    }
}

// MARK: - UIMarkdown (Streaming CommonMark + GFM Tables + Fences + Mermaid)

/// Streaming CommonMark + GFM `Markdown` ornament powered by ``RuneKit/Markdown`` and ``RuneKit/markdown/parse(_:)``.
public struct UIMarkdown: GPUAOrnament {
    public var source: String
    public var streaming: Bool

    public init(_ source: String, streaming: Bool = false) {
        self.source = source
        self.streaming = streaming
    }

    private func renderInlineGPUI(
        _ inline: RuneKit.MarkdownInline,
        fontSizePx: Float,
        defaultWeight: GPUI.FontWeight = .normal,
        theme: OrnamentTheme
    ) -> GPUI.AnyElement {
        if inline.spans.isEmpty && inline.links.isEmpty {
            return GPUI.div()
                .textSize(.pixels(GPUI.px(fontSizePx)))
                .lineHeight(.pixels(GPUI.px((fontSizePx * 1.48).rounded())))
                .fontWeight(defaultWeight)
                .textColor(theme.foreground.toGPUIHsla())
                .child(inline.text)
                .intoAnyElement()
        }

        let bytes = Array(inline.text.utf8)
        var boundaries: Set<Int> = [0, bytes.count]
        for (a, b, _) in inline.spans {
            boundaries.insert(Swift.max(0, Swift.min(a, bytes.count)))
            boundaries.insert(Swift.max(0, Swift.min(b, bytes.count)))
        }
        for (a, b, _) in inline.links {
            boundaries.insert(Swift.max(0, Swift.min(a, bytes.count)))
            boundaries.insert(Swift.max(0, Swift.min(b, bytes.count)))
        }
        let sorted = boundaries.sorted()
        var row = GPUI.div().flex().flexRow().flexWrap().itemsCenter()

        for idx in 0..<(sorted.count - 1) {
            let s = sorted[idx]
            let e = sorted[idx + 1]
            guard e > s else { continue }
            var isCode = false
            var isStrong = false
            var isEm = false
            var isStrike = false
            var isLink = false
            var skipPad = false
            for (sa, sb, st) in inline.spans where sa <= s && sb >= e {
                switch st {
                case .code: isCode = true
                case .codePad: skipPad = true
                case .strong: isStrong = true
                case .em: isEm = true
                case .strike: isStrike = true
                case .link: isLink = true
                }
            }
            for (la, lb, _) in inline.links where la <= s && lb >= e {
                isLink = true
            }
            if skipPad { continue }

            let segment = sliceUTF8(bytes, s..<e)
            var el = GPUI.div()
                .textSize(.pixels(GPUI.px(isCode ? fontSizePx * 0.90 : fontSizePx)))
                .lineHeight(.pixels(GPUI.px((fontSizePx * 1.48).rounded())))
                .fontWeight(isStrong ? .semibold : defaultWeight)
                .textColor((isLink ? theme.primary : theme.foreground).toGPUIHsla())
            if isCode {
                el = el
                    .fontFamily(GPUI.SharedString(theme.fontMono))
                    .px(.pixels(GPUI.px(5.0)))
                    .py(.pixels(GPUI.px(1.0)))
                    .rounded(.pixels(GPUI.px(theme.radii.xs)))
                    .bg(theme.muted.toGPUIHsla())
                    .border1()
                    .borderColor(theme.border.withAlpha(0.7).toGPUIHsla())
            }
            if isEm { el = el.italic() }
            if isStrike { el = el.lineThrough() }
            if isLink { el = el.underline() }
            row = row.child(el.child(segment))
        }
        return row.intoAnyElement()
    }

    private func renderBlockGPUI(_ block: RuneKit.MarkdownBlock, theme: OrnamentTheme) -> GPUI.AnyElement {
        switch block {
        case let .heading(level, inline):
            let pxSize: Float = {
                switch level {
                case 1: return 20.0
                case 2: return 17.0
                case 3: return 15.0
                default: return 13.5
                }
            }()
            return renderInlineGPUI(inline, fontSizePx: pxSize, defaultWeight: .semibold, theme: theme)

        case .para(let inline):
            return renderInlineGPUI(inline, fontSizePx: 13.2, defaultWeight: .normal, theme: theme)

        case .code(let raw):
            return UICodeBlock(raw, language: "swift", showLineNumbers: false, showCopyButton: false)
                .renderGPUI(theme: theme)

        case .diff(let patch):
            return UIDiffBlock(patch: patch).renderGPUI(theme: theme)

        case .mermaid(let mmd):
            return UIMermaidCard(mmd, maxWidthPx: 480.0, streaming: streaming).renderGPUI(theme: theme)

        case .rule:
            return GPUI.div().wFull().h(GPUI.px(1.0)).bg(theme.border.toGPUIHsla()).intoAnyElement()

        case .quote(let inner):
            var col = GPUI.div()
                .flex()
                .flexCol()
                .gap(.pixels(GPUI.px(6.0)))
                .pl(.pixels(GPUI.px(12.0)))
                .py(.pixels(GPUI.px(2.0)))
                .borderL(.pixels(GPUI.px(3.0)))
                .borderColor(theme.primary.withAlpha(0.65).toGPUIHsla())
            for b in inner {
                col = col.child(renderBlockGPUI(b, theme: theme))
            }
            return col.intoAnyElement()

        case let .list(start, items):
            var listCol = GPUI.div().flex().flexCol().gap(.pixels(GPUI.px(5.0)))
            for (idx, itemBlocks) in items.enumerated() {
                let marker = start.map { "\($0 + UInt64(idx))." } ?? "•"
                var itemCol = GPUI.div().flex().flexCol().gap(.pixels(GPUI.px(4.0))).flex1()
                for b in itemBlocks {
                    itemCol = itemCol.child(renderBlockGPUI(b, theme: theme))
                }
                listCol = listCol.child(
                    GPUI.div()
                        .flex()
                        .flexRow()
                        .itemsStart()
                        .gap(.pixels(GPUI.px(8.0)))
                        .child(
                            GPUI.div()
                                .w(GPUI.px(16.0))
                                .textSize(.pixels(GPUI.px(13.0)))
                                .fontWeight(.semibold)
                                .textColor(theme.mutedForeground.toGPUIHsla())
                                .flexShrink0()
                                .child(marker)
                        )
                        .child(itemCol)
                )
            }
            return listCol.intoAnyElement()

        case .table(let tbl):
            var tableBox = GPUI.div()
                .flex()
                .flexCol()
                .wFull()
                .rounded(.pixels(GPUI.px(theme.radii.md)))
                .border1()
                .borderColor(theme.border.toGPUIHsla())
                .overflowHidden()

            if !tbl.head.isEmpty {
                var headRow = GPUI.div()
                    .flex()
                    .flexRow()
                    .wFull()
                    .bg(theme.muted.withAlpha(0.75).toGPUIHsla())
                    .borderB(.pixels(GPUI.px(1.0)))
                    .borderColor(theme.border.toGPUIHsla())
                for cell in tbl.head {
                    headRow = headRow.child(
                        GPUI.div()
                            .flex1()
                            .px(.pixels(GPUI.px(10.0)))
                            .py(.pixels(GPUI.px(7.0)))
                            .child(renderInlineGPUI(cell, fontSizePx: 12.0, defaultWeight: .semibold, theme: theme))
                    )
                }
                tableBox = tableBox.child(headRow)
            }

            for (rIdx, rowCells) in tbl.rows.enumerated() {
                var bodyRow = GPUI.div()
                    .flex()
                    .flexRow()
                    .wFull()
                if rIdx > 0 {
                    bodyRow = bodyRow.borderT(.pixels(GPUI.px(1.0))).borderColor(theme.border.withAlpha(0.6).toGPUIHsla())
                }
                if rIdx % 2 == 1 {
                    bodyRow = bodyRow.bg(theme.muted.withAlpha(0.25).toGPUIHsla())
                }
                for colIdx in 0..<Swift.max(tbl.head.count, rowCells.count) {
                    let cell = colIdx < rowCells.count ? rowCells[colIdx] : RuneKit.MarkdownInline()
                    bodyRow = bodyRow.child(
                        GPUI.div()
                            .flex1()
                            .px(.pixels(GPUI.px(10.0)))
                            .py(.pixels(GPUI.px(6.5)))
                            .child(renderInlineGPUI(cell, fontSizePx: 12.2, defaultWeight: .normal, theme: theme))
                    )
                }
                tableBox = tableBox.child(bodyRow)
            }
            return tableBox.intoAnyElement()
        }
    }

    public func renderGPUI(theme: OrnamentTheme) -> GPUI.AnyElement {
        let effectiveSource = (!streaming && !source.hasSuffix("\n")) ? (source + "\n") : source
        let blocks = RuneKit.markdown.parse(effectiveSource)
        var root = GPUI.div().flex().flexCol().gap(.pixels(GPUI.px(10.0))).wFull()
        for b in blocks {
            root = root.child(renderBlockGPUI(b, theme: theme))
        }
        return root.intoAnyElement()
    }

    public func renderRune(theme: OrnamentTheme, layer _: inout [Rune.El]) -> Rune.El {
        var md = RuneKit.Markdown(source)
        if streaming {
            md = md.streaming(true)
        }
        return md.build(theme.runeKit())
    }
}

// MARK: - UIKnobsHUD (Live Parameter Tuning HUD via RuneKnobs)

/// Live parameter tuning HUD backed by ``RuneKnobs/Group`` definitions and knob values,
/// rendering interactive sliders, preset chips, segmented choices, and Reset/Undo/Random actions
/// on both ``Rune`` (via ``RuneKnobs/inline(_:_:_:_:_:)``) and ``GPUI``.
public struct UIKnobsHUD: GPUAOrnament {
    public var title: String
    public var groups: [RuneKnobs.Group]
    public var values: [String: Float]
    public var activeGroupName: String?
    public var widthPx: Float

    public init(
        title: String = "Live Parameters",
        groups: [RuneKnobs.Group],
        values: [String: Float] = [:],
        activeGroupName: String? = nil,
        widthPx: Float = 300.0
    ) {
        self.title = title
        self.groups = groups
        self.values = values
        self.activeGroupName = activeGroupName
        self.widthPx = widthPx
    }

    public init(
        title: String = "Live Parameters",
        knobs: RuneKnobs.Knobs,
        groups: [RuneKnobs.Group],
        widthPx: Float = 300.0
    ) {
        self.title = title
        self.groups = groups
        self.values = knobs.values
        self.activeGroupName = knobs.group
        self.widthPx = widthPx
    }

    private func makeKnobsSnapshot() -> RuneKnobs.Knobs {
        var k = RuneKnobs.Knobs()
        k.values = values
        k.group = activeGroupName ?? groups.first?.name
        return k
    }

    public func renderGPUI(theme: OrnamentTheme) -> GPUI.AnyElement {
        let snap = makeKnobsSnapshot()
        let selectedGroup = snap.current(groups) ?? groups.first

        let header = GPUI.div()
            .flex()
            .flexRow()
            .itemsCenter()
            .justifyBetween()
            .px(.pixels(GPUI.px(12.0)))
            .py(.pixels(GPUI.px(10.0)))
            .bg(theme.muted.withAlpha(0.55).toGPUIHsla())
            .borderB(.pixels(GPUI.px(1.0)))
            .borderColor(theme.border.toGPUIHsla())
            .child(
                GPUI.div().flex().flexRow().itemsCenter().gap(.pixels(GPUI.px(7.0)))
                    .child(OrnamentIcon.sliders.renderGPUI(sizePx: 14.0, color: theme.primary))
                    .child(
                        GPUI.div()
                            .textSize(.pixels(GPUI.px(12.5)))
                            .fontWeight(.semibold)
                            .textColor(theme.foreground.toGPUIHsla())
                            .child(title)
                    )
            )
            .child(UIKbd(["⌘", "⇧", "K"], compact: true).renderGPUI(theme: theme))

        var panel = GPUI.div()
            .flex()
            .flexCol()
            .w(GPUI.px(widthPx))
            .rounded(.pixels(GPUI.px(theme.radii.lg)))
            .bg(theme.card.toGPUIHsla())
            .border1()
            .borderColor(theme.border.toGPUIHsla())
            .shadow(theme.gpuiPopoverShadows())
            .overflowHidden()
            .child(header)

        if groups.count > 1, let active = selectedGroup {
            let tabItems = groups.map { UITabItem(id: $0.name, label: $0.name) }
            panel = panel.child(
                GPUI.div()
                    .px(.pixels(GPUI.px(10.0)))
                    .pt(.pixels(GPUI.px(8.0)))
                    .child(UITabs(items: tabItems, activeId: active.name).renderGPUI(theme: theme))
            )
        }

        if let g = selectedGroup {
            if !g.presets.isEmpty {
                let activePreset = snap.active(g)
                var chips = GPUI.div()
                    .flex()
                    .flexRow()
                    .flexWrap()
                    .itemsCenter()
                    .gap(.pixels(GPUI.px(5.0)))
                    .px(.pixels(GPUI.px(12.0)))
                    .pt(.pixels(GPUI.px(10.0)))
                let allNames = [g.defaultLabel] + g.presets.map(\.name)
                for pName in allNames {
                    let isCur = pName == activePreset
                    chips = chips.child(
                        UIBadge(pName, status: isCur ? .default : .secondary).renderGPUI(theme: theme)
                    )
                }
                panel = panel.child(chips)
            }

            var rows = GPUI.div().flex().flexCol().gap(.pixels(GPUI.px(8.0))).p(GPUI.px(12.0))
            for knob in g.knobs {
                let val = snap.get(knob)
                let valStr = RuneKnobs.readout(knob, val)
                if !knob.labels.isEmpty {
                    let idx = Swift.max(0, Swift.min(Int(val.rounded()), knob.labels.count - 1))
                    let segItems = knob.labels.enumerated().map { i, lbl in
                        UITabItem(id: "\(i)", label: lbl)
                    }
                    rows = rows.child(
                        GPUI.div().flex().flexCol().gap(.pixels(GPUI.px(5.0)))
                            .child(
                                GPUI.div().flex().flexRow().itemsCenter().justifyBetween()
                                    .child(
                                        GPUI.div()
                                            .textSize(.pixels(GPUI.px(12.0)))
                                            .fontWeight(.medium)
                                            .textColor(theme.foreground.toGPUIHsla())
                                            .child(knob.title())
                                    )
                                    .child(
                                        GPUI.div()
                                            .fontFamily(GPUI.SharedString(theme.fontMono))
                                            .textSize(.pixels(GPUI.px(11.0)))
                                            .textColor(theme.mutedForeground.toGPUIHsla())
                                            .child(valStr)
                                    )
                            )
                            .child(UITabs(items: segItems, activeId: "\(idx)").renderGPUI(theme: theme))
                    )
                } else {
                    let span = Swift.max(knob.max - knob.min, 1e-6)
                    let frac = Swift.min(Swift.max((val - knob.min) / span, 0.0), 1.0)
                    let trackW = widthPx - 24.0
                    let fillW = Swift.max(6.0, trackW * frac)

                    rows = rows.child(
                        GPUI.div()
                            .flex()
                            .flexCol()
                            .gap(.pixels(GPUI.px(5.0)))
                            .child(
                                GPUI.div()
                                    .flex()
                                    .flexRow()
                                    .itemsCenter()
                                    .justifyBetween()
                                    .child(
                                        GPUI.div()
                                            .textSize(.pixels(GPUI.px(12.0)))
                                            .fontWeight(.medium)
                                            .textColor(theme.foreground.toGPUIHsla())
                                            .child(knob.title())
                                    )
                                    .child(
                                        GPUI.div()
                                            .fontFamily(GPUI.SharedString(theme.fontMono))
                                            .textSize(.pixels(GPUI.px(11.5)))
                                            .textColor(theme.primary.toGPUIHsla())
                                            .child(valStr)
                                    )
                            )
                            .child(
                                GPUI.div()
                                    .relative()
                                    .wFull()
                                    .h(GPUI.px(8.0))
                                    .roundedFull()
                                    .bg(theme.muted.toGPUIHsla())
                                    .border1()
                                    .borderColor(theme.border.withAlpha(0.6).toGPUIHsla())
                                    .overflowHidden()
                                    .child(
                                        GPUI.div()
                                            .hFull()
                                            .w(GPUI.px(fillW))
                                            .roundedFull()
                                            .bg(theme.primary.toGPUIHsla())
                                    )
                            )
                    )
                }
            }
            panel = panel.child(rows)
        }

        let footer = GPUI.div()
            .flex()
            .flexRow()
            .itemsCenter()
            .justifyBetween()
            .px(.pixels(GPUI.px(10.0)))
            .py(.pixels(GPUI.px(8.0)))
            .bg(theme.muted.withAlpha(0.45).toGPUIHsla())
            .borderT(.pixels(GPUI.px(1.0)))
            .borderColor(theme.border.toGPUIHsla())
            .child(UIButton("Reset", variant: .ghost, size: .xs).renderGPUI(theme: theme))
            .child(
                GPUI.div().flex().flexRow().itemsCenter().gap(.pixels(GPUI.px(4.0)))
                    .child(UIButton("Random", variant: .secondary, size: .xs, icon: .sparkles).renderGPUI(theme: theme))
                    .child(UIButton("Copy", variant: .outline, size: .xs, icon: .copy).renderGPUI(theme: theme))
            )

        return panel.child(footer).intoAnyElement()
    }

    public func renderRune(theme: OrnamentTheme, layer _: inout [Rune.El]) -> Rune.El {
        let snap = makeKnobsSnapshot()
        let lens = RuneKnobs.KnobsAccess<RuneKnobs.Knobs> { state, body in
            body(&state)
        }
        return Rune.col()
            .w(widthPx)
            .child(RuneKnobs.inline(snap, groups, theme.knobsStyle(), lens, false))
    }
}
