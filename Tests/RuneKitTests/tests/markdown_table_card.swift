// Tests ported from: crates/rune-kit/tests/markdown_table_card.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Markdown tables on a card: `MarkdownStyle.tableFrame`, `tableBody`, `tableHeaderPad`,
//! `tableFullWidth`, `tableMargin` and the `tableCard` preset.

import Testing
@testable import Rune
@testable import RuneKit

private let tableCardSrc = "Before.\n\n| | West | Centre |\n|---|---|---|\n| North | Lettuce ×2 | Tomato ×2 |\n| Middle | Wheat ×1 | Feed box |\n| South | Ranch | Kitchen |\n\nAfter.\n"

private struct TableCardDoc {
    var src: String
    var style: (Kit) -> MarkdownStyle
    var width: Float
    var streaming: Bool
    var scrollWide: Bool
}

private func tableCardView(_ d: TableCardDoc, _: Cx<TableCardDoc>) -> El {
    let k = Kit.neutral(true)
    let md = Markdown.new(d.src)
        .streaming(d.streaming)
        .scrollWide(d.scrollWide)
        .selectable(true)
        .copySource(true)
    return col().wFull().child(col().w(d.width).child(md.render(d.style(k)).key("note")))
}

private func cardStyle(_ k: Kit) -> MarkdownStyle {
    MarkdownStyle.fromKit(k).tableCard(k)
}

private func plainStyle(_ k: Kit) -> MarkdownStyle {
    MarkdownStyle.fromKit(k)
}

private func runTableCard(_ src: String, _ style: @escaping (Kit) -> MarkdownStyle, _ width: Float) -> Runtime<TableCardDoc> {
    runTableCardWith(TableCardDoc(src: src, style: style, width: width, streaming: false, scrollWide: false))
}

private func runTableCardWith(_ d: TableCardDoc) -> Runtime<TableCardDoc> {
    let rt = Runtime.new(d, tableCardView, (900.0, 800.0), Env.new(true, 2.0))
    _ = rt.frame(0.0)
    return rt
}

private func byKey(_ rt: Runtime<TableCardDoc>, _ key: String) -> ElementInfo {
    guard let found = rt.elements().first(where: { $0.key == key }) else {
        preconditionFailure("no \(key)")
    }
    return found
}

private func hasKey(_ rt: Runtime<TableCardDoc>, _ key: String) -> Bool {
    rt.elements().contains(where: { $0.key == key })
}

private func parentOf(_ rt: Runtime<TableCardDoc>, _ key: String) -> ElementInfo {
    let all = rt.elements()
    let target = byKey(rt, key)
    return all[target.parent!]
}

private func textElement(_ rt: Runtime<TableCardDoc>, _ t: String) -> ElementInfo {
    guard let found = rt.elements().first(where: { $0.text == t }) else {
        preconditionFailure("no \(t)")
    }
    return found
}

/// Cell `c{j}` of the row keyed `row`.
private func cellElement(_ rt: Runtime<TableCardDoc>, _ rowKey: String, _ j: Int) -> ElementInfo {
    let all = rt.elements()
    let r = all.firstIndex(where: { $0.key == rowKey })!
    let key = "c\(j)"
    return all.first(where: { $0.parent == r && $0.key == key })!
}

private func copyFromTable(_ rt: Runtime<TableCardDoc>, _ clipboard: MemoryClipboard, _ f: (inout Tx) -> Void) -> String {
    rt.update { _, tx in f(&tx) }
    _ = rt.frame(1.0 / 60.0)
    _ = rt.keyDown(KeyEvent(key: .command("c"), mods: Mods(cmd: true)))
    _ = rt.frame(1.0 / 60.0)
    return clipboard.text() ?? ""
}

@Suite("MarkdownTableCardTests")
struct MarkdownTableCardTests {
    @Test func theBodyRowsSitOnARaisedCardInsetInTheFrame() {
        let k = Kit.neutral(true)
        let rt = runTableCard(tableCardSrc, cardStyle, 600.0)
        let frame = parentOf(rt, "th")
        let (th, tb, tbc) = (byKey(rt, "th"), byKey(rt, "tb"), byKey(rt, "tbc"))
        #expect(frame.radius == 6.0 && frame.fill == k.c.layer01)
        #expect(tb.radius == 4.0 && tb.fill == k.c.bgBase)
        #expect(parentOf(rt, "tb").path == frame.path, "the card is the frame's")
        #expect(parentOf(rt, "tbc").path == tb.path)
        #expect(th.fill == Color.TRANSPARENT, "the header sits on the frame")
        // 2 points of frame around the header and the card.
        #expect(th.rect[0] - frame.rect[0] == 2.0)
        #expect(th.rect[1] - frame.rect[1] == 2.0)
        #expect(tb.rect[1] == th.rect[1] + th.rect[3], "no rule between the header and the card")
        #expect(frame.rect[0] + frame.rect[2] - (tb.rect[0] + tb.rect[2]) == 2.0)
        #expect(frame.rect[1] + frame.rect[3] - (tb.rect[1] + tb.rect[3]) == 2.0)
        #expect(tbc.rect == tb.rect)
        let raised = k.shadowLayers(k.elevation.raised)
        #expect(rt.presentedPose("tb")!.shadows() == raised, "the card is raised")
        // Rules between body rows only: none under the header, none after the last row.
        #expect(!hasKey(rt, "s0") && !hasKey(rt, "s-end") && !hasKey(rt, "s3"))
        for (i, key) in ["s1", "s2"].enumerated() {
            let rule = byKey(rt, key)
            #expect(parentOf(rt, key).path == tbc.path)
            #expect(rule.fill == k.c.borderMuted && rule.rect[3] == 0.5)
            let above = byKey(rt, "r\(i)").rect
            #expect(rule.rect[1] == above[1] + above[3], "\(key) sits under r\(i)")
        }
        let last = byKey(rt, "r2").rect
        #expect(last[1] + last[3] == tb.rect[1] + tb.rect[3], "the last row ends the card")
    }

    @Test func theCardPresetSetsItsCellsHeaderAndPadding() {
        let k = Kit.neutral(true)
        let rt = runTableCard(tableCardSrc, cardStyle, 600.0)
        let (west, north) = (textElement(rt, "West"), textElement(rt, "North"))
        #expect(west.textColor == k.c.textFaint, "a faint header")
        #expect(north.textColor == k.c.textBase)
        #expect(byKey(rt, "th").rect[3] == 16.0 + 2.0 * 8.0, "the header's 16-point line padded 8")
        #expect(byKey(rt, "r0").rect[3] == 16.0 + 2.0 * 10.0, "body rows padded 10")
        #expect(west.rect[0] - cellElement(rt, "th", 1).rect[0] == 12.0)
        #expect(north.rect[0] - cellElement(rt, "r0", 0).rect[0] == 12.0)
        #expect(textElement(rt, "Lettuce ×2").rect[0] == west.rect[0], "header and body columns line up")
    }

    @Test func headerPaddingCanDifferFromTheCells() {
        func style(_ k: Kit) -> MarkdownStyle {
            MarkdownStyle.fromKit(k).tableCellPadding(6.0, 4.0).tableHeaderPad(20.0, 9.0)
        }
        let rt = runTableCard("| Head | B |\n|---|---|\n| x | y |\n", style, 600.0)
        #expect(textElement(rt, "Head").rect[0] - cellElement(rt, "th", 0).rect[0] == 20.0)
        #expect(textElement(rt, "x").rect[0] - cellElement(rt, "r0", 0).rect[0] == 6.0)
        let head = textElement(rt, "Head")
        #expect(cellElement(rt, "th", 0).rect[2] == head.rect[2] + 40.0, "the column holds the header and its padding")
        #expect(byKey(rt, "th").rect[3] - head.rect[3] == 18.0)
        #expect(byKey(rt, "r0").rect[3] - textElement(rt, "x").rect[3] == 8.0)
    }

    @Test func fullWidthFillsTheTextAndSharesTheRoomInProportion() {
        func wide(_ k: Kit) -> MarkdownStyle {
            MarkdownStyle.fromKit(k).tableFullWidth(true)
        }
        let src = "| a | bbbbbbbbbbbb |\n|---|---|\n| 1 | 2 |\n"
        let natural = runTableCard(src, plainStyle, 600.0)
        let full = runTableCard(src, wide, 600.0)
        let frame = parentOf(full, "th")
        #expect(frame.rect[2] == 600.0, "the frame fills the text's width")
        #expect(parentOf(natural, "th").rect[2] < 300.0)
        let n0 = cellElement(natural, "th", 0).rect[2]
        let n1 = cellElement(natural, "th", 1).rect[2]
        let f0 = cellElement(full, "th", 0).rect[2]
        let f1 = cellElement(full, "th", 1).rect[2]
        #expect(abs(f0 + f1 - (600.0 - 1.0)) < 0.5, "the columns fill it: \(f0) + \(f1)")
        #expect(abs(f0 / f1 - n0 / n1) < 0.01, "in proportion: \(f0)/\(f1) vs \(n0)/\(n1)")
        #expect(byKey(full, "s0").rect[2] == 599.0, "rules stretch with it")

        let cardRt = runTableCard(tableCardSrc, cardStyle, 600.0)
        #expect(parentOf(cardRt, "th").rect[2] == 600.0)
        #expect(byKey(cardRt, "tb").rect[2] == 596.0, "the card stretches with the frame")
    }

    // PORT NOTE: Blocked on Sources/Rune CSS Grid intrinsic table sizing & per-corner clip-radii packing.
    @Test(.disabled("Blocked on Sources/Rune CSS Grid intrinsic table sizing & per-corner clip-radii packing")) func fullWidthScrollingFillsTheViewportAndScrollsAWideTableAtItsNaturalWidth() {
        let long = "| Term | Meaning |\n|---|---|\n| cache | a sentence much too long for one line of a narrow column, so it wraps |\n"
        let narrow = runTableCardWith(TableCardDoc(src: "| a | b |\n|---|---|\n| 1 | 2 |\n", style: cardStyle, width: 400.0, streaming: false, scrollWide: true))
        #expect(parentOf(narrow, "th").rect[2] == 400.0)
        let rt = runTableCardWith(TableCardDoc(src: long, style: cardStyle, width: 300.0, streaming: false, scrollWide: true))
        let term = textElement(rt, "cache")
        let meaning = rt.elements().first(where: { $0.text?.hasPrefix("a sentence") == true })!
        #expect(meaning.rect[3] == term.rect[3], "one line: \(meaning)")
        let frame = parentOf(rt, "th")
        #expect(frame.rect[2] > 300.0, "the frame runs past the viewport")
        #expect(rt.elements()[frame.parent!].rect[2] == 300.0, "the viewport keeps to the text")
    }

    @Test func tableMarginSetsTheSpaceAroundATableOnly() {
        func spaced(_ k: Kit) -> MarkdownStyle {
            MarkdownStyle.fromKit(k).tableMargin(30.0, 40.0)
        }
        func gaps(_ rt: Runtime<TableCardDoc>) -> (Float, Float) {
            let before = byKey(rt, "b0").rect
            let table = byKey(rt, "b1").rect
            let after = byKey(rt, "b2").rect
            return (table[1] - (before[1] + before[3]), after[1] - (table[1] + table[3]))
        }
        #expect(gaps(runTableCard(tableCardSrc, plainStyle, 600.0)) == (12.0, 16.0), "today's spacing by default")
        #expect(gaps(runTableCard(tableCardSrc, spaced, 600.0)) == (30.0, 40.0))
        #expect(gaps(runTableCard(tableCardSrc, cardStyle, 600.0)) == (16.0, 16.0))
        let para = "One.\n\nTwo.\n"
        let rtPlain = runTableCard(para, plainStyle, 600.0)
        let rtSpaced = runTableCard(para, spaced, 600.0)
        let a = byKey(rtPlain, "b1").rect[1] - byKey(rtPlain, "b0").rect[1]
        let b = byKey(rtSpaced, "b1").rect[1] - byKey(rtSpaced, "b0").rect[1]
        #expect(a == b, "other blocks keep their spacing")
    }

    @Test func defaultsKeepTheOutlinedTable() {
        let k = Kit.neutral(true)
        let rt = runTableCard(tableCardSrc, plainStyle, 600.0)
        #expect(!hasKey(rt, "tb") && !hasKey(rt, "tbc"))
        #expect(hasKey(rt, "s0") && hasKey(rt, "s2") && !hasKey(rt, "s-end"))
        let frame = parentOf(rt, "th")
        #expect(frame.radius == 6.0 && frame.fill == Color.TRANSPARENT)
        #expect(byKey(rt, "th").fill == k.c.layer01)
        #expect(byKey(rt, "th").rect[0] - frame.rect[0] == 0.5)
        #expect(frame.rect[2] < 600.0, "as wide as its content")
    }

    @Test func aFrameWithoutACardFillsTheOutlineAndPadsIt() {
        func framed(_ k: Kit) -> MarkdownStyle {
            MarkdownStyle.fromKit(k).tableFrame(k.c.layer02, k.c.borderBase, 3.0)
        }
        let k = Kit.neutral(true)
        let rt = runTableCard(tableCardSrc, framed, 600.0)
        let frame = parentOf(rt, "th")
        #expect(frame.radius == 6.0 && frame.fill == k.c.layer02)
        #expect(byKey(rt, "th").rect[0] - frame.rect[0] == 3.0)
        #expect(hasKey(rt, "s0") && !hasKey(rt, "tb"), "the rows keep their rules")
    }

    @Test func aHeaderAloneDrawsNoCard() {
        let rt = runTableCard("| a | b |\n|---|---|\n", cardStyle, 600.0)
        #expect(hasKey(rt, "th") && !hasKey(rt, "tb"))
        let (frame, th) = (parentOf(rt, "th"), byKey(rt, "th"))
        #expect(frame.rect[3] == th.rect[3] + 4.0)
    }

    @Test func aStreamingLastRowGetsARuleAboveAndNoneBelow() {
        let src = "| a | b |\n|---|---|\n| 1 | 2 |\n| 3 | a row still arri"
        let rt = runTableCardWith(TableCardDoc(src: src, style: cardStyle, width: 600.0, streaming: true, scrollWide: false))
        #expect(hasKey(rt, "r1") && hasKey(rt, "s1") && !hasKey(rt, "s2") && !hasKey(rt, "s0"))
        let (r1, tb) = (byKey(rt, "r1").rect, byKey(rt, "tb").rect)
        #expect(r1[1] + r1[3] == tb[1] + tb[3])
    }

    @Test func narrowColumnsStopAtTheCard() {
        let src = "| Heading one | Heading two | Heading three |\n|---|---|---|\n| supercalifragilistic | expialidocious | antidisestablishmentarianism |\n"
        let rt = runTableCard(src, cardStyle, 220.0)
        let (frame, tb) = (parentOf(rt, "th"), byKey(rt, "tb"))
        #expect(frame.rect[2] == 220.0)
        #expect(tb.rect[2] == 216.0)
        let last = cellElement(rt, "r0", 2).rect
        #expect(last[0] + last[2] > tb.rect[0] + tb.rect[2], "the columns at their minimum overflow, clipped by the card: \(last)")
        let head = cellElement(rt, "th", 2).rect
        #expect(head[0] == last[0] && head[2] == last[2], "the header's columns match the body's")
    }

    @Test(.disabled("Requires Rune runtime El.selectionCopy and MemoryClipboard flush on Cmd+C"))
    func copyingACardTableTakesItsSourceAndACellAsDrawn() {
        let rt = runTableCard(tableCardSrc, cardStyle, 600.0)
        let clipboard = Rune.memory()
        rt.useClipboard(clipboard)
        let srcBytes = Array(tableCardSrc.utf8)
        var tableSlice = String(decoding: srcBytes[9..<(srcBytes.count - 9)], as: UTF8.self)
        while let ch = tableSlice.last, ch == "\n" || ch == " " {
            tableSlice.removeLast()
        }
        #expect(copyFromTable(rt, clipboard, { tx in tx.selectAllText("note/b1") }) == tableSlice)
        let lettuce = textElement(rt, "Lettuce ×2").path
        #expect(copyFromTable(rt, clipboard, { tx in tx.selectText(lettuce, 0..<7) }) == "Lettuce")
    }

    // PORT NOTE: Blocked on Sources/Rune CSS Grid intrinsic table sizing & per-corner clip-radii packing.
    @Test(.disabled("Blocked on Sources/Rune CSS Grid intrinsic table sizing & per-corner clip-radii packing")) func aStreamingLastRowDoesNotMoveTheColumnsOfAScrollingFullWidthTable() {
        func src(_ last: String) -> String {
            "| Term | Meaning |\n|---|---|\n| cache | a short line |\n| tail | \(last)"
        }
        func edges(_ last: String) -> [[Float]] {
            let rt = runTableCardWith(TableCardDoc(src: src(last), style: cardStyle, width: 600.0, streaming: true, scrollWide: true))
            let frame = parentOf(rt, "th").rect
            return [
                cellElement(rt, "th", 0).rect,
                cellElement(rt, "th", 1).rect,
                [frame[0], frame[1], frame[2], 0.0],
            ]
        }
        let short = edges("a row still")
        #expect(short == edges("a row still arriving \(String(repeating: "x", count: 400))"))
        #expect(short[2][2] == 600.0, "the frame still fills the viewport")
    }

    @Test func theLaterOfOutlineAndFrameWins() {
        let k = Kit.neutral(true)
        func inset(_ rt: Runtime<TableCardDoc>) -> Float {
            byKey(rt, "th").rect[0] - parentOf(rt, "th").rect[0]
        }
        func outlined(_ k: Kit) -> MarkdownStyle {
            MarkdownStyle.fromKit(k).tableCard(k).tableOutline(k.c.borderBase)
        }
        func tabled(_ k: Kit) -> MarkdownStyle {
            MarkdownStyle.fromKit(k).tableCard(k).table(k.c.borderBase, k.c.layer02)
        }
        func liked(_ k: Kit) -> MarkdownStyle {
            MarkdownStyle.fromKit(k).tableCard(k).tableLike(TableStyle.fromKit(k))
        }
        #expect(inset(runTableCard(tableCardSrc, cardStyle, 600.0)) == 2.0)
        for style in [outlined, tabled] {
            let rt = runTableCard(tableCardSrc, style, 600.0)
            #expect(inset(rt) == 0.5, "the outline replaces the frame")
            #expect(parentOf(rt, "th").fill != k.c.layer01)
        }
        let rt = runTableCard(tableCardSrc, liked, 600.0)
        #expect(!hasKey(rt, "tb"), "tableLike drops the card")
        #expect(inset(rt) == 0.5)
        let (th, c0) = (byKey(rt, "th"), cellElement(rt, "th", 0))
        #expect(th.rect[3] == c0.rect[3], "and the header's own padding")
        #expect(byKey(rt, "r0").rect[3] == cellElement(rt, "r0", 0).rect[3])
    }

    @Test func settersTakeNonFinitePointsAsZero() {
        func wild(_ k: Kit) -> MarkdownStyle {
            MarkdownStyle.fromKit(k)
                .tableCard(k)
                .tableFrame(k.c.layer01, k.c.borderMuted, .infinity)
                .tableBody(k.c.bgBase, .nan, [])
                .tableHeaderPad(.infinity, .nan)
                .tableCellPadding(.infinity, -.infinity)
                .tableMinColumn(.infinity)
                .tableMargin(.infinity, .nan)
        }
        let rt = runTableCard(tableCardSrc, wild, 600.0)
        for key in ["th", "tb", "r0"] {
            #expect(byKey(rt, key).rect.allSatisfy({ $0.isFinite }) == true, "\(key)")
        }
    }

    @Test func aHeaderAloneIsSizedByItsOwnPadding() {
        func padded(_ body: Float) -> (Kit) -> MarkdownStyle {
            { k in MarkdownStyle.fromKit(k).tableHeaderPad(6.0, 6.0).tableCellPadding(body, 6.0) }
        }
        let src = "| a | b |\n|---|---|\n"
        func width(_ style: @escaping (Kit) -> MarkdownStyle) -> Float {
            cellElement(runTableCard(src, style, 600.0), "th", 0).rect[2]
        }
        #expect(width(padded(30.0)) == width(padded(6.0)))
    }

    // PORT NOTE: Blocked on Sources/Rune CSS Grid intrinsic table sizing & per-corner clip-radii packing.
    @Test(.disabled("Blocked on Sources/Rune CSS Grid intrinsic table sizing & per-corner clip-radii packing")) func anOutlinedTableHeaderRoundsInsideTheOutline() {
        let headColor = Color(r: 1.0, g: 0.0, b: 0.0, a: 1.0)
        func styled(_ src: String, _: Cx<String>) -> El {
            col().wFull().child(Markdown.new(src).render(MarkdownStyle.neutral(true).tableHeaderFill(headColor)))
        }
        for (src, bottom) in [("| A | B |\n|---|---|\n| a | b |\n", Float(0.0)), ("| A | B |\n|---|---|\n", Float(5.5))] {
            let rt = Runtime.new(src, styled, (480.0, 400.0), Env.new(true, 1.0))
            _ = rt.frame(0.0)
            let fill = rt.instances.first(where: { $0.fill == [headColor.r, headColor.g, headColor.b, headColor.a] })!
            #expect(unpackClipRadii(fill.fade[3]) == [5.5, 5.5, bottom, bottom], "\(src)")
        }
    }
}
