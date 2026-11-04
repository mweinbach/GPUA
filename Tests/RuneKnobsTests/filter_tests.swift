// Tests ported from: crates/rune-knobs/src/filter_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Rune
import Testing
@testable import RuneKnobs

private struct FilterT {
    var knobs: Knobs
}

private let filterL = Knob.new("Left size", 0.0, 10.0, 5.0).label("Left column size")
private let filterR = Knob.new("Right pad", 0.0, 40.0, 20.0).step(1.0)
private let filterG = Knob.new("Right gap", 0.0, 40.0, 10.0).step(1.0)
private let filterGroups: [Group] = [
    Group.new("Left", "left", [filterL]),
    Group.new("Right", "right", [filterR, filterG]),
]

private func filterView(_ s: FilterT, _: Cx<FilterT>) -> El {
    let page = row()
        .key("cols")
        .wFull()
        .hFull()
        .child(col().key("left").w(300.0).hFull())
        .child(col().key("right").grow(1.0).hFull())
    return side(page, s.knobs, filterGroups, Style.dark(), \FilterT.knobs)
}

private func settle(_ rt: Runtime<FilterT>) {
    for _ in 0..<40 {
        _ = rt.frame(1.0 / 60.0)
    }
}

private func press(_ rt: Runtime<FilterT>, _ key: Key, _ mods: Mods) {
    _ = rt.keyDown(KeyEvent(key: key, mods: mods))
    settle(rt)
}

private func tap(_ rt: Runtime<FilterT>, _ key: Key) {
    press(rt, key, Mods())
}

private func typeStr(_ rt: Runtime<FilterT>, _ s: String) {
    for c in s {
        tap(rt, .text(String(c)))
    }
}

private func cmd(_ c: Character) -> (Key, Mods) {
    (.command(c), Mods(cmd: true))
}

/// An open panel with the keyboard in it, the filter editing.
private func editing() -> Runtime<FilterT> {
    var s = FilterT(knobs: Knobs())
    s.knobs.show()
    s.knobs.setFolded("Right", false)
    let rt = Runtime.new(s, filterView, (1000.0, 700.0), Env.new(true, 1.0))
    rt.bindKnobsFilter(filterGroups, \FilterT.knobs)
    settle(rt)
    let (x, y) = rt.find("knobs-filter")!
    rt.pointerMove(x, y)
    settle(rt)
    _ = rt.pointerDown(x, y)
    rt.pointerUp(x, y)
    settle(rt)
    #expect(rt.state.knobs.filtering, "a click starts filtering")
    return rt
}

/// The panel focused with the filter idle, the keyboard on Right pad.
private func idle() -> Runtime<FilterT> {
    let rt = editing()
    typeStr(rt, "right")
    tap(rt, .escape)
    return rt
}

private func caret(_ rt: Runtime<FilterT>) -> (Int, Int) {
    rt.state.knobs.edit().range()
}

private func clickPanel(_ rt: Runtime<FilterT>) {
    let (x, y) = rt.find("knobs-about")!
    rt.pointerMove(x, y)
    settle(rt)
    _ = rt.pointerDown(x, y)
    rt.pointerUp(x, y)
    settle(rt)
}

extension RuneKnobsSerializedSuites {
@Suite("RuneKnobs filter tests", .serialized)
@MainActor
struct RuneKnobsFilterTests {
    @Test("typing_filters_and_the_caret_moves_without_stepping_a_knob")
    func typingFiltersAndTheCaretMovesWithoutSteppingAKnob() {
        let rt = editing()
        #expect(rt.find("knobs-filter-input") != nil && rt.state.knobs.edit().focused)
        typeStr(rt, "rigt")
        #expect(rt.state.knobs.query == "rigt")
        tap(rt, .left)
        #expect(caret(rt) == (3, 3), "← moves the caret")
        typeStr(rt, "h")
        #expect(rt.state.knobs.query == "right")
        #expect(rt.state.knobs.at() == .knob(1, 0), "the keyboard is on the first match")
        let before = rt.state.knobs
        tap(rt, .right)
        tap(rt, .left)
        tap(rt, .left)
        #expect(rt.state.knobs.values == before.values, "← → step no knob")
        #expect(rt.state.knobs.folded == before.folded && rt.state.knobs.unfolded == before.unfolded, "and fold nothing")
        press(rt, .left, Mods(shift: true))
        #expect(caret(rt) == (2, 3), "⇧← extends the selection")
    }

    @Test("select_all_then_typing_replaces_the_query")
    func selectAllThenTypingReplacesTheQuery() {
        let rt = editing()
        typeStr(rt, "right")
        let (k, m) = cmd("a")
        press(rt, k, m)
        #expect(caret(rt) == (0, 5))
        typeStr(rt, "left")
        #expect(rt.state.knobs.query == "left")
    }

    @Test("word_and_line_deletes_and_paste_work")
    func wordAndLineDeletesAndPasteWork() {
        let rt = editing()
        typeStr(rt, "right pad")
        press(rt, .backspace, Mods(alt: true))
        #expect(rt.state.knobs.query == "right ")
        press(rt, .left, Mods(alt: true))
        #expect(caret(rt) == (0, 0), "⌥← jumps a word")
        press(rt, .right, Mods(cmd: true))
        #expect(caret(rt) == (6, 6), "⌘→ goes to the end")
        press(rt, .backspace, Mods(cmd: true))
        #expect(rt.state.knobs.query == "")
        _ = rt.paste("gap")
        settle(rt)
        #expect(rt.state.knobs.query == "gap")
        typeStr(rt, "/")
        #expect(rt.state.knobs.query == "gap/", "a / is text while editing")
        #expect(rt.state.knobs.filtering)
    }

    @Test("down_while_typing_moves_the_row")
    func downWhileTypingMovesTheRow() {
        let rt = editing()
        typeStr(rt, "right")
        #expect(rt.state.knobs.at() == .knob(1, 0))
        tap(rt, .down)
        #expect(rt.state.knobs.at() == .knob(1, 1))
        #expect(rt.state.knobs.filtering && rt.state.knobs.edit().focused, "the field keeps focus")
        tap(rt, .up)
        #expect(rt.state.knobs.at() == .knob(1, 0))
        #expect(rt.state.knobs.query == "right")
    }

    @Test("escape_and_return_stop_filtering_then_clear_then_close")
    func escapeAndReturnStopFilteringThenClearThenClose() {
        let rt = editing()
        typeStr(rt, "right")
        tap(rt, .enter)
        #expect(!rt.state.knobs.filtering && rt.state.knobs.query == "right", "Return stops and keeps the matches")
        #expect(rt.find("knobs-filter-input") == nil)
        tap(rt, .text("/"))
        #expect(rt.state.knobs.filtering, "/ starts again")
        tap(rt, .escape)
        #expect(!rt.state.knobs.filtering && rt.state.knobs.query == "right")
        tap(rt, .escape)
        #expect(rt.state.knobs.query.isEmpty && rt.state.knobs.open, "a second Esc clears")
        tap(rt, .escape)
        #expect(!rt.state.knobs.open, "a third closes")
    }

    @Test("with_the_field_idle_the_arrows_step_and_fold_again")
    func withTheFieldIdleTheArrowsStepAndFoldAgain() {
        let rt = idle()
        #expect(rt.state.knobs.at() == .knob(1, 0))
        tap(rt, .right)
        #expect(rt.state.knobs.get(filterR) == 21.0, "→ steps the knob: focus went back to the panel")
        tap(rt, .left)
        #expect(rt.state.knobs.get(filterR) == 20.0)
        rt.state.knobs.setQuery("")
        rt.invalidate()
        settle(rt)
        rt.state.knobs.setAt(.group(1), filterGroups)
        tap(rt, .left)
        #expect(rt.state.knobs.folded.contains("Right"), "← folds a header")
        tap(rt, .text("/"))
        #expect(rt.state.knobs.filtering, "/ starts when the field is idle")
    }

    @Test("clicking_away_ends_editing")
    func clickingAwayEndsEditing() {
        let rt = editing()
        typeStr(rt, "gap")
        clickPanel(rt)
        tap(rt, .right)
        #expect(!rt.state.knobs.filtering, "the arrows are the panel's again")
    }

    @Test("query_set_by_the_app_shows_in_the_field")
    func querySetByTheAppShowsInTheField() {
        let rt = editing()
        rt.state.knobs.setQuery("pad")
        rt.invalidate()
        settle(rt)
        typeStr(rt, "s")
        #expect(rt.state.knobs.query == "pads", "typing continues from the set text")
    }
}
}
