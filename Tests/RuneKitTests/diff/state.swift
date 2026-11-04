// Tests ported from: crates/rune-kit/src/diff/state.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import RuneKit

private func numberedLines(_ n: UInt32) -> String {
    (1...n).map { "line \($0)\n" }.joined()
}

private func replaceFirst(_ s: String, _ target: String, _ replacement: String) -> String {
    guard let range = s.range(of: target) else { return s }
    var copy = s
    copy.replaceSubrange(range, with: replacement)
    return copy
}

private func sampleState() -> DiffState {
    let old = numberedLines(100)
    let new = replaceFirst(old, "line 50\n", "line fifty\n")
    return DiffState.new([FileDiff.fromTexts("a.txt", old, new)])
}

private func shownRows(_ s: DiffState) -> [String] {
    s.rows.map { r in
        switch r {
        case .file:
            return "file"
        case .note:
            return "note"
        case .gap(_, let gap):
            return "gap\(gap):\(s.hidden(0, Int(gap))!)"
        case .ctx(_, let old, let new):
            return "\(old)=\(new)"
        case .line, .pair:
            let o = s.rowLine(r, .old).map(String.init) ?? "-"
            let n = s.rowLine(r, .new).map(String.init) ?? "-"
            return "\(o)|\(n)"
        }
    }
}

@Suite("DiffStateTests")
struct DiffStateTests {
    @Test func collapsedRangesExpandByTwentyAndAll() {
        var s = sampleState()
        #expect(Array(shownRows(s).prefix(3)) == ["file", "gap0:46", "47|47"])
        #expect(s.hidden(0, 1) == 47)

        s.expand(0, 0, .up)
        #expect(s.hidden(0, 0) == 26)
        let rows1 = shownRows(s)
        #expect(Array(rows1[1..<4]) == ["gap0:26", "27=27", "28=28"])

        s.expand(0, 1, .down)
        let rows2 = shownRows(s)
        let after = rows2.firstIndex(of: "53|53")!
        #expect(Array(rows2[(after + 1)..<(after + 3)]) == ["54=54", "55=55"])
        #expect(rows2.last == "gap1:27")

        s.expand(0, 1, .all)
        #expect(s.hidden(0, 1) == 0)
        #expect(shownRows(s).last == "100=100")

        s.expand(0, 0, .all)
        #expect(shownRows(s).count == 1 + 101)
        #expect(s.sideLine(0, .old, 10) == "line 10")
        #expect(s.sideLine(0, .new, 50) == "line fifty")
    }

    @Test func splitPairsChangesAndKeepsKeys() {
        let old = "a\nb\nc\nd\n"
        let new = "a\nB\nC\nX\nd\n"
        var s = DiffState.new([FileDiff.fromTexts("x", old, new)])
        let unified = shownRows(s)
        #expect(unified == ["file", "1|1", "2|-", "3|-", "-|2", "-|3", "-|4", "4|5"])
        let keyB = s.keys[2]
        s.setMode(.split)
        #expect(shownRows(s) == ["file", "1|1", "2|2", "3|3", "-|4", "4|5"])
        #expect(s.keys[2] == keyB)
    }

    @Test func lineSelectionCopiesOneSide() {
        let old = "keep\nold one\nold two\nend\n"
        let new = "keep\nnew one\nnew two\nend\n"
        var s = DiffState.new([FileDiff.fromTexts("x", old, new)])
        s.pressLine(0, LineRef.new(.new, 1))
        s.releaseLine()
        s.shift = true
        s.pressLine(0, LineRef.new(.new, 4))
        s.releaseLine()
        #expect(s.selectedText() == "keep\nnew one\nnew two\nend")

        s.setSelection(LineRange(file: 0, start: LineRef.new(.old, 3), end: LineRef.new(.old, 2)))
        #expect(s.selectedText() == "old one\nold two")

        // Pressing the one selected line clears it, unless the press drags.
        s.shift = false
        let one = LineRange.line(0, LineRef.new(.new, 1))
        s.pressLine(0, one.start)
        s.releaseLine()
        s.pressLine(0, one.start)
        #expect(s.releaseLine() == nil)

        s.pressLine(0, one.start)
        s.releaseLine()
        s.pressLine(0, one.start)
        s.dragTo(0, LineRef.new(.new, 2))
        #expect(s.releaseLine() == LineRange(file: one.file, start: one.start, end: LineRef.new(.new, 2)))
    }

    @Test func cancellingAGutterDragRestoresTheSelectionBeforeThePress() {
        var s = sampleState()
        let originals: [LineRange?] = [nil, LineRange.line(0, LineRef.new(.old, 2))]
        for original in originals {
            s.setSelection(original)
            s.pressLine(0, LineRef.new(.new, 1))
            s.dragTo(0, LineRef.new(.new, 3))
            s.cancelLine()
            #expect(s.selection() == original)
            #expect(!s.selecting && !s.unselect)
        }
    }

    @Test func copyFollowsTheHoveredSideUnlessAPressHoldsTheOther() {
        var s = sampleState()
        s.hoverText(.old, "a", true)
        #expect(s.copySide() == .old)
        // A drag that started on the old side enters a new-side cell: the old one stays held.
        s.hoverText(.new, "b", true)
        #expect(s.copySide() == .old)
        s.hoverText(.old, "a", false)
        s.hoverText(.new, "b", false)
        s.hoverText(.new, "c", true)
        #expect(s.copySide() == .new)
    }

    @Test func theVisibleFileFollowsRowsAtTheTop() {
        // Rows: f0 header 0, lines 1-2; f1 header 3, lines 4-5; f2 header 6, lines 7-8.
        let files = (0..<3).map { i in FileDiff.fromTexts("f\(i)", "a\n", "b\n") }
        var s = DiffState.new(files)
        #expect(s.rows.count == 9)

        let r0 = s.setVisibleRows(0..<6)
        #expect(r0.0 == 0 && r0.1 == false)
        #expect(s.sticky() == nil)

        // Scrolled past file 0's header: file 0 sticks at the top.
        let r1 = s.setVisibleRows(1..<7)
        #expect(r1.0 == nil && r1.1 == true)
        #expect(s.visibleFile() == 0 && s.sticky() == 0)

        // At file 1's header: file 1 is visible, its own header row is at the top.
        let r2 = s.setVisibleRows(3..<9)
        #expect(r2.0 == 1 && r2.1 == true)
        #expect(s.visibleFile() == 1 && s.sticky() == nil)

        // Past file 1's header: file 1 sticks.
        let r3 = s.setVisibleRows(4..<9)
        #expect(r3.0 == nil && r3.1 == true)
        #expect(s.visibleFile() == 1 && s.sticky() == 1)

        // A jump into file 2's lines.
        let r4 = s.setVisibleRows(7..<9)
        #expect(r4.0 == 2 && r4.1 == true)
        #expect(s.visibleFile() == 2 && s.sticky() == 2)
        #expect(s.rowFrom(7, 25.0) == 8)
    }
}
