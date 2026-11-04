// Tests ported from: crates/rune-knobs/src/tree_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Rune
import Testing
@testable import RuneKnobs

private let treeA = Knob.new("Header fade", 0.0, 10.0, 5.0).about("How tall the fade under the header is")
private let treeB = Knob.choice("Table look", ["Lines", "Zebra"], 0)
private let treeC = Knob.new("Row gap", 0.0, 8.0, 2.0)
private let treeD = Knob.new("Dock radius", 0.0, 24.0, 14.0)
private let treeGroups: [Group] = [
    Group.new("Header", "hdr", [treeA]).under("Item page"),
    Group.new("Tables", "table", [treeB]).under("Item page"),
    Group.new("Rows", "list", [treeC]).under("Sidebar"),
    Group.new("Dock", "dock", [treeD]),
]

private func seen(_ gs: [Int]) -> Set<Int> {
    Set(gs)
}

@discardableResult
private func sendKey(_ k: inout Knobs, _ ev: Key) -> Did {
    let p = plan(k, treeGroups, seen([0, 3]))
    return k.treeKey(treeGroups, p, KeyEvent(key: ev, mods: Mods()))
}

extension RuneKnobsSerializedSuites {
@Suite("RuneKnobs tree tests", .serialized)
@MainActor
struct RuneKnobsTreeTests {
    @Test("everything_starts_folded_with_a_dot_on_whats_on_screen")
    func everythingStartsFoldedWithADotOnWhatsOnScreen() {
        let k = Knobs()
        let p = plan(k, treeGroups, seen([0, 3]))
        #expect(p.sections.count == 3, "Item page, Sidebar, Dock")
        #expect(p.sections[0].head == .page("Item page"))
        #expect(p.sections.allSatisfy { $0.head == .bare || !$0.open }, "every page folded")
        #expect(p.sections.flatMap(\.subs).allSatisfy { !$0.open }, "every group folded")
        #expect(p.sections[0].seen && !p.sections[1].seen)
        #expect(p.sections[0].subs[0].seen && !p.sections[0].subs[1].seen)
        #expect(p.sections[2].head == .bare, "a group on its own needs no page")
        #expect(rows(p) == [.page("Item page"), .page("Sidebar"), .group(3)])
    }

    @Test("explicit_folds_win")
    func explicitFoldsWin() {
        var k = Knobs()
        k.setFolded("Header", false)
        k.setFolded("Item page", true)
        k.setFolded("Sidebar", false)
        let p = plan(k, treeGroups, seen([0, 3]))
        #expect(p.sections[0].subs[0].open && !p.sections[0].open)
        #expect(p.sections[1].open)
    }

    @Test("reopening_folds_all_but_the_group_last_left_open")
    func reopeningFoldsAllButTheGroupLastLeftOpen() {
        var k = Knobs()
        k.show()
        k.setFolded("Sidebar", false)
        k.setFolded("Rows", false)
        k.setFolded("Item page", false)
        k.setFolded("Tables", false)
        k.group = "Tables"
        k.close()
        k.show()
        let p = plan(k, treeGroups, seen([]))
        #expect(p.sections[0].open && p.sections[0].subs[1].open, "Tables and its page open")
        #expect(!p.sections[0].subs[0].open && !p.sections[1].open, "the rest folded")
        k.setFolded("Tables", true)
        k.close()
        k.show()
        let p2 = plan(k, treeGroups, seen([]))
        #expect(!p2.sections[0].open, "folded last, so nothing stays open")
    }

    @Test("on_screen_layout_lists_whats_showing_first")
    func onScreenLayoutListsWhatsShowingFirst() {
        var k = Knobs()
        k.set(LAYOUT, 1.0)
        let p = plan(k, treeGroups, seen([1, 3]))
        #expect(p.sections[0].head == .caption(SEEN))
        #expect(p.sections[0].subs.map(\.g) == [1, 3])
        #expect(p.sections[0].subs[0].full, "it names its page")
        #expect(p.sections[1].head == .caption(REST))
        #expect(p.sections[1].subs.allSatisfy { !$0.open })
    }

    @Test("tabs_layout_opens_on_the_page_thats_showing")
    func tabsLayoutOpensOnThePageThatsShowing() {
        var k = Knobs()
        k.set(LAYOUT, 2.0)
        let p = plan(k, treeGroups, seen([2]))
        #expect(p.tab == "Sidebar")
        #expect(p.tabs.count == 3)
        #expect(p.sections[0].subs.map(\.g) == [2])
        _ = k.treeKey(treeGroups, p, KeyEvent(key: .text("]"), mods: Mods()))
        #expect(plan(k, treeGroups, seen([2])).tab == "Dock")
    }

    @Test("slash_then_a_query_filters_by_name_and_description")
    func slashThenAQueryFiltersByNameAndDescription() {
        var k = Knobs()
        #expect(sendKey(&k, .text("t")) == .not, "a letter alone doesn't filter")
        #expect(k.query.isEmpty)
        sendKey(&k, .text("/"))
        #expect(k.filtering)
        #expect(sendKey(&k, .text("t")) == .not, "the field takes typing, not the tree")
        #expect(sendKey(&k, .right) == .not, "and ← →")
        k.setQuery("tall")
        k.refilter(treeGroups, plan(k, treeGroups, seen([])))
        let p = plan(k, treeGroups, seen([]))
        #expect(rows(p) == [.group(0), .knob(0, 0)], "matches A's description")
        #expect(k.at() == .knob(0, 0), "the keyboard lands on the first match")
        sendKey(&k, .escape)
        #expect(!k.filtering && k.query == "tall", "Esc stops typing and keeps the matches")
        sendKey(&k, .escape)
        #expect(k.query.isEmpty, "a second Esc clears the filter")
    }

    @Test("number_keys_pick_the_keyboard_choices_option")
    func numberKeysPickTheKeyboardChoicesOption() {
        var k = Knobs()
        k.open = true
        k.setFolded("Item page", false)
        k.setFolded("Tables", false)
        let p = plan(k, treeGroups, seen([0, 3]))
        k.setAt(.knob(1, 0), treeGroups)
        #expect(rows(p).contains(.knob(1, 0)))
        #expect(sendKey(&k, .text("2")) == .now)
        #expect(k.get(treeB) == 1.0, "2 picks Zebra")
        sendKey(&k, .text("3"))
        #expect(k.get(treeB) == 1.0, "past the last option does nothing")
        k.undo()
        #expect(k.get(treeB) == 0.0, "undoable")
    }

    @Test("arrows_walk_rows_and_fold_headers")
    func arrowsWalkRowsAndFoldHeaders() {
        var k = Knobs()
        k.open = true
        #expect(sendKey(&k, .down) == .now)
        #expect(k.at() == .page("Item page"))
        #expect(sendKey(&k, .right) == .fold)
        #expect(k.unfolded.contains("Item page"))
        #expect(sendKey(&k, .left) == .fold)
        #expect(k.folded.contains("Item page"))
        #expect(sendKey(&k, .down) == .now)
        #expect(k.at() == .page("Sidebar"), "the folded page's rows are skipped")
        #expect(sendKey(&k, .right) == .fold)
        #expect(k.unfolded.contains("Sidebar"))
        sendKey(&k, .right)
        #expect(k.at() == .group(2), "→ on an open header goes in")
        sendKey(&k, .right)
        sendKey(&k, .right)
        #expect(k.at() == .knob(2, 0))
        sendKey(&k, .right)
        #expect(abs(k.get(treeC) - 2.08) < 1e-4, "→ on a knob steps it")
        #expect(k.group == "Rows")
    }
}
}
