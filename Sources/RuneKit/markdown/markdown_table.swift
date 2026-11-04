// Ported from: crates/rune-kit/src/markdown/table.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! GFM tables: columns sized from their content with `Rune.measure`, then shared out by
//! flex growth so every row's cells line up without a grid.

#if !os(WASI)
import Foundation
#endif
import Rune

/// Estimated bytes of column widths kept beyond the tables on screen.
private let WIDTHS_BYTES: Int = 1 << 20

/// A setter's points: zero when negative, NaN or infinite, so a width never goes non-finite.
private func pts(_ x: Float) -> Float {
    x.isFinite ? max(x, 0.0) : 0.0
}

/// Per column: the content's width on one line and its longest word (capped), padding included.
final class TableColumns: Sendable {
    let natural: [Float]
    let min: [Float]

    init(natural: [Float], min: [Float]) {
        self.natural = natural
        self.min = min
    }
}

private final class TableWidthsCacheBox {
    var budget: Budget<UInt64, TableColumns> = Budget(WIDTHS_BYTES)
}

#if os(WASI)
// PORT NOTE: WASI (`wasm32-unknown-wasip1`) is single-threaded, matching Rust `thread_local!` in `markdown/table.rs`.
nonisolated(unsafe) private let wasiTableWidths = TableWidthsCacheBox()
#else
private let tableWidthsThreadKey = "gpua.runekit.markdown.tableWidths"
#endif

private func withTableWidths<R>(_ body: (inout Budget<UInt64, TableColumns>) -> R) -> R {
    #if os(WASI)
    return body(&wasiTableWidths.budget)
    #else
    let dict = Thread.current.threadDictionary
    let box: TableWidthsCacheBox
    if let existing = dict[tableWidthsThreadKey] as? TableWidthsCacheBox {
        box = existing
    } else {
        let created = TableWidthsCacheBox()
        dict[tableWidthsThreadKey] = created
        box = created
    }
    return body(&box.budget)
    #endif
}

private struct FontCacheKey: Hashable {
    var sizeBits: UInt32
    var weightBits: UInt32
    var lineHeightBits: UInt32
    var trackingBits: UInt32
    var familyDesc: String
    var variations: String
    var features: String
    var italic: Bool

    init(_ f: TextStyle) {
        self.sizeBits = f.size.bitPattern
        self.weightBits = f.weight.bitPattern
        self.lineHeightBits = f.lineHeight.bitPattern
        self.trackingBits = f.tracking.bitPattern
        self.familyDesc = "\(f.family)"
        self.variations = f.variations
        self.features = f.features
        self.italic = f.italic
    }
}

/// `features` with tabular figures on.
// PORT NOTE: Swift `TextStyle.features` is a value-typed `String` (not `&'static str`), so no string leaking is needed.
private func withTnum(_ features: String) -> String {
    if features.isEmpty {
        return "'tnum' 1"
    }
    if features.contains("tnum") {
        return features
    }
    return "\(features), 'tnum' 1"
}

extension MarkdownStyle {
    /// A table's outline and row rules, and its header row's fill.
    public func table(_ border: Color, _ headerFill: Color) -> MarkdownStyle {
        var copy = self
        copy.tableOutlineColor = border
        copy.tableFrameSpec = nil
        copy.tableRuleColor = border
        copy.tableHeadFill = headerFill
        return copy
    }

    /// The rounded outline around a table, or `nil` for none; a rule then runs under the
    /// last row too, as on a web page. A ``tableFrame(_:_:_:)`` draws in its place.
    public func tableOutline(_ outline: Color?) -> MarkdownStyle {
        var copy = self
        copy.tableOutlineColor = outline
        copy.tableFrameSpec = nil
        return copy
    }

    /// The hairline under the header and between rows.
    public func tableRules(_ c: Color) -> MarkdownStyle {
        var copy = self
        copy.tableRuleColor = c
        return copy
    }

    /// The header row's text colour (the body text colour by default).
    public func tableHeaderText(_ c: Color) -> MarkdownStyle {
        var copy = self
        copy.tableHeadText = c
        return copy
    }

    /// The header row's fill alone (``table(_:_:)`` sets it with the border).
    public func tableHeaderFill(_ c: Color) -> MarkdownStyle {
        var copy = self
        copy.tableHeadFill = c
        return copy
    }

    /// The hairline under the header row, when it should stand out from the row rules.
    public func tableHeaderRule(_ c: Color) -> MarkdownStyle {
        var copy = self
        copy.tableHeadRule = c
        return copy
    }

    /// The header row's weight (the strong weight by default).
    public func tableHeaderWeight(_ w: Float) -> MarkdownStyle {
        var copy = self
        copy.tableHeadWeight = w
        return copy
    }

    /// Whether cells set figures at one width (OpenType `tnum`) so numbers line up down a
    /// column. On by default; only digits change.
    public func tableTabularFigures(_ on: Bool) -> MarkdownStyle {
        var copy = self
        copy.tableTabular = on
        return copy
    }

    /// The narrowest a column shrinks to when its longest word is wider (120 points by default).
    public func tableMinColumn(_ points: Float) -> MarkdownStyle {
        var copy = self
        copy.tableMinColumnPt = pts(points)
        return copy
    }

    /// The cells' font (the body font by default).
    public func tableFont(_ f: TextStyle) -> MarkdownStyle {
        var copy = self
        copy.tableFontStyle = f
        return copy
    }

    /// Each cell's padding: `x` on the left and right, `y` above and below (10 and 6 points by
    /// default).
    public func tableCellPadding(_ x: Float, _ y: Float) -> MarkdownStyle {
        var copy = self
        copy.tablePad = [pts(x), pts(y)]
        return copy
    }

    /// Whether the first column starts at the table's left edge, with no left padding.
    public func tableFlushLeft(_ on: Bool) -> MarkdownStyle {
        var copy = self
        copy.tableFlushLeftFlag = on
        return copy
    }

    /// Tables that read like a data ``Table`` beside them: its cell font, cell padding, rules
    /// and muted header text.
    public func tableLike(_ t: TableStyle) -> MarkdownStyle {
        var copy = self
        copy.tableFontStyle = t.font
        copy.tablePad = [t.cellPad, max((t.rowHeight - t.font.lineHeight) / 2.0, 0.0)]
        copy.tableRuleColor = t.rule
        copy.tableHeadText = t.headerText
        copy.tableOutlineColor = copy.tableOutlineColor.map { _ in t.rule }
        copy.tableFrameSpec = nil
        copy.tableBodySpec = nil
        copy.tableHeadPad = nil
        return copy
    }

    /// A rounded frame around the table in place of the outline: filled `fill`, with a
    /// half-point `ring` drawn inside its edge and `pad` points between the edge and the rows.
    public func tableFrame(_ fill: Color, _ ring: Color, _ pad: Float) -> MarkdownStyle {
        var copy = self
        copy.tableFrameSpec = TableFrame(fill: fill, ring: ring, pad: pts(pad))
        return copy
    }

    /// The body rows on a card of their own inside the frame: filled `fill`, rounded `radius`,
    /// with `shadows` under it.
    public func tableBody(_ fill: Color, _ radius: Float, _ shadows: [Shadow]) -> MarkdownStyle {
        var copy = self
        copy.tableBodySpec = TableBody(fill: fill, radius: pts(radius), shadows: shadows)
        return copy
    }

    /// The header cells' padding, `x` on the left and right and `y` above and below.
    public func tableHeaderPad(_ x: Float, _ y: Float) -> MarkdownStyle {
        var copy = self
        copy.tableHeadPad = [pts(x), pts(y)]
        return copy
    }

    /// Whether a table fills the text's width (a web table's `width: 100%`).
    public func tableFullWidth(_ on: Bool) -> MarkdownStyle {
        var copy = self
        copy.tableFullWidthFlag = on
        return copy
    }

    /// The space above and below a table (12 and 16 points by default).
    public func tableMargin(_ top: Float, _ bottom: Float) -> MarkdownStyle {
        var copy = self
        copy.tableMarginPt = [pts(top), pts(bottom)]
        return copy
    }

    /// A data table on a card, from the kit's tokens.
    public func tableCard(_ k: Kit) -> MarkdownStyle {
        let c = k.c
        let raised = k.shadowLayers(k.elevation.raised)
        var font = k.ty.uiCompact
        font.weight = 440.0
        font.tracking = -0.04
        return self
            .tableFrame(c.layer01, c.borderMuted, 2.0)
            .tableBody(c.bgBase, 4.0, raised)
            .tableRules(c.borderMuted)
            .tableHeaderText(c.textFaint)
            .tableHeaderWeight(500.0)
            .tableHeaderPad(12.0, 8.0)
            .tableCellPadding(12.0, 10.0)
            .tableFont(font)
            .tableTabularFigures(true)
            .tableFullWidth(true)
            .tableMargin(16.0, 16.0)
    }
}

extension Renderer {
    private func headFont() -> TextStyle {
        var base = s.tableFontStyle ?? s.bodyStyle
        base.weight = s.tableHeadWeight ?? s.strongWeightValue
        return cellFont(base)
    }

    private func bodyFont() -> TextStyle {
        cellFont(s.tableFontStyle ?? s.bodyStyle)
    }

    /// Column `j`'s left padding in a row padded `x` on either side.
    private func padLeft(_ j: Int, _ x: Float) -> Float {
        (j == 0 && s.tableFlushLeftFlag) ? 0.0 : x
    }

    private func headPad() -> [Float] {
        s.tableHeadPad ?? s.tablePad
    }

    private func cellFont(_ f: TextStyle) -> TextStyle {
        guard s.tableTabular else { return f }
        var copy = f
        copy.features = withTnum(f.features)
        return copy
    }

    func table(_ t: MarkdownTable, _ headMaps: [SpanMap], _ rowMaps: [[SpanMap]]) -> El {
        let n = max(t.align.count, max(t.head.count, 1))
        let cols = columns(t, n)
        let total = cols.natural.reduce(Float(0.0), +)

        let ring: Color?
        let fill: Color?
        let inset: Float
        if let f = s.tableFrameSpec {
            ring = f.ring
            fill = f.fill
            inset = max(f.pad, 0.5)
        } else if let outline = s.tableOutlineColor {
            ring = outline
            fill = nil
            inset = 0.5
        } else {
            ring = nil
            fill = nil
            inset = 0.0
        }

        var frame = col().wFull().padding(inset)
        if !s.tableFullWidthFlag {
            frame = frame.maxW(total + 2.0 * inset)
        }
        if let fill {
            frame = frame.radius(6.0).fill(fill)
        }

        let headRow = tableRow(t.head, headMaps, t, cols, headFont(), s.tableHeadText, headPad()).key("th")
        func rule(_ key: String) -> El {
            el().key(key).wFull().h(0.5).fill(s.tableRuleColor)
        }
        func rowAt(_ i: Int, _ cells: [MarkdownInline]) -> El {
            let rmap = i < rowMaps.count ? rowMaps[i] : []
            return tableRow(cells, rmap, t, cols, bodyFont(), s.textColor, s.tablePad).key("r\(i)")
        }

        if let body = s.tableBodySpec {
            if let ring {
                frame = frame.radius(6.0).border(0.5, ring)
            }
            let head: El
            if ring != nil || fill != nil {
                let r = max(6.0 - inset, 0.0)
                head = headRow.clipCorners([r, r, 0.0, 0.0])
            } else {
                head = headRow.clipSoft(0.0)
            }
            frame = frame.child(head)
            if !t.rows.isEmpty {
                var rowsEl = col().key("tbc").wFull().clipRounded(body.radius)
                for (i, cells) in t.rows.enumerated() {
                    if i > 0 {
                        rowsEl = rowsEl.child(rule("s\(i)"))
                    }
                    rowsEl = rowsEl.child(rowAt(i, cells))
                }
                var card = col().key("tb").wFull().radius(body.radius).fill(body.fill)
                for sh in body.shadows {
                    card = card.boxShadow(sh)
                }
                frame = frame.child(card.child(rowsEl))
            }
        } else {
            if let ring {
                frame = frame.radius(6.0).border(0.5, ring).clipRounded(6.0)
            } else {
                frame = frame.clipSoft(0.0)
            }
            var head = headRow.fill(s.tableHeadFill)
            if ring != nil {
                let r = max(6.0 - inset, 0.0)
                let b: Float = t.rows.isEmpty ? r : 0.0
                head = head.clipCorners([r, r, b, b])
            }
            frame = frame.child(head)
            for (i, cells) in t.rows.enumerated() {
                var sep = rule("s\(i)")
                if i == 0, let hr = s.tableHeadRule {
                    sep = sep.fill(hr)
                }
                frame = frame.child(sep).child(rowAt(i, cells))
            }
            if ring == nil {
                var end = rule("s-end")
                if t.rows.isEmpty, let hr = s.tableHeadRule {
                    end = end.fill(hr)
                }
                frame = frame.child(end)
            }
        }

        if scrollWide {
            let sizedFrame = s.tableFullWidthFlag
                ? frame.maxW(total + 2.0 * inset)
                : frame.w(total + 2.0 * inset)
            return col().key("scroll").wFull().scrollX().child(sizedFrame)
        }
        return frame
    }

    private func tableRow(
        _ cells: [MarkdownInline],
        _ maps: [SpanMap],
        _ t: MarkdownTable,
        _ cols: TableColumns,
        _ font: TextStyle,
        _ color: Color,
        _ pad: [Float]
    ) -> El {
        let padX = pad[0]
        let padY = pad[1]
        let empty = MarkdownInline()
        let total = cols.natural.reduce(Float(0.0), +)
        var r = row().wFull()
        for j in 0..<cols.natural.count {
            let natural = cols.natural[j]
            let minCol = cols.min[j]
            let inl = j < cells.count ? cells[j] : empty
            let align = j < t.align.count ? t.align[j] : .start
            let content = rich(inl.text, spans(inl, font.size))
                .font(font)
                .color(color)
                .align(align)
                .reveal(reveal)
                .wFull()
            var cell = col().key("c\(j)")
            switch (s.tableFullWidthFlag && total > 0.0, scrollWide) {
            case (false, _):
                cell = cell.w(natural).shrink().minW(minCol)
            case (true, false):
                cell = cell.wFrac(natural / total).shrink().minW(minCol)
            case (true, true):
                cell = cell.wFrac(natural / total).shrink().minW(natural)
            }
            let cellMap: SpanMap? = j < maps.count ? maps[j] : nil
            r = r.child(
                cell
                    .pl(padLeft(j, padX))
                    .pr(padX)
                    .py(padY)
                    .clipSoft(0.0)
                    .child(selectInline(content, inl, cellMap))
            )
        }
        return r
    }

    /// Column widths from the header and every finished row, cached by content and font.
    private func columns(_ t: MarkdownTable, _ n: Int) -> TableColumns {
        let head = headFont()
        let body = bodyFont()
        let settled = (t.open && streaming) ? max(t.rows.count - 1, 0) : t.rows.count
        let rowsSlice = Array(t.rows[0..<settled])
        let cap = s.tableMinColumnPt
        let hp = headPad()

        var hasher = Hasher()
        hasher.combine(n)
        hasher.combine(t.head)
        hasher.combine(rowsSlice)
        hasher.combine(FontCacheKey(head))
        hasher.combine(FontCacheKey(body))
        hasher.combine(cap.bitPattern)
        hasher.combine(s.inlineCodeScale.bitPattern)
        hasher.combine(s.inlineCodeWeight.bitPattern)
        hasher.combine(s.tablePad[0].bitPattern)
        hasher.combine(s.tablePad[1].bitPattern)
        hasher.combine(hp[0].bitPattern)
        hasher.combine(hp[1].bitPattern)
        hasher.combine(s.tableFlushLeftFlag)
        if let look = linkLook {
            for inl in t.head {
                for (_, _, url) in inl.links {
                    if let (sp, _) = look(url) {
                        hasher.combine(true)
                        hasher.combine(sp.weight?.bitPattern)
                        hasher.combine(sp.size?.bitPattern)
                        hasher.combine(sp.mono)
                        hasher.combine(sp.italic)
                    } else {
                        hasher.combine(false)
                    }
                }
            }
            for row in rowsSlice {
                for inl in row {
                    for (_, _, url) in inl.links {
                        if let (sp, _) = look(url) {
                            hasher.combine(true)
                            hasher.combine(sp.weight?.bitPattern)
                            hasher.combine(sp.size?.bitPattern)
                            hasher.combine(sp.mono)
                            hasher.combine(sp.italic)
                        } else {
                            hasher.combine(false)
                        }
                    }
                }
            }
        }
        hasher.combine(Rune.fontEpoch())
        let key = UInt64(bitPattern: Int64(hasher.finalize()))

        if let hit = withTableWidths({ $0.get(key) }) {
            return hit
        }

        func measureLines(_ lines: [[MarkdownInline]], _ font: TextStyle) -> ([Float], [Float]) {
            var nat = [Float](repeating: 0.0, count: n)
            var minW = [Float](repeating: 0.0, count: n)
            for cells in lines {
                let limit = min(cells.count, n)
                for j in 0..<limit {
                    let inl = cells[j]
                    if inl.text.isEmpty {
                        continue
                    }
                    let sp = spans(inl, font.size)
                    nat[j] = max(nat[j], Rune.measure(inl.text, sp, font, nil).0)
                    minW[j] = max(minW[j], min(Rune.measure(inl.text, sp, font, 0.0).0, cap))
                }
            }
            return (nat, minW)
        }

        let (headNatural, headMin) = measureLines([t.head], head)
        let (bodyNatural, bodyMin) = measureLines(rowsSlice, body)
        let headX = hp[0]
        let bodyX = s.tablePad[0]
        let hasBody = !rowsSlice.isEmpty

        func padded(_ h: [Float], _ b: [Float]) -> [Float] {
            (0..<n).map { j in
                let hw = h[j] + padLeft(j, headX) + headX
                if hasBody {
                    return max(hw, b[j] + padLeft(j, bodyX) + bodyX)
                } else {
                    return hw
                }
            }
        }

        let cols = TableColumns(
            natural: padded(headNatural, bodyNatural),
            min: padded(headMin, bodyMin)
        )
        withTableWidths { cache in
            cache.insert(key, cols, 8 * n + 64)
        }
        return cols
    }
}
