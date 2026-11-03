// Tests ported from: crates/rune/src/runtime/virtual_selection_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private let virtualRowCount = 55
private let virtualRowHeight: Float = 56.0

private func expectedRowText(_ i: Int) -> String {
    if i % 5 == 2 {
        return String(format: "Row %02d header\nleft-%02d\nright-%02d", i, i, i)
    } else {
        return String(format: "Row %02d header\nMessage body for virtual row %02d with words to select.", i, i)
    }
}

private func buildRowEl(_ i: Int) -> El {
    let style = TextStyle.new(14.0, 400.0).lh(20.0)
    let head = rtSelectable(
        text(String(format: "Row %02d header", i)).key("head").font(style).wFull(),
        true
    )
    let body: El
    if i % 5 == 2 {
        body = row().key("cells").wFull().children([
            rtSelectable(text(String(format: "left-%02d", i)).key("c0").font(style).w(160.0), true),
            rtSelectable(text(String(format: "right-%02d", i)).key("c1").font(style).w(160.0), true),
        ])
    } else {
        body = rtSelectable(
            text(String(format: "Message body for virtual row %02d with words to select.", i))
                .key("body")
                .font(style)
                .wFull(),
            true
        )
    }
    return col().key("r\(i)").wFull().h(virtualRowHeight).pad(6.0).gap(4.0).children([head, body])
}

@Suite("RuntimeVirtualSelectionTests")
struct RuntimeVirtualSelectionTests {
    @Test("Cmd+A and Tx.selectAllText select every row in a scrollable timeline group")
    func cmdAAndSelectAllTextCopyEveryRow() {
        let rt = Runtime.new(virtualRowCount, { count, _ in
            let rows = (0..<count).map { buildRowEl($0) }
            return col().wFull().hFull().child(
                col().key("scroll").wFull().grow(1.0).scroll(ScrollSpec(stickBottom: false)).child(
                    rtSelectionGroup(col().key("timeline").wFull().growth(GrowthSpec()), true)
                        .children(rows)
                )
            )
        }, (1280.0, 420.0), Env.new(true, 2.0))

        _ = rt.frame(0.0)
        rtStepFrames(rt, 20)

        let expected = (0..<virtualRowCount).map(expectedRowText).joined(separator: "\n")

        // 1. Cmd+A selects from the first row to the last row and Cmd+C copies all 55 rows
        _ = rt.keyDown(KeyEvent(key: .command(Character("a")), mods: Mods(cmd: true)))
        _ = rt.frame(1.0 / 60.0)
        #expect(rt.elements().first { $0.path.hasSuffix("r0/head") }?.selected == "Row 00 header")
        #expect(rt.selectedText() == expected)

        _ = rt.keyDown(KeyEvent(key: .command(Character("c")), mods: Mods(cmd: true)))
        #expect(rt.takeClipboardWrite() == .text(expected))

        // Clearing selection removes highlights
        rt.update { _, tx in tx.clearTextSelection() }
        _ = rt.frame(1.0 / 60.0)
        #expect(rt.selectedText() == nil)

        // 2. Scrolled down into the middle, Tx.selectAllText("timeline") still selects all 55 rows
        for _ in 0..<6 {
            rt.wheel(640.0, 210.0, 0.0, -160.0)
            _ = rt.frame(1.0 / 60.0)
        }
        rtStepFrames(rt, 30)
        rt.update { _, tx in tx.selectAllText("timeline") }
        _ = rt.frame(1.0 / 60.0)
        #expect(rt.selectedText() == expected)
    }

    @Test("VirtualSelectionStore preserves anchor and focus across unmounted middle rows in order")
    func virtualSelectionStoreCopiesAcrossUnmountedRows() {
        var store = VirtualSelectionStore()
        for i in 0..<virtualRowCount {
            let txt = expectedRowText(i)
            store.record(
                VirtualTextEntry(
                    scrollKey: "scroll",
                    itemIndex: i,
                    itemKey: "r\(i)",
                    path: "#0/scroll/timeline/r\(i)",
                    text: txt
                )
            )
        }

        // Anchor inside row 3 starting at `"virtual row 03..."` and focus inside row 40 ending after `"row 40"`
        let row3 = expectedRowText(3)
        let startOffset = row3.utf8.count - "virtual row 03 with words to select.".utf8.count
        let row40Prefix = "Row 40 header\nMessage body for virtual row 40"
        store.anchor = VirtualSelectionAnchor(
            scrollKey: "scroll",
            itemIndex: 3,
            itemKey: "r3",
            byteOffset: startOffset
        )
        store.focus = VirtualSelectionAnchor(
            scrollKey: "scroll",
            itemIndex: 40,
            itemKey: "r40",
            byteOffset: row40Prefix.utf8.count
        )

        let items = store.selectedItems(for: "scroll")
        #expect(items.count == 38)
        #expect(items.first?.text == "virtual row 03 with words to select.")
        #expect(!items.first!.isWhole())
        #expect(items[1].isWhole())
        #expect(items.last?.text == row40Prefix)
        #expect(!items.last!.isWhole())

        var expectedParts = ["virtual row 03 with words to select."]
        for i in 4..<40 {
            expectedParts.append(expectedRowText(i))
        }
        expectedParts.append(row40Prefix)
        #expect(items.map(\.text).joined(separator: "\n") == expectedParts.joined(separator: "\n"))
    }

    @Test("Uniform and variable virtual window ranges clamp scroll offsets and include overscan")
    func uniformAndVariableVirtualWindowsTrackScroll() {
        let topWin = computeUniformVirtualWindow(
            itemCount: 55,
            rowHeight: 56.0,
            scrollOffset: 0.0,
            viewportHeight: 420.0,
            overscan: 3
        )
        #expect(topWin.start == 0)
        #expect(topWin.end > 8 && topWin.end <= 16)
        #expect(topWin.leadSpacer == 0.0)
        #expect(topWin.totalExtent == 55.0 * 56.0)

        let midWin = computeUniformVirtualWindow(
            itemCount: 55,
            rowHeight: 56.0,
            scrollOffset: 1000.0,
            viewportHeight: 420.0,
            overscan: 3
        )
        #expect(midWin.start > 0)
        #expect(midWin.end < 55)
        #expect(midWin.leadSpacer > 0.0)
        #expect(midWin.trailSpacer > 0.0)

        let heights = (0..<30).map { $0 % 2 == 0 ? Float(36.0) : Float(77.0) }
        let varWin = computeVariableVirtualWindow(
            heights: heights,
            gap: 4.0,
            scrollOffset: 500.0,
            viewportHeight: 300.0,
            overscan: 2
        )
        #expect(varWin.start > 0 && varWin.end < 30)
        #expect(abs((varWin.leadSpacer + varWin.trailSpacer) - varWin.totalExtent) < varWin.totalExtent)
    }

    @Test("Programmatic Tx.selectText highlights target row across scroll round-trip")
    func txSelectTextSurvivesScrollRoundTrip() {
        let rt = Runtime.new(virtualRowCount, { count, _ in
            let rows = (0..<count).map { buildRowEl($0) }
            return col().wFull().hFull().child(
                col().key("scroll").wFull().grow(1.0).scroll(ScrollSpec(stickBottom: false)).child(
                    rtSelectionGroup(col().key("timeline").wFull(), true).children(rows)
                )
            )
        }, (1280.0, 420.0), Env.new(true, 2.0))

        _ = rt.frame(0.0)
        rt.update { _, tx in
            tx.selectText("r45/body", 0..<12)
        }
        _ = rt.frame(1.0 / 60.0)
        #expect(rt.selectedText() == "Message body")
        #expect(rt.scrollOffset("scroll") == 0.0)

        // Scroll down to row 45 and back up: highlight remains intact
        for _ in 0..<20 {
            rt.wheel(640.0, 210.0, 0.0, -200.0)
            _ = rt.frame(1.0 / 60.0)
        }
        rtStepFrames(rt, 30)
        #expect(rt.elements().first { $0.path.hasSuffix("r45/body") }?.selected == "Message body")
    }
}
